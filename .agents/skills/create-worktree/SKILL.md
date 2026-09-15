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

## 先決定照哪一份跑

本 skill 可能同時裝在 repo 與全域（`~/.agents/skills/`），開工前先做這兩件事：

1. 你讀的若是 `~/.agents/skills/create-worktree/SKILL.md`（全域版），先看 repo 根（`git rev-parse --show-toplevel`）：有 `.agents/skills/create-worktree/SKILL.md`，或有 `.claude/skills/create-worktree/SKILL.md` 且它不是只轉交到 `.agents/skills/create-worktree/SKILL.md` 的薄 stub → **改讀 repo 那份照做，本檔以下全部不適用**。專案版通常客製過（label、tracker、流程），全域版只在專案沒有時補位。
2. 下文所有 `.agents/…` 路徑：repo 根有該檔就用 repo 的，沒有就用 `~/.agents/…` 同名檔（`~` 展開成家目錄絕對路徑再讀）。

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

### Step 2: 產生 Branch 與目錄名稱

先產生一段 `<slug>`（簡短描述），**branch 與 worktree 目錄共用同一段**：

- **Branch**：`<prefix><issue-number>-<slug>`
- **目錄**：`issue-<issue-number>-<slug>`（在 `worktree_root` 底下 `ls` 就看得出每個 worktree 在做什麼）

| Issue Labels | Prefix（`branch_prefix`） | 範例 |
|---|---|---|
| 含 `bug` 或 `fix` | `fix/` | `fix/123-redis-timeout-missing` |
| 含 `feature` 或 `enhancement` | `feat/` | `feat/456-add-afterhours-support` |
| 其他 | `chore/` | `chore/789-update-dependencies` |

`<slug>` 的寫法——目的是**只看名字就知道這個分支在幹嘛**：
- 從 issue title（必要時看內文）抓「做什麼 + 對象」，寫成 3–5 個英文單字的 kebab-case（小寫、`-` 連接、只留 `a-z0-9-`）
- title 是中文時**翻成英文關鍵字**，不要音譯、不要留空；例如 bug issue #123「盤後資料缺漏」→ slug `missing-afterhours-data` → branch `fix/123-missing-afterhours-data`、目錄 `issue-123-missing-afterhours-data`
- 別只寫模組名（`redis`、`api`）或籠統詞（`update`、`fix-bug`）——看不出在做什麼
- 已經由 prefix 表達的類型（fix / feat）不必在 slug 裡重複，除非去掉後語意不清

**向使用者確認產生的 branch 名稱與目錄名稱**，允許微調 slug 後再繼續（改 slug 時兩者一起改）。

### Step 3: 檢查衝突

檢查 branch 和目錄是否已存在，以及**同一個 issue 是否已有 worktree**（可能是舊的 `issue-<number>` 命名或不同 slug）。注意 `git branch --list` 不管有無匹配 exit code 都是 0，**必須檢查輸出是否為空**。

```bash
LOCAL=$(git branch --list '<branch-name>')
REMOTE=$(git ls-remote --heads origin '<branch-name>')
ls -d <worktree_root>/issue-<number>-<slug> 2>/dev/null
git worktree list --porcelain | grep -E '^worktree .*/issue-<number>(-|$)'
```

判斷邏輯：
- **`$LOCAL` 非空** → 本地已有 branch，提示使用者：用現有 branch 建 worktree（`git worktree add <path> <existing-branch>`），或刪除重建
- **`$REMOTE` 非空** → 遠端已有 branch，提示使用者：`git worktree add <path> --track origin/<branch-name>`
- **目錄已存在，或 `git worktree list` 命中同 issue 的 worktree** → 該 issue 已有 worktree，列出其路徑與 branch，問使用者是否切換過去
- **都不存在** → 繼續 Step 4

### Step 4: 建立 Worktree

```bash
git fetch origin <base_branch>
mkdir -p <worktree_root>
git worktree add -b <branch-name> <worktree_root>/issue-<number>-<slug> origin/<base_branch>
```

- Base 預設 `origin/<base_branch>`，使用者可在輸入覆蓋
- 目錄名 `issue-<number>-<slug>`，slug 與 branch 相同

### Step 5: 回報結果

```markdown
## Worktree 已建立

- **Issue**: #<number> <title>
- **Branch**: `<branch-name>`
- **Base**: `origin/<base_branch>` (<short-sha>)
- **路徑**: <worktree_root>/issue-<number>-<slug>

### 開啟方式
  cd <worktree_root>/issue-<number>-<slug>
  # 或在新的 agent session 中開啟此目錄

### 下一步
在 worktree 中開啟新 session 後，呼叫 skill `fix-issue`，參數 `<issue_number>`
```

## Important Notes

- **此 skill 只負責建立 worktree 和 branch** — 不做程式碼分析或修改
- **Branch 與目錄名稱需使用者確認**後才建立
- 對話語言依 conventions 的 `language`
- **不自動 push branch** — 留給後續工作流程處理
- **若目錄已存在**，提示使用者處理方式
