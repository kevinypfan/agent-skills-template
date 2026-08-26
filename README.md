# agent-skills-template

Claude Code 與 Codex **共用**的 repo-local 骨架：一組 issue-flow skill（GitLab / GitHub 通吃）＋五個委派角色（sub agent）。
兩邊的行為只寫一份，各自的工具設定檔是薄 stub，由腳本產生 / 由守門逐字比對。

```
.agents/
├── conventions.md          ← 複製後唯一要改的檔（分支、label、測試指令…）
├── skills/
│   ├── README.md           ← 寫作規則
│   ├── _tracker/           ← glab / gh 指令對照（非 skill）
│   └── create-issue/  create-worktree/  fix-issue/  commit-push-pr/  ask-agents/
└── roles/                  ← 委派角色本體（唯一指令真相）
    └── scout  runner  reviewer  worker  architect
.claude/skills/             ← 產生的 Claude skill stub（勿手改）
.claude/agents/             ← Claude sub agent stub（model / tools 在這）
.codex/agents/              ← Codex agent stub（model / effort / sandbox 在這）
scripts/
├── generate-skill-stubs.sh ← skill 真身 → stub
├── check-skill-stubs.sh    ← 守門（skill stub + agent 三集合一致性）
└── pre-commit-skill-guard.sh
```

## 套用到專案

1. 複製 `.agents/`、`.claude/skills/`、`.claude/agents/`、`.codex/agents/`、`scripts/` 到 repo 根（或 GitHub「Use this template」）。
2. 填 `.agents/conventions.md`（至少 `base_branch`；有 label / 測試指令就填）。
3. 調 model：`.claude/agents/*.md` 的 `model`、`.codex/agents/*.toml` 的 `model` / `model_reasoning_effort` 換成你帳號可用的；語言宣告依 conventions 的 `language`。
4. 想讓角色被自動派（而非每次點名），把 `.agents/roles/README.md`「讓它自動被派」那段的政策片段貼進 repo 根的 `CLAUDE.md` / `AGENTS.md`。
5. 裝 pre-commit 守門（二選一）：
   - husky：`.husky/pre-commit` 加一行 `sh scripts/pre-commit-skill-guard.sh`
   - 無 husky：`mkdir .githooks && printf '#!/bin/sh\nsh scripts/pre-commit-skill-guard.sh\n' > .githooks/pre-commit && chmod +x .githooks/pre-commit && git config core.hooksPath .githooks`
6. `bash scripts/check-skill-stubs.sh` 應印 ✓。
7. 確認 CLI：GitLab 專案 `glab auth status`、GitHub 專案 `gh auth status`。`ask-agents` 另需 `codex` / `claude` / `agy`。

## 呼叫

| | Claude Code | Codex |
|---|---|---|
| skill | `/create-issue …` | `$create-issue …` |
| 角色 | Agent tool，`subagent_type` 填角色名 | `.codex/agents/<r>.toml` 的 agent |
| 前提 | 無 | Codex 需 trust 此專案才會載入 `.agents/` |

skill 流程：`create-issue` → `create-worktree` → （新 session）`fix-issue` → `commit-push-pr`。
角色分工：**scout 找、runner 跑、worker 做、reviewer 挑、architect 判**（詳見 `.agents/roles/README.md`）。
角色的 `description` 帶觸發語，主對話比對到就自己派；要更可靠再加 `CLAUDE.md` 政策段與 skill 本文的確定性派工。

## 新增自己的 skill / 角色

- skill：`mkdir .agents/skills/<name>` 寫 `SKILL.md`（規則見 `.agents/skills/README.md`）→ `bash scripts/generate-skill-stubs.sh` → commit。
- 角色：`.agents/roles/<r>.md` 寫本體，再手寫 `.claude/agents/<r>.md` 與 `.codex/agents/<r>.toml` 兩份 stub（本文是 canonical 一句，守門逐字比對）→ commit。

守門會擋：stub 與產生器輸出不符、手改 stub 本文、兩邊 description 不一致、讀寫權限兩邊不對稱、純讀角色本體漏掉唯讀守則句、skill 真身硬編 `glab` / `gh` 或用了 Claude 專屬 macro。

## 已知未含

- **review 類 skill**（在 PR diff 上留 inline comment、回覆 / resolve thread）：GitLab 與 GitHub 的 inline API 語意不對等（GitHub resolve 只有 GraphQL），本版 `_tracker/*.md` 的「inline comment」節標為未提供，`commit-push-pr` 遇到會跳過該步。
