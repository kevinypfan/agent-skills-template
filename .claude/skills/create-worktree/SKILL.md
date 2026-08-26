---
name: create-worktree
description: >
  從 issue（GitLab 或 GitHub，自動偵測）建立獨立 git worktree 和分支，不影響當前工作目錄。
  使用時機：(1) 使用者提供 issue 編號並想開 worktree,
  (2) 使用者說「開 worktree」「建 worktree」「create worktree」並提到 issue,
  (3) 使用者明確呼叫 /create-worktree。
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read `.agents/skills/create-worktree/SKILL.md` 並嚴格照其流程執行——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
