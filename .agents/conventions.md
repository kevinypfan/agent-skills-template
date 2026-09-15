# 專案慣例（複製 template 後**只需改這一檔**）

所有 issue-flow skill 執行時先讀本檔取值；本檔沒寫的就用「預設」欄。
skill 本文**不得**硬編這些值，改值一律改這裡。

| key | 預設 | 本專案值 | 用途 |
|---|---|---|---|
| `tracker` | `auto` | `auto` | `auto` = `git remote get-url origin` 含 `github.com` → GitHub，否則 GitLab；可強制 `gitlab` / `github`。偵測細節見 `.agents/skills/_tracker/README.md` |
| `base_branch` | `main` | `main` | 開發分支：worktree 的 base、PR 的 target |
| `worktree_root` | `<repo 父目錄>/<repo 目錄名>-worktrees` | （同預設） | `create-worktree` 放 worktree 的目錄，子目錄 `issue-<number>-<slug>`（slug 與 branch 共用，見 `create-worktree`） |
| `branch_prefix` | `fix/` `feat/` `chore/` | （同預設） | 依 issue label 對應的分支前綴，規則見 `create-worktree` |
| `issue_labels_required` | （無） | | `create-issue` 每張 issue 必加的 label（逗號分隔；如 `team::backend`） |
| `issue_labels_type` | `bug` `feature` `maintenance` `doc` | | type label 名稱；tracker 有 scoped label（GitLab `type::bug`）就寫完整名 |
| `issue_labels_optional` | （無） | | priority / component 等選填 label 表，格式自由（skill 只在使用者提到時套用） |
| `pr_labels` | （無） | | `commit-push-pr` 建 PR 時加的 label |
| `pr_assignee` | `@me` | | 建 PR 的 assignee |
| `commit_scopes` | （無） | | Conventional Commits 的合法 scope 清單（如 `api, parser, web`）；空 = 不限制 |
| `commit_language` | 依 `git log` 主要語言 | （同預設） | commit message 的語言：看 `git log -30 --format=%s` 多數 subject 用哪種語言；repo 無歷史則英文。可強制寫 `英文` / `繁體中文` |
| `commit_trailer` | `Co-Authored-By: <agent>` | | commit message 結尾 trailer。Claude Code 用 `Co-Authored-By: Claude <noreply@anthropic.com>`；Codex 用 `Co-Authored-By: Codex <noreply@openai.com>` |
| `verify_commands` | （無） | | `commit-push-pr` Step 2.5 的驗證閘門：`<觸發條件（git status 路徑 regex）> → <指令>`，可多列。空 = 跳過閘門。範例：`^.{2} crates/.*\.rs$ → cd crates && make test` |
| `test_command` | （無） | | `fix-issue` Step 3 跑的測試指令（可依路徑分列） |
| `lint_command` | （無） | | `fix-issue` Step 3 跑的 lint 指令 |
| `language` | 繁體中文 | | 對話、issue、PR 內文的語言；commit message 語言另見 `commit_language` |

## 範例（填好的樣子）

```
tracker: gitlab
base_branch: develop
issue_labels_required: team::backend
issue_labels_type: type::bug, type::feature, type::maintenance, type::doc
issue_labels_optional:
  priority: priority::0（hotfix）… priority::3（有空再做）
  component: comp::api / comp::worker / comp::web
pr_labels: team::backend
commit_scopes: api, worker, web, infra
verify_commands:
  ^.{2} services/.*\.go$ → go test ./...
  ^.{2} web/.*\.tsx?$ → pnpm --filter web test
test_command: pnpm test <files>（TS）/ go test ./...（Go）
lint_command: pnpm run lint（TS）/ golangci-lint run（Go）
```

## repo 沒有本檔時（全域安裝）

你讀的若是 `~/.agents/conventions.md`——代表 repo 根沒有自己的 `.agents/conventions.md`、skill / 角色是從全域安裝來的——上表「本專案值」欄與上面的範例**都不適用**（那是 template 的示範值）。逐 key 依下表從**當前 repo** 推斷：

| key | 推斷方式 |
|---|---|
| `tracker` | 照上表 `auto` 規則 |
| `base_branch` | `git symbolic-ref --short refs/remotes/origin/HEAD` 去掉 `origin/`；失敗再依序看 `main` / `master` / `develop` 是否存在 |
| `worktree_root` / `branch_prefix` | 用「預設」欄；`git branch -r` 若明顯用別的前綴（如 `feature/`），跟著 repo |
| `issue_labels_*` / `pr_labels` | **不推斷**。要用時問使用者；不要自創 label |
| `pr_assignee` | `@me` |
| `commit_scopes` | 不限制，但 scope 盡量沿用 `git log -30 --format=%s` 已出現過的 |
| `commit_language` | 照上表規則 |
| `commit_trailer` | host 有給 commit attribution 指示（如 Claude Code 的 system reminder）就用 host 的；否則「預設」欄 |
| `test_command` / `lint_command` / `verify_commands` | 依序找第一個有寫的來源：repo 規範檔（`CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md`）→ `Makefile` 的 test / check / lint target → `package.json` scripts → `Cargo.toml`（`cargo test` / `cargo clippy`）→ `pyproject.toml`（pytest / ruff）→ `.github/workflows` / `.gitlab-ci.yml` 實際跑的指令。多語言 repo 依改動路徑分列 |
| `language` | repo 規範檔的語言政策；沒寫就用「預設」欄 |

規則：
- 推斷出來的值在預覽 / 回報裡標「（推斷自 <來源>）」，讓使用者一眼看出哪些不是設定值。
- 推斷不出、而當下步驟又必須用到 → 停下來問使用者，不要套示範值硬做。
- 同一 repo 反覆用到、推斷又不穩時，建議使用者在 repo 放一份 `.agents/conventions.md` 固定下來。
