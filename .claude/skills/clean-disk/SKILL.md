---
name: clean-disk
description: >
  清理本機開發空間：掃描根目錄底下所有 repo 的 git worktree（agent 平行處理 issue 後留下的）、
  可重建的依賴／建置產物（node_modules、.venv、target…）、全域開發快取（npm、pnpm、uv、Docker…），
  用 script 把每一項分成「可刪／要看／保留」三級並說明理由，使用者確認後才刪，回報釋放的空間。
  使用時機：(1) 使用者說「磁碟滿了」「空間不夠」「清一下空間」「disk full」「清理 worktree」「刪舊 worktree」「worktree 太多」，
  (2) 想知道哪些 worktree／branch 已經 merge 可以刪，(3) node_modules、快取、Docker 佔太多空間，
  (4) 使用者明確呼叫 /clean-disk。就算使用者只說「電腦快沒空間了」也適用。
compatibility: Requires git and bash; PR status lookup uses glab (GitLab) or gh (GitHub) when available. Scripts tested on macOS (bash 3.2) and Linux.
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read 真身並嚴格照其流程執行：repo 根有 `.agents/skills/clean-disk/SKILL.md` 就讀它，沒有就讀 `~/.agents/skills/clean-disk/SKILL.md`（全域安裝）——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
