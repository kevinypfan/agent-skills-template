---
name: fix-issue
description: Read an issue (GitLab or GitHub, auto-detected), analyze the problem, implement the fix after user confirmation, and push via the commit-push-pr skill. Assumes branch/worktree is already set up (use create-worktree first). Use when: (1) user mentions an issue number with intent to fix, (2) user says "fix issue", "修 issue", "處理 issue", or (3) user explicitly invokes /fix-issue.
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

> This skill should only be invoked explicitly by the user or other skills.

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

You **MUST** consider the user input before proceeding (if not empty). The user input may contain:
- Issue number (e.g., `123`) or full issue URL
- Additional context or constraints for the fix

## Step 0: 讀設定

1. 讀 `.agents/conventions.md` 取 `base_branch`、`test_command`、`lint_command`、`language`。
2. 依 `.agents/skills/_tracker/README.md` 判斷 tracker，讀對應 `.agents/skills/_tracker/<tracker>.md`。

## Workflow

### Step 1: 讀取 Issue

執行 **[tracker] 看 issue（JSON）**（支援編號或 URL），取得：
- `title` — 識別 issue
- 內文（GitLab `description` / GitHub `body`） — 分析問題
- URL — PR 關聯用

> **注意**：此 skill 假設你已在正確的 branch/worktree 上。若尚未建立，先呼叫 skill `create-worktree`（參數 `<issue_number>`）。

### Step 2: 討論修改方案（可能多輪）(IMPORTANT)

#### 2a. 分析問題、提出初步方案

1. **搜尋相關程式碼** — 找出需要修改的檔案和函式
2. **分析根本原因** — 理解問題本質，不只是表面症狀
3. **列出修改方案**：

```markdown
## 修改方案

### Issue: #<number> <title>
<簡述問題>

### 需要修改的檔案
1. `<file-path>` — <具體修改說明>

### 風險評估
- <潛在影響或副作用>

### 測試策略
- <如何驗證修正>
```

#### 2b. 多輪討論（視需要）

使用者可能提出修改意見、質疑方案、要求調整。**持續討論直到方案定版**，不急著進入實作。

#### 2c. 方案定版後做一次獨立審查

從三個角度審查方案（環境若有內建的 simplify / review 類 skill 可呼叫它；沒有就自己逐項過）：
- 是否有更簡單的做法被忽略
- 修改範圍是否過大或不足
- 風險評估是否遺漏重要項目

將審查結果回報給使用者。

#### 2d. 使用者確認

等使用者回覆 **'proceed'** 才進入 Step 3。

### Step 3: 實作修正

1. **修改程式碼**
2. **執行測試**：跑 conventions 的 `test_command`（依改動路徑選對應那列；未定義就問使用者要跑什麼）
3. **執行 lint**：跑 conventions 的 `lint_command`（同上）

### Step 4: 呼叫 skill `commit-push-pr`

測試通過後，呼叫 skill `commit-push-pr`，參數：

```
關聯 issue #<issue_number>，target branch: <base_branch>
```

commit-push-pr 會處理：self-review → 驗證閘門 → staging → commit → push → 建立 PR。

## Important Notes

- **假設已在正確的 branch/worktree 上**
- **不自動 assign issue** — 避免未經確認的副作用
- **分析完畢必須等使用者確認**才能動手改 code
- **不自己處理 commit/PR** — 一律透過 skill `commit-push-pr`
- 對話語言依 `language`；**commit message 一律英文**（Conventional Commits）
