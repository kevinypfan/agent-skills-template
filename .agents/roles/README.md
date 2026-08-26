# Agent roles（Claude Code 與 Codex 共用）

本目錄是委派角色的**唯一指令真相**。兩個工具各自只放薄 stub，行為只寫在本體。

| 角色 | 本體 | Claude stub | Codex stub | 可寫檔 |
|---|---|---|---|---|
| scout | `scout.md` | `.claude/agents/scout.md`（haiku） | `.codex/agents/scout.toml`（低 effort） | ✗ |
| runner | `runner.md` | `.claude/agents/runner.md`（sonnet） | `.codex/agents/runner.toml`（中 effort） | ✗（sandbox 例外見下） |
| reviewer | `reviewer.md` | `.claude/agents/reviewer.md`（sonnet） | `.codex/agents/reviewer.toml`（中 effort） | ✗ |
| worker | `worker.md` | `.claude/agents/worker.md`（sonnet） | `.codex/agents/worker.toml`（中 effort） | ✓ |
| architect | `architect.md` | `.claude/agents/architect.md`（fable） | `.codex/agents/architect.toml`（高 effort） | ✗ |

原則：**便宜 model 找與做、貴 model 判**。改行為改本體；改 model / effort / 權限改對應 stub。
stub 裡的 model 名是範例（Claude：`haiku` / `sonnet` / `fable` / `opus`；Codex：填你帳號可用的 model id），依專案預算調整。

## 共同守則（各角色本體不再重述）

- 唯讀角色（scout / runner / reviewer / architect）**不改任何檔案**。這是 best-effort 邊界、不是安全保證：Claude stub 的 `tools` 白名單只拿掉 Edit/Write（Bash 仍能 `sed -i` / 重導向 / `git add`）、Codex 的 `sandbox_mode = "read-only"` 會被 parent turn 的 full-access 覆蓋；真正的防線是各純讀本體逐字都有的守則句「Bash 只用於唯讀指令；不重導向寫檔、不 `sed -i`、不 `git add`」（`check-skill-stubs.sh` 強制存在）＋使用者端 permission。
- **runner 是刻意的例外**：建置 / 測試工具要寫 build 產物（`target/`、`.next/`、coverage…），Codex 端必須 `workspace-write` 才跑得動，Claude 端仍不給 Edit/Write。check script 對此有 allowlist。
- Claude stub（`.claude/agents/<r>.md`）本文**只能是**指回本體的那一句（check 逐字比對，刻意不留補充空間）；Codex toml 的 `developer_instructions` 可加補充行，但 canonical 兩句不可改寫。
- Codex toml 末尾的語言宣告依 `.agents/conventions.md` 的 `language` 調整——Codex 沒有 `CLAUDE.md` 那層語言政策，不宣告就會回英文；Claude 端由根 `CLAUDE.md` / `AGENTS.md` 覆蓋。
- 本體與 stub 內的相對路徑一律相對 repo 根（`git rev-parse --show-toplevel`）；從子目錄啟動工具時先回到根。
- 專案專屬的值（測試指令、分支、label）一律寫「conventions 的 `<key>`」，不硬編在本體。
- 所有角色**未經 spec 明示不 commit / push / 開 PR / deploy**。

## 讓它自動被派（兩個層次）

主對話會拿使用者的請求比對每個 stub 的 `description`，命中就自己派——**這是預設行為，不必點名**。但描述比對只是機率，兩件事要做：

1. **description 帶觸發語**：本 template 的五個 stub 都寫成「…。主動使用：<什麼情境>，不必等使用者點名」。你新增角色時照這個形狀寫，只描述「我是誰」的 description 命中率很低。
2. **把政策放進永遠在 context 的檔案**：`description` 只在工具選擇時參與比對，而 repo 根的 `CLAUDE.md` / `AGENTS.md` 每回合都在。把下面這段貼進去（依專案調整指令與契約名稱）：

```markdown
## 委派角色（sub agents，本體在 `.agents/roles/`）

scout 找、runner 跑、reviewer 挑、worker 做、architect 判（見 `.agents/roles/README.md`）。

**主動派工，不必等使用者點名**：
- 跨多檔／多目錄的搜尋、找同一份邏輯的其他實作 → `scout`
- 會吐大量輸出或耗時超過一兩分鐘的指令 → `runner`（輸出不進主 context 是重點）
- 改動達 3 檔以上、或動到對外契約的 diff → `reviewer`
- spec 已明確且與主線討論脫鉤的實作 → `worker`
- 要動 API 形狀 / schema / 部署順序，或有多個做法要取捨 → `architect`

**不要派**：已知檔案的單點查詢、一兩行的改動、需要當下對話脈絡才判斷得出來的問題——sub agent 拿不到這段對話，把背景重打一遍比自己做還慢，而且它只回摘要、細節會遺失。
```

⚠ 有些 session 會被 host 端關掉自動派工（system prompt 出現「不要主動呼叫 Agent tool」之類的指令），此時上面兩層都無效、只能點名。這與本 repo 的設定無關。
第三層是**確定性觸發**：在 skill 本文寫死「派給 `runner` agent 跑驗證」，走到那步一定派，不看描述比對。

## 呼叫

| | Claude Code | Codex |
|---|---|---|
| 派工 | Agent tool，`subagent_type` 填角色名 | `.codex/agents/<r>.toml` 定義的 agent |

主對話負責決定派誰、給多少脈絡；角色只在自己的邊界內回報，不互相呼叫。
