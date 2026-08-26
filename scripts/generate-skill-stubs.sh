#!/usr/bin/env bash
# 從 .agents/skills/<s>/SKILL.md（Claude Code / Codex 共用真身）產生 .claude/skills/<s>/SKILL.md（Claude stub）。
# stub = 真身 frontmatter 逐字複製 + $ARGUMENTS 轉交（四反引號 fence：參數含 ``` 不會提前關閉）+ 「Read 真身照做」。
# ⚠ 等價範圍只有 frontmatter + $ARGUMENTS：真身經 Read 打開是普通 markdown，Claude 載入 skill 檔時的前處理
#   （$1… 替換、!`cmd` 預執行、$CLAUDE_* 變數）不會發生——真身不得依賴它們（check-skill-stubs.sh 會擋）。
# `_` 開頭目錄（如 _tracker）不是 skill、沒有 SKILL.md，glob 自然跳過。
# 用法：bash scripts/generate-skill-stubs.sh [OUT_DIR]   （預設 .claude/skills；check 用臨時目錄比對）
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
out="${1:-.claude/skills}"
for real in .agents/skills/*/SKILL.md; do
  s=${real#.agents/skills/}; s=${s%/SKILL.md}
  case "$s" in _*) echo "✗ $s: _ 開頭目錄不該有 SKILL.md（_ 保留給非 skill 的共用資料）" >&2; exit 1 ;; esac
  mkdir -p "$out/$s"
  {
    awk -v f="$real" '
      NR==1 && $0!="---" { print "✗ " f ": 第 1 行不是 frontmatter 起始 ---" > "/dev/stderr"; bad=1; exit 1 }
      $0=="---" { c++; print; if (c==2) { done=1; exit } ; next }
      c==1 { print }
      END { if (!done && !bad) { print "✗ " f ": frontmatter 未閉合" > "/dev/stderr"; exit 1 } }' "$real"
    cat <<STUB

## User Input

\`\`\`\`text
\$ARGUMENTS
\`\`\`\`

本檔由 \`scripts/generate-skill-stubs.sh\` 產生，勿手改。Read \`.agents/skills/$s/SKILL.md\` 並嚴格照其流程執行——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
STUB
  } > "$out/$s/SKILL.md.tmp"
  mv "$out/$s/SKILL.md.tmp" "$out/$s/SKILL.md"
done
