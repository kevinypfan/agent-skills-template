# pre-merge（範例：複製到 `.agents/extensions/pre-merge.md` 後改）

merge 前逐項執行，全部通過才算可合併。每項只做唯讀查詢；**查不到＝未檢查，擋住 merge**（除非該項「查不到時」明確另寫）。
不用的項目整段刪掉；專案查詢腳本自己放在 repo（例：`<腳本路徑>`），不要把主機或 key 寫死在 template。

### CI 綠燈不等於通過（allow_failure / continue-on-error）

- 怎麼查：列出本 PR 最新 pipeline / checks 的每個 job，找出標了 `allow_failure` 或 `continue-on-error` 的 job，逐個看實際結果。
- 通過條件：這類 job 的狀態是 success；failed / warning / skipped 都不算。
- 查不到時：未檢查。

### 該跑的 job 有出現（路徑篩選）

- 怎麼查：對照 `<CI 設定檔路徑>` 的 `changes:` / `paths:` 規則與本 PR 的改動檔案，列出「依規則應該出現」的 job；再比對 pipeline / checks 實際有哪些。
- 通過條件：每個應出現的 job 都存在且 success。沒出現 ＝ 沒跑，不算通過。
- 查不到時：未檢查。

### 必須手動觸發的 job 已跑過

- 怎麼查：列出 pipeline 中 manual 狀態的 job：`<manual job 名稱清單>`。
- 通過條件：清單內每個 job 都已被觸發，且最新 commit 之後的那次是 success。
- 查不到時：未檢查（不要自行觸發；觸發是寫入動作，回報給使用者）。

### Sonar 品質門檻：source / target 分支比對

- 怎麼查：用 `<專案的唯讀查詢腳本>` 或 Sonar API，對 `<Sonar 主機>` 的專案 `<project key>` 各查一次：
  1. source 分支（PR 分支）在本 PR 改動檔案上的 open issue
  2. target 分支（`base_branch`）在**同一批檔案**上的 open issue
  3. 另外讀 source 分支的 Quality Gate 狀態
  兩邊 issue 以（rule、檔案、message）比對，不比 issue key 與行號（key 因分支而異、行號會位移）。
- 通過條件：source 的 issue 集合沒有比 target 多出來的項目（多出來的才算本 PR 引入），**且** Quality Gate 為 OK。只看分支自己的 Gate 不夠：分支分析的「新程式碼」基準可能與 target 不同，Gate 顯示 OK 合併後仍會多 issue。
- 查不到時：未檢查。source 分支尚未分析（含 Sonar job 是 `allow_failure` 而沒跑或失敗）一律算未檢查，不當成「沒有 issue」。

### bot review 的未解決 thread

- 怎麼查：列出本 PR 的 review thread / discussion，篩出作者為 `<bot 帳號>` 且未 resolve 的項目。
- 通過條件：沒有未解決的 thread；或每個未解決項目都已在 PR 留言說明為何不處理。
- 查不到時：未檢查（bot 結果只在留言裡，不在 job 狀態）。
