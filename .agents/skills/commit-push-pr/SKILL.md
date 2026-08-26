---
name: commit-push-pr
description: Self-review diff, run the project's verification gate, commit, push, and create or update a Pull Request / Merge Request (GitLab or GitHub, auto-detected) with the standard template.
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

> This skill should only be invoked explicitly by the user or other skills.

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

You **MUST** consider the user input before proceeding (if not empty). The user input may contain:
- Target branch (default: conventions 的 `base_branch`)
- PR title
- Related issue number
- Additional context for the PR description

## Step 0: 讀設定

1. 讀 `.agents/conventions.md` 取 `base_branch`、`pr_labels`、`pr_assignee`、`commit_scopes`、`commit_trailer`、`verify_commands`、`language`。
2. 依 `.agents/skills/_tracker/README.md` 判斷 tracker，讀對應 `.agents/skills/_tracker/<tracker>.md`。下文 **[tracker] 動作** 一律查該檔。

## Workflow

### Step 1: Gather Information

```bash
BRANCH=$(git branch --show-current)
git diff HEAD
git log --oneline -10
git status --short
```

再執行 **[tracker] 查目前分支的 PR**。成功就記下 PR 編號與 target branch——決定 Step 4 是建新 PR、更新描述、還是追加 comment。

### Step 2: Self-Review (IMPORTANT)

先對所有變更做一次審查（環境若有內建的 simplify / review 類 skill 可呼叫它；沒有就自己逐項過），三個角度：
- **Reuse** — 是否有現有工具函式可取代新寫的 code
- **Quality** — 冗餘狀態、copy-paste、leaky abstraction、不必要的註解
- **Efficiency** — 不必要的計算、缺少並行、hot-path 問題

**只做 review，不做 auto-fix。** 審查完成後：
1. **列出問題清單**，讓使用者決定要修哪些
2. 根據使用者確認的項目修正，跳過不想改的
3. **Review untracked files**：哪些該 commit、哪些該 ignore
4. **使用者確認所有想修的都修完**才進 Step 2.5

### Step 2.5: Verification Gate（conditional）

> **為什麼**：本 skill 假設呼叫端（`fix-issue` 等）已先驗證，但**直接呼叫**時沒有任何 build/test 把關，可能 push 壞掉的 code。此 gate 補這個洞。與 caller 冗餘是刻意的——重跑廉價且 idempotent，寧可冗餘也不要漏網的壞 build。

對 conventions `verify_commands` 的每一列 `<regex> → <指令>`：

```bash
git status --short | grep -qE '<regex>' && echo MATCH || echo SKIP
```

- `MATCH` → 跑該指令；**fail 就停**，回報錯誤、絕不 commit
- 全部 `SKIP` 或 `verify_commands` 為空 → 跳過

### Step 3: Commit and Push

```bash
# 只 stage 與本次任務相關的檔案（禁止 git add -u / git add .）
git add <file1> <file2> ...
# 確認沒有無關檔案被 stage；有就 git reset <file>

git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

<commit_trailer>
EOF
)"
git push -u origin "$(git branch --show-current)"
```

- `<scope>` 須在 `commit_scopes` 內（若有定義）
- `<commit_trailer>` 依 conventions（Claude Code / Codex 各自的 Co-Authored-By）

### Step 4: Create or Update PR

#### Option A: PR 已存在

**詢問使用者**要：
- **追加 comment**（預設，適合小修正 / review 回應）→ **[tracker] 留 PR 總結 comment**，內容：

  ```markdown
  ## 追加變更

  ### Commit: <latest commit hash>
  <簡述原因：回應 review、修正問題等>

  ### 變更內容
  <bullet points>
  ```

- **更新 PR 描述**（大幅變更，會覆寫原描述）→ **[tracker] 更新 PR 描述**，內容用 Option B 的 template 重填

#### Option B: 建新 PR

1. 讀 `.agents/skills/commit-push-pr/assets/pr-template.md`
2. 替換佔位符：
   - `{{RELATED_ISSUES}}` → 相關 issue/PR 連結，若無寫「無」
   - `{{SUMMARY}}` → 目的和主要變更
   - `{{CHANGES}}` → 變更內容（bullet points）
   - `{{TESTING}}` → 如何測試；有新增/修改測試案例則逐一條列
   - `{{NOTES}}` → 其他說明，若無寫「無」
3. 執行 **[tracker] 建 PR**：title `<type>(<scope>): <PR title>`、base = target branch、assignee = `pr_assignee`、labels = `pr_labels`、內文 = 填好的 template

### Step 5: Inline Comments on Diff (Optional)

PR 建好後**詢問使用者**是否要在 diff 上留 inline comment 解釋非顯而易見的設計決策（為何選 A 不選 B、trade-off、workaround、隱含相依）。

若使用者同意：依 `.agents/skills/_tracker/<tracker>.md` 的「inline comment」節操作。**該節標示未提供時跳過此步並告知使用者**（改把要點併進 PR 描述或總結 comment）。只留必要的，不重複 PR 描述已說的。

### Step 6: Report Result

1. PR URL
2. PR 內容摘要
3. 若有留 inline comment，列出留了哪些

## Important Notes

- **Always do self-review first**
- PR 內文語言依 `language`；**commit message 一律英文**（Conventional Commits `type(scope): description`）
- **Target branch 預設 `base_branch`**，使用者可覆蓋
- **Never skip the review step** — push 前要使用者確認
- **Verification gate**：`verify_commands` 有命中就必須綠才 commit
- **PR 已存在**：問使用者要更新描述還是追加 comment；小變更預設 comment
- **Staging**：永遠明列檔案，禁止 `git add -u` / `git add .`
