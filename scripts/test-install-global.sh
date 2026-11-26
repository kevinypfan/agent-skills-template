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
D='$HOME/.claude/agent-skills-template'
HOOK="bash \"$D/subagent-model.sh\""; SL="bash \"$D/statusline.sh\""
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
check "重跑 idempotent" '[ "$before" = "$(cat "$S")" ] && grep -q "建立 0、更新 0、已裝 [0-9]*、衝突跳過 0" <<<"$out"'
check "重跑 --quiet 不出聲" '[ -z "$(run --apply --quiet)" ]'
run --uninstall >/dev/null
check "uninstall 拿掉兩筆，剩 {}" '[ "$(jq -c . "$S")" = "{}" ]'
check "uninstall 拿掉 symlink" '[ ! -L "$H/.claude/agent-skills-template/subagent-model.sh" ] && [ ! -L "$H/.claude/agent-skills-template/statusline.sh" ]'

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
check "不中止、報衝突、不留 tmp" '[ "$rc" = 0 ] && grep -q "不可寫入" <<<"$out" && [ ! -e "$S.tmp" ] && [ "$(cat "$H/ro/settings.json")" = "{}" ]'
chmod 644 "$H/ro/settings.json"

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
  check "失敗不謊報成功：$bad" '! grep -q "建立 [1-9].*衝突跳過 0" <<<"$out" || jq -e "[.hooks.SubagentStop[]?.hooks[]?.command] | length > 0" "$S" >/dev/null'
done

echo "7. 非法 JSON"
fresh; echo '{not json' > "$S"
out=$(run --apply)
check "不動檔案、報衝突" '[ "$(cat "$S")" = "{not json" ] && grep -q "不是合法的 JSON" <<<"$out"'
out=$(run --uninstall)
check "uninstall 只提醒" 'grep -q "未處理" <<<"$out" && ! grep -q "衝突" <<<"$out"'

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
