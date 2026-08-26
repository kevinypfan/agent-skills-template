---
name: fix-issue
description: Read an issue (GitLab or GitHub, auto-detected), analyze the problem, implement the fix after user confirmation, and push via the commit-push-pr skill. Assumes branch/worktree is already set up (use create-worktree first). Use when: (1) user mentions an issue number with intent to fix, (2) user says "fix issue", "修 issue", "處理 issue", or (3) user explicitly invokes /fix-issue.
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read `.agents/skills/fix-issue/SKILL.md` 並嚴格照其流程執行——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
