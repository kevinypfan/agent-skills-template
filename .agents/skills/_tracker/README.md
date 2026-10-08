# `_tracker` — issue tracker 指令對照層

本目錄**不是 skill**（沒有 `SKILL.md`，產生器與守門腳本跳過 `_` 開頭目錄）。
issue-flow 的 skill 本文只寫**動作名**（如「[tracker] 看 issue」），執行時到這裡查該 tracker 的實際指令與 JSON 欄位。
新增第三種 tracker（Gitea、Bitbucket…）= 多一份 `<name>.md`，skill 不用改。

## 判斷用哪個 tracker

1. 讀 `.agents/conventions.md` 的 `tracker`。是 `gitlab` / `github` 就直接用對應檔。
2. 是 `auto`（預設）：

```bash
git remote get-url origin
```

- URL 含 `github.com` → 讀 `.agents/skills/_tracker/github.md`（CLI：`gh`）
- 其他（含 self-hosted GitLab）→ 讀 `.agents/skills/_tracker/gitlab.md`（CLI：`glab`）

3. 開工前確認 CLI 在 PATH 且已登入（`gh auth status` / `glab auth status`）；沒有就停下來告訴使用者，不要退回 curl 硬打 API。

## 動作表（A 表）

| 動作 | GitLab（`glab`） | GitHub（`gh`） | 備註 |
|---|---|---|---|
| 列出 open issue | `glab issue list --output json --per-page 100` | `gh issue list --state open --limit 100 --json number,title,labels,url` | 調度盤點用 |
| 列出 open PR | `glab mr list --output json --per-page 100` | `gh pr list --state open --limit 100 --json number,title,headRefName,baseRefName,mergeable,mergeStateStatus,statusCheckRollup,closingIssuesReferences,url` | 含 head／base 分支；GitLab 的 CI 與可否合併要逐個「看 PR 可否合併」 |
| 看 issue（JSON） | `glab issue view <N> --output json` | `gh issue view <N> --json number,title,body,labels,url` | 欄位名不同，見各檔「JSON 欄位」 |
| 建 issue | `glab issue create --title --label --assignee --description` | `gh issue create --title --label --assignee --body` | GitLab `--description` ≡ GitHub `--body` |
| 查目前分支的 PR | `glab mr view "$BRANCH" --output json` | `gh pr view "$BRANCH" --json number,title,baseRefName,url,state` | 兩邊都以分支名查；不存在時非零 exit |
| 看 PR（JSON） | `glab mr view <N> --output json` | `gh pr view <N> --json number,title,body,author,baseRefName,headRefName,state,headRefOid,baseRefOid,url` | 標題、描述、作者、base／head、狀態、sha；欄位名不同，見各檔「看 PR（JSON）」 |
| 看 PR（含 comments） | `glab mr view <N> --comments` | `gh pr view <N> --comments` | |
| 找 repo 的 PR template | （檔案偵測）`git ls-files` | （檔案偵測）`git ls-files` | 路徑與順序見各檔「repo 的 PR template」；`commit-push-pr` 在 `pr_template: auto` 時用 |
| 建 PR | `glab mr create --title --target-branch --assignee --label --description --remove-source-branch` | `gh pr create --title --base --assignee --label --body` | GitHub 無 `--remove-source-branch`（repo 設定 auto-delete） |
| 更新 PR 描述 | `glab mr update <N> --description` | `gh pr edit <N> --body` | |
| 留 PR 總結 comment | `glab mr note <N> --message` | `gh pr comment <N> --body` | |
| 取自己帳號 | `glab api user`（`.username`） | `gh api user`（`.login`） | 過濾「自己留的 comment」用 |
| 檢查 token 權限 | `glab auth status` | `gh auth status`（看 Token scopes） | 見各檔「token 權限」；不足時請使用者補，不要改用別的帳號 |
| 在 issue 留言 | `glab issue note <N> --message` | `gh issue comment <N> --body-file <file>` | 記錄決定用；長內文先寫暫存檔 |
| 看 PR CI 狀態（含等待） | `glab ci status --branch <b> [--wait]` | `gh pr checks <N> [--watch]` | 0 個 check 常代表 PR 有衝突、CI 沒跑，見各檔 |
| 看 PR 會關閉哪些 issue | `glab api projects/:id/merge_requests/<N>/closes_issues`（`[].iid`） | `gh pr view <N> --json closingIssuesReferences`（`[].number`） | merge 前核對；只應包含這個 PR 完整解決的 issue。關鍵字規則見各檔「自動關閉關鍵字」 |
| 重新打開 issue | `glab issue reopen <N>` | `gh issue reopen <N> --comment <text>` | 被誤關時用；GitLab 另外 [tracker] 在 issue 留言說明 |
| 看 PR 可否合併 | `glab mr view <N> --output json`（`detailed_merge_status`、`has_conflicts`） | `gh pr view <N> --json mergeable,mergeStateStatus` | 可合併的判準見各檔 |
| merge PR | `glab mr merge <N> --auto-merge=false [--squash\|--rebase] --message` | `gh pr merge <N> --merge\|--squash\|--rebase --subject --body` | 方法依 conventions 的 `merge_method`；GitLab 務必 `--auto-merge=false` |
| 更新 PR 分支（base 併進來） | `glab mr rebase <N>`（會改寫歷史）或本地 merge base 後 push | `gh pr update-branch <N>`（merge，不 force push） | |
| 改 PR base | `glab mr update <N> --target-branch <b>` | `gh pr edit <N> --base <b>` | 疊分支的前一個 PR merge 後用 |
| 手動觸發 workflow / pipeline | `glab ci run --branch <b>` | `gh workflow run <file> --ref <b>` + `gh run watch <run>` | |
| 看失敗 job log | `glab ci trace <job-id>` | `gh run view <run> --job <job> --log-failed` | |
| 看 PR diff 版本（sha） | `glab mr view <N> --output json`（`diff_refs.{base_sha,head_sha,start_sha}`）；不用 `git merge-base` 推算 | `gh pr view <N> --json headRefOid,baseRefOid` | 留 inline 前先取；GitLab 要三個 sha，GitHub 只用 head。sha 在本地不存在時 fetch PR ref（GitHub `pull/<N>/head`、GitLab `merge-requests/<N>/head`），見各檔同節 |
| 列出 PR thread（含 resolved） | `glab api ".../merge_requests/<N>/discussions?per_page=100" --paginate`（多頁是串接陣列，要逐段解析） | GraphQL `reviewThreads`（可分頁） | 回傳 thread id、note id、resolved 狀態；解析細節見各檔。GitLab 的輸出只是索引，要完整 notes 需另取（見 `gitlab.md`） |
| 列出未解決 thread | 過濾 `notes[0].resolvable && !notes[0].resolved` | 過濾 `isResolved == false` | 同上 |
| 列出總結 comment | `glab api .../notes`，`system=false` 且無 `position` | `issues/<N>/comments` + `pulls/<N>/reviews` 的 body | 不含 inline thread |
| 在 diff 上留 inline comment（選用） | `POST discussions` 帶 `position`；JSON 用 `--input`，不可 `-f` 傳 nested | `POST pulls/<N>/comments`（`commit_id`、`path`、`line`、`side`） | 預設不留；行須在 diff 內，否則失敗，改走總結 comment |
| 回覆 thread | `POST discussions/<thread id>/notes` | `POST pulls/<N>/comments/<note id>/replies` | GitHub 的 `<note id>` 是 thread 首則 comment 的 `databaseId` |
| resolve / unresolve thread | `PUT discussions/<thread id> -f resolved=true\|false` | GraphQL `resolveReviewThread` / `unresolveReviewThread` | GitHub 要 thread node id，不是 `databaseId` |

## 術語對照

| 本 template 用詞 | GitLab | GitHub |
|---|---|---|
| PR | Merge Request（MR） | Pull Request |
| `<N>` | MR / issue 的 **iid**（專案內編號） | number |
| 開發分支（`base_branch`） | target branch | base branch |
| CI | pipeline | checks / workflow run |
| 總結 comment | note | issue comment |
| inline thread | discussion | review thread |
| thread id | discussion 的 `id` | review thread 的 GraphQL node `id`（`PRRT_…`） |
| note id | note 的 `id` | review comment 的 `databaseId`（REST 的 comment id） |

skill 本文與 PR 內文一律用「PR」；面對 GitLab 使用者口頭說 MR 也不用糾正。
