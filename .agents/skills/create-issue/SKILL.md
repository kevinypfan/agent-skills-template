---
name: create-issue
description: Create a standardized issue (GitLab or GitHub, auto-detected) with proper labels, assignee, and description template. Use when: (1) user says "開 issue", "建 issue", "create issue", (2) user wants to track a bug, feature, or maintenance task, or (3) user explicitly invokes /create-issue.
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

> This skill should only be invoked explicitly by the user or other skills.

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

You **MUST** consider the user input before proceeding (if not empty). The user input may contain:
- Issue title or description
- Type hint (bug, feature, maintenance, doc)
- Priority level
- Assignee
- Related component or service name

## Step 0: 讀設定

1. 讀 `.agents/conventions.md` 取 `issue_labels_required`、`issue_labels_type`、`issue_labels_optional`、`language`。
2. 依 `.agents/skills/_tracker/README.md` 判斷 tracker，讀對應的 `.agents/skills/_tracker/<tracker>.md`。下文的 **[tracker] 動作** 一律查該檔。

## Workflow

### Step 1: 收集資訊

從使用者輸入和對話上下文中提取：

- **Title** — 簡潔描述（若有外部來源可加前綴，如 `[客戶名]`）
- **Type** — 從描述推斷，對應 `issue_labels_type` 的其中一個
- **Priority / Component** — 只在使用者提到、且 `issue_labels_optional` 有定義時套用
- **Assignee** — 預設 `@me`
- **Description** — 問題描述、預期功能、驗收標準

若資訊不足以判斷 type 或填寫 description，**詢問使用者**補充。至少需要 title 和 type 才能繼續。

### Step 2: 填寫 Template

讀取 `.agents/skills/create-issue/assets/issue-template.md`，將佔位符替換為實際內容：
- `{{DESCRIPTION}}` → 問題或需求的描述
- `{{EXPECTED}}` → 預期的功能或修復結果（bullet points）
- `{{ACCEPTANCE}}` → 驗收標準（checkbox 格式：`- [ ] 條件`）
- `{{NOTES}}` → 其他備註，若無則寫「無」

### Step 3: 預覽 Issue

列出完整的 issue 內容供使用者確認：

```
## Issue 預覽

**Title**: <title>
**Labels**: <labels, 逗號分隔（含 issue_labels_required）>
**Assignee**: <assignee>

--- Description ---
<填好的 template 內容>
```

**等使用者確認或修改後才進入 Step 4。**

### Step 4: 建立 Issue

執行 **[tracker] 建 issue**（title / labels / assignee / 內文）。
GitHub 端 label 必須已存在於 repo（見 `github.md`），不存在時先告知使用者、不要自行建 label。

### Step 5: 回報結果

回報：
1. Issue URL
2. Issue number
3. 已套用的 labels

## Important Notes

- **`issue_labels_required` 每張都加**（若有定義）
- **Type label 必填** — 若無法判斷，詢問使用者
- **預覽後必須等使用者確認**才能建立
- issue title 與內文語言依 `language`
- **不自動指定 milestone** — 留給後續規劃
- **不自動關聯 PR** — PR 建立時再由 skill `commit-push-pr` 關聯
