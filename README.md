# agent-skills-template

Claude Code 與 Codex **共用**的骨架：一組 issue-flow skill（GitLab / GitHub 通吃）＋五個委派角色（sub agent）。
可以**複製進單一 repo**，也可以**全域安裝**到家目錄給所有專案共用（兩種可並存，專案版優先）。
兩邊的行為只寫一份，各自的工具設定檔是薄 stub，由腳本產生 / 由守門逐字比對。

```
.agents/
├── conventions.md          ← 複製後唯一要改的檔（分支、label、測試指令…）
├── skills/
│   ├── README.md           ← 寫作規則
│   ├── _tracker/           ← glab / gh 指令對照（非 skill）
│   ├── _multiplexer/       ← herdr 等 terminal multiplexer 指令對照（非 skill）
│   └── create-issue/  create-worktree/  fix-issue/  commit-push-pr/  orchestrate-issues/  ask-agents/
└── roles/                  ← 委派角色本體（唯一指令真相）
    └── scout  runner  reviewer  worker  architect
.claude/skills/             ← 產生的 Claude skill stub（勿手改）
.claude/agents/             ← Claude sub agent stub（model / tools 在這）
.codex/agents/              ← Codex agent stub（model / effort / sandbox 在這）
scripts/
├── generate-skill-stubs.sh ← skill 真身 → stub
├── check-skill-stubs.sh    ← 守門（skill stub + agent 三集合一致性 + 讓位段）
├── pre-commit-skill-guard.sh
├── install-global.sh       ← 全域安裝（~/.agents、~/.claude、~/.codex）
└── post-change-sync.sh     ← git hook 呼叫：已全域安裝時自動同步
global/
└── AGENT-ROLES.md          ← 全域派工政策（Claude 用 @import、Codex 寫進 ~/.codex/AGENTS.md 區塊）
.githooks/                  ← pre-commit 守門 + post-commit/merge/checkout/rewrite 自動同步
```

## 套用到專案

1. 複製 `.agents/`、`.claude/skills/`、`.claude/agents/`、`.codex/agents/`、`scripts/` 到 repo 根（或 GitHub「Use this template」）。
2. 填 `.agents/conventions.md`（至少 `base_branch`；有 label / 測試指令就填）。
3. 調 model：`.claude/agents/*.md` 的 `model`、`.codex/agents/*.toml` 的 `model` / `model_reasoning_effort` 換成你帳號可用的；語言宣告依 conventions 的 `language`。Claude 用別名會自動跟上新版；**Codex 沒有別名，換代時要手動改 toml 與 `ask-agents`**（見 `.agents/roles/README.md`）。
4. 想讓角色被自動派（而非每次點名），把 `.agents/roles/README.md`「讓它自動被派」那段的政策片段貼進 repo 根的 `CLAUDE.md` / `AGENTS.md`。
5. 裝 pre-commit 守門（二選一）：
   - husky：`.husky/pre-commit` 加一行 `sh scripts/pre-commit-skill-guard.sh`
   - 無 husky：`mkdir .githooks && printf '#!/bin/sh\nsh scripts/pre-commit-skill-guard.sh\n' > .githooks/pre-commit && chmod +x .githooks/pre-commit && git config core.hooksPath .githooks`
6. `bash scripts/check-skill-stubs.sh` 應印 ✓。
7. 確認 CLI：GitLab 專案 `glab auth status`、GitHub 專案 `gh auth status`。`ask-agents` 另需 `codex` / `claude` / `agy`。

## 全域安裝（所有專案共用）

```bash
bash scripts/install-global.sh            # dry-run：列出會建立 / 更新哪些項目、哪些目標已存在（衝突不覆寫）
bash scripts/install-global.sh --apply    # 執行；--no-codex 略過 ~/.codex/agents
bash scripts/install-global.sh --uninstall  # 只移除本腳本裝的項目
```

本 repo 是所有專案共用的來源，改壞會立刻影響全部專案——clone 後先 `git config core.hooksPath .githooks`：啟用 pre-commit 守門，以及 commit / merge / checkout / rebase 後自動重跑 `--apply --quiet`（只在本機已全域安裝時動作，改完 Codex toml 或派工政策不必記得手動同步）。

**派工政策**（`global/AGENT-ROLES.md`，讓主對話主動派 scout / runner…）一併安裝：Claude 端 symlink 到 `~/.claude/AGENT-ROLES.md` 並在 `~/.claude/CLAUDE.md` 加一行 `@AGENT-ROLES.md`；Codex 的 `AGENTS.md` 沒有 import，改寫進 `~/.codex/AGENTS.md` 的標記區塊（檔內其他內容不動，`--uninstall` 只拿掉該區塊）。新增角色時要在政策裡點名，守門會檢查。

**換機器**：clone 本 repo → `git config core.hooksPath .githooks` → `bash scripts/install-global.sh --apply`，就這樣。

裝完後，沒有自己版本的專案直接可用；**有同名客製版的專案仍跑專案版**。同名時兩個工具的優先序不同，所以用了三層處理：

| 同名情境 | 工具行為 | 本 template 的處理 |
|---|---|---|
| Claude agent | 專案 `.claude/agents/` > 全域 | 天然專案優先；全域 stub 也會先找 repo 的 `.agents/roles/<r>.md` |
| Claude skill | **全域 `~/.claude/skills/` > 專案** | 全域版照樣被載入，但真身開頭「先決定照哪一份跑」讓位段會改讀 repo 的 `.agents/skills/<s>/SKILL.md` 或客製 `.claude/skills/<s>/SKILL.md` |
| Codex skill | 兩份並列 | 同上讓位段 |
| Codex agent | 官方未說明；**不載入 symlink 的 toml** | `~/.codex/agents/` 改用複製（首行有標記）；stub 先找 repo 的角色本體 |

- repo 沒有 `.agents/conventions.md` 時，skill / 角色讀到的是 `~/.agents/conventions.md`，照其「repo 沒有本檔時」段從 repo 推斷（`git log` 語言、`Makefile` / `package.json` 指令…），推斷值會標註來源。
- **個人設定放 `~/.agents/conventions.local.md`**（只列要覆寫的 key，格式見 `.agents/conventions.md`「寫入規則」）。優先序：專案 `.agents/conventions.md` > 個人 local 檔 > template 預設／推斷。**不要改 `~/.agents/conventions.md`**——它是指回本 repo 的 symlink，改了等於改 template、會被 commit 成所有人的預設。`install-global.sh` 不建立也不刪除 local 檔；`orchestrate-issues` 首次使用時的引導設定預設就存到這裡。
- 讓位時用的是專案版的**流程**，但觸發比對（description）在 Claude 端用的是全域版的。
- symlink 指向本 repo 的 working tree：本 repo 切到哪個分支，全域就生效哪個版本。**例外是複製 / 區塊項目**（Codex agent、`~/.codex/AGENTS.md`）：靠上面的 git hook 自動同步；沒啟用 hook 就手動重跑 `--apply`，dry-run 會標「過期」。
- skill 讓位段判斷「全域版」的依據是**檔案不在當前 repo 內**，而不是路徑字面是 `~/.agents`——Codex 會把 symlink 解析成本 repo 的實際路徑顯示。

## 呼叫

| | Claude Code | Codex |
|---|---|---|
| skill | `/create-issue …` | `$create-issue …` |
| 角色 | Agent tool，`subagent_type` 填角色名 | `.codex/agents/<r>.toml` 的 agent |
| 前提 | 無 | Codex 需 trust 此專案才會載入 `.agents/` |

skill 流程：`create-issue` → `create-worktree` → （新 session）`fix-issue` → `commit-push-pr`。

**調度模式**（一次處理多個 issue）：主 session 呼叫 `orchestrate-issues`，它依檔案重疊分線，用 terminal multiplexer（目前支援 herdr；不在 multiplexer 內時退化成只建 worktree、請你自己開 session）替每條線開 worktree + agent session 跑 `fix-issue`，並監看各線、把關 review / CI / merge、收尾：

```
orchestrate-issues（主 session）
├── 分線 → 方向決策寫進 issue 留言
├── lane A: worktree + session → fix-issue → commit-push-pr ─┐
├── lane B: worktree + session → fix-issue → commit-push-pr ─┤
│                                                            ▼
└── 監看各線 → PR 關卡（reviewer / CI / merge）→ 收尾（移除 worktree、刪分支）
```

merge 預設要問你（`auto_merge`）；yolo mode（`agent_start_args`）預設關閉。首次使用會引導設定這些 key 並記住。
角色分工：**scout 找、runner 跑、worker 做、reviewer 挑、architect 判**（詳見 `.agents/roles/README.md`）。
角色的 `description` 帶觸發語，主對話比對到就自己派；要更可靠再加 `CLAUDE.md` 政策段與 skill 本文的確定性派工。

## 新增自己的 skill / 角色

- skill：`mkdir .agents/skills/<name>` 寫 `SKILL.md`（規則見 `.agents/skills/README.md`）→ `bash scripts/generate-skill-stubs.sh` → commit。
- 角色：`.agents/roles/<r>.md` 寫本體，再手寫 `.claude/agents/<r>.md` 與 `.codex/agents/<r>.toml` 兩份 stub（本文是 canonical 一句，守門逐字比對）→ commit。

守門會擋：stub 與產生器輸出不符、手改 stub 本文、兩邊 description 不一致、讀寫權限兩邊不對稱、純讀角色本體漏掉唯讀守則句、skill 真身硬編 `glab` / `gh`、出現 multiplexer CLI 名（`herdr`）或用了 Claude 專屬 macro、skill 真身缺讓位段。

## 已知未含

- **review 類 skill**（在 PR diff 上留 inline comment、回覆 / resolve thread）：GitLab 與 GitHub 的 inline API 語意不對等（GitHub resolve 只有 GraphQL），本版 `_tracker/*.md` 的「inline comment」節標為未提供，`commit-push-pr` 遇到會跳過該步。
