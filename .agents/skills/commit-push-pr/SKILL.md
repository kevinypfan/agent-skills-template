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
- 呼叫端可指定「PR 已存在時採追加 comment」（Option A 有此指定就不再詢問）
- 呼叫端可指定「只 rebase」：PR 已存在、沒有新變更，只要把分支 rebase 到最新 base 再推上去（`orchestrate-issues` 在 base 前進造成衝突時使用）
- 疊分支時，呼叫端可給「上一條分支改寫前的 head」（`<old-parent>`）：上一條分支被 squash merge 或 rebase 過時，Step 2.5.0 用 `--onto` 只搬本分支自己的 commit

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

呼叫端指定「只 rebase」且 Step 1 確認工作樹乾淨、PR 已存在 → 跳過本步的審查，直接 Step 2.5（沒有新變更可審）。**push 前的確認不跳過**：Step 3 push 前列出 rebase 前後的 head、`<base>`、有沒有用 `--onto`、有沒有解過衝突（解過的附 2.5.0 的 `range-diff`），等使用者確認（`orchestrate-issues` 的線上由主 session 確認）才 force push。工作樹不乾淨或 PR 不存在 → 停下回報，不猜呼叫端的意思。

先對所有變更做一次審查（環境若有內建的 simplify / review 類 skill 可呼叫它；沒有就自己逐項過），四個角度：
- **Reuse** — 是否有現有工具函式可取代新寫的 code
- **Quality** — 冗餘狀態、copy-paste、leaky abstraction、不必要的註解
- **Efficiency** — 不必要的計算、缺少並行、hot-path 問題
- **專案 review 清單** — 讀擴充點 `.agents/extensions/review.md`：只看當前 repo 根（`git rev-parse --show-toplevel`），不退到 `~/.agents`；有就照做、沒有就跳過，兩種情況都寫進回報的「擴充點」列。逐項檢查清單，並避開檔內列的「常見過嚴意見」。檢查項只做判讀、不改檔；要修的照本 skill 既有的自審確認流程。

**只做 review，不做 auto-fix。** 本步驟是 push 前的自審；skill `review-pr` 審的是已建立的 PR，不適用於這一步。審查完成後：
1. **列出問題清單**，讓使用者決定要修哪些
2. 根據使用者確認的項目修正，跳過不想改的
3. **Review untracked files**：哪些該 commit、哪些該 ignore
4. **使用者確認所有想修的都修完**才進 Step 2.5

### Step 2.5: Rebase 到最新 base，再跑 Verification Gate

#### 2.5.0 必要時 rebase 到 `origin/<base>`（在 commit／push 前）

> **為什麼**：base 在分支開出後可能又 merge 了別的 PR（尤其改同一段文件的）；衝突若拖到 PR 關卡才發現，review 與驗證都已做完，rebase 後 head 變了還要重審。新分支在第一次 push 前先跟上 base；已 push 的分支 rebase 會改寫歷史、讓下一輪 review 退回全量，所以只在真的需要時做。

**`<base>`**：Step 1 查到 PR 已存在 → 一律用該 PR 的 target branch（呼叫端給的 target 只用在建新 PR；疊分支的 PR base 可能已被調度者改回 `base_branch`，呼叫端的值會過期）；PR 不存在 → 使用者指定的 target branch，沒指定用 conventions 的 `base_branch`。

**何時 rebase**：

- PR 不存在：base 有前進就 rebase（分支已 push 過但還沒開 PR 時，照下面的 lease 規則）。
- PR 已存在：只有呼叫端指定「只 rebase」，或 **[tracker] 看 PR 可否合併** 顯示衝突／需更新分支（GitHub `CONFLICTING`、`mergeStateStatus` 為 `DIRTY` 或 `BEHIND`；GitLab `has_conflicts` 或 `need_rebase`；`UNKNOWN` 隔幾秒再查）時才 rebase，其餘跳過。

```bash
git fetch origin <base>                    # 失敗（例如疊分支的上一條分支已刪）→ 停下回報
git rev-list --count HEAD..origin/<base>   # 0 → base 沒前進，跳過 rebase（不產生空 rebase）
```

**分支已 push 過：先確認遠端沒有本地沒有的 commit，並記下 lease**

```bash
git fetch origin <branch>
LEASE=$(git rev-parse origin/<branch>)     # Step 3 的 --force-with-lease 用這個 sha
git rev-list --count HEAD..$LEASE          # 非 0 → 停下回報，不 rebase、不 push
```

遠端領先（網頁上 apply 的 suggestion、別人 push、`gh pr update-branch`／`glab mr rebase` 在伺服器端改過分支）時，rebase 後強推會把那些 commit 蓋掉；交給使用者決定怎麼整合。

**rebase**

```bash
OLD=$(git rev-parse HEAD)
git rebase --autostash origin/<base>                         # 一般情況
git rebase --autostash --onto origin/<base> <old-parent>     # 疊分支且呼叫端給了 <old-parent>
```

- **疊分支**：上一條分支被 squash merge 或 rebase 過時，直接 rebase 會重放它原本的 commit、幾乎一定衝突，所以要用 `--onto`。呼叫端沒給 `<old-parent>`，而 `git log --oneline origin/<base>..HEAD` 列出不屬於本分支的 commit → 停下回報，不硬 rebase。
- `--autostash` 還原時**不保留 staged 狀態**：rebase 前先記下 `git diff --cached --name-only`，rebase 後照清單重新 `git add`（有些閘門比對的是 index，例如產生的檔案要先 stage）。**autostash 還原時衝突 → 停下回報**，附上 `git stash list` 裡那一筆；未 commit 的成果在 stash 裡，不自行解衝突、不 `git stash drop`。
- rebase 有衝突：需要判斷（兩邊改同一段語意）或解不了 → `git rebase --abort`、停下回報，不硬解。機械性衝突可以在這裡解，但**解過衝突就要把 `git range-diff <OLD 的 base 點>..$OLD origin/<base>..HEAD` 交給使用者確認**後才往下（`<OLD 的 base 點>` 是 `git merge-base $OLD origin/<base>`，用 `--onto` 時是 `<old-parent>`）；Step 2 的確認發生在 rebase 前，涵蓋不到這些內容。
- **rebase 移動了 HEAD → 呼叫端先前的綠燈作廢**：呼叫端（`fix-issue`、`address-pr-review`）是在舊 base 上跑的測試，`.agents/roles/worktree-fingerprint.sh` 的指紋含 HEAD，也會因此對不上。2.5.1 要重跑驗證。
- 分支已 push 過：Step 3 用 `git push --force-with-lease=<branch>:$LEASE`（不用 `--force`，也不用不帶參數的 `--force-with-lease`：tracking ref 被別的 fetch 更新過時，不帶參數的 lease 會照樣把遠端蓋掉），且 Step 4 Option A 的追加 comment 要註明「已 rebase 到 origin/<base>」。

#### 2.5.1 Verification Gate（conditional）

> **為什麼**：本 skill 假設呼叫端（`fix-issue` 等）已先驗證，但**直接呼叫**時沒有任何 build/test 把關，可能 push 壞掉的 code。此 gate 補這個洞。與 caller 冗餘是刻意的——重跑廉價且 idempotent，寧可冗餘也不要漏網的壞 build。

對 conventions `verify_commands` 的每一列 `<regex> → <指令>`：

```bash
git status --short --untracked-files=all | grep -qE '<regex>' && echo MATCH || echo SKIP
```

- 一定要 `--untracked-files=all`：預設只把新目錄印成一行 `?? newdir/`，裡面的檔案比對不到，整個新模組會漏過閘門
- `MATCH` → 跑該指令；**fail 就停**，回報錯誤、絕不 commit
- 全部 `SKIP` 或 `verify_commands` 為空 → 跳過
- **2.5.0 rebase 移動了 HEAD**：除了上面的比對，另外跑 conventions 的 `test_command` 與 `lint_command`（依改動路徑選對應那列，跟 `fix-issue` Step 3 同一組），派給 `runner` agent 並等結果，綠燈要綁定指紋（`.agents/roles/README.md`「綠燈要綁定內容」）。兩者都沒定義 → 問使用者要跑什麼；使用者說不跑就在回報註明「rebase 後未驗證」。fail 就停，絕不 push

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
# 2.5.0 rebase 過且分支已 push 過 → 改用：
# git push --force-with-lease=<branch>:$LEASE origin <branch>
```

- 「只 rebase」：沒有東西可 commit，跳過 `git add`／`git commit`，經 Step 2 所列的確認後只做 push（用上面的 `--force-with-lease`）；2.5.0 判定不用 rebase 就什麼都不推，回報「base 沒前進／無衝突，未 rebase」
- push 被 lease 擋下 → 停下回報，不改用 `--force`
- `<scope>` 須在 `commit_scopes` 內（若有定義）
- `<commit_trailer>` 依 conventions（Claude Code / Codex 各自的 Co-Authored-By）

### Step 4: Create or Update PR

#### Option A: PR 已存在

呼叫端已指定採追加 comment → 直接採用，不再詢問；否則**詢問使用者**要：
- **追加 comment**（預設，適合小修正 / review 回應）→ **[tracker] 留 PR 總結 comment**，內容：

  ```markdown
  ## 追加變更

  ### Commit: <latest commit hash>
  <簡述原因：回應 review、修正問題等>

  ### 變更內容
  <bullet points>
  ```

  Step 2.5.0 有 rebase 過（head 因此改變）時，在「簡述原因」註明「已 rebase 到 origin/<base>」，並寫 rebase 後是否重跑了驗證。「只 rebase」沒有新 commit：`### Commit` 填 rebase 後的 head，「變更內容」寫「無新變更，僅 rebase」（解過衝突則列出解了哪些檔）。

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

1. PR URL；可接著呼叫 skill `review-pr` 審這個 PR
2. PR 內容摘要，含用了哪份內文骨架（內建／repo 的哪個檔）
3. 若有留 inline comment，列出留了哪些；有失敗而改併進總結 comment 的，另列哪幾條、原因
4. 讀擴充點 `.agents/extensions/pre-merge.md`：只看當前 repo 根（`git rev-parse --show-toplevel`），不退到 `~/.agents`；有就照做、沒有就跳過，兩種情況都寫進回報的「擴充點」列。此處只讀出 `###` 標題，不執行任何「怎麼查」指令；本 skill 不等 CI，註明「merge 前由調度者（`orchestrate-issues` 5.3）或人工執行」。
5. 固定一列：「擴充點：review 已套用／無；pre-merge：<名稱> 未檢查（未執行，merge 前由 orchestrate-issues 5.3 或人工執行）」，每個項目一筆；沒有 pre-merge 寫「pre-merge：無」

## Important Notes

- **Always do self-review first**
- PR 內文語言依 `language`；**commit message 語言依 `commit_language`**，格式一律 Conventional Commits `type(scope): description`
- **Target branch 預設 `base_branch`**，使用者可覆蓋
- **Never skip the review step** — push 前要使用者確認
- **Rebase 先於 gate**：新分支 push 前先 rebase 到 `origin/<base>`；已 push 的分支只在衝突、需更新或呼叫端「只 rebase」時才 rebase，先確認遠端沒有領先，再用帶 sha 的 `--force-with-lease=<branch>:<sha>`；衝突需要判斷、autostash 還原衝突、lease 被擋 → 停下回報
- **Verification gate**：`verify_commands` 有命中就必須綠才 commit；rebase 移動了 HEAD 就另跑 `test_command`／`lint_command`，綠燈對的是 rebase 後的內容
- **PR 已存在**：問使用者要更新描述還是追加 comment；小變更預設 comment
- **Staging**：永遠明列檔案，禁止 `git add -u` / `git add .`
