# Skills（Claude Code 與 Codex 共用真身）

本目錄是 repo-local skill 的**唯一真相**（[Agent Skills](https://agentskills.io) 標準 `SKILL.md`）。
- **Codex** 原生掃 `.agents/skills/`，直接讀這裡（呼叫 `$skill-name`）。
- **Claude Code** 只讀 `.claude/skills/`，那裡每個 skill 是一份薄 stub（呼叫 `/skill-name`）——**由 `scripts/generate-skill-stubs.sh` 產生、勿手改**：frontmatter 逐字複製 + `$ARGUMENTS` 轉交 + 一句「Read `.agents/skills/<s>/SKILL.md` 照做」。
- `_` 開頭目錄（`_tracker/`）**不是 skill**，是給 skill 查的共用資料，沒有 `SKILL.md`。

## 目前內容（issue-flow）

| skill | 做什麼 | 接誰 |
|---|---|---|
| `create-issue` | 依 template 建 issue | → `create-worktree` |
| `create-worktree` | 從 issue 開 worktree + 分支 | → `fix-issue` |
| `fix-issue` | 讀 issue、討論方案、實作、測試 | → `commit-push-pr` |
| `commit-push-pr` | self-review、驗證閘門、commit、push、建/更新 PR | （終點；review 類 skill 未含） |
| `ask-agents` | 打包問題給 codex / agy 拿第二意見 | 獨立 |

專案差異全在 `.agents/conventions.md`；tracker（GitLab / GitHub）差異全在 `_tracker/`。

## 寫作規則（標 ✅ 者由 `scripts/check-skill-stubs.sh` 在 pre-commit 強制；其餘人工審）

- ✅ 改行為、改 frontmatter 都只改這裡，然後跑 `bash scripts/generate-skill-stubs.sh` 重生 stub（pre-commit 擋不一致）。
- frontmatter 可含 Claude 擴充欄位（`allowed-tools`、`disable-model-invocation` 等）——Codex 忽略未知欄位，產生器整段複製給 stub。
- ✅ **stub 的等價範圍只有 frontmatter + `$ARGUMENTS` 轉交**。真身經 `Read` 打開是普通 markdown，Claude 載入 skill 檔時才做的前處理一律不會發生：`$ARGUMENTS` / `$1`… 不替換、`` !`cmd` `` 不預執行、`$CLAUDE_PROJECT_DIR` 等變數不存在。真身**不得**含這些——使用者參數一律寫 `<使用者參數（由呼叫端帶入）>`；要先跑的指令寫成「先用 Bash 執行」的普通步驟，repo 根用 `git rev-parse --show-toplevel`。
- ✅ 附屬檔一律 repo 相對路徑 `.agents/skills/<s>/assets/...`；不得用 `../` 或裸 `assets/`。所有路徑相對 repo 根；repo 根的腳本寫 `./scripts/…`。
- ✅ **不要寫 `/name`**，也不要並列 per-tool 語法（Claude 為 `/name`；Codex 為 `$name`），對照只在本 README 一處。串接其他 skill 寫「呼叫 skill `name`」，參數另起 code block。
- ✅ **不硬編 tracker CLI**：本文只寫「**[tracker] 動作名**」（動作表在 `_tracker/README.md`），`glab` / `gh` 指令只能出現在 `_tracker/<tracker>.md` 與 frontmatter 的 `compatibility` 行。
- **不硬編專案值**（分支名、路徑、label、測試指令）：寫「conventions 的 `<key>`」。check 不查這條，靠人工審。
- Claude 專屬機制（`$SCRATCHPAD`、`AskUserQuestion`）若真身要用，同一句要寫明 Codex 端的替代（`mktemp -d`、對話中列選項）。

為何不用 symlink：Windows 需 Developer Mode 才能 checkout symlink，stub 是純檔案、任何平台可用；且 Claude 專屬 frontmatter 得以隔離。
