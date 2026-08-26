---
name: create-worktree
description: >
  從 issue（GitLab 或 GitHub，自動偵測）建立獨立 git worktree 和分支，不影響當前工作目錄。
  使用時機：(1) 使用者提供 issue 編號並想開 worktree,
  (2) 使用者說「開 worktree」「建 worktree」「create worktree」並提到 issue,
  (3) 使用者明確呼叫 /create-worktree。
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

> This skill should only be invoked explicitly by the user or other skills.

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

The user input may contain:
- Issue number (e.g., `123`) or full issue URL
- Base branch override (default: conventions 的 `base_branch`)

## Step 0: 讀設定

1. 讀 `.agents/conventions.md` 取 `base_branch`、`worktree_root`、`branch_prefix`。
   `worktree_root` 用預設時實際路徑 = `$(dirname "$(git rev-parse --show-toplevel)")/$(basename "$(git rev-parse --show-toplevel)")-worktrees`。
2. 依 `.agents/skills/_tracker/README.md` 判斷 tracker，讀對應 `.agents/skills/_tracker/<tracker>.md`。

## Workflow

### Step 1: 讀取 Issue

執行 **[tracker] 看 issue（JSON）**，取得：
- `title` — 用於 branch 命名
- `labels` — 用於判斷 branch type（GitHub 是物件陣列，取 `.name`）
- 編號（GitLab `iid` / GitHub `number`）

### Step 2: 產生 Branch 名稱

**命名規則**：`<prefix><issue-number>-<kebab-case-描述>`

| Issue Labels | Prefix（`branch_prefix`） | 範例 |
|---|---|---|
| 含 `bug` 或 `fix` | `fix/` | `fix/123-redis-timeout-missing` |
| 含 `feature` 或 `enhancement` | `feat/` | `feat/456-add-afterhours-support` |
| 其他 | `chore/` | `chore/789-update-dependencies` |

描述從 issue title 擷取，轉為 kebab-case（小寫、空格換 `-`、去特殊字元），控制在 3-5 個英文單字以內。

**向使用者確認產生的 branch 名稱**，允許微調後再繼續。

### Step 3: 檢查衝突

檢查 branch 和目錄是否已存在。注意 `git branch --list` 不管有無匹配 exit code 都是 0，**必須檢查輸出是否為空**。

```bash
LOCAL=$(git branch --list '<branch-name>')
REMOTE=$(git ls-remote --heads origin '<branch-name>')
ls -d <worktree_root>/issue-<number> 2>/dev/null
```

判斷邏輯：
- **`$LOCAL` 非空** → 本地已有 branch，提示使用者：用現有 branch 建 worktree（`git worktree add <path> <existing-branch>`），或刪除重建
- **`$REMOTE` 非空** → 遠端已有 branch，提示使用者：`git worktree add <path> --track origin/<branch-name>`
- **目錄已存在** → 該 issue 已有 worktree，是否切換過去
- **都不存在** → 繼續 Step 4

### Step 4: 建立 Worktree

```bash
git fetch origin <base_branch>
mkdir -p <worktree_root>
git worktree add -b <branch-name> <worktree_root>/issue-<number> origin/<base_branch>
```

- Base 預設 `origin/<base_branch>`，使用者可在輸入覆蓋
- 目錄名固定 `issue-<number>`

### Step 5: 回報結果

```markdown
## Worktree 已建立

- **Issue**: #<number> <title>
- **Branch**: `<branch-name>`
- **Base**: `origin/<base_branch>` (<short-sha>)
- **路徑**: <worktree_root>/issue-<number>

### 開啟方式
  cd <worktree_root>/issue-<number>
  # 或在新的 agent session 中開啟此目錄

### 下一步
在 worktree 中開啟新 session 後，呼叫 skill `fix-issue`，參數 `<issue_number>`
```

## Important Notes

- **此 skill 只負責建立 worktree 和 branch** — 不做程式碼分析或修改
- **Branch 名稱需使用者確認**後才建立
- 對話語言依 conventions 的 `language`
- **不自動 push branch** — 留給後續工作流程處理
- **若目錄已存在**，提示使用者處理方式
