#!/usr/bin/env bash
# install-global.sh 的情境測試，聚焦 ~/.claude/settings.json 合併與 global/claude/ 的兩個 script。
# 每個情境用 mktemp 建一個假 HOME，不碰真實的 ~。用法：bash scripts/test-install-global.sh
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
inst="$repo/scripts/install-global.sh"
command -v jq >/dev/null || { echo "需要 jq"; exit 2; }
fail=0; pass=0; tmps=()
check() { if eval "$2"; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
fresh() { H=$(mktemp -d "${TMPDIR:-/tmp}/install-test ${1:-x}.XXXXXX"); tmps+=("$H"); mkdir -p "$H/.claude"; S="$H/.claude/settings.json"; }
run() { HOME="$H" bash "$inst" --no-codex "$@" 2>&1; }
trap 'rm -rf "${tmps[@]}"' EXIT
HOOK='[ ! -f "$HOME/.claude/agent-skills-template/subagent-model.sh" ] || bash "$HOME/.claude/agent-skills-template/subagent-model.sh"'
SL='[ ! -f "$HOME/.claude/agent-skills-template/statusline.sh" ] || bash "$HOME/.claude/agent-skills-template/statusline.sh"'
hooks() { jq -c '[.hooks.SubagentStop[]?.hooks[]?.command]' "$S"; }

echo "1. 全新安裝（沒有 settings.json），HOME 含空白"
fresh
out=$(run); check "dry-run 不建 settings.json" '[ ! -e "$S" ]'
check "dry-run 列出要加 hook" 'grep -q "加入  ~/.claude/settings.json 的 SubagentStop hook" <<<"$out"'
run --apply >/dev/null
check "hook 指令寫字面 \$HOME" '[ "$(hooks)" = "$(jq -nc --arg c "$HOOK" "[\$c]")" ]'
check "statusLine 寫字面 \$HOME" '[ "$(jq -r .statusLine.command "$S")" = "$SL" ]'
check "兩個 symlink 指回 repo" '[ "$(readlink "$H/.claude/agent-skills-template/subagent-model.sh")" = "$repo/global/claude/subagent-model.sh" ] && [ "$(readlink "$H/.claude/agent-skills-template/statusline.sh")" = "$repo/global/claude/statusline.sh" ]'
check "hook 指令在含空白的 HOME 下可執行" '[ "$(echo "{}" | HOME="$H" bash -c "$HOOK"; echo rc=$?)" = "rc=0" ]'
before=$(cat "$S"); out=$(run --apply)
check "重跑 idempotent" '[ "$before" = "$(cat "$S")" ] && grep -q "建立 0、更新 0、移除 0、已裝 [0-9]*、衝突跳過 0" <<<"$out"'
check "重跑 --quiet 不出聲" '[ -z "$(run --apply --quiet)" ]'
run --uninstall >/dev/null
check "uninstall 拿掉兩筆，剩 {}" '[ "$(jq -c . "$S")" = "{}" ]'
check "uninstall 拿掉 symlink 與空目錄" '[ ! -e "$H/.claude/agent-skills-template" ]'
check "script 不存在時 hook 指令安靜結束" '[ "$(echo "{}" | HOME="$H" bash -c "$HOOK"; echo rc=$?)" = "rc=0" ]'
check "script 不存在時 statusLine 指令安靜結束" '[ "$(echo "{}" | HOME="$H" bash -c "$SL"; echo rc=$?)" = "rc=0" ]'

echo "2. 既有設定：別的 hook、自己的 statusLine"
fresh
echo '{"model":"opus","statusLine":{"type":"command","command":"my-line"},"hooks":{"SubagentStop":[{"hooks":[{"type":"command","command":"other"}]}],"Stop":[{"hooks":[{"type":"command","command":"s"}]}]}}' > "$S"
out=$(run --apply)
check "自己的 statusLine 不動" '[ "$(jq -r .statusLine.command "$S")" = my-line ]'
check "自己的 statusLine 不算衝突" 'grep -q "衝突跳過 0" <<<"$out"'
check "--quiet 不為 statusLine 出聲" '[ -z "$(run --apply --quiet)" ]'
check "別的 hook 保留、本筆接在後面" '[ "$(hooks)" = "$(jq -nc --arg c "$HOOK" "[\"other\",\$c]")" ]'
check "其他 key 保留" '[ "$(jq -r .model "$S")" = opus ] && [ "$(jq -r ".hooks.Stop[0].hooks[0].command" "$S")" = s ]'
run --uninstall >/dev/null
check "uninstall 不碰別人的設定" '[ "$(hooks)" = "[\"other\"]" ] && [ "$(jq -r .statusLine.command "$S")" = my-line ] && [ "$(jq -r ".hooks.Stop[0].hooks[0].command" "$S")" = s ]'

echo "3. settings.json 是 symlink（dotfiles）"
fresh; mkdir -p "$H/dotfiles"; echo '{}' > "$H/dotfiles/settings.json"; ln -s "$H/dotfiles/settings.json" "$S"
run --apply >/dev/null
check "仍是 symlink，目標檔有寫入" '[ -L "$S" ] && [ "$(jq "[.hooks.SubagentStop[]]|length" "$H/dotfiles/settings.json")" = 1 ]'

echo "4. settings.json 指向唯讀檔"
fresh; mkdir -p "$H/ro"; echo '{}' > "$H/ro/settings.json"; chmod 444 "$H/ro/settings.json"; ln -s "$H/ro/settings.json" "$S"
out=$(run --apply); rc=$?
check "不中止、報衝突、不留暫存檔" '[ "$rc" = 0 ] && grep -q "不可寫入" <<<"$out" && [ -z "$(ls "$H/.claude" | grep "settings.json\.")" ] && [ "$(cat "$H/ro/settings.json")" = "{}" ]'
check "失敗不顯示加入" '! grep -q "加入  ~/.claude/settings.json" <<<"$out"'
chmod 644 "$H/ro/settings.json"

echo "4b. 已安裝後 settings.json 變唯讀，再 uninstall"
fresh; run --apply >/dev/null; chmod 444 "$S"
out=$(run --uninstall)
check "不謊報移除" '! grep -q "移除  ~/.claude/settings.json" <<<"$out"'
check "保留兩個 script，不留懸空的 hook" '[ -L "$H/.claude/agent-skills-template/subagent-model.sh" ] && [ -L "$H/.claude/agent-skills-template/statusline.sh" ] && grep -q "保留" <<<"$out"'
chmod 644 "$S"

echo "5. 目標位置已有別人的檔案"
fresh; mkdir -p "$H/.claude/agent-skills-template"; echo 'echo mine' > "$H/.claude/agent-skills-template/subagent-model.sh"
out=$(run --apply)
check "別人的檔案不動、hook 不寫入" '[ "$(cat "$H/.claude/agent-skills-template/subagent-model.sh")" = "echo mine" ] && [ "$(hooks)" = "[]" ]'
check "同一原因只算一次衝突" 'grep -q "衝突跳過 1" <<<"$out"'
check "statusLine 照樣裝" '[ "$(jq -r .statusLine.command "$S")" = "$SL" ]'

echo "6. 合法 JSON 但型別不符"
for bad in '{"hooks":[]}' '{"statusLine":"x"}' '{"hooks":{"SubagentStop":{}}}'; do
  fresh; echo "$bad" > "$S"
  out=$(run --apply); rc=$?
  check "不中止：$bad" '[ "$rc" = 0 ] && grep -q "^完成" <<<"$out"'
  check "沒寫入就不顯示加入：$bad" '! grep -q "加入  ~/.claude/settings.json 的 SubagentStop" <<<"$out" || [ "$(jq -c "[.hooks.SubagentStop[]?.hooks[]?.command]" "$S")" = "$(jq -nc --arg c "$HOOK" "[\$c]")" ]'
done
fresh; echo '{"statusLine":"x"}' > "$S"; run --apply >/dev/null
check "格式不對的 statusLine 也算使用者自己的，不覆寫" '[ "$(jq -r .statusLine "$S")" = x ]'

echo "7. 非法 JSON"
fresh; echo '{not json' > "$S"
out=$(run --apply)
check "不動檔案、報衝突" '[ "$(cat "$S")" = "{not json" ] && grep -q "不是合法的 JSON" <<<"$out"'
out=$(run --uninstall)
check "uninstall 只提醒" 'grep -q "未處理" <<<"$out" && ! grep -q "衝突" <<<"$out"'

echo "7b. uninstall 遇到沒有 .hooks 的 SubagentStop 項目"
fresh; run --apply >/dev/null
jq '.hooks.SubagentStop += [{"matcher":"x"}, "junk"]' "$S" > "$S.new" && mv "$S.new" "$S"
out=$(run --uninstall)
check "本筆移除、其他項目保留" '[ "$(jq -c .hooks.SubagentStop "$S")" = "[{\"matcher\":\"x\"},\"junk\"]" ] && grep -q "移除  ~/.claude/settings.json 的 SubagentStop hook" <<<"$out"'

echo "10. 另一個 install-global.sh 拿著鎖"
fresh; mkdir "$H/.claude/.agent-skills-template.lock"
out=$(run --apply)
check "拿不到鎖就跳過，不建 settings.json" '[ ! -e "$S" ] && grep -q "鎖住" <<<"$out"'
rmdir "$H/.claude/.agent-skills-template.lock"
run --apply >/dev/null
check "鎖釋放後正常安裝、結束後不留鎖" '[ "$(hooks)" = "$(jq -nc --arg c "$HOOK" "[\$c]")" ] && [ ! -e "$H/.claude/.agent-skills-template.lock" ]'

echo "11. conventions.local.md 設 claude_settings: false"
for form in '| `claude_settings` | `false` | |' 'claude_settings: false'; do
  fresh; mkdir -p "$H/.agents"; printf '%s\n' "$form" > "$H/.agents/conventions.local.md"
  out=$(run --apply)
  check "不碰 settings.json：$form" '[ ! -e "$S" ] && grep -q "claude_settings: false" <<<"$out" && grep -q "衝突跳過 0" <<<"$out"'
  check "--quiet 不出聲：$form" '[ -z "$(run --apply --quiet)" ]'
done
fresh; run --apply >/dev/null; mkdir -p "$H/.agents"; echo 'claude_settings: false' > "$H/.agents/conventions.local.md"
run --uninstall >/dev/null
check "opt-out 後 uninstall 仍清掉本腳本的兩筆" '[ "$(jq -c . "$S")" = "{}" ]'

echo "12. 寫回前的防護（用假的 jq 包裝模擬）"
fake_jq() {
  mkdir -p "$H/bin"
  cat > "$H/bin/jq" <<'SH'
#!/usr/bin/env bash
case "$FAKE_JQ_MODE:$*" in
  truncate:*'| length > 0'*) : > "$HOME/.claude/settings.json" ;;   # 查詢時，別的程式把檔案清空
  empty:*'+= [{hooks'*) exit 0 ;;                                     # 寫入時 jq 輸出空字串並回傳 0
esac
exec "$REAL_JQ" "$@"
SH
  chmod +x "$H/bin/jq"
}
run_fake() { HOME="$H" PATH="$H/bin:$PATH" REAL_JQ=$(command -v jq) FAKE_JQ_MODE=$1 bash "$inst" --no-codex --apply 2>&1; }
fresh; fake_jq; echo '{"model":"opus"}' > "$S"
out=$(run_fake truncate)
check "處理中被清空：報衝突、不當成 {} 重寫" 'grep -q "在處理中被清空" <<<"$out" && [ ! -s "$S" ] && ! grep -q "加入  ~/.claude/settings.json" <<<"$out"'
fresh; fake_jq; echo '{"model":"opus"}' > "$S"
out=$(run_fake empty)
check "jq 輸出空內容：不寫回、原本設定完整" 'grep -q "寫入失敗（加入 SubagentStop hook）" <<<"$out" && [ "$(jq -r .model "$S")" = opus ] && [ "$(hooks)" = "[]" ]'

echo "8. hook script"
fresh; t="$H/t.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user"}}' '{"type":"assistant","advisorModel":"claude-opus-x","message":{"model":"claude-haiku-x"}}' > "$t"
msg=$(jq -nc --arg t "$t" '{agent_type:"scout",effort:{level:"low"},agent_transcript_path:$t}' | bash "$repo/global/claude/subagent-model.sh" | jq -r .systemMessage)
check "只讀 assistant 訊息的 model" '[ "$msg" = "🤖 scout → claude-haiku-x (effort: low)" ]'
check "沒有 transcript 時安靜結束" '[ "$(echo "{}" | bash "$repo/global/claude/subagent-model.sh"; echo rc=$?)" = "rc=0" ]'

echo "9. statusline script"
line=$(jq -nc --arg c "$repo" '{cwd:$c,model:{display_name:"M"},context_window:{used_percentage:12.6}}' | bash "$repo/global/claude/statusline.sh")
check "顯示 model 與 context 用量" 'grep -q "| M | ctx:13%" <<<"$line"'
line=$(jq -nc --arg c "${HOME}2/x" '{cwd:$c}' | bash "$repo/global/claude/statusline.sh")
check "HOME 前綴相同的路徑不縮寫成 ~" '! grep -q "~2/x" <<<"$line"'

echo; echo "pass=$pass fail=$fail"; [ "$fail" = 0 ]
