# herdr 指令細節

前提：`test "${HERDR_ENV:-}" = 1` 通過（本 agent 在 herdr 管理的 pane 內）；`herdr` 在 PATH。
指令語法以 `herdr <group>`（不帶 subcommand 印說明）為準；**不要跑裸 `herdr`**（會開 TUI），也不要省略參數試探會變更狀態的指令。
大多數指令回傳 JSON；ID 一律從回傳取，不要從範例或 sidebar 順序推。錯誤是 stderr JSON + exit 1，語法錯 exit 2。

## 建 worktree + 獨立 session

```bash
herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" \
  --branch <branch> \
  --base origin/<base> \
  --path <worktree_root>/issue-<N>-<slug> \
  --label <label> \
  --no-focus
```

- 先 `git fetch origin <base>`；疊分支時 `--base` 用前一條分支（本地已有就用 `<prev-branch>`，只在遠端就 `origin/<prev-branch>`）。
- 分支 / 目錄名照 `create-worktree` 的規則（`<prefix><N>-<slug>`、`issue-<N>-<slug>`）。
- 回傳（`type: worktree_created`）：
  - `.result.workspace.workspace_id` → 之後關 session 用
  - `.result.root_pane.pane_id` → 啟動 agent 用
  - `.result.worktree.path` / `.branch`
- 分支已存在：改用 `herdr worktree open --workspace "$HERDR_WORKSPACE_ID" --path <path>`（或 `--branch <b>`），回傳欄位相同，多一個 `already_open`。

## 啟動 agent

```bash
herdr agent start <name> --kind <agent_kind> --pane <pane_id> [--timeout 60000] [-- <agent_start_args...>]
```

- `<name>`：`[a-z][a-z0-9_-]{0,31}` 且與現有 live agent 不重複（先 `herdr agent list` 看 `.result.agents[].name`）；建議用線名或 issue 簡稱。
- `agent_start_args` 為空時整段 `--` 省略。
- 成功時已偵測到 agent 可互動；回 `agent_not_ready` 代表啟動時就卡在確認畫面（例如首次信任資料夾）——name 仍可用，讀畫面後送按鍵。
- 可用 kind：`herdr agent` 印出的清單。

## 送指令給 agent

```bash
herdr agent prompt <name> "<text>"
```

- 多行長指令可直接放在一個參數裡（herdr 會用 bracketed paste）；內含雙引號時用單引號包或先寫暫存檔再 `"$(cat <file>)"`。
- agent 在 `blocked` 時會直接回 `agent_blocked`、不送出——先處理確認畫面。
- **確認真的送出**：送完 `herdr agent get <name>` 看 `.result.agent.agent_status`（或 `agent list` 同名那筆），幾秒內沒變 `working` → 讀畫面；輸入框殘留剛才的文字就 `herdr agent send-keys <name> enter`。
- 送出後 5 秒內沒有狀態變化時，`--wait` 模式會回 `agent_prompt_stalled`；調度流程不用 `--wait`（會卡住主 session），改用下方輪詢。
- agent 正在 `working` 時送 prompt 會排進它的輸入佇列，不會打斷目前這一步。

## 讀 agent 畫面

```bash
herdr agent read <name> --source recent-unwrapped --lines 120
herdr agent read <name> --source visible            # blocked（選單 / 權限確認）時用這個
```

- 讀不到更早的內容（agent 用 alternate screen）時，請 agent 把完整回覆寫成暫存檔再回報路徑。
- **輸入框裡的灰色文字是 Claude Code 自動產生的建議回覆，不是使用者打的**：不能當成使用者的決定，按 Enter 也送不出去；要回覆一律用 `agent prompt` 明確送出。

## 查狀態

```bash
herdr agent get <name>
herdr agent list      # .result.agents[] 的 name / agent_status / cwd / pane_id / workspace_id
```

`idle` 與 `done` 本質相同（都在等輸入），`done` = 使用者還沒在 UI 看過；CLI 讀取不會把 `done` 變 `idle`。

## 等任一條線停下

herdr 沒有「等多個 agent 其中一個」的指令，用輪詢 loop（在背景執行：Claude Code 用 Bash 背景執行；Codex 前景執行並設 timeout）：

```bash
names="lane-a lane-b lane-c"   # 本次調度的 agent name
while :; do
  out=$(herdr agent list | python3 -c '
import sys, json
want = set(sys.argv[1].split())
agents = {a.get("name"): a["agent_status"] for a in json.load(sys.stdin)["result"]["agents"] if a.get("name") in want}
stopped = [n + "=" + agents.get(n, "gone") for n in sorted(want) if agents.get(n) != "working"]
print(" ".join(stopped))' "$names")
  [ -n "$out" ] && { echo "$out"; break; }
  sleep 20
done
```

- 輸出例：`lane-b=done`；`gone` = agent 已退出（session 被關或 agent 結束）。
- 剛送出指令的線可能還沒進 `working`，啟動 loop 前先確認每條線都已 `working`，或把剛送出的線暫時排除。
- 已知在等使用者決定、暫不處理的線也從 `names` 拿掉，否則 loop 會立刻返回。

## 送按鍵

```bash
herdr agent send-keys <name> enter
herdr agent send-keys <name> down down enter
herdr agent send-keys <name> esc
```

herdr 先驗證所有 key 再寫入；選單操作前一定先 `--source visible` 讀畫面確認游標位置與選項內容。

## 關 session 並移除 worktree

```bash
git -C <worktree-path> status --porcelain        # 確認沒有追蹤檔變更
herdr worktree remove --workspace <workspace_id>          # 乾淨時
herdr worktree remove --workspace <workspace_id> --force  # 只剩 untracked 的 venv / build 產物時
herdr workspace close <workspace_id>                      # worktree 已先被移除、只剩 session 時
```

- 只關本次調度建立的 workspace；不要關使用者或其他 session 的。
- 永遠不要 `herdr server stop`。
