# 總結 comment 範本

填入 `{{...}}` 後，作為 **[tracker] 留 PR 總結 comment** 的內容。內文語言依 conventions 的 `language`（標題固定）。
沒有內容的區段整段省略，不要留空標題。`{{SHORT_SHA}}` 至少 7 碼（`git rev-parse --short=7 <head>`，碰撞時會更長），同一 PR 跨輪用同樣長度；解析端接受 7 碼以上。

**只輸出下方第一條 `---` 之後的範本本體**；本檔開頭到該線為止是填寫說明，所有 `<!-- -->` 註解也要在發出前移除。

行文：
- 問題導向，篇幅給問題與可執行建議；正面評價壓縮成一句確認，不立「亮點」章節。
- 不吹捧，用「符合預期」「解決問題」這類中性描述。
- 單一觀點只在一個區段說一次；結論不重述前文。
- 嚴重度只用文字（blocker / major / minor / nit / needs-architect），不用 emoji。
- 長程式碼或技術細節用 `<details>` 折疊。

---

## PR Review（第 {{ROUND}} 輪，審至 {{SHORT_SHA}}）

### 總覽

{{OVERVIEW}}
<!-- 2-4 句：這個 PR 做什麼、整體評價、本輪核心結論。
     自審在此註明「自審」；第 2 輪起先一句帶過上輪處理狀況；
     審查範圍若退回全量（上輪 sha 不可用、或不是目前 head 的祖先）要在此說明。 -->

### 上輪追蹤
<!-- 第 2 輪起才有；第 1 輪整段省略 -->

| 上輪 finding | 狀態 |
|---|---|
| {{PREV_FINDING}} | {{已修（{{SHA}}）／未修／未修（非阻塞）／不採納（理由成立）／已解決（無需改動）}} |
<!-- 含人留的未解決 thread。未修的在下方 findings 再點名；已修、不採納與已解決（無需改動）列在這裡即可。「未修（非阻塞）」只用於上輪的 minor／nit。 -->

### Findings

<!-- 依嚴重度排：blocker → major → minor → nit → needs-architect。
     每條一個小標，標題前加序號 {{N}}（1 起，依排序；供 `summary:<comment id>#<序號>` 引用），附 file:line（diff 新檔行號）。
     沒有檔案可附時（例如 PR 描述與實際不符）寫「（PR 描述「<段落>」）」取代 file:line。 -->

#### {{N}}. [{{SEVERITY}}] {{TITLE}}（`{{FILE}}:{{LINE}}`）<!-- 無檔案時：（PR 描述「<段落>」） -->

{{DESCRIPTION}}
<!-- 問題是什麼、為什麼是問題（對照實際 code）、建議修法。
     已另留 inline 的在標題後加「（已留 inline）」。
     對照 spec 審時，另列「spec 有但 diff 沒做」「diff 有但 spec 沒要」。 -->

### Assumptions
<!-- 有 assumption 清單才有；沒有整段省略 -->

| 前提（出處） | 證據 | 判定 |
|---|---|---|
| {{ASSUMPTION}}（{{PR 描述／註解 file:line／測試名／由 code 推導}}） | {{file:line 或「未找到」}} | {{成立／無證據且缺 guard／待外部確認（要問誰）／證據相反}} |
<!-- 「無證據且缺 guard」「證據相反」要在 Findings 有對應條目；「待外部確認」不算 finding、不擋收斂，但要寫清楚去哪確認。 -->

### Adversarial pass
<!-- 自審或高風險的 PR 才有（其他整段省略）；一旦有過，之後每一輪都要保留。第一句固定寫狀態：「外部 agent／reviewer 已於第 N 輪（審至 <sha>）對整個 PR 跑過」（第 2 輪起沿用歷輪的 N 與 sha，下一輪靠這句判讀，不重跑）；或「未執行」與原因。一段加清單：
     問了誰（外部 agent／reviewer agent（含 adversarial_external=false 或外部不可用）／主對話自審）、對整個 PR 或增量、
     屬實併入上方的幾條（標來源）、經查不成立的逐條「宣稱 → 為何不成立」。
     未執行要明寫原因，且結論不得寫「建議合併」。 -->

### 結論

{{CONCLUSION}}
<!-- 一段：建議合併／處理 blocker 後合併／建議再討論；點名阻塞項與非阻塞項。
     「建議合併」的條件：本輪無新 blocker／major，上輪的 blocker／major 已修或不採納成立（minor／nit 未處理不阻擋），且無未裁決的 needs-architect；
     自審或高風險另要求 Adversarial pass 已對整個 PR 跑過。 -->
