# GitHub（`gh`）指令細節

前提：`gh auth status` 通過；在 repo 目錄下執行（`gh` 由 `origin` 推 repo）。

## 看 issue

```bash
gh issue view <N> --json number,title,body,labels,url,state
```

JSON 欄位：`number`（編號）、`title`、`body`（內文）、`labels`（**物件陣列**，取 `.name`）、`url`、`state`。
使用者給的是 URL（`https://github.com/<owner>/<repo>/issues/<N>`）時取最後一段當 `<N>`；`gh issue view` 也直接吃 URL。

## 建 issue

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

## 更新 PR 描述 / 留總結 comment

```bash
gh pr edit <N> --body "<內文>"
gh pr comment <N> --body "<內文>"
```

## 取自己帳號

```bash
gh api user --jq .login
```

## inline comment（diff 上的 review comment）

**本版未提供。** 對應 API 為 `POST repos/{owner}/{repo}/pulls/<N>/comments`（定位用 `commit_id + path + line + side`，與 GitLab 三 sha 不同）、回覆用 `pulls/<N>/comments/{id}/replies`、**resolve 只有 GraphQL `resolveReviewThread`**。之後移植 review skill 時補在這裡；skill 遇到「inline comment」步驟且本節仍是此狀態就**跳過該步並告知使用者**。
