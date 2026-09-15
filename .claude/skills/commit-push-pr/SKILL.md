---
name: commit-push-pr
description: Self-review diff, run the project's verification gate, commit, push, and create or update a Pull Request / Merge Request (GitLab or GitHub, auto-detected) with the standard template.
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read 真身並嚴格照其流程執行：repo 根有 `.agents/skills/commit-push-pr/SKILL.md` 就讀它，沒有就讀 `~/.agents/skills/commit-push-pr/SKILL.md`（全域安裝）——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
