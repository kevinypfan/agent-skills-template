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

## 呼叫

| | Claude Code | Codex |
|---|---|---|
| 派工 | Agent tool，`subagent_type` 填角色名 | `.codex/agents/<r>.toml` 定義的 agent |

主對話負責決定派誰、給多少脈絡；角色只在自己的邊界內回報，不互相呼叫。
