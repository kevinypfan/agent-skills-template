# 擴充點（專案在固定時機「多做一步」）

專案客製有三層，從輕到重：

| 層 | 放什麼 | 在哪 |
|---|---|---|
| conventions key | 單一值（`base_branch`、`verify_commands`…） | `.agents/conventions.md` |
| **擴充點** | 在固定時機要多做的事（合併前查外部檢查、專屬檢查清單、先讀領域文件） | `.agents/extensions/<name>.md` |
| 整份讓位 | 流程真正不同時，fork 整份 skill | 專案自己的 `.agents/skills/<s>/` |

擴充點 = 固定目錄、固定檔名、固定時機：專案在**自己 repo** 放 `.agents/extensions/<name>.md`，skill 走到對應步驟就讀、照做。不必 fork skill，也就不會跟 template 分歧。
擴充檔放在專案 repo，同事與 CI agent 讀得到（全域 template 只在使用者本機生效）。

## 通則

- 擴充檔描述**時機**、不描述 skill；讀到的 skill 會做檔內全部內容，要限定某個 skill 就用文字寫條件（例：「只有 `orchestrate-issues` 要做」）。
- **只讀當前 repo 根**（`git rev-parse --show-toplevel`），不隨全域安裝、不退到 `~/.agents`；v1 **不支援個人層**（擴充點是團隊流程；個人偏好用 `~/.agents/conventions.local.md`）。
- 擴充檔**不得要求本次改動範圍以外的寫入**（merge、deploy、改 tracker、觸發 job）；這類項目一律拒絕並回報。`pre-merge` 另外加嚴：**只能唯讀查詢與判定**。擴充檔與 `CLAUDE.md` 同信任等級，所以設下這些限制。
- 目錄內出現清單外的檔名（不是下面三個，也不是 `README.md`、`examples/`）→ 回報警告、不執行。
- 專案 fork 整份 skill 後讀不讀擴充點由 fork 本文決定；建議從含擴充步驟的現版 fork。
- 遵從：skill 回報固定一列「擴充點：context 已讀／無；review 已套用／無；pre-merge：<各項 通過|未通過|未檢查>」，兩種情況（有、沒有）都要寫。
- 用法：複製 `examples/<name>.md` 到專案 `.agents/extensions/<name>.md`，把 `<佔位符>` 換成專案值、刪掉用不到的項目。範例本身不會被讀（只讀 `.agents/extensions/<name>.md`）。

## context

- 時機：`fix-issue` 分析前；architect / reviewer / worker 開工前。`fix-issue` 收尾（Step 4 前）會提示「有新領域知識就建議更新它指向的文件」。
- 格式：自由文字——哪類改動先讀哪份文件，加上索引路徑。
- 範例：[`examples/context.md`](examples/context.md)（含建議的文件結構：精簡 `CLAUDE.md` 當索引、`reference/` 按需讀、`CONTEXT-MAP.md` + 各 context 的 `CONTEXT.md`、`legacy.md`）

## review

- 時機：`commit-push-pr` Step 2 自審（作為第四個角度）；reviewer 的 Standards 軸。
- 格式：條列檢查項；可附「常見過嚴意見」（reviewer 不該提的，避免來回）。
- 範例：[`examples/review.md`](examples/review.md)

## pre-merge

- 時機：`orchestrate-issues` 5.3 CI 判讀後、5.4 merge 前**逐項執行**；`commit-push-pr` Step 6 只列出項目名（它不等 CI）。全部通過是 `auto_merge` 的條件之一。
- 格式：每項一個 `###` 區塊，四欄：

  | 欄 | 內容 |
  |---|---|
  | 名稱 | 區塊標題 |
  | 怎麼查 | 唯讀指令或 API |
  | 通過條件 | 可判定的條件 |
  | 查不到時 | 預設＝**未檢查**，擋住 merge；可明確改寫 |

- 要分辨的四種情況：`allow_failure` / `continue-on-error` 的 job 失敗卻顯示綠燈；路徑篩選使該跑的 job 沒出現；只能手動觸發、合併前必須跑的 job 還沒跑；結果不在 job 狀態裡（外部系統、bot 留的 thread）。後兩種預設判「未通過或未檢查」。
- 範例：[`examples/pre-merge.md`](examples/pre-merge.md)（含 Sonar source / target 比對）

## 不開的擴充點

- `pre-commit`：`verify_commands` 已涵蓋。
- `pr-body`：偵測 repo 自己的 PR template 已涵蓋。

## 全域安裝

`scripts/install-global.sh` **不安裝** `.agents/extensions`，`~/.agents/extensions` 不會存在；skill 與角色即使存在也不讀它。守門（`scripts/check-skill-stubs.sh`）會擋 skill 真身與角色本體出現 `~/.agents/extensions`，以及 `.agents/extensions/` 內清單外檔名的 `.md`（`context` / `review` / `pre-merge` 的 `.md`、`README.md`、`examples/` 不算；專案放自己的擴充檔不受影響）。
