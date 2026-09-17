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

## inline comment（diff 上的 review comment）

**本版未提供。** 對應 API 為 `POST repos/{owner}/{repo}/pulls/<N>/comments`（定位用 `commit_id + path + line + side`，與 GitLab 三 sha 不同）、回覆用 `pulls/<N>/comments/{id}/replies`、**resolve 只有 GraphQL `resolveReviewThread`**。之後移植 review skill 時補在這裡；skill 遇到「inline comment」步驟且本節仍是此狀態就**跳過該步並告知使用者**。
