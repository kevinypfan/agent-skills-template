---
name: orchestrate-issues
description: 主 session 當調度者，用 terminal multiplexer 同時開多條 agent 線（每條線一個 worktree + session 跑 fix-issue），依檔案重疊分線、監看各線、把關 review / CI / merge 並收尾。使用時機：(1) 使用者要一次處理多個 issue、「平行處理這些 issue」「調度」「開幾條線」「orchestrate」，(2) 延續中的多線調度，(3) 使用者明確呼叫 /orchestrate-issues。
compatibility: Requires git, glab (GitLab) or gh (GitHub); automatic lanes need a terminal multiplexer (herdr), otherwise degrades to worktree-only
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read 真身並嚴格照其流程執行：repo 根有 `.agents/skills/orchestrate-issues/SKILL.md` 就讀它，沒有就讀 `~/.agents/skills/orchestrate-issues/SKILL.md`（全域安裝）——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
