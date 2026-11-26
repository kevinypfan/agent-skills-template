# `_autopilot` — 自動推進規則

`fix-issue`、`commit-push-pr`、`review-pr`、`address-pr-review` 的確認點平常都會停下等使用者。conventions 的 `autopilot` 決定這條鏈能自己推進到哪裡：

| 值 | 推進到 |
|---|---|
| `off`（預設） | 不自動推進，每個確認點照各 skill 本文停下 |
| `pr` | 自審 → commit → push → 開／更新 PR → `review-pr` 審一輪並發佈，**停** |
| `merge` | 接著循環：`address-pr-review` 修 → `review-pr` 下一輪，直到結論「建議合併」，再過下方「merge 關卡」自動 merge |

各 skill 在 Step 0 讀 `autopilot`，依下面「何時生效」判斷本次的有效值；確認點寫「`autopilot` 生效時」的地方照本檔做。本檔沒列的確認點一律照原本停下。

## 何時生效

依序判斷，第一個成立的決定結果：

1. **參數含「由 orchestrate-issues 調度」或「由 orchestrate-issues 呼叫」** → `off`。review、merge 由調度者把關，線內不能自己推進。
2. **PR 已存在，且不確定是自己的 PR** → `off`。用 **[tracker] 看 PR（JSON）** 的作者比對 **[tracker] 取自己帳號**，**確定相同才算自己的**；查不到、判不出來、或只是「這段 code 是本 session 寫的」（例如替同事的 PR 補 commit）都算不確定。替別人的 PR 自動修、自動發 comment、自動 merge 都是對外動作，不在自動範圍。（`review-pr` 為了 adversarial pass「判不出來當自審」的規則方向相反，不影響這裡。）
3. **參數含「由 autopilot 串接（`<值>`）」** → 用該值，不再讀 conventions。鏈的第一跳已經把使用者的臨時指定與 conventions 合成這個值，下游照傳就好。
4. **參數含「由 review-pr 呼叫」但沒有第 3 點的標記**（使用者在 `off` 下手動選了「發佈並處理」）→ `off`。
5. **user input 臨時指定**（「這次手動」「這次只到 pr」「這次做到 merge」）→ 照它，只影響本次。
6. 其餘照 conventions 的值（依該檔「設定來源與優先序」）。

生效時，在該 skill 第一則回報標一行「autopilot：`<值>`（<來源>）」。串接下一個 skill 時，參數一律帶「由 autopilot 串接（`<值>`）」，格式見各 skill 的呼叫範例：

```text
由 autopilot 串接（merge）；42
由 review-pr 呼叫；42，第 2 輪；由 autopilot 串接（merge）
```

## 各 skill 的自動行為

「自動」= 照預設選項做下去，仍在對話中呈現內容與決定，只是不等回覆。

| skill | 確認點 | `pr` / `merge` 時 |
|---|---|---|
| `fix-issue` | 2d 方案 proceed | **照停**（方向確認，省掉風險最大） |
| `fix-issue` | Step 4 建議更新的 context 文件 | 本次範圍內的直接一起改，範圍外的列在回報 |
| `commit-push-pr` | Step 2 self-review 修正確認 | 修法明確、不擴大範圍的直接修；要擴大範圍、改對外契約、或有取捨的 → 停。**自動修過檔案**就要在 commit 前重跑驗證：派 `runner` 跑 `test_command` 與 `lint_command`（依改動路徑），綠燈綁定指紋（`.agents/roles/README.md`「綠燈要綁定內容」）；兩者都沒定義 → 停下問 |
| `commit-push-pr` | PR 已存在：更新描述或追加 comment | 追加 comment |
| `commit-push-pr` | Step 6 之後 | 呼叫 skill `review-pr`（呼叫端是 `address-pr-review` 時不串，由它接） |
| `review-pr` | Step 4 稿件確認 | 先看下面「`review-pr` 的自動選項」，仍完整呈現稿件 |
| `review-pr` | Step 6 回報後 | 狀態不是 `complete` → 停。`merge` 且結論「建議合併」→ 進「merge 關卡」。選了「發佈並處理」→ 串 `address-pr-review` |
| `address-pr-review` | Step 3 分級確認 | 只有 `merge` 自動：Must、Should → 修；Skip → 不採納（理由照寫）；**Discuss → 只拿 Discuss 那幾條問使用者**，定案後繼續自動 |
| `address-pr-review` | Step 4 實作計畫 | 呈現計畫，不等確認 |
| `address-pr-review` | Step 9 回報後 | 有 push → 呼叫 skill `review-pr` 審下一輪；全部不做、沒有 push → 停 |

### `review-pr` 的自動選項

依序判斷，一律不留 inline：

1. 狀態會是 `needs-decision`（有未裁決的 `needs-architect`）或 `incomplete` → **不自動選**，照原本流程問使用者。
2. 結論「建議合併」→「只發佈」（還有非阻塞的 minor／nit 也一樣，不為它們多跑一輪）。`merge` 接著進 merge 關卡，`pr` 停。
3. 本輪輪次 **≥** `autopilot_max_rounds` → 「只發佈」並停，列出剩下的 blocker／major。輪次照 `review-pr` Step 2 的算法，是 PR 上的總輪次，含 autopilot 之前手動審的輪次。
4. `merge` → 「發佈並處理」；本地分支不符該選項的條件 → 「只發佈」並停。`pr` →「只發佈」並停。

## 仍然要停的情況

不論 `autopilot` 是什麼值，下列情況都停下回報、等使用者決定：

- `fix-issue` 的方案 proceed；測試／lint 指令未定義
- 測試或驗證閘門修兩輪仍不過
- `commit-push-pr` 2.5.0 的停點：遠端有本地沒有的 commit、衝突需要判斷、解過衝突要確認的 `range-diff`、autostash 還原衝突、lease 被擋
- 發佈或 push 前發現 PR head 被別人改過（各 skill 的 head 比對）
- `review-pr` 狀態 `needs-decision` 或 `incomplete`
- `address-pr-review` 要處理的 finding 中有**他人（人，不是 bot）留的**意見：整個 Step 3 退回原本的逐條確認；resolve 他人 thread 本來就要問。bot = 帳號名以 `[bot]` 結尾，或 tracker 標為 bot
- `address-pr-review` 實作時發現某條 finding 不該改或做法要變
- 輪數上限（見上方第 3 點）
- merge 關卡任一項不成立

## merge 關卡

只在有效值為 `merge`、`review-pr` 剛回報 `complete` 且結論「建議合併」時進入。先讀 conventions 的 `merge_method`、`merge_subject`、`delete_branch_after_merge`。審到的 sha 記為 `<reviewed>`。依序檢查，**任一項不成立就停下回報**，不自行修 CI、不重試：

1. **CI**：**[tracker] 看 PR CI 狀態（含等待）**，等到跑完。全綠才過。0 個 check：repo 沒有 CI 設定（GitHub `.github/workflows/`、GitLab `.gitlab-ci.yml` 都不存在）視為通過；有設定卻 0 個 → 不過（常是衝突或 CI 沒觸發）。
2. **可合併**：**[tracker] 看 PR 可否合併** 為可合併狀態（判準見 tracker 檔）。
3. **他人的 review**：**[tracker] 列出未解決 thread**，有他人（非 bot）留的未解決 thread → 不過。**[tracker] 看 PR review 狀態**，有人要求修改（GitHub `CHANGES_REQUESTED`）或還缺必要的核准 → 不過。`review-pr` 第 1 輪不看人留的 thread，0 finding 時又不會經過 `address-pr-review`，所以這裡要補查。
4. **pre-merge**：讀擴充點 `.agents/extensions/pre-merge.md`：只看當前 repo 根（`git rev-parse --show-toplevel`），不退到 `~/.agents`；有就照做、沒有就跳過，兩種情況都寫進回報的「擴充點」列。只跑唯讀查詢，**全部通過**才過；未通過或未檢查都不過（語意同 `orchestrate-issues` 5.3）。
5. **head 沒變**：**[tracker] 看 PR（JSON）** 的 head sha 等於 `<reviewed>`。
6. **關閉的 issue**：**[tracker] 看 PR 會關閉哪些 issue**，必須正好是這個 PR 完整解決的 issue；多了或少了 → 停（改 PR 內文需要判斷，不自動改）。
7. **merge**：**[tracker] merge PR**，方法 = `merge_method`，subject 依 `merge_subject`，**一定帶 `<reviewed>`**（GitHub `--match-head-commit`、GitLab `--sha`）。失敗就停，不改成不帶 sha 重試。
8. **收尾**：確認關聯 issue 已關閉（沒關就回報）。`delete_branch_after_merge` 為 `true` → 先 **[tracker] 列出 open PR**，有 PR 以這條分支為 base（疊分支）就不刪、回報裡說明；沒有才刪遠端分支。本地分支若正是目前 checkout 或某個 worktree 的分支，不動它，回報裡提醒可用 skill `clean-disk` 清。

回報：PR URL、merge 方法與 commit、共跑了幾輪 review、各輪修了哪些 finding、不採納的項目與理由、擴充點列。

## 與其他 key 的關係

- `auto_merge` 只管 `orchestrate-issues` 調度時的 merge；單 session 這條鏈只看 `autopilot`。
- `autopilot` 不放寬任何權限，也不跳過驗證閘門、adversarial pass、head 比對；它只省掉「等使用者說好」。
