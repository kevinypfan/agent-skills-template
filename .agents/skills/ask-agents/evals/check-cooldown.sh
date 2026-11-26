#!/usr/bin/env bash
# cooldown.sh 的斷言測試：記錄、查詢、過期、覆寫、解除、錯誤輸入。狀態檔放暫存目錄，不碰 ~/.agents/state。
# 手動：bash .agents/skills/ask-agents/evals/check-cooldown.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
c="$here/../scripts/cooldown.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export ASK_AGENTS_STATE="$tmp/state/agent-cooldown"
pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "✗ $1"; }
now=$(date +%s)

bash "$c" check codex >/dev/null && ok || bad "沒有狀態檔時應可用"
bash "$c" set codex 3600 "usage limit" >/dev/null || bad "set 秒數失敗"
out=$(bash "$c" check codex); [ $? -eq 1 ] && ok || bad "冷卻中 check 應 exit 1"
case "$out" in *"usage limit"*) ok ;; *) bad "check 輸出缺原因：$out" ;; esac
bash "$c" check claude >/dev/null && ok || bad "別家不受影響"
bash "$c" set agy "@$((now + 60))" >/dev/null && ! bash "$c" check agy >/dev/null && ok || bad "set @epoch 失敗"
bash "$c" set codex 7200 again >/dev/null; [ "$(grep -c '^codex' "$ASK_AGENTS_STATE")" = 1 ] && ok || bad "重設同一家應覆寫、不疊加"
printf 'old\t%s\tx\n' "$((now - 10))" >> "$ASK_AGENTS_STATE"
bash "$c" check old >/dev/null && ok || bad "過期的紀錄應視為可用"
bash "$c" set claude 60 >/dev/null; grep -q '^old' "$ASK_AGENTS_STATE" && bad "寫入時應清掉過期紀錄" || ok
bash "$c" clear codex; bash "$c" check codex >/dev/null && ok || bad "clear 後應可用"
[ "$(bash "$c" list | wc -l | tr -d ' ')" = 2 ] && ok || bad "list 應只列仍在冷卻的（agy、claude）"
bash "$c" set codex "@$((now - 1))" 2>/dev/null; [ $? -eq 2 ] && ok || bad "過去的到期時間應拒絕"
bash "$c" set codex soon 2>/dev/null; [ $? -eq 2 ] && ok || bad "非數字時間應拒絕"
bash "$c" set codex 60 "$(printf 'a\tb\nc')" >/dev/null; awk -F'\t' 'NF != 3 { bad=1 } END { exit bad }' "$ASK_AGENTS_STATE" && ok || bad "原因含 tab／換行不能破壞格式（每行要正好 3 欄）"
bash "$c" set codex 5h >/dev/null && [ "$(awk -F'\t' '$1=="codex"{print $2}' "$ASK_AGENTS_STATE")" -ge $((now + 18000)) ] && ok || bad "5h 應換算成 18000 秒"
bash "$c" set codex 30m >/dev/null && ok || bad "30m 應接受"
bash "$c" set codex 5x 2>/dev/null; [ $? -eq 2 ] && ok || bad "未知單位應拒絕"
bash "$c" set codex @12abc 2>/dev/null; [ $? -eq 2 ] && ok || bad "@ 後非數字應拒絕"
bash "$c" set codex 99999999999999999999 2>/dev/null; [ $? -eq 2 ] && ok || bad "過大的時長應拒絕"
bash "$c" set codex 31d 2>/dev/null; [ $? -eq 2 ] && ok || bad "超過 30 天應拒絕"
# 平行寫入不能互相蓋掉
bash "$c" clear codex; bash "$c" clear claude; bash "$c" clear agy
rc_file="$tmp/rc"; : > "$rc_file"
for i in $(seq 1 30); do ( bash "$c" set "a$i" 600 >/dev/null 2>&1 || echo "a$i" >> "$rc_file" ) & done; wait
[ "$(bash "$c" list | wc -l | tr -d ' ')" = 30 ] && [ ! -s "$rc_file" ] && ok || bad "平行 set 30 家應全部成功、留下 30 筆，實際 $(bash "$c" list | wc -l | tr -d ' ') 筆、失敗 $(wc -l < "$rc_file" | tr -d ' ') 個"
[ -d "$ASK_AGENTS_STATE.lock" ] && bad "鎖沒有釋放" || ok
# 時刻與前導零
bash "$c" set codex 08h >/dev/null && [ "$(awk -F'\t' '$1=="codex"{print $2}' "$ASK_AGENTS_STATE")" -ge $((now + 28800)) ] && ok || bad "08h 應以十進位換算（不能當八進位）"
bash "$c" set codex 90s >/dev/null && bash "$c" set codex 1d >/dev/null && ok || bad "90s／1d 應接受"
t=$(date -d '@'$((now + 7200)) '+%H:%M' 2>/dev/null || date -r $((now + 7200)) '+%H:%M')
bash "$c" set codex "$t" >/dev/null && u=$(awk -F'\t' '$1=="codex"{print $2}' "$ASK_AGENTS_STATE") && [ "$u" -gt "$now" ] && [ "$u" -le $((now + 86400)) ] && ok || bad "HH:MM 應換算成未來 24 小時內"
p=$(date -d '@'$((now - 3600)) '+%H:%M' 2>/dev/null || date -r $((now - 3600)) '+%H:%M')
bash "$c" set codex "$p" >/dev/null && u=$(awk -F'\t' '$1=="codex"{print $2}' "$ASK_AGENTS_STATE") && [ "$u" -gt $((now + 79000)) ] && ok || bad "已過的 HH:MM 應算明天"
d=$(date -d '@'$((now + 86400)) '+%Y-%m-%d %H:%M' 2>/dev/null || date -r $((now + 86400)) '+%Y-%m-%d %H:%M')
bash "$c" set codex "$d" >/dev/null && ok || bad "\"YYYY-MM-DD HH:MM\" 應接受"
bash "$c" set codex 25:99 2>/dev/null; [ $? -eq 2 ] && ok || bad "不存在的時刻應拒絕"
# 用法錯與冷卻中要分得開
bash "$c" check 2>/dev/null; [ $? -eq 2 ] && ok || bad "check 缺參數應 exit 2（不是冷卻的 1）"
# 殘留的鎖：新的要等，超過 60 秒的要清掉；check 不受鎖影響
mkdir "$ASK_AGENTS_STATE.lock"; touch -t "$(date -r $((now - 120)) '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '@'$((now - 120)) '+%Y%m%d%H%M.%S')" "$ASK_AGENTS_STATE.lock"
bash "$c" set stale 60 >/dev/null && ok || bad "超過 60 秒的殘留鎖應被清掉"
mkdir "$ASK_AGENTS_STATE.lock"; bash "$c" check stale >/dev/null; [ $? -eq 1 ] && ok || bad "有鎖時 check 仍要能讀"
bash "$c" set fresh 60 2>/dev/null; [ $? -eq 3 ] && ok || bad "新鮮的鎖應等到逾時後 exit 3"
rmdir "$ASK_AGENTS_STATE.lock"
echo "cooldown：${pass} 通過，${fail} 失敗"
[ "$fail" = 0 ]
