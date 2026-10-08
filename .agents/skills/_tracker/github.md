# GitHub（`gh`）指令細節

前提：`gh auth status` 通過；在 repo 目錄下執行（`gh` 由 `origin` 推 repo）。

## 看 issue

```bash
gh issue view <N> --json number,title,body,labels,url,state
```

JSON 欄位：`number`（編號）、`title`、`body`（內文）、`labels`（**物件陣列**，取 `.name`）、`url`、`state`。
使用者給的是 URL（`https://github.com/<owner>/<repo>/issues/<N>`）時取最後一段當 `<N>`；`gh issue view` 也直接吃 URL。

## 列出 open issue / open PR

```bash
gh issue list --state open --limit 100 --json number,title,labels,url
gh pr list --state open --limit 100 \
  --json number,title,headRefName,baseRefName,isDraft,mergeable,mergeStateStatus,statusCheckRollup,closingIssuesReferences,url
```

- `labels` 是物件陣列（取 `.name`）。
- PR 對應 issue：`closingIssuesReferences[].number`（PR 內文有 `Closes #N`）；沒有時再從 `headRefName` 的 `<prefix><N>-<slug>` 取編號。
- CI 概況：`statusCheckRollup[]` 的 `conclusion`（`SUCCESS` / `FAILURE`…）與 `status`（`IN_PROGRESS`…）；空陣列 = 沒跑 CI（常見原因是衝突）。
- issue 超過 100 個時加 `--label` / `--search` 縮小，或問使用者範圍。



```bash
gh issue create \
  --title "<title>" \
  --label "<label1>,<label2>" \
  --assignee "<assignee>" \
  --body "<內文>"
```

- label 逗號分隔；label **必須已存在於 repo**（`gh` 不會自動建，不存在會失敗——先 `gh label list` 確認）
- `--assignee "@me"` 可用
- 回傳 issue URL

## repo 的 PR template

`commit-push-pr` 在 `pr_template: auto` 時用。檔名大小寫不拘，用 `git ls-files` 比對（不要用 `test -f`，Linux 上會漏大小寫）：

```bash
git ls-files | grep -iE '^(\.github/|docs/)?pull_request_template\.md$'
git ls-files | grep -iE '^(\.github/|docs/)?pull_request_template/[^/]+\.md$'
```

1. 單檔 `pull_request_template.md`，依序找 `.github/`、repo 根、`docs/`，用第一份
2. 沒有單檔、但有 `PULL_REQUEST_TEMPLATE/` 目錄（同樣可在 `.github/`、根、`docs/`）→ GitHub 本身不會自動套用目錄裡的 template（要 `?template=` 指定），列出檔名問使用者要用哪一份或用內建版
3. 都沒有 → 用內建版

- `gh pr create --body` 會整個取代 repo template，內文要自己依 template 填好再帶進去

## 查目前分支的 PR

```bash
gh pr view "$(git branch --show-current)" --json number,title,baseRefName,url,state 2>/dev/null
```

成功 → JSON 有 `number`、`title`、`baseRefName`（= target）、`url`、`state`；失敗（非零 exit）= 尚無 PR。

## 建 PR

```bash
gh pr create \
  --title "<title>" \
  --base "<base_branch>" \
  --assignee "<pr_assignee>" \
  --label "<pr_labels>" \
  --body "<內文>"
```

- 無 `--remove-source-branch` 對應：由 repo 設定「Automatically delete head branches」決定
- `--label` 為空時整個 flag 省略
- fork 流程（head 在 fork）要加 `--head <user>:<branch>`；本 template 假設同 repo 分支

## 自動關閉關鍵字

PR 內文（以及 merge 進預設分支的 commit message）只要出現 **`close` / `closes` / `closed` / `fix` / `fixes` / `fixed` / `resolve` / `resolves` / `resolved` 緊接 `#N`**（大小寫不拘、不看上下文），PR merge 時 GitHub 就會關閉該 issue。

- 只完成 issue 一部分的 PR（例如拆成 core PR 與 bindings PR）**整份內文與 commit message 都不能出現上述組合**，連「PR 2 會 close #46」「屆時 close #46」這種敘述也會觸發（實際踩過：issue 被提早關閉）。改寫成 `Refs #N`、「完成後由 PR 2 關閉 issue #N」這類不含關鍵字緊鄰 `#N` 的說法。
- merge 前用 `gh pr view <N> --json closingIssuesReferences --jq '[.closingIssuesReferences[].number]'` 核對；多出不該關的 issue 就先改 PR 內文（`gh pr edit <N> --body`）。
- 已經誤關：`gh issue reopen <N> --comment "<原因與剩餘工作>"`。

## 更新 PR 描述 / 留總結 comment

```bash
gh pr edit <N> --body "<內文>"
gh pr comment <N> --body "<內文>"
```

## 取自己帳號

```bash
gh api user --jq .login
```

## token 權限

```bash
gh auth status   # 看 "Token scopes"
```

- 一般流程需要 `repo`。
- **PR 改到 `.github/workflows/`、且 base 上的 workflow 也變過**時，merge 與 update-branch 需要 `workflow` scope。沒有時症狀是 PR 一直 `BLOCKED`、`gh pr update-branch` 報 `refusing to allow an OAuth App to create or update workflow`。
- 不足就停下請使用者自己執行 `gh auth refresh -s workflow`（會開瀏覽器授權），不要改用其他 token。

## 在 issue 留言

```bash
gh issue comment <N> --body-file <file>   # 短內文可用 --body "<內文>"
```

## 看 PR CI 狀態

```bash
gh pr checks <N>                       # 一次性；exit 0 = 全綠、1 = 有失敗、8 = 仍在跑
gh pr checks <N> --watch --fail-fast   # 等到結束
gh pr checks <N> --json name,state,link,workflow
```

- 顯示 `no checks reported` / 0 個 check：PR 與 base **有衝突時 GitHub 不跑 `pull_request` CI**，先看「可否合併」、解衝突再等 CI。
- `gh pr checks` 的整體結果不代表每個檢查都有意義：設了 `continue-on-error: true` 的 job / step 失敗時，workflow（或該 job）仍可能顯示成功，要看 log 或 step 結果；`paths` 篩選沒命中的 workflow 根本不會出現在 checks 裡。逐個看 `--json name,state,workflow`，對照該跑的檢查。
- checks 是在 base 變動前跑的（別的 PR 剛 merge、尤其動到同檔案）→ 先「更新 PR 分支」讓 CI 以新 base 重跑。

## 看 PR 可否合併

```bash
gh pr view <N> --json mergeable,mergeStateStatus,baseRefName,headRefName
```

- `mergeable`：`MERGEABLE` / `CONFLICTING` / `UNKNOWN`（剛 push 時是 UNKNOWN，隔幾秒再查）
- `mergeStateStatus`：`CLEAN` 才算可 merge；`BEHIND` = 需更新分支；`BLOCKED` = required check / review 未過（或 token 缺 `workflow` scope，見上）；`DIRTY` = 衝突；`UNSTABLE` = 非 required check 失敗

## merge PR

```bash
gh pr merge <N> --merge --subject "<merge_subject>" --body "<body>"   # merge_method=merge
gh pr merge <N> --squash --subject "<subject>" --body "<body>"         # squash
gh pr merge <N> --rebase                                                # rebase（無 subject）
```

- 不加 `--delete-branch`：刪分支由收尾步驟依 `delete_branch_after_merge` 處理（疊分支時下一個 PR 還指著它當 base）。
- merge 後 `gh issue view <issue> --json state` 確認 issue 已因 `Closes #<issue>` 自動關閉。

## 更新 PR 分支 / 改 PR base

```bash
gh pr update-branch <N>            # 把 base merge 進 head，不 force push
gh pr edit <N> --base <branch>
```

## 手動觸發 workflow 與看 log

```bash
gh workflow run <workflow-file> --ref <branch>
gh run list --workflow <workflow-file> --branch <branch> --limit 1 --json databaseId,status,conclusion
gh run watch <run-id> --exit-status
gh run view <run-id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | .databaseId'
gh run view <run-id> --job <job-id> --log-failed
```

`gh workflow run` 不回傳 run id：觸發後隔幾秒用 `gh run list` 取最新一筆。

## 看 PR diff 版本（sha）

```bash
gh pr view <N> --json headRefOid,baseRefOid
```

- `headRefOid` = PR 最新 head commit；inline comment 的 `commit_id` 用它。
- `baseRefOid` = base 分支目前的 commit；審查範圍用 `git diff <baseRefOid>...<headRefOid>`。
- 只需要 head sha 一個（GitLab 要三個）。每次 push 後 `headRefOid` 會變，留 inline 前重取。

## 列出 PR thread（含 resolved）

review thread 只有 GraphQL 拿得到 `isResolved` 與 thread node id。

```bash
gh api graphql --paginate \
  -F owner='{owner}' -F repo='{repo}' -F number=<N> \
  -f query='
query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 100) {
            nodes { databaseId url author { login } body }
          }
        }
      }
    }
  }
}'
```

欄位：

- thread `id`：**thread id**（node id，形如 `PRRT_…`），resolve / unresolve 用。
- `isResolved`、`isOutdated`（程式碼已被後續 commit 改動）、`path`、`line`（outdated 時可能為 `null`）。
- `comments.nodes[]`：`databaseId` = **note id**（數字，REST 用）、`url`、`author.login`、`body`。**首則** comment 的 `databaseId` 給「回覆 thread」用。

分頁：

- `reviewThreads` 一頁最多 100 筆。`gh api graphql --paginate` 會自動帶 `$endCursor` 翻頁，前提是 query 有宣告 `$endCursor: String`、用 `after: $endCursor`，且 `pageInfo { hasNextPage endCursor }` 在 `reviewThreads` 底下（上面已寫好）。
- `--paginate` 的輸出是**串接的多個 JSON 物件**（每頁一個），不是一個 array；要合併用 `--slurp`（需 gh 2.48 以上）：`gh api graphql --paginate --slurp ... | jq '[.[].data.repository.pullRequest.reviewThreads.nodes[]]'`。
- 單一 thread 內 `comments(first: 100)` 也有上限；超過 100 則回覆的 thread 極少見，遇到就對該 thread 的 `id` 另用 `node(id: ...)` 查並翻頁。

## 列出未解決 thread

沿用上一節的 query，過濾 `isResolved == false`：

```bash
gh api graphql --paginate --slurp \
  -F owner='{owner}' -F repo='{repo}' -F number=<N> \
  -f query='<同上>' \
  | jq '[.[].data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)
         | {id, path, line, isOutdated, note_id: .comments.nodes[0].databaseId, author: .comments.nodes[0].author.login, body: .comments.nodes[0].body}]'
```

## 列出總結 comment

總結 comment 分兩處：PR 對話區的 issue comment，與 review 送出時的整體 body。

```bash
gh api "repos/{owner}/{repo}/issues/<N>/comments" --paginate \
  --jq '.[] | {id, user: .user.login, body, html_url, created_at}'
gh api "repos/{owner}/{repo}/pulls/<N>/reviews" --paginate \
  --jq '.[] | select(.body != "") | {id, user: .user.login, state, body, html_url, submitted_at}'
```

- `--jq` 對每頁各跑一次，多頁輸出直接串接即可，不用特別合併。
- reviews 的 `body` 為空（只有 inline comment 的 review）要略過；`state` 為 `APPROVED` / `CHANGES_REQUESTED` / `COMMENTED`。
- 要找自己留的，用 [tracker] 取自己帳號後比對 `user.login`。

## 在 diff 上留 inline comment（選用）

預設不留，只有使用者要求才用。先 [tracker] 看 PR diff 版本取 `headRefOid`。逐條送出，不做批次 review API。

```bash
gh api "repos/{owner}/{repo}/pulls/<N>/comments" \
  -f body='comment 內容' \
  -f commit_id='<headRefOid>' \
  -f path='<path>' \
  -F line=42 \
  -f side='RIGHT'
```

- `line` 必須是整數，用 `-F`（`-f` 會變字串）；`body` 含中文或多行時改 `-F body=@<file>`。
- `side`：`RIGHT` = 新檔案（新增行或 context 行）；刪除行用 `LEFT`，此時 `line` 是舊檔行號。
- 該行必須**出現在本次 diff 中**；不在 diff 內會回 HTTP 422（`line could not be resolved` / `Validation Failed`），這類內容改走總結 comment。
- 多行範圍可加 `start_line` 與 `start_side`（`start_line` 小於 `line`）。
- 回傳的 `.id` 是 note id，`.html_url` 是連結；新 thread 的 thread id 要再用「列出 PR thread」查。
- rename 不用分開填舊／新路徑：`path` 填 head 上的路徑。

## 回覆 thread

```bash
gh api "repos/{owner}/{repo}/pulls/<N>/comments/<note id>/replies" \
  -f body='回覆內容'
```

- `<note id>` = thread **首則** comment 的 `databaseId`（來自「列出 PR thread」）。回覆已是回覆的 comment 會失敗。
- 回傳的 `.id` 是新 note id。

## resolve / unresolve thread

只有 GraphQL；`<thread id>` 是 `reviewThreads.nodes[].id`（`PRRT_…`），不是 `databaseId`。

```bash
gh api graphql -f threadId='<thread id>' -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}'

gh api graphql -f threadId='<thread id>' -f query='
mutation($threadId: ID!) {
  unresolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}'
```

- 回傳的 `thread.isResolved` 應為 `true`（resolve）或 `false`（unresolve），用來確認。
- 需要 token 有 `repo` scope，且對該 PR 有寫入權限。
