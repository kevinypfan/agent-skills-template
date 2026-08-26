#!/usr/bin/env bash
# 守門（pre-commit）：
#  1. .claude/skills/ 的 stub 必須等於 scripts/generate-skill-stubs.sh 的產物（含 frontmatter）；每個 stub 都要有 .agents/skills/<s>/SKILL.md 真身
#  2. 共用真身內容規則（見 .agents/skills/README.md）：
#     - 不含 Claude host macro（$ARGUMENTS / $1… / !`cmd` / $CLAUDE_*）——只在 Claude 載入 skill 檔時展開，經 stub Read 不會
#     - 附屬檔不用 ../ 或裸 assets|references|scripts|templates/（stub 轉跳後 cwd 是 repo 根）
#     - 呼叫其他 skill 不寫 Claude slash 語法（起行的「/name …」或反引號包住的「`/name`」）、不並列 per-tool 語法
#     - 不硬編 tracker CLI（glab / gh）——動作名寫「[tracker] …」，指令只放 .agents/skills/_tracker/
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
[ $fail -eq 0 ] && echo "✓ skill stubs（${n}）一致，真身規則全過"
exit $fail
