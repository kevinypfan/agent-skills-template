# GitLab（`glab`）指令細節

前提：`glab auth status` 通過；在 repo 目錄下執行（`glab` 由 `origin` 推專案）。

## 看 issue

```bash
glab issue view <N> --output json
```

JSON 欄位：`iid`（編號）、`title`、`description`（內文）、`labels`（**字串陣列**）、`web_url`、`state`。
使用者給的是 URL（`https://<host>/<group>/<repo>/-/issues/<N>`）時取最後一段當 `<N>`。

## 列出 open issue / open PR

```bash
glab issue list --output json --per-page 100      # 預設只列 opened
glab mr list --output json --per-page 100         # 預設只列 opened
```

- issue 欄位：`iid`、`title`、`labels`（字串陣列）、`web_url`。
- MR 欄位：`iid`、`title`、`source_branch`（= head）、`target_branch`（= base）、`draft`、`web_url`；**列表不含可靠的 pipeline 與 `detailed_merge_status`**，要逐個 `glab mr view <N> --output json` 看 `head_pipeline.status`、`detailed_merge_status`、`has_conflicts`。
- MR 對應 issue：內文 `Closes #N`，或從 `source_branch` 的 `<prefix><N>-<slug>` 取編號。
- 超過 100 個時加 `--label` / `--search` 縮小，或問使用者範圍。

## 建 issue

```bash
glab issue create \
  --title "<title>" \
  --label "<label1>,<label2>" \
  --assignee "<assignee>" \
  --description "<內文>"
```

- label 逗號分隔、一個 `--label`；scoped label（`type::bug`）直接寫完整字串
- ⚠ **label 不存在時 GitLab 會靜默新建**（不報錯）。label 名稱含前綴字元（如 `# type::bug`、`$ priority::1`）時前綴也是名稱的一部分，漏寫就會多出一個新 label。建立前用 `glab label list --per-page 100` 核對字串完全一致
- `--assignee "@me"` 可用
- 回傳 issue URL（stdout 最後一行）

## repo 的 PR template

`commit-push-pr` 在 `pr_template: auto` 時用。檔名大小寫不拘，用 `git ls-files` 比對（不要用 `test -f`，Linux 上會漏大小寫）：

```bash
git ls-files '.gitlab/merge_request_templates/*.md'
```

1. 其中檔名為 `default.md`（大小寫不拘，GitLab 的預設 template）→ 用它
2. 沒有 default、但有其他 template（如 `Bug.md`）→ GitLab 不會自動套用這些，列出檔名問使用者要用哪一份或用內建版
3. 都沒有 → 用內建版

- GitLab 專案設定裡的「Default description template」（不是檔案）偵測不到；團隊若用它，請在 conventions 把 `pr_template` 指到一份 repo 檔
- `glab mr create` 不會自動套用 repo template，內文要自己帶進 `--description`

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

## 自動關閉關鍵字

MR 描述（以及 merge 進預設分支的 commit message）出現 **`Close` / `Closes` / `Closed` / `Closing`、`Fix` / `Fixes` / `Fixed` / `Fixing`、`Resolve` / `Resolves` / `Resolved` / `Resolving`、`Implement` / `Implements` / `Implemented` / `Implementing` 緊接 `#N`**（大小寫不拘；專案可在設定改 closing pattern），MR merge 時 GitLab 就會關閉該 issue。

- 只完成 issue 一部分的 MR **整份描述與 commit message 都不能出現上述組合**，連「之後的 MR 會 close #46」這種敘述也會觸發。改寫成 `Related to #N`、「完成後由下一個 MR 關閉 issue #N」這類說法。
- merge 前核對：`glab api projects/:id/merge_requests/<N>/closes_issues | jq '[.[].iid]'`（`glab api` 沒有 `--jq`，接 `jq`）；多出不該關的 issue 就先 `glab mr update <N> --description` 改掉。
- 標題、描述、留言、commit message 裡的 `#N` 會自動連結並**通知該 issue 的參與者**；只是舉例或引用別專案編號時改寫成 `issue 46`、`` `#46` `` 之類不會被解析的寫法。
- 已經誤關：`glab issue reopen <N>`，再 `glab issue note <N> --message "<原因與剩餘工作>"`。

## 更新 PR 描述 / 留總結 comment

```bash
glab mr update <N> --description "<內文>"
glab mr note <N> --message "<內文>"
glab mr note <N> --message "$(cat <file>)"   # 長內文先寫暫存檔（glab 無 --body-file）
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
glab api projects/:id/pipelines/<pipeline-id>/jobs --paginate | jq '.[] | {name, stage, status, allow_failure}'
```

- 以 `head_pipeline` 為準：job 設 `only: merge_requests` / `rules` 只在 MR pipeline 跑時，`--branch` 抓到的 branch pipeline 可能沒有這些 job。
- pipeline `success` 不代表每個 job 都過：`allow_failure: true` 的 job 失敗時 pipeline 仍是 `success`（job `status` = `failed`）；manual job 預設也是 `allow_failure: true`。逐個看 jobs。
- `rules:changes` 沒命中的 job 不會出現在 jobs 裡，「沒有失敗」不等於「有跑」。
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
- 要綁定已審查的 sha 時加 `--sha <sha>`（完整 40 碼）：source 分支 HEAD 不等於該 sha 就拒絕 merge（確保只合併審過的 commit）。
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

## 看 PR（JSON）

```bash
glab mr view <N> --output json
```

JSON 欄位：`iid`（編號）、`title`、`description`（描述）、`author.username`、`target_branch`（= base）、`source_branch`（= head 分支）、`state`（`opened` / `merged` / `closed`）、`diff_refs.base_sha` / `diff_refs.head_sha`（base 與 head sha）、`web_url`。
`diff_refs` 在 push 後可能短暫落後，見下節。

## 看 PR diff 版本（sha）

inline comment 的 `position` 要三個 sha：`base_sha`、`head_sha`、`start_sha`。

```bash
glab mr view <N> --output json     # .diff_refs.{base_sha,head_sha,start_sha}（優先用這個）
glab api "projects/:id/merge_requests/<N>/versions" | python3 -c "
import sys,json
v = json.load(sys.stdin)[0]       # 第 0 筆 = 最新 version
print('base_sha: ', v['base_commit_sha'])
print('head_sha: ', v['head_commit_sha'])
print('start_sha:', v['start_commit_sha'])
"
```

- ⚠ **不要用 `git merge-base`、本地 branch HEAD 推算**：GitLab 比對的是 MR 自己記錄的 diff version，sha 對不上時 API 回 400，或 comment 不會出現在 Changes tab。
- 每次 push 都會產生新 version；留 inline 前重取，不要沿用舊的。
- ⚠ push 後 GitLab 是**非同步**產生新 version：剛 push 完取到的 `head_sha` 可能還是舊的。先確認 `diff_refs.head_sha` 等於剛 push 的 commit（`git rev-parse HEAD`），不相等就隔幾秒重取，最多重試數次；仍不相等就停下回報。
- **fetch PR head**：`<base_sha>` 或 `<head_sha>` 任一在本地不存在（`git cat-file -e <sha>^{commit}` 失敗）就 fetch。head 用 MR ref，不依賴分支名：

```bash
git fetch origin "merge-requests/<N>/head"   # 取回後 FETCH_HEAD 即 head；base 則 git fetch origin <target 分支名>
```

## 列出 PR thread（含 resolved）

```bash
glab api "projects/:id/merge_requests/<N>/discussions?per_page=100" --paginate | python3 -c "
import json, sys
dec = json.JSONDecoder()
raw = sys.stdin.read()
idx, items = 0, []
while idx < len(raw):
    while idx < len(raw) and raw[idx] in ' \t\r\n': idx += 1
    if idx >= len(raw): break
    page, idx = dec.raw_decode(raw, idx)
    items.extend(page)
for d in items:
    n = d['notes'][0]
    print(d['id'], n['id'], n.get('resolvable'), n.get('resolved'), bool(n.get('position')), n['body'][:60].replace('\n', ' '))
"
```

- ⚠ **`--paginate` 多頁輸出是串接的多個 JSON array**（`[...][...]`），不能直接 `json.load`（會爆 `Extra data`）。上面用 `raw_decode` 迴圈逐段消化，body 內含 `][` 字面也不怕。單頁（< 100 筆）時結果相同。
- discussion 物件只有 `id`（**thread id**）、`individual_note`、`notes` 三個 key，**沒有 top-level `resolved`**：`resolved` 在 `notes[].resolved`，且僅 `resolvable: true` 的 diff note 有意義（純 comment 為 `null`）。照字面用 `.resolved` 會全拿到 `null`，把已 resolve 的誤判成未修。
- inline thread = `notes[].position` 非 null；`position` 內有 `new_path`、`old_path`、`new_line`、`old_line`。
- `notes[]` 欄位：`id`（**note id**）、`body`、`author.username`、`system`（系統訊息，要排除）、`created_at`。
- note 的 URL：`<web_url>#note_<note id>`（`web_url` 取自 `glab mr view <N> --output json`）。
- ⚠ 上面的輸出**只是索引**（只印每個 discussion 的首則 note、body 截斷 60 字）。要納入上輪追蹤的 thread，再從同一份 `discussions` 回應取該 discussion 完整的 `notes[]`：每則的作者（`author.username`）、完整 `body`、`position`、以及後續回覆，不能只憑索引那一行判斷。

## 列出未解決 thread

沿用上一節的取得方式，過濾條件：首則 note `resolvable == true` 且 `resolved == false`。

```bash
# 把上一節 python 的 for 迴圈改成：
for d in items:
    n = d['notes'][0]
    if n.get('resolvable') and not n.get('resolved'):
        print(d['id'], n['id'], n['body'][:60].replace('\n', ' '))
```

`individual_note: true` 的是單則 comment、不是 thread，不會被 `resolvable` 命中。

## 列出總結 comment

```bash
glab api "projects/:id/merge_requests/<N>/notes?per_page=100&sort=asc" --paginate
```

- 多頁時同樣是串接 array，解析方式同「列出 PR thread」。
- 總結 comment = `system == false` 且**沒有** `position` 的 note；`body` 是內文、`author.username` 是作者、`id` 是 note id。
- 要找自己留的，用 [tracker] 取自己帳號後比對 `author.username`。

## 在 diff 上留 inline comment（選用）

預設不留，只有使用者要求才用。先 [tracker] 看 PR diff 版本取三個 sha。

`<tmpdir>` = 暫存目錄（Claude Code 用 scratchpad，Codex 用 `mktemp -d`），不要寫進 repo。

```bash
jq -n \
  --arg body "comment 內容（可多行、含引號）" \
  --arg base "<base_sha>" --arg head "<head_sha>" --arg start "<start_sha>" \
  --arg path "<path>" --argjson line 42 \
  '{body: $body, position: {position_type: "text", base_sha: $base, head_sha: $head, start_sha: $start,
    new_path: $path, old_path: $path, new_line: $line}}' > <tmpdir>/inline.json

glab api "projects/:id/merge_requests/<N>/discussions" \
  --method POST \
  --header "Content-Type: application/json" \
  --input <tmpdir>/inline.json
```

回傳新 discussion，`.id` 是 thread id、`.notes[0].id` 是 note id。

硬性規則：

- ⚠ **JSON 一律用 `--input`，嚴禁 `-f` / `--field` 傳 `position`**：`-f` 走 form data，nested object（`position.base_sha` 等）解析不了，comment 不會釘上 Changes tab。
- ⚠ **JSON 用 `jq -n --arg` 產生**：自動處理換行、引號與中文。嚴禁用 `printf` 拼 JSON（中文字元會壞格式）；手寫 heredoc 時 body 裡的換行要寫成 `\n`、雙引號寫成 `\"`，容易出錯。
- 行號：
  - 該行必須**出現在本次 diff 中**（新增、刪除或 diff 的 context 行）。
  - **新增行**：只填 `new_line`（新檔行號）。
  - **刪除行**：只填 `old_line`（舊檔行號），省略 `new_line`。
  - **context 行**（未變更、出現在 diff 上下文）：`old_line` 與 `new_line` **都要填**，只填 `new_line` 會回 400（`line_code can't be blank`）。
  - 未變更且不在 diff context 內的行**釘不上**，API 會回錯（多半 HTTP 400）；這類內容改走總結 comment。
- 檔案 rename：`old_path` 填舊路徑、`new_path` 填新路徑；不確定時先看 `git diff --stat -M` 的 rename 標記。未 rename 兩者填同一個。

## 回覆 thread

```bash
jq -n --arg body "回覆內容" '{body: $body}' > <tmpdir>/reply.json
glab api "projects/:id/merge_requests/<N>/discussions/<thread id>/notes" \
  --method POST --header "Content-Type: application/json" --input <tmpdir>/reply.json
```

- `<thread id>` = discussion 的 `id`（不是 note id）。
- 這裡只有 flat field，技術上可用 `-f body=...`；含中文或多行時仍用 `--input`。

## resolve / unresolve thread

```bash
glab api "projects/:id/merge_requests/<N>/discussions/<thread id>" --method PUT -f resolved=true | jq '.notes[0].resolved'
glab api "projects/:id/merge_requests/<N>/discussions/<thread id>" --method PUT -f resolved=false | jq '.notes[0].resolved'
```

- 回傳的 `.notes[0].resolved` 應為 `true`（resolve）或 `false`（unresolve），用來確認；不符就回報。

- `resolved` 是 flat field，可用 `-f`。
- 只對 `resolvable` 的 thread 有效。
