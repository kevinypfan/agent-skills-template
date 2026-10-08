---
name: review-pr
description: 審查 PR / MR（自審或審別人）並發佈總結 comment：逐檔增量讀取、必要時派 reviewer 分組 fan-out、自審與高風險跑 adversarial pass、多輪審查只看增量並追蹤上輪 findings。使用時機：(1) 使用者說「review 這個 PR」「幫我審 PR」「審 MR」「自審」「review 一下再發」，(2) orchestrate-issues 的 PR 關卡需要審查，(3) 使用者明確呼叫 /review-pr。
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read 真身並嚴格照其流程執行：repo 根有 `.agents/skills/review-pr/SKILL.md` 就讀它，沒有就讀 `~/.agents/skills/review-pr/SKILL.md`（全域安裝）——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
