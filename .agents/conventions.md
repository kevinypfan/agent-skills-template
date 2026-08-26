# 專案慣例（複製 template 後**只需改這一檔**）

所有 issue-flow skill 執行時先讀本檔取值；本檔沒寫的就用「預設」欄。
skill 本文**不得**硬編這些值，改值一律改這裡。

| key | 預設 | 本專案值 | 用途 |
|---|---|---|---|
| `tracker` | `auto` | `auto` | `auto` = `git remote get-url origin` 含 `github.com` → GitHub，否則 GitLab；可強制 `gitlab` / `github`。偵測細節見 `.agents/skills/_tracker/README.md` |
| `base_branch` | `main` | `main` | 開發分支：worktree 的 base、PR 的 target |
| `worktree_root` | `<repo 父目錄>/<repo 目錄名>-worktrees` | （同預設） | `create-worktree` 放 worktree 的目錄，子目錄固定 `issue-<number>` |
| `branch_prefix` | `fix/` `feat/` `chore/` | （同預設） | 依 issue label 對應的分支前綴，規則見 `create-worktree` |
| `issue_labels_required` | （無） | | `create-issue` 每張 issue 必加的 label（逗號分隔；如 `team::backend`） |
| `issue_labels_type` | `bug` `feature` `maintenance` `doc` | | type label 名稱；tracker 有 scoped label（GitLab `type::bug`）就寫完整名 |
| `issue_labels_optional` | （無） | | priority / component 等選填 label 表，格式自由（skill 只在使用者提到時套用） |
| `pr_labels` | （無） | | `commit-push-pr` 建 PR 時加的 label |
| `pr_assignee` | `@me` | | 建 PR 的 assignee |
| `commit_scopes` | （無） | | Conventional Commits 的合法 scope 清單（如 `api, parser, web`）；空 = 不限制 |
| `commit_trailer` | `Co-Authored-By: <agent>` | | commit message 結尾 trailer。Claude Code 用 `Co-Authored-By: Claude <noreply@anthropic.com>`；Codex 用 `Co-Authored-By: Codex <noreply@openai.com>` |
| `verify_commands` | （無） | | `commit-push-pr` Step 2.5 的驗證閘門：`<觸發條件（git status 路徑 regex）> → <指令>`，可多列。空 = 跳過閘門。範例：`^.{2} crates/.*\.rs$ → cd crates && make test` |
| `test_command` | （無） | | `fix-issue` Step 3 跑的測試指令（可依路徑分列） |
| `lint_command` | （無） | | `fix-issue` Step 3 跑的 lint 指令 |
| `language` | 繁體中文 | | 對話、issue、PR 內文的語言；commit message 一律英文 |

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
