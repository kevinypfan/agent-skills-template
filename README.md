# agent-skills-template

Claude Code 與 Codex **共用**的 repo-local skill 骨架 + 一組 issue-flow skill（GitLab / GitHub 通吃）。

```
.agents/
├── conventions.md          ← 複製後唯一要改的檔（分支、label、測試指令…）
└── skills/
    ├── README.md           ← 寫作規則
    ├── _tracker/           ← glab / gh 指令對照（非 skill）
    ├── create-issue/  create-worktree/  fix-issue/  commit-push-pr/  ask-agents/
.claude/skills/             ← 產生的 Claude stub（勿手改）
scripts/
├── generate-skill-stubs.sh ← 真身 → stub
├── check-skill-stubs.sh    ← pre-commit 守門
└── pre-commit-skill-guard.sh
```

## 套用到專案

1. 複製 `.agents/`、`.claude/skills/`、`scripts/` 三個目錄到 repo 根（或 GitHub「Use this template」）。
2. 填 `.agents/conventions.md`（至少 `base_branch`；有 label / 測試指令就填）。
3. 裝 pre-commit 守門（二選一）：
   - husky：`.husky/pre-commit` 加一行 `sh scripts/pre-commit-skill-guard.sh`
   - 無 husky：`mkdir .githooks && printf '#!/bin/sh\nsh scripts/pre-commit-skill-guard.sh\n' > .githooks/pre-commit && chmod +x .githooks/pre-commit && git config core.hooksPath .githooks`
4. `bash scripts/check-skill-stubs.sh` 應印 ✓。
5. 確認 CLI：GitLab 專案 `glab auth status`、GitHub 專案 `gh auth status`。`ask-agents` 另需 `codex` / `agy`。

## 呼叫

| | Claude Code | Codex |
|---|---|---|
| 呼叫 skill | `/create-issue …` | `$create-issue …` |
| 前提 | 無 | Codex 需 trust 此專案才會載入 `.agents/` |

流程：`create-issue` → `create-worktree` → （新 session）`fix-issue` → `commit-push-pr`。

## 新增自己的 skill

1. `mkdir .agents/skills/<name>`，寫 `SKILL.md`（照 `.agents/skills/README.md` 規則，frontmatter 至少 `name` + `description`）。
2. `bash scripts/generate-skill-stubs.sh`。
3. commit（守門會自動跑）。

## 已知未含

- **review 類 skill**（在 PR diff 上留 inline comment、回覆 / resolve thread）：GitLab 與 GitHub 的 inline API 語意不對等（GitHub resolve 只有 GraphQL），本版 `_tracker/*.md` 的「inline comment」節標為未提供，`commit-push-pr` 遇到會跳過該步。
- **委派角色**（scout / reviewer / worker…）的 `.claude/agents` + `.codex/agents` 雙 stub 機制：另案。
