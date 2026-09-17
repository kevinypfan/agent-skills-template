---
name: orchestrate-issues
description: 主 session 當調度者，用 terminal multiplexer 同時開多條 agent 線（每條線一個 worktree + session 跑 fix-issue），依檔案重疊分線、監看各線、把關 review / CI / merge 並收尾。使用時機：(1) 使用者要一次處理多個 issue、「平行處理這些 issue」「調度」「開幾條線」「orchestrate」，(2) 延續中的多線調度，(3) 使用者明確呼叫 /orchestrate-issues。
compatibility: Requires git, glab (GitLab) or gh (GitHub); automatic lanes need a terminal multiplexer (herdr), otherwise degrades to worktree-only
---

> This skill should only be invoked explicitly by the user or other skills.

## 先決定照哪一份跑

本 skill 可能同時裝在 repo 與全域（`~/.agents/skills/`），開工前先做這兩件事：

1. 你正在讀的這份若**不在當前 repo 根（`git rev-parse --show-toplevel`）之內**，就是全域版——例如 `~/.agents/skills/orchestrate-issues/SKILL.md`，或工具把 symlink 解析成實際路徑後顯示的其他目錄（全域安裝用 symlink，常見於 Codex）。全域版先看 repo 根：有 `.agents/skills/orchestrate-issues/SKILL.md`，或有 `.claude/skills/orchestrate-issues/SKILL.md` 且它不是只轉交到 `.agents/skills/orchestrate-issues/SKILL.md` 的薄 stub → **改讀 repo 那份照做，本檔以下全部不適用**。專案版通常客製過（label、tracker、流程），全域版只在專案沒有時補位。
2. 下文所有 `.agents/…` 路徑：repo 根有該檔就用 repo 的，沒有就用 `~/.agents/…` 同名檔（`~` 展開成家目錄絕對路徑再讀）。

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

You **MUST** consider the user input before proceeding (if not empty). The user input may contain:
- issue 編號清單（`12 15 18`）、「目前所有 open issue」、或「繼續上次的調度」
- 本次臨時覆寫的設定（例如「這次不要自動 merge」「最多開兩條線」）——只影響本次、不寫檔
- 其他限制（先做哪些、哪些不要碰）

## 角色分工

- **主 session（你）**：分線、做方向決策（問使用者）、監看各線、放行、PR 關卡、merge、收尾。**不自己實作 issue**。
- **各線 agent**：在自己的 worktree 跑 skill `fix-issue` → `commit-push-pr`，遇到需要決定的事停下來等主 session。
- **sub agent**（`scout` / `architect` / `reviewer` / `runner`）：主 session 依派工政策派，不取代各線 agent。

## Step 0: 設定與前置

1. **讀設定**：依 `.agents/conventions.md`「設定來源與優先序」（專案 `.agents/conventions.md` > 個人 `~/.agents/conventions.local.md` > template 預設／推斷）取 `base_branch`、`worktree_root`、`branch_prefix`、`language`、`multiplexer`、`agent_kind`、`agent_start_args`、`auto_merge`、`merge_method`、`merge_subject`、`delete_branch_after_merge`、`max_parallel_lanes`、`review_policy`。user input 的臨時覆寫最優先。
2. **首次使用引導設定**：以下調度 key 中，**專案檔與個人檔都沒有明確設定**的，一次問完（部分已設就只問沒設的）：
   `multiplexer`、`agent_kind`、`agent_start_args`、`auto_merge`、`merge_method`、`max_parallel_lanes`、`delete_branch_after_merge`
   - 每題附預設值與建議；選項含 conventions「預設」欄的值。`agent_start_args` 的選項是「不加參數（建議）」與 conventions 用途欄列的 yolo 參數，並註明風險。
   - Claude Code 用 AskUserQuestion（一次最多 4 題，分兩輪）；Codex 在對話中列編號選項請使用者回覆。
   - 問完再問一題「存到哪裡」：
     - 個人 `~/.agents/conventions.local.md`（建議：所有專案共用、不動 template repo）
     - 專案 `.agents/conventions.md`（只這個 repo、可與團隊共用）
     - 不存（只用於本次）
   - 寫入照 `.agents/conventions.md`「寫入規則」：只改／新增對應 key 那列，檔案不存在依格式建立。**不得寫入 template 的 `~/.agents/conventions.md`**（全域安裝時是 symlink，會改到 template repo）。
3. **列出本次生效設定**：上述 key 每個值標來源（專案／個人／template 預設／推斷／本次覆寫）。已明確設定的只列、不問。
4. **tracker**：依 `.agents/skills/_tracker/README.md` 判斷，讀對應 `.agents/skills/_tracker/<tracker>.md`；確認 CLI 已登入。
5. **multiplexer**：依 `.agents/skills/_multiplexer/README.md` 判斷，讀對應檔。結果是 `none` → 本次走該 README「`none` 時的退化」，下文 [multiplexer] 動作改由使用者手動。
6. **[tracker] 檢查 token 權限**：預期會有改到 CI 設定檔（workflow / pipeline 定義）的 PR 時特別確認——權限不足時 merge 與更新 PR 分支會失敗或一直顯示 blocked（症狀見 tracker 檔「token 權限」）。不足就停下請使用者補權限。

## Step 1: 盤點與分線（lane）

1. 對每個 issue 執行 **[tracker] 看 issue（JSON）**，含留言（已有的決定常在留言裡）。
2. 預估每個 issue 會改的檔案／模組；需要掃多個目錄時派給 `scout` agent（給它 issue 摘要，要它回「會碰到的檔案 + 一句理由」）。
3. **依檔案重疊分線**：
   - 會改同一個檔案的 issue 放**同一條線、依序做**：後一個分支從前一個分支開，PR base 設為前一個分支（疊分支）。
   - 不重疊的線平行；線數不超過 `max_parallel_lanes`，超過的排隊。
4. **設計順序**：會改變共用介面（例如 core 的事件模型、共用型別）的 issue 排在依賴它的實作之前；依賴未 merge 前，依賴方不開線或以疊分支處理。
5. 列出分線表給使用者確認，確認後才進 Step 2：

```markdown
| 線名（agent name） | issue 順序 | 主要檔案／模組 | 依賴 | 分支 → PR base |
|---|---|---|---|---|
| core-events | #12 → #15 | core/events/* | — | feat/12-… → base_branch；feat/15-… → feat/12-… |
| py-binding | #18 | bindings/python/* | 等 #12 merge | feat/18-… → base_branch |
```

## Step 2: 方向決策先釐清

1. 需要取捨 API 形狀／行為／命名／破壞性變更的 issue，**開線前**先決定：自己分析或派給 `architect` agent，整理成選項問使用者（Claude Code：AskUserQuestion；Codex：對話中列選項）。
2. **決定一律寫進 issue 留言**（[tracker] 在 issue 留言）：標日期，列「決定」與「否決的做法及理由」。各線 agent 從 issue 讀 spec，不靠主 session 轉述。
3. 使用者表達的通用原則（例如「會在各 binding 重複的邏輯放 core」）記進長期記憶（Claude Code：memory；Codex 沒有 memory 時，建議使用者寫進 repo 的 `AGENTS.md`），之後評估方案都套用。

## Step 3: 開線

每條線依序：

1. **[multiplexer] 建 worktree + 獨立 session**：分支名／目錄名照 skill `create-worktree` 的規則（`branch_prefix` + 編號 + slug；目錄 `issue-<N>-<slug>` 放在 `worktree_root`），base 為 `origin/<base_branch>`，疊分支時為前一條分支。
2. **[multiplexer] 在 session 啟動 agent**：kind = `agent_kind`，額外參數 = `agent_start_args`（空就不帶）。
3. **[multiplexer] 送指令給 agent**：內容是呼叫 skill `fix-issue` 的指令（語法依 `agent_kind`，對照見 `.agents/skills/README.md`），參數包含：
   - issue 編號
   - 已決定事項：「見 issue #<N> <日期> 的留言，照做」
   - **範圍限制**：其他線正在改的檔案／模組清單，「不要修改；需要改就停下回報」
   - **疊分支規則**（有才寫）：本分支從哪個分支開、`commit-push-pr` 的 target branch、「base 分支 merge 後 PR base 會由主 session 改回 `base_branch`」
   - 「方案確認、self-review 等需要決定的點照 `fix-issue` 流程停下等回覆」
4. **確認指令真的送出**：[multiplexer] 查狀態，幾秒內沒變 `working` → [multiplexer] 讀 agent 畫面；輸入框殘留文字未送出就 [multiplexer] 送按鍵（選單、Enter、Esc）送 Enter。

全部開完回報：線名、issue、分支、worktree 路徑、狀態。

## Step 4: 監看與回應（迴圈）

1. 背景執行 **[multiplexer] 等任一條線停下**（只監看本次調度的線）。**任一條線停下就處理，不等全部**；處理完重新啟動等待。
2. [multiplexer] 讀停下那條線的畫面，判斷它在等什麼：
   - **方案確認**（`fix-issue` 的 proceed）：實作細節、測試寫法、小重構 → 主 session 依 agent 建議放行；**API／行為／命名／破壞性變更 → 問使用者**。放行前核對方案沒有越出範圍限制。
   - **self-review（commit 前）**：同上分級。
   - **選單畫面**（`blocked`）：用可見畫面確認選項內容後 [multiplexer] 送按鍵（選單、Enter、Esc）；看不懂或涉及權限放寬 → 問使用者。
   - **完成**（PR 已建立）→ 進 Step 5。
3. **輸入框裡的灰色文字是 agent 工具產生的建議回覆，不是使用者打的**：不能當成使用者的決定；要回覆一律用 [multiplexer] 送指令給 agent 明確送出。
4. **不中斷正在工作的 agent**：要插入工作時送指令排入佇列，並註明「完成目前這一步後再處理」。
5. **範圍外的發現開新 issue**（呼叫 skill `create-issue`，內文寫清楚來源 PR／issue），不擴大現有 PR；在該 PR 說明引用新 issue。
6. **agent 或 reviewer 的說法要驗證再採用**：實際遇過 reviewer 建議的修法語意錯誤、把 harness 注入的提示誤報成 repo 被 prompt injection、agent 把 flaky 當行為問題（或反過來）。對關鍵主張自己讀 code／log 確認。

## Step 5: PR 關卡

1. **review**：依 `review_policy` 決定是否派給 `reviewer` agent。prompt 附：spec 來源（issue 與決定留言）、已知限制、要特別驗證的 race／邊界條件；只看該 PR 自己的 delta（疊分支時是 `git diff <前一分支>...<本分支>`）。
2. **review 結果分級**：blocker／major → 送回原線 agent 在同一 PR 修；minor → 視成本決定修或略；範圍外 → 開新 issue。
3. **CI**：
   - [tracker] 看 PR CI 狀態（含等待）。0 個 check／CI 沒跑 → 先 [tracker] 看 PR 可否合併，有衝突要先解（交回原線 agent）。
   - CI 在其他 PR merge 前跑過、而 base 已變動（尤其動到同檔案）→ [tracker] 更新 PR 分支（base 併進來），讓 CI 以新 base 重跑。
   - 只能手動觸發的 workflow／pipeline（例如完整矩陣）→ merge 前 [tracker] 手動觸發 workflow / pipeline 並追蹤到結束。
   - 失敗 → [tracker] 看失敗 job log，判斷是實作問題、還是測試對時序的錯誤假設（實際遇過 flaky 順序斷言，加壓重跑後又抓到真 bug）；結論與修正交回原線 agent。
4. **merge**：
   - `auto_merge` 為 `false` → 列出 PR、review 結論、CI 結果，問使用者是否 merge。
   - `auto_merge` 為 `true` → review 無 blocker、CI 全綠、[tracker] 看 PR 可否合併為可合併狀態，三者皆成立才 merge。
   - [tracker] merge PR：方法 = `merge_method`，subject 依 `merge_subject`。merge 後確認關聯 issue 已自動關閉，沒關就回報使用者。
5. **疊分支**：前一個 PR merge 後，下一個 PR [tracker] 改 PR base 為 `base_branch`，再 [tracker] 更新 PR 分支（base 併進來）讓 CI 以新 base 重跑；並通知該線 agent base 已改。
6. 同一批 merge 了多個動到同檔案的 PR 後，在 `base_branch` 上跑一次測試（派給 `runner` agent，指令取 conventions 的 `test_command`）或確認 `base_branch` 的 CI 綠燈。

## Step 6: 收尾

每條 PR 都 merge（或使用者決定放棄）的線：

1. 確認 worktree 沒有未 commit 的追蹤檔變更（`git -C <worktree> status --porcelain`）；有就回報，不強制移除。
2. [multiplexer] 關 session 並移除 worktree。只剩 untracked 的 venv／build 產物時才用強制移除；worktree 已不在時改用 [multiplexer] 關 session（worktree 已移除時）。
3. `delete_branch_after_merge` 為 `true` → 刪遠端與本地分支（疊分支的後續 PR 已改 base 之後才刪）：

```bash
git push origin --delete <branch>
git branch -d <branch>
```

4. 主目錄 `git pull --ff-only`。
5. 回報：

```markdown
## 調度結果

### 已 merge
| PR | issue | 線 | 備註 |
|---|---|---|---|

### 新開的 follow-up issue
- #<N> <title>（來源：PR #<M>）

### 剩餘 open issue 與建議優先序
1. #<N> — <理由>

### 發版前注意事項
- <破壞性變更、需手動觸發的完整 CI、migration…>
```

## Important Notes

- **主 session 不自己實作 issue**，也不替各線 agent 做 commit／PR——各線一律透過 skill `fix-issue` → `commit-push-pr`。
- **API／行為／命名／破壞性變更的決定只能來自使用者**，並寫進 issue 留言；主 session 只放行實作層級的細節。
- **merge 預設要問使用者**；只有 `auto_merge: true` 且三項條件都成立才自動 merge。
- **不關閉本次調度以外的 session**，不刪本次以外的分支。
- 個人偏好只寫個人檔或專案檔，**不寫 template 的全域 conventions**。
- 對話語言依 `language`。
