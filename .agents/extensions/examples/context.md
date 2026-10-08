# context（範例：複製到 `.agents/extensions/context.md` 後改）

開工前（分析 issue、設計、實作之前）先照下表讀對應文件。查完沒找到相關說明，本身就是「新知識」的訊號：收尾時補進它指向的文件。

## 一定先讀

- `CLAUDE.md` / `AGENTS.md`（索引，約 50 行）：只寫一定要知道的事，細節連到 `reference/`。
- `<docs 目錄>/CONTEXT-MAP.md`：各 bounded context、上下游關係、同名不同義的陷阱。

## 依改動類型再讀

| 改動碰到 | 先讀 |
|---|---|
| `<目錄 A>/` | `<目錄 A>/CONTEXT.md`（詞彙表）、`<docs 目錄>/reference/<主題 A>.md` |
| `<目錄 B>/` | `<目錄 B>/CONTEXT.md`、`<docs 目錄>/reference/<主題 B>.md` |
| 資料 schema / migration | `<docs 目錄>/reference/<資料主題>.md` |
| 跨 context 的呼叫 | `<docs 目錄>/CONTEXT-MAP.md` 的上下游章節 |

## 過時寫法

- `<docs 目錄>/legacy.md`：集中列出過時寫法與死碼位置，**不要當範本照抄**。目標是逐步歸零；改到其中一項時，在回報中建議更新該檔。

## 建議的文件結構

```
CLAUDE.md / AGENTS.md         精簡索引，只寫一定要知道的事
<docs 目錄>/
├── CONTEXT-MAP.md            bounded context 清單、上下游關係、同名陷阱
├── legacy.md                 過時寫法與死碼位置（集中一份）
└── reference/                各主題一份，需要時才讀
    └── <主題>.md
<context 目錄>/CONTEXT.md     該 context 的詞彙表
```

- `CONTEXT.md` 每個詞條：定義、**避免使用的說法**（同名不同義或舊稱）。
- 「這個詞是什麼意思」（`CONTEXT.md`）與「這個詞在 code 哪裡」（`reference/`）分開寫。

## 收尾

- 這次有學到新的領域知識（新詞、新的 context 邊界、新發現的過時寫法）→ 提醒使用者、在回報中建議更新上面指向的文件（不自行改動範圍以外的檔案）。
