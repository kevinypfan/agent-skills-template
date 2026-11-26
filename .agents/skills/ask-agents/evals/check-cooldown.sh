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
bash "$c" set codex 60 "$(printf 'a\tb\nc')" >/dev/null; [ "$(grep -c '^codex' "$ASK_AGENTS_STATE")" = 1 ] && ok || bad "原因含 tab／換行不能破壞格式"
bash "$c" set codex 5h >/dev/null && [ "$(awk -F'\t' '$1=="codex"{print $2}' "$ASK_AGENTS_STATE")" -ge $((now + 18000)) ] && ok || bad "5h 應換算成 18000 秒"
bash "$c" set codex 30m >/dev/null && ok || bad "30m 應接受"
bash "$c" set codex 5x 2>/dev/null; [ $? -eq 2 ] && ok || bad "未知單位應拒絕"
bash "$c" set codex @12abc 2>/dev/null; [ $? -eq 2 ] && ok || bad "@ 後非數字應拒絕"
bash "$c" set codex 99999999999999999999 2>/dev/null; [ $? -eq 2 ] && ok || bad "過大的時長應拒絕"
bash "$c" set codex 31d 2>/dev/null; [ $? -eq 2 ] && ok || bad "超過 30 天應拒絕"
# 平行寫入不能互相蓋掉
bash "$c" clear codex; bash "$c" clear claude; bash "$c" clear agy
for a in a1 a2 a3 a4 a5 a6; do bash "$c" set "$a" 600 >/dev/null & done; wait
[ "$(bash "$c" list | wc -l | tr -d ' ')" = 6 ] && ok || bad "平行 set 6 家應留下 6 筆，實際 $(bash "$c" list | wc -l | tr -d ' ')"
[ -d "$ASK_AGENTS_STATE.lock" ] && bad "鎖沒有釋放" || ok
echo "cooldown：${pass} 通過，${fail} 失敗"
[ "$fail" = 0 ]
