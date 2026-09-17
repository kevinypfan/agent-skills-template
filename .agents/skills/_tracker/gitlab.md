# GitLab（`glab`）指令細節

前提：`glab auth status` 通過；在 repo 目錄下執行（`glab` 由 `origin` 推專案）。

## 看 issue

```bash
glab issue view <N> --output json
```

JSON 欄位：`iid`（編號）、`title`、`description`（內文）、`labels`（**字串陣列**）、`web_url`、`state`。
使用者給的是 URL（`https://<host>/<group>/<repo>/-/issues/<N>`）時取最後一段當 `<N>`。

## 建 issue

```bash
glab issue create \
  --title "<title>" \
  --label "<label1>,<label2>" \
  --assignee "<assignee>" \
  --description "<內文>"
```

- label 逗號分隔、一個 `--label`；scoped label（`type::bug`）直接寫完整字串
- `--assignee "@me"` 可用
- 回傳 issue URL（stdout 最後一行）

## 查目前分支的 PR

```bash
glab mr view "$(git branch --show-current)" --output json 2>/dev/null
```

成功 → JSON 有 `iid`、`title`、`target_branch`、`web_url`、`state`；失敗（非零 exit）= 尚無 MR。

## 建 PR

```bash
glab mr create \
  --title "<title>" \
  --target-branch "<base_branch>" \
  --assignee "<pr_assignee>" \
  --label "<pr_labels>" \
  --remove-source-branch \
  --description "<內文>"
```

- ⚠ **不要加 `--reviewer "@owners"`**：`@owners` 不是 valid username（沒有 CODEOWNERS 展開），`glab mr create` 會失敗 `failed to find user by name: @owners`。要指定 reviewer 寫真實 username
- `--label` 為空時整個 flag 省略（空字串會報錯）

## 更新 PR 描述 / 留總結 comment

```bash
glab mr update <N> --description "<內文>"
glab mr note <N> --message "<內文>"
```

## 取自己帳號

```bash
glab api user | python3 -c "import sys,json;print(json.load(sys.stdin)['username'])"
```

## token 權限

```bash
glab auth status
```

- 調度流程（merge、rebase、觸發 pipeline）需要 token 有 `api` scope；`read_api` 只能看。
- merge 到受保護分支需要該分支的 merge 權限；改到 `.gitlab-ci.yml` 若專案限制 CI 設定變更，可能需要 Maintainer。
- 不足就停下請使用者重新 `glab auth login`（或換有權限的 token），不要自己改用其他帳號。

## 在 issue 留言

```bash
glab issue note <N> --message "<內文>"
```

## 看 PR CI 狀態

```bash
glab ci status --branch <source-branch>          # 一次性
glab ci status --branch <source-branch> --wait   # 等 pipeline 結束
glab mr view <N> --output json                   # head_pipeline.status / head_pipeline.id
```

- MR 有衝突時 merged-results pipeline 不會跑，先看「可否合併」。
- pipeline 是在 target 變動前跑的 → 先「更新 PR 分支」讓 pipeline 重跑。

## 看 PR 可否合併

```bash
glab mr view <N> --output json
```

看 `has_conflicts`（true = 衝突）與 `detailed_merge_status`：`mergeable` 才算可 merge；`need_rebase` = 需更新分支；`ci_must_pass` / `ci_still_running` = pipeline 未過；`not_approved` = 缺 approval；`conflict` = 衝突。

## merge PR

```bash
glab mr merge <N> --auto-merge=false --message "<merge_subject>"   # merge_method=merge
glab mr merge <N> --auto-merge=false --squash --message "<subject>"
glab mr merge <N> --auto-merge=false --rebase
```

- ⚠ **一定要 `--auto-merge=false`**：pipeline 還在跑時 `glab mr merge` 預設開 auto-merge 並立刻返回，不是真的 merge 了。調度流程是 CI 通過後才 merge。
- 不加 `--remove-source-branch`：刪分支由收尾步驟依 `delete_branch_after_merge` 處理。
- merge 後 `glab issue view <issue> --output json` 看 `state` 確認 issue 已因 `Closes #<issue>` 關閉。

## 更新 PR 分支 / 改 PR base

```bash
glab mr rebase <N>                          # 伺服器端 rebase：會改寫分支歷史
glab mr update <N> --target-branch <branch>
```

不想改寫歷史（分支上有人在跟）就在該 worktree 本地 `git fetch origin && git merge origin/<target>` 後 push。

## 手動觸發 pipeline 與看 log

```bash
glab ci run --branch <branch>
glab ci status --branch <branch> --wait
glab ci get --branch <branch> --output json   # jobs[].id / name / status
glab ci trace <job-id>
```

## inline comment（diff 上的 discussion）

**本版未提供。** 需要 `merge_requests/<N>/versions` 取 `base_sha/head_sha/start_sha`、再 POST `discussions` 帶 `position` JSON；有硬性限制（不可用 `-f` 傳 nested、`new_line`/`old_line` 規則）。之後從 review skill 移植時補在這裡；skill 遇到「inline comment」步驟且本節仍是此狀態就**跳過該步並告知使用者**。
