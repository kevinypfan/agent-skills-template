# `_multiplexer` — terminal multiplexer 指令對照層

本目錄**不是 skill**（沒有 `SKILL.md`，產生器與守門腳本跳過 `_` 開頭目錄）。
`orchestrate-issues` 的本文只寫**動作名**（如「[multiplexer] 讀 agent 畫面」），執行時到這裡查該 multiplexer 的實際指令與 JSON 欄位。
新增 tmux、Superset 等 = 多一份 `<name>.md` 並在下方判斷規則與動作表加一欄，skill 不用改。

## 判斷用哪個 multiplexer

1. 讀 conventions 的 `multiplexer`（依 `.agents/conventions.md`「設定來源與優先序」）。是 `herdr` / `none` 就直接用。
2. 是 `auto`（預設）：

```bash
test "${HERDR_ENV:-}" = 1 && echo herdr || echo none
```

- `herdr` → 讀 `.agents/skills/_multiplexer/herdr.md`
- `none` → 見下方「`none` 時的退化」

3. 指定了 multiplexer 但不在其中（例如 `herdr` 卻 `HERDR_ENV` 不是 1）→ 停下告訴使用者，不要從外部去控制別人的 session。

## 動作表（A 表）

| 動作 | herdr | 備註 |
|---|---|---|
| 確認在 multiplexer 內 | `test "${HERDR_ENV:-}" = 1` | |
| 取主 session 位置 | `$HERDR_WORKSPACE_ID` | 建 worktree 時掛在哪個 workspace 下 |
| 建 worktree + 獨立 session | `herdr worktree create --workspace <ws> --branch <b> --base origin/<base> --path <path> --label <label> --no-focus` | 回傳 session（workspace）id 與空 shell pane id |
| 在既有 worktree 開 session | `herdr worktree open --workspace <ws> --path <path> --no-focus` | 分支已存在、或重建調度時補開；回傳欄位同上 |
| 在 session 啟動 agent | `herdr agent start <name> --kind <agent_kind> --pane <pane> [-- <agent_start_args>]` | name 是之後所有動作的 target |
| 送指令給 agent | `herdr agent prompt <name> "<text>"` | 送完要確認真的開始工作，見 `herdr.md` |
| 讀 agent 畫面 | `herdr agent read <name> --source recent-unwrapped --lines N` | `blocked` 時改 `--source visible` |
| 查狀態 | `herdr agent get <name>` / `herdr agent list` | 狀態：`working` / `idle` / `done` / `blocked` / `unknown` |
| 列出所有 agent／session | `herdr agent list`、`herdr workspace list`、`herdr worktree list --workspace <ws>` | 重建調度狀態用：agent 名稱、cwd、狀態；session 與其 worktree 分支 |
| 等任一條線停下 | 輪詢 `herdr agent list` 的 loop（見 `herdr.md`） | 背景執行，有線離開 `working` 就回報 |
| 送按鍵（選單、Enter、Esc） | `herdr agent send-keys <name> enter\|esc\|down\|up` | |
| 關 session 並移除 worktree | `herdr worktree remove --workspace <ws> [--force]` | |
| 關 session（worktree 已移除時） | `herdr workspace close <ws>` | |

## 狀態語意（各 multiplexer 共用）

| 狀態 | 意思 | 調度者該做的事 |
|---|---|---|
| `working` | agent 正在跑 | 不打斷；要插入工作用「送指令」排入佇列 |
| `idle` / `done` | 在等輸入（`done` = 背景完成、使用者還沒看過） | 讀畫面判斷它在等什麼 |
| `blocked` | 卡在權限確認或選單 | 讀畫面（visible）確認選項再送按鍵 |
| `unknown` | 認不出狀態 | 讀畫面，不要當成完成 |

## `none` 時的退化

沒有 multiplexer 就無法替使用者開 session 與監看：

1. 每條線呼叫 skill `create-worktree` 建 worktree 與分支（參數為 issue 編號；疊分支時註明 base）。
2. 列出每條線要貼到新 session 的完整 `fix-issue` 指令（含範圍限制與疊分支規則），請使用者自己開 session 執行。
3. 「監看與回應」改為使用者回報進度時處理；PR 關卡與收尾照常由主 session 做。

## 術語

| 本 template 用詞 | herdr |
|---|---|
| session（一條線的獨立工作區） | workspace（由 `worktree create` 建立，含一個 tab 與 root pane） |
| pane | pane |
| agent name | `agent start` 的 `<name>`（`[a-z][a-z0-9_-]{0,31}`，live agent 間唯一） |
