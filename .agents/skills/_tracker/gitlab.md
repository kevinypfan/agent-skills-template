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

## inline comment（diff 上的 discussion）

**本版未提供。** 需要 `merge_requests/<N>/versions` 取 `base_sha/head_sha/start_sha`、再 POST `discussions` 帶 `position` JSON；有硬性限制（不可用 `-f` 傳 nested、`new_line`/`old_line` 規則）。之後從 review skill 移植時補在這裡；skill 遇到「inline comment」步驟且本節仍是此狀態就**跳過該步並告知使用者**。
