#!/usr/bin/env bash
# 守門（pre-commit）：
#  1. .claude/skills/ 的 stub 必須等於 scripts/generate-skill-stubs.sh 的產物（含 frontmatter）；每個 stub 都要有 .agents/skills/<s>/SKILL.md 真身
#  2. 共用真身內容規則（見 .agents/skills/README.md）：
#     - 不含 Claude host macro（$ARGUMENTS / $1… / !`cmd` / $CLAUDE_*）——只在 Claude 載入 skill 檔時展開，經 stub Read 不會
#     - 附屬檔不用 ../ 或裸 assets|references|scripts|templates/（stub 轉跳後 cwd 是 repo 根）
#     - 呼叫其他 skill 不寫 Claude slash 語法（起行的「/name …」或反引號包住的「`/name`」）、不並列 per-tool 語法
#     - 不硬編 tracker CLI（glab / gh）——動作名寫「[tracker] …」，指令只放 .agents/skills/_tracker/
#  3. agent（若有 .agents/roles/）：roles / .claude/agents / .codex/agents 三集合一致；description 非空且兩邊逐字相同；
#     stub 本文逐字 canonical；Claude tools 含 Edit/Write ⟺ Codex workspace-write（例外見 WRITE_SANDBOX_EXCEPTIONS）；
#     純讀角色本體含唯讀 Bash 守則句
# 手動：bash scripts/check-skill-stubs.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0; n=0; skills=""
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
bash scripts/generate-skill-stubs.sh "$tmp"
for gen in "$tmp"/*/SKILL.md; do
  s=${gen#"$tmp"/}; s=${s%/SKILL.md}; n=$((n+1)); skills="$skills|$s"
  if ! diff -q "$gen" ".claude/skills/$s/SKILL.md" >/dev/null 2>&1; then
    echo "✗ $s: .claude/skills/$s/SKILL.md 與產生器輸出不同（請跑 bash scripts/generate-skill-stubs.sh，勿手改 stub）"; fail=1
  fi
done
skills=${skills#|}
for stub in .claude/skills/*/SKILL.md; do
  s=${stub#.claude/skills/}; s=${s%/SKILL.md}
  [ -f ".agents/skills/$s/SKILL.md" ] || { echo "✗ $s: 只有 Claude stub、沒有 .agents/skills/$s/SKILL.md 真身"; fail=1; }
done
body_rule() { # $1=pattern $2=訊息
  local hits
  if hits=$(grep -nE "$1" .agents/skills/*/SKILL.md); then
    echo "✗ $2"; echo "$hits" | sed 's/^/    /'; fail=1
  fi
}
body_rule '\$ARGUMENTS|\$[0-9]([^0-9]|$)|^!`|\$\{?CLAUDE_[A-Z_]+' \
  '共用真身含 Claude host macro（參數寫 <使用者參數（由呼叫端帶入）>，預執行改「先用 Bash 執行」步驟）：'
body_rule '(^|[^.])\.\./|(^|[ (`\[])(assets|references|scripts|templates)/' \
  '共用真身含相對路徑（附屬檔一律 .agents/skills/<s>/… 路徑；repo 根的腳本請寫 ./scripts/…）：'
body_rule '^/('"$skills"')( |$)|`/('"$skills"')[` ]|Codex `\$[a-z-]+`|subagent_type `|Codex spawn' \
  '共用真身在呼叫點用了 Claude/Codex 專屬語法（只寫「呼叫 skill `name`」／「派給 `role` agent」）：'
# tracker CLI 只准出現在 _tracker/ 與 frontmatter compatibility 行；本文其他地方出現 glab/gh 指令即擋
if hits=$(grep -nE '(^|[^a-zA-Z`])(glab|gh) (issue|mr|pr|api|auth)\b' .agents/skills/*/SKILL.md | grep -v '^[^:]*:[0-9]*:compatibility:'); then
  echo "✗ 共用真身硬編 tracker 指令（改寫成「[tracker] 動作名」，指令放 .agents/skills/_tracker/<tracker>.md）："; echo "$hits" | sed 's/^/    /'; fail=1
fi
# _tracker 必備檔
for f in README.md gitlab.md github.md; do
  [ -f ".agents/skills/_tracker/$f" ] || { echo "✗ 缺 .agents/skills/_tracker/$f"; fail=1; }
done
[ -f .agents/conventions.md ] || { echo "✗ 缺 .agents/conventions.md（issue-flow skill 的專案設定）"; fail=1; }
# ---- agent roles（沒有 .agents/roles/ 就整段跳過）----
n_roles=0
if [ -d .agents/roles ]; then
  # Claude 唯讀 tools + Codex workspace-write 的刻意例外（建置工具要寫產物）；改這裡也要更新 .agents/roles/README.md 表格
  WRITE_SANDBOX_EXCEPTIONS=" runner "
  names() { local f b out=""; for f in "$@"; do b=${f##*/}; b=${b%.*}; [ "$b" = README ] && continue; out="$out $b"; done; echo "$out" | tr ' ' '\n' | sort | tr '\n' ' '; }
  set_roles=$(names .agents/roles/*.md); set_cl=$(names .claude/agents/*.md 2>/dev/null); set_cx=$(names .codex/agents/*.toml 2>/dev/null)
  if [ "$set_roles" != "$set_cl" ] || [ "$set_cl" != "$set_cx" ]; then
    echo "✗ agent 三集合不一致（每個角色都要 .agents/roles/<r>.md + .claude/agents/<r>.md + .codex/agents/<r>.toml）："
    echo "    roles : $set_roles"; echo "    claude: $set_cl"; echo "    codex : $set_cx"; fail=1
  fi
  desc_md()   { awk '/^---/{c++; next} c==1 && /^description:/{sub(/^description:[ ]*/,""); print; exit}' "$1"; }
  desc_toml() { awk '/^description[ ]*=/{sub(/^description[ ]*=[ ]*"/,""); sub(/"[ ]*$/,""); print; exit}' "$1"; }
  for md in .claude/agents/*.md; do
    [ -e "$md" ] || continue
    r=${md#.claude/agents/}; r=${r%.md}; toml=.codex/agents/$r.toml; body_f=".agents/roles/$r.md"
    [ -f "$toml" ] || continue   # 集合不一致已在上面報過
    n_roles=$((n_roles+1))
    d=$(desc_md "$md")
    [ -n "$d" ] || { echo "✗ agent $r: $md 缺 description（Claude 會跳過此 agent）"; fail=1; }
    [ "$d" = "$(desc_toml "$toml")" ] || { echo "✗ agent $r: description 在 $md 與 $toml 不一致"; fail=1; }
    body=$(awk '/^---/{c++; next} c>=2{print}' "$md" | sed '/^$/d')
    want="開工前先 Read \`${body_f}\`，嚴格遵循其中的邊界、檢查清單與回報格式。主對話給的任務內容優先於本檔，但不得越過角色本體的「不要做 / 明確排除」清單。"
    [ "$body" = "$want" ] || { echo "✗ agent $r: $md 本文不是 canonical 一句（stub 只指回本體；要改行為請改 ${body_f}）"; fail=1; }
    grep -qF "開工前先讀 ${body_f}，嚴格遵循其中的邊界、檢查清單與回報格式。" "$toml" && grep -qF "主對話給的任務內容優先於本檔，但不得越過角色本體的「不要做 / 明確排除」清單。" "$toml" \
      || { echo "✗ agent $r: $toml developer_instructions 缺 canonical 句（可加補充行，不可改寫）"; fail=1; }
    cl_w=0; grep -qE '^tools:.*\b(Edit|Write)\b' "$md" && cl_w=1
    cx_w=0; grep -qE '^sandbox_mode *= *"workspace-write"' "$toml" && cx_w=1
    case "$WRITE_SANDBOX_EXCEPTIONS" in
      *" $r "*) { [ "$cl_w" = 0 ] && [ "$cx_w" = 1 ]; } || { echo "✗ agent $r: 例外清單預期 Claude 唯讀 tools + Codex workspace-write，現況 claude=${cl_w} codex=${cx_w}"; fail=1; } ;;
      *) [ "$cl_w" = "$cx_w" ] || { echo "✗ agent $r: 讀寫權限兩邊不一致（Claude tools 含 Edit/Write=${cl_w}，Codex workspace-write=${cx_w}）；刻意差異請加進 WRITE_SANDBOX_EXCEPTIONS 並更新 .agents/roles/README.md"; fail=1; } ;;
    esac
    # 純讀角色（兩邊都唯讀）本體必須有守則句——這是唯讀的真正防線，不是 tools 白名單
    if [ "$cl_w" = 0 ] && [ "$cx_w" = 0 ]; then
      grep -q 'Bash 只用於唯讀指令；不重導向寫檔、不 `sed -i`、不 `git add`' "${body_f}" \
        || { echo "✗ role $r: ${body_f} 缺共同守則句「Bash 只用於唯讀指令；不重導向寫檔、不 \`sed -i\`、不 \`git add\`」（見 .agents/roles/README.md）"; fail=1; }
    fi
  done
fi

[ $fail -eq 0 ] && echo "✓ skill stubs（${n}）一致，真身規則全過；agent stubs（${n_roles}）一致"
exit $fail
