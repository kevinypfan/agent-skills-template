# Agent roles（Claude Code 與 Codex 共用）

本目錄是委派角色的**唯一指令真相**。兩個工具各自只放薄 stub，行為只寫在本體。

| 角色 | 本體 | Claude stub | Codex stub | 可寫檔 |
|---|---|---|---|---|
| scout | `scout.md` | `.claude/agents/scout.md`（haiku） | `.codex/agents/scout.toml`（低 effort） | ✗ |
| runner | `runner.md` | `.claude/agents/runner.md`（sonnet） | `.codex/agents/runner.toml`（中 effort） | ✗（sandbox 例外見下） |
| reviewer | `reviewer.md` | `.claude/agents/reviewer.md`（opus） | `.codex/agents/reviewer.toml`（高 effort） | ✗ |
| worker | `worker.md` | `.claude/agents/worker.md`（sonnet） | `.codex/agents/worker.toml`（中 effort） | ✓ |
| architect | `architect.md` | `.claude/agents/architect.md`（fable） | `.codex/agents/architect.toml`（高 effort） | ✗ |

原則：**便宜 model 找與做、貴 model 判**。改行為改本體；改 model / effort / 權限改對應 stub。
stub 裡的 model 名是範例，依預算調整。Claude 端寫別名（`haiku` / `sonnet` / `fable` / `opus`），CLI 自動用該系列最新版、不必維護；Codex 端沒有別名，填 slug（可用清單見 `~/.codex/models_cache.json`），**換代時要手動改**。目前 Codex 配置：scout `gpt-5.6-luna`、runner / worker `gpt-5.6-terra`、reviewer `gpt-5.6-sol`、architect `gpt-6-astra`。

## 共同守則（各角色本體不再重述）

- 唯讀角色（scout / runner / reviewer / architect）**不改任何檔案**。這是 best-effort 邊界、不是安全保證：Claude stub 的 `tools` 白名單只拿掉 Edit/Write（Bash 仍能 `sed -i` / 重導向 / `git add`）、Codex 的 `sandbox_mode = "read-only"` 會被 parent turn 的 full-access 覆蓋；真正的防線是各純讀本體逐字都有的守則句「Bash 只用於唯讀指令；不重導向寫檔、不 `sed -i`、不 `git add`」（`check-skill-stubs.sh` 強制存在）＋使用者端 permission。
- **runner 是刻意的例外**：建置 / 測試工具要寫 build 產物（`target/`、`.next/`、coverage…），Codex 端必須 `workspace-write` 才跑得動，Claude 端仍不給 Edit/Write。check script 對此有 allowlist。
- Claude stub（`.claude/agents/<r>.md`）本文**只能是**指回本體的 canonical 段（先 repo 根 `.agents/roles/<r>.md`、沒有才 `~/.agents/roles/<r>.md`；check 逐字比對，刻意不留補充空間）；Codex toml 的 `developer_instructions` 可加補充行，但 canonical 三句不可改寫。全域安裝見根 `README.md`。
- Codex toml 末尾的語言宣告依 `.agents/conventions.md` 的 `language` 調整——Codex 沒有 `CLAUDE.md` 那層語言政策，不宣告就會回英文；Claude 端由根 `CLAUDE.md` / `AGENTS.md` 覆蓋。
- 本體與 stub 內的相對路徑一律相對 repo 根（`git rev-parse --show-toplevel`）；從子目錄啟動工具時先回到根。
- 專案專屬的值（測試指令、分支、label）一律寫「conventions 的 `<key>`」，不硬編在本體。
- 所有角色**未經 spec 明示不 commit / push / 開 PR / deploy**。
- **不是唯一在 worktree 工作的 agent**：主線與其他角色可能同時在動同一個 worktree（主線等結果時會繼續工作）。runner / worker 本體逐字都有守則句「你不是唯一在這個 worktree 工作的 agent：不還原、不覆蓋、不 stash 不是你做的改動」（`check-skill-stubs.sh` 對會寫檔或跑建置的角色強制存在）。
- architect / reviewer / worker 開工前讀專案擴充點：context（reviewer 另讀 review）。canonical 句直接寫在各角色本體（stub 只載入本體；也讓守門涵蓋角色），機制見 `.agents/extensions/README.md`。擴充檔不得要求本次改動範圍以外的寫入（merge、deploy、改 tracker、觸發 job）。scout / runner 不讀擴充點。

## 讓它自動被派（兩個層次）

主對話會拿使用者的請求比對每個 stub 的 `description`，命中就自己派——**這是預設行為，不必點名**。但描述比對只是機率，兩件事要做：

1. **description 帶觸發語**：本 template 的五個 stub 都寫成「…。主動使用：<什麼情境>，不必等使用者點名」。你新增角色時照這個形狀寫，只描述「我是誰」的 description 命中率很低。
2. **把政策放進永遠在 context 的檔案**（全域安裝已由 `global/AGENT-ROLES.md` 處理；以下是單一 repo 版）：`description` 只在工具選擇時參與比對，而 repo 根的 `CLAUDE.md` / `AGENTS.md` 每回合都在。把下面這段貼進去（依專案調整指令與契約名稱）：

```markdown
## 委派角色（sub agents，本體在 `.agents/roles/`）

scout 找、runner 跑、reviewer 挑、worker 做、architect 判（見 `.agents/roles/README.md`）。

**主動派工，不必等使用者點名**：
- 跨多檔／多目錄的搜尋、找同一份邏輯的其他實作 → `scout`
- 會吐大量輸出或耗時超過一兩分鐘的指令 → `runner`（輸出不進主 context 是重點）；改完 code 後的 test／lint／build 一律派，不因為指令小就自己跑
- 改動達 3 檔以上、或動到對外契約的 diff → `reviewer`
- spec 已明確且與主線討論脫鉤的實作 → `worker`
- 要動 API 形狀 / schema / 部署順序，或有多個做法要取捨 → `architect`

**派出去就不等**：派工前用一行告訴使用者派了什麼、為什麼（不必等回覆；使用者回「你做」就收回自己做）。派出去後主線繼續做不依賴結果的事，結果回來再判讀；等待期間不改交辦範圍內的檔案。交辦內容照 `.agents/roles/README.md`「交辦模板」給齊。

**不要派**：已知檔案的單點查詢、一兩行的改動、需要當下對話脈絡才判斷得出來的問題——sub agent 拿不到這段對話，把背景重打一遍比自己做還慢，而且它只回摘要、細節會遺失。
```

⚠ 有些 session 會被 host 端關掉自動派工（system prompt 出現「不要主動呼叫 Agent tool」之類的指令），此時上面兩層都無效、只能點名。這與本 repo 的設定無關。
第三層是**確定性觸發**：在 skill 本文寫死「派給 `runner` agent 跑驗證」，走到那步一定派，不看描述比對。

## 交辦模板

主線派工時照這個形狀寫（sub agent 拿不到對話，缺一項它就只能猜）：

```text
目標：<一句話，要達成什麼>
背景：<它需要知道、但讀檔讀不出來的決定與前提>
可改範圍：<檔案／目錄；runner、唯讀角色寫「不改檔」>
禁止碰：<明確排除的檔案、指令、外部寫入>
完成條件：<怎樣算做完>
驗證：<要跑的指令，或要附的證據>
回報：改了什麼（路徑）、驗證結果、未解風險；不貼整檔
```

## 派出去之後：主線不等

背景派工的價值在於主線不閒著。派出去後主線做**不依賴結果**的事：self-review 自己的 diff、草擬 commit message／PR 描述、讀下一步要動的檔案、回答使用者。邊界：

- **交辦範圍內的檔案，主線在等待期間不改**——runner 測到一半檔案變了，結果就不可信；worker 改到一半主線也改，會互相覆蓋。真的要改就先等它回來。
- 依賴結果的下一步（commit、push、宣告完成）一定等結果回來、主線判讀後才做。
- **決定能否 commit 的那次驗證**，派出前所有 writer（主線、worker）都要停手；主線不改檔只約束主線自己，平行的 worker 仍可能改到受測的共用檔。
- **綠燈要綁定內容**：runner 回報測試前後的內容指紋（`.agents/roles/worktree-fingerprint.sh`）。前後不同時看 runner 列的變動路徑：有 source → 結果作廢、重派；只有測試產生的建置產物 → 結果有效、以測試後的指紋為準，並提醒使用者補 `.gitignore`（不這樣判，產物每跑一次都會變，會無限重派）。主線 commit 前再算一次，與綠燈那次相同才能用；之後又改了檔（含 commit 前 self-review 的修正），就重派驗證。
- 平行派多個 worker 時，可改範圍必須互斥；切不開就不要平行。formatter 也只能對各自範圍內的檔案跑；要整包格式化，等所有 writer 停手後由單一 agent 做。
- 同一個建置輸出目錄（`target/`、`dist/`）不要同時跑兩個 build。
- runtime 的 sub agent 呼叫會阻塞（沒有背景執行）時，照常等結果即可；上面的邊界照樣適用。

## 呼叫

| | Claude Code | Codex |
|---|---|---|
| 派工 | Agent tool，`subagent_type` 填角色名 | `.codex/agents/<r>.toml` 定義的 agent |

主對話負責決定派誰、給多少脈絡；角色只在自己的邊界內回報，不互相呼叫。
