---
name: commit-push-pr
description: Self-review diff, run the project's verification gate, commit, push, and create or update a Pull Request / Merge Request (GitLab or GitHub, auto-detected) with the standard template.
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

> This skill should only be invoked explicitly by the user or other skills.

## 先決定照哪一份跑

本 skill 可能同時裝在 repo 與全域（`~/.agents/skills/`），開工前先做這兩件事：

1. 你正在讀的這份若**不在當前 repo 根（`git rev-parse --show-toplevel`）之內**，就是全域版——例如 `~/.agents/skills/commit-push-pr/SKILL.md`，或工具把 symlink 解析成實際路徑後顯示的其他目錄（全域安裝用 symlink，常見於 Codex）。全域版先看 repo 根：有 `.agents/skills/commit-push-pr/SKILL.md`，或有 `.claude/skills/commit-push-pr/SKILL.md` 且它不是只轉交到 `.agents/skills/commit-push-pr/SKILL.md` 的薄 stub → **改讀 repo 那份照做，本檔以下全部不適用**。專案版通常客製過（label、tracker、流程），全域版只在專案沒有時補位。
2. 下文所有 `.agents/…` 路徑：repo 根有該檔就用 repo 的，沒有就用 `~/.agents/…` 同名檔（`~` 展開成家目錄絕對路徑再讀）。

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

1. 讀 `.agents/conventions.md`（依該檔「設定來源與優先序」：專案 `.agents/conventions.md` > 個人 `~/.agents/conventions.local.md` > template 預設／推斷）取 `base_branch`、`pr_labels`、`pr_assignee`、`pr_template`、`commit_scopes`、`commit_trailer`、`commit_language`、`verify_commands`、`language`。
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

先對所有變更做一次審查（環境若有內建的 simplify / review 類 skill 可呼叫它；沒有就自己逐項過），四個角度：
- **Reuse** — 是否有現有工具函式可取代新寫的 code
- **Quality** — 冗餘狀態、copy-paste、leaky abstraction、不必要的註解
- **Efficiency** — 不必要的計算、缺少並行、hot-path 問題
- **專案 review 清單** — 讀擴充點 `.agents/extensions/review.md`：只看當前 repo 根（`git rev-parse --show-toplevel`），不退到 `~/.agents`；有就照做、沒有就跳過，兩種情況都寫進回報的「擴充點」列。逐項檢查清單，並避開檔內列的「常見過嚴意見」。檢查項只做判讀、不改檔；要修的照本 skill 既有的自審確認流程。

**只做 review，不做 auto-fix。** 審查完成後：
1. **列出問題清單**，讓使用者決定要修哪些
2. 根據使用者確認的項目修正，跳過不想改的
3. **Review untracked files**：哪些該 commit、哪些該 ignore
4. **使用者確認所有想修的都修完**才進 Step 2.5

### Step 2.5: Verification Gate（conditional）

> **為什麼**：本 skill 假設呼叫端（`fix-issue` 等）已先驗證，但**直接呼叫**時沒有任何 build/test 把關，可能 push 壞掉的 code。此 gate 補這個洞。與 caller 冗餘是刻意的——重跑廉價且 idempotent，寧可冗餘也不要漏網的壞 build。

對 conventions `verify_commands` 的每一列 `<regex> → <指令>`：

```bash
git status --short --untracked-files=all | grep -qE '<regex>' && echo MATCH || echo SKIP
```

- 一定要 `--untracked-files=all`：預設只把新目錄印成一行 `?? newdir/`，裡面的檔案比對不到，整個新模組會漏過閘門
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

- **更新 PR 描述**（大幅變更，會覆寫原描述）→ **[tracker] 更新 PR 描述**，內容依 Option B 步驟 1–3（選骨架、填寫、關閉語法）重填

#### Option B: 建新 PR

1. 選內文骨架（依 `pr_template`）：
   - `auto`：**[tracker] 找 repo 的 PR template**，找到就用它；沒有 → 內建 `.agents/skills/commit-push-pr/assets/pr-template.md`
   - `builtin`：內建那份
   - 路徑：用該檔；檔案不存在就停下來告訴使用者
2. 填寫：
   - **內建 template**：替換佔位符
     - `{{RELATED_ISSUES}}` → 相關 issue/PR 連結，若無寫「無」（關閉語法見步驟 3）
     - `{{SUMMARY}}` → 目的和主要變更
     - `{{CHANGES}}` → 變更內容（bullet points）
     - `{{TESTING}}` → 如何測試；有新增/修改測試案例則逐一條列
     - `{{NOTES}}` → 其他說明，若無寫「無」
   - **repo 的 template**：
     - 保留它的標題、順序與欄位，逐欄依 commit 與 diff 填寫；填不出來寫「無」或「不適用」，**不要刪欄位**
     - 標題沿用 template 原文，填寫內容依 `language`
     - checkbox 只勾實際做過、驗證過的項目，其餘保持未勾
     - 寫給填寫者看的 HTML 註解（`<!-- 請說明… -->`）填完後刪掉；看起來是工具標記的註解（release / changelog bot 等的 marker）保留
     - 概要、變更內容、關聯 issue、測試這四項：template 有同義標題或專用欄位（不論語言，如 `How to test` ≡ 測試）就算涵蓋，內容填進該欄；都沒有才在最後補一段。沒把握時填進最接近的欄位，不另外加段
     - 驗證閘門結果：有對應 checkbox 就照實勾，沒有就在測試欄註記
3. **關閉語法（不論哪份骨架，送出前檢查整份內文）**：這個 PR 完整解決 issue 才寫關閉語法（如 `Closes #N`）；只完成一部分、或 issue 拆成多個 PR 時寫 `Refs #N`，而且**整份內文與 commit message 都不能出現 tracker 的自動關閉關鍵字緊接 `#N`**（連「之後的 PR 會 close #N」這種敘述也會觸發，關鍵字清單見 `_tracker/<tracker>.md`「自動關閉關鍵字」）。repo template 預填的 `Closes #` / `Fixes #` 也照此改寫
4. 執行 **[tracker] 建 PR**：title `<type>(<scope>): <PR title>`、base = target branch、assignee = `pr_assignee`、labels = `pr_labels`、內文 = 填好的 template

### Step 5: Inline Comments on Diff (Optional)

**預設不留。** 只有使用者要求在 diff 上留 inline comment（解釋非顯而易見的設計決策：為何選 A 不選 B、trade-off、workaround、隱含相依）時才做：

1. **[tracker] 看 PR diff 版本**，取得定位用的 sha（剛 push 完要確認 head sha 已更新，見 tracker 檔）。取不到 → 整批改併進 **[tracker] 留 PR 總結 comment**，並在 Step 6 註明原因
2. 逐條 **[tracker] 在 diff 上留 inline comment**。只留必要的，不重複 PR 描述已說的
3. **單條失敗不中斷**（多半是該行不在 diff 內）：繼續留剩下的；全部試完後，把失敗的項目（每條標明原定 `檔案:行號`）併進一則 **[tracker] 留 PR 總結 comment**，並在 Step 6 列出

### Step 6: Report Result

1. PR URL
2. PR 內容摘要，含用了哪份內文骨架（內建／repo 的哪個檔）
3. 若有留 inline comment，列出留了哪些；有失敗而改併進總結 comment 的，另列哪幾條、原因
4. 讀擴充點 `.agents/extensions/pre-merge.md`：只看當前 repo 根（`git rev-parse --show-toplevel`），不退到 `~/.agents`；有就照做、沒有就跳過，兩種情況都寫進回報的「擴充點」列。此處只讀出 `###` 標題，不執行任何「怎麼查」指令；本 skill 不等 CI，註明「merge 前由調度者（`orchestrate-issues` 5.3）或人工執行」。
5. 固定一列：「擴充點：review 已套用／無；pre-merge：<名稱> 未檢查（未執行，merge 前由 orchestrate-issues 5.3 或人工執行）」，每個項目一筆；沒有 pre-merge 寫「pre-merge：無」

## Important Notes

- **Always do self-review first**
- PR 內文語言依 `language`；**commit message 語言依 `commit_language`**，格式一律 Conventional Commits `type(scope): description`
- **Target branch 預設 `base_branch`**，使用者可覆蓋
- **Never skip the review step** — push 前要使用者確認
- **Verification gate**：`verify_commands` 有命中就必須綠才 commit
- **PR 已存在**：問使用者要更新描述還是追加 comment；小變更預設 comment
- **Staging**：永遠明列檔案，禁止 `git add -u` / `git add .`
