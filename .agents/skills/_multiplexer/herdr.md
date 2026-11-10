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

- **`--workspace` 不可省略。** 少了它，herdr 會回退去用 UI 當前聚焦的 workspace 來決定從哪個 repo 開 worktree——那可能是別的專案。失敗是無聲的：`--path` 照你給的位置建出來、`--branch` 照你給的名字建出來，只有內容是別的 repo，而且那個分支會留在別的 repo 裡。
- **建完、放 agent 進去之前先驗一次**（省略 `--workspace` 只會在這裡現形）：

  ```bash
  git -C "$(...worktree.path)" rev-parse --git-common-dir   # 必須指向預期 repo 的 .git
  ```

  不符就 `herdr worktree remove --workspace <id> --force`，到被誤用的 repo `git worktree prune`、`git branch -D <branch>` 清掉殘留分支，再用正確的 `--workspace` 重建。派 agent 時也在 prompt 開頭要它自己確認一次，不符就停下回報——這樣就算建的時候沒發現，agent 也會先擋下來而不是改錯 repo。
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
- `agent_kind` 是 `codex` 時**必須在 `--` 後面加 `--no-daemon`**（`-- --no-daemon [<agent_start_args...>]`）。不加時，只要本機的共用 daemon（`codex app-server`）在跑，Codex 執行的指令就會是 daemon 的子程序，不在 herdr pane 裡（codex-cli 0.163、herdr 0.9.5 實測）。
- 成功時已偵測到 agent 可互動；回 `agent_not_ready` 代表啟動時就卡在確認畫面（例如首次信任資料夾）——name 仍可用，讀畫面後送按鍵。
- 可用 kind：`herdr agent` 印出的清單。

## 送指令給 agent

```bash
herdr agent prompt <name> "$(cat '<prompt-file>')"
```

- 多行長指令可直接放在一個參數裡（herdr 會用 bracketed paste）。指令先寫成暫存檔再 `"$(cat '<prompt-file>')"`，不要直接放進雙引號：Codex 的 skill 語法是 `$fix-issue`，寫成 `"$fix-issue …"` 時 shell 會把 `$fix` 當變數展開。
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

## 列出所有 agent／session

```bash
herdr agent list                                          # .result.agents[]：name / agent / agent_status / cwd / workspace_id / pane_id
herdr workspace list                                      # .result.workspaces[]：workspace_id / label / agent_status / worktree
herdr worktree list --workspace "$HERDR_WORKSPACE_ID"     # .result.worktrees[]：path / branch / open_workspace_id（null = 沒有開 session）
```

- `worktree list` 列的是**同一個 repo** 的所有 worktree（含主 checkout，`is_linked_worktree: false`）；用 `open_workspace_id` 對回 workspace、用 `path` 對回 agent 的 `cwd`。
- 沒有 `name` 的 agent 是使用者自己開的或名稱已被清掉；cwd 在本 repo 的 worktree 下仍可能是某條線，重新命名前先讀畫面確認：`herdr agent rename <pane_id> <name>`。
- 只挑 cwd 落在本 repo（主 checkout 或 `worktree_root` 底下）的 agent，其他專案的不要碰。



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

先停 agent、關 workspace，再檢查，最後用 git 移除 worktree。**不要用 `herdr worktree remove`**：它把「關 agent」和「刪 worktree」綁成一步，中間沒有機會檢查，而且帶不帶 `--force` 都會刪掉被 ignore 的檔案。

```bash
herdr agent send-keys <name> esc                 # 停掉正在跑的這一輪
herdr agent prompt <name> '/stop'                # 只有 Codex：被打斷後它的指令會轉成背景 terminal 繼續跑，/stop 才會關掉
herdr agent wait <name> --until idle --timeout 30000   # 只有 Codex：等 /stop 處理完，再 --source visible 讀畫面確認沒有「background terminal running」
herdr workspace close <workspace_id>             # 關掉這條線的 session（agent 會一起結束）
bash .agents/skills/clean-disk/scripts/active-in.sh <worktree-path>       # 還有 process 的 cwd 在 worktree 裡：exit 1 → 列出來問使用者；exit 2 → 回報，不刪
git -C <worktree-path> rev-parse --show-toplevel # 必須等於該線的 worktree 路徑，且不是主 checkout；不符就停下
git -C <worktree-path> status --porcelain        # 有追蹤檔變更 → 回報，不刪
bash .agents/skills/clean-disk/scripts/ignored-extras.sh <worktree-path>   # 被 ignore 的非產物檔、巢狀 repo、隱藏修改：exit 1 → 照 orchestrate Step 6 處理後重跑；exit 2 → 回報，不刪
bash .agents/skills/clean-disk/scripts/active-in.sh <worktree-path>       # 移除前再跑一次這兩個檢查，縮短窗口；都要回 exit 0
bash .agents/skills/clean-disk/scripts/ignored-extras.sh <worktree-path>
git worktree remove <worktree-path>              # 不帶 --force；被拒（有修改或未追蹤檔）→ 回報，不要改用 --force
```

- 關 workspace 收不掉 Codex 已經在跑的指令：實測關掉 workspace 後，沒加 `--no-daemon` 的指令留在 daemon 底下，加了的變成孤兒程序（被 pid 1 收養），兩者都還可能在 worktree 裡寫檔。所以關之前先打斷（Codex 再加 `/stop`），關之後跑 `active-in.sh`。exit 1 時的處理、exit 0 的意義與限制，見 `hc.md`「關 session 並移除 worktree」的說明（兩邊相同）。
- `status --porcelain` 看不到被 ignore 的檔案，但 `git worktree remove` 會刪掉它們；所以 `ignored-extras.sh` 沒回 exit 0 之前不移除。exit 1 時，使用者對清單逐項決定後，只處理清單上的路徑，再重跑到 exit 0。
- script 路徑：repo 沒有就用 `~/.agents/skills/clean-disk/scripts/`（`active-in.sh`、`ignored-extras.sh`）。
- 「worktree 已移除時關 session」：只做 `herdr workspace close <workspace_id>`。
- 只關本次調度建立的 workspace；不要關使用者或其他 session 的。
- 永遠不要 `herdr server stop`。
