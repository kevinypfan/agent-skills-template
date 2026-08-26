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
| 看 issue（JSON） | `glab issue view <N> --output json` | `gh issue view <N> --json number,title,body,labels,url` | 欄位名不同，見各檔「JSON 欄位」 |
| 建 issue | `glab issue create --title --label --assignee --description` | `gh issue create --title --label --assignee --body` | GitLab `--description` ≡ GitHub `--body` |
| 查目前分支的 PR | `glab mr view "$BRANCH" --output json` | `gh pr view "$BRANCH" --json number,title,baseRefName,url,state` | 兩邊都以分支名查；不存在時非零 exit |
| 看 PR（含 comments） | `glab mr view <N> --comments` | `gh pr view <N> --comments` | |
| 建 PR | `glab mr create --title --target-branch --assignee --label --description --remove-source-branch` | `gh pr create --title --base --assignee --label --body` | GitHub 無 `--remove-source-branch`（repo 設定 auto-delete） |
| 更新 PR 描述 | `glab mr update <N> --description` | `gh pr edit <N> --body` | |
| 留 PR 總結 comment | `glab mr note <N> --message` | `gh pr comment <N> --body` | |
| 取自己帳號 | `glab api user`（`.username`） | `gh api user`（`.login`） | 過濾「自己留的 comment」用 |
| 在 diff 上留 inline comment | 見 `gitlab.md`「inline comment」 | 見 `github.md`「inline comment」 | 語意不對等；**本版兩邊皆未提供**，skill 遇到就跳過該步 |
| 回覆 / resolve inline thread | 同上 | 同上（resolve 只有 GraphQL） | 同上 |

## 術語對照

| 本 template 用詞 | GitLab | GitHub |
|---|---|---|
| PR | Merge Request（MR） | Pull Request |
| `<N>` | MR / issue 的 **iid**（專案內編號） | number |
| 開發分支（`base_branch`） | target branch | base branch |
| 總結 comment | note | issue comment |
| inline thread | discussion | review thread |

skill 本文與 PR 內文一律用「PR」；面對 GitLab 使用者口頭說 MR 也不用糾正。
