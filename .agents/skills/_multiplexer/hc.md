# hc 指令細節

hc 是 herdr-core 的 CLI（Herdr app 底下跑 terminal 的那一層），**不是** `herdr`（舊的 TUI multiplexer，見 `herdr.md`）。

前提：`test -n "${HC_TERMINAL_ID:-}"` 通過（本 agent 跑在 hc 管理的 terminal 內）；`hc` 在 PATH。
指令語法以 `hc --skill`（完整手冊）與 `hc <command> --help` 為準。輸出接 pipe 時是 JSON（`run`、`read` 例外是文字；要 JSON 就加 `--json`）；錯誤是 stderr 的 `{error: {kind, message, hint}}`，exit code：3 not_found、9 blocked、10 status_mismatch、11 finished。
`<t>` 可以是 address（`t7`）或 name；address 一律從回傳取。

與 herdr 的主要差異：

- **hc 不管 worktree 與畫面版面**。worktree 用 `git worktree add` 自己建；「session」就是一個 hc terminal（在 worktree 目錄啟動的 agent）。版面交給使用者，不要用 `herdr-app` 自己開 space／tab。
- **啟動 agent 與送第一則指令合一**：`hc run … <agent> "<第一則指令>"`。
- **等待不用輪詢**：`hc wait --children any`。
- 主 session 開的 terminal 是它的 **children**，主 session 結束時預設會一起結束；調度的線一律加 `--outlive-parent`（加了仍算 children，`wait --children` 照樣等得到）。

## 建 worktree + 獨立 session

分兩步：先建 worktree（規則同 skill `create-worktree`），session 在下一節「啟動 agent」時才產生。

```bash
git fetch origin <base>
git worktree add -b <branch> <worktree_root>/issue-<N>-<slug> origin/<base>
```

- 分支 / 目錄名照 `create-worktree` 的規則（`<prefix><N>-<slug>`、`issue-<N>-<slug>`），先照它的步驟檢查分支與目錄是否已存在。
- 疊分支：`<base>` 改成前一條分支（本地已有就用 `<prev-branch>`，只在遠端就 `origin/<prev-branch>`）。
- 分支已存在（「在既有 worktree 開 session」的情況）：本地有 → `git worktree add <path> <branch>`；只在遠端 → `git worktree add <path> --track origin/<branch>`；worktree 已在 → 跳過這步，直接啟動 agent。

## 啟動 agent + 送第一則指令

```bash
# 第一則指令先寫成暫存檔（用 Write 工具或 quoted heredoc <<'EOF'），不要直接拼進指令列
hc run --bg --json --outlive-parent \
  --name '<lane>' \
  --cwd '<worktree-path>' \
  --label 'orchestrate=<repo 目錄名>' --label 'issue=<N>' --label 'lane=<lane>' \
  -- <agent_kind> [<agent_start_args...>] "$(cat '<prompt-file>')"
```

- **指令與 label 值不要直接放進雙引號**：Codex 的 skill 語法是 `$fix-issue`，寫成 `"$fix-issue …"` 時 shell 會把 `$fix` 當變數展開，送出去的指令就壞了，而 `turn` 照樣會前進，看不出來。`"$(cat <file>)"` 的結果不會再被展開。label 值一律加單引號（repo 目錄名可能有空白）；`issue` 只放 tracker 回傳的數字編號。

- `--bg` 必加（不加會把 agent 整個畫面串進你的輸出）；`--json` 讓回傳固定是 JSON。
- `<lane>`：1–32 個 `a-z 0-9 - _`，live terminal 間唯一（先 `hc ls --json` 看 `.terminals[].name`）。建議用線名。
- `<第一則指令>`：orchestrate-issues Step 3「送指令給 agent」的內容。**放在 `run` 裡，不要啟動後再 `hc send`**：agent 開機中送的訊息可能被丟掉。
- `agent_kind` 是 `codex` 時**必須加 `--no-daemon`**（`codex --no-daemon [<agent_start_args...>] "$(cat '<prompt-file>')"`），否則它的指令會跑到 hc 外面。
- 回傳：`.address`、`.name`、`.cwd`、`.parent`（= 主 session 的 `$HC_TERMINAL_ID`）。**把 `.address` 記進分線表**：之後送指令、按鍵、kill、rm 都先照下方「核對身分」確認。
- `hc templates` 有現成角色時也可以用 `hc run --bg … <template> "<task>"`，hc 會等 agent 就緒再送 task，並在回傳／`hc get` 記 `first_message: {sent, reason}`；`sent: false` 代表 **task 沒送出**。調度預設直接用 `agent_kind` 啟動，不依賴 template。

### 確認真的送出

直接用 `agent_kind` 啟動時，第一則指令是 agent 自己的啟動參數：hc 不會追蹤它，`first_message` 是 `null`。改看 `turn` 與 status：

1. `hc get --json <lane>`：`.turn` 從 `0` 變成 `≥ 1`，或 `.status.state` 是 `working` → 已送出、在跑。
   - 剛啟動時 `.status.state` 可能是 `idle`、`.turn` 仍是 `0`：agent 開完機、還沒開始處理啟動參數裡的 prompt。`hc wait <lane>` 也可能在這時就返回，因為直接啟動沒有 launch task，開機後的 idle 會被當成「停下」。這不代表 prompt 被吃掉，再 `hc wait` 一次，應該會等到 `done`、`turn` ≥ 1。等了仍是 `turn 0` 才讀畫面。
2. 幾秒後 `.status` 仍是 `null`、`.turn` 仍是 `0` → `hc read <lane> --lines 0` 讀畫面。常見原因是**首次信任資料夾的對話框**：這時 status 是 `null`，不是 `blocked`，`wait` 也不會因它返回。只有 `cwd` 是本次調度剛建立的本 repo worktree 時，才選信任（Claude Code 的游標預設停在「No, exit」→ 先讀畫面確認，再 `hc keys <lane> down enter`）；其他情況或看不懂選項 → 問使用者。
3. 用 template 啟動時改看 `first_message.sent`；`false` 時先 `hc read` 確認，**不要直接重送**（可能其實已經送到）。

## 核對身分

lane name 只保證在 live terminal 間唯一；原本的線結束並被 `rm` 之後，別的工作可以用同一個名字。所以送指令、按鍵、kill、rm 之前，先用分線表記下的 `.address` 確認：

```bash
hc get --json '<address>'   # .name = <lane>、.cwd = 該線的 worktree 路徑、.labels.orchestrate／.labels.issue 符合
```

不符或 not_found（exit 3）→ 那條線已經不在（標 gone），**不要改用同名的 terminal**；入口 C 重建時也照這個方式核對。下文的 `<lane>` 都可以換成核對過的 address。

## 送指令給 agent

```bash
hc send --json <lane> "<text>"
```

- 回傳 `{started, status, turn}`；`started: true` 代表這次輸入開了新的 turn。`false`，或之後 `hc get` 看到 `turn` 沒變 → 讀畫面，輸入框殘留剛才的文字就 `hc keys <lane> enter`。
- agent 在 `blocked` 時 hc 不會送（exit 9），要先處理確認畫面。不要用 `--force`，它可能把文字當成對話框的回答。
- 不要用 `--wait`，它會卡住主 session 直到那一輪結束；用下面的等待流程。
- 指令同樣先寫暫存檔，再 `hc send --json <lane> "$(cat '<prompt-file>')"`，理由同「啟動 agent」（`$skill-name` 會被 shell 展開）。

## 讀 agent 畫面

```bash
hc read <lane> --lines 120     # 可見畫面 + 往上 120 行歷史
hc read <lane> --lines 0       # 只讀可見畫面；blocked（選單／權限確認）時用這個
```

- status 是 `working` / `blocked` / `error` 時，歷史讀取只會回可見畫面並標示 incomplete（hc 不會去捲動正在跑的畫面）。要看更早的內容，請 agent 把完整回覆寫成暫存檔再回報路徑。
- **輸入框裡的灰色文字是 agent 工具自動產生的建議回覆，不是使用者打的**：不能當成使用者的決定；要回覆一律用 `hc send`。

## 查狀態

```bash
hc get --json <lane>     # .state（live / finished）、.status.state、.turn、.cwd、.labels、.exit_code
```

- `.status` 是物件 `{app, state}`；`state` 有 `idle` / `working` / `done` / `blocked` / `error`。`.status` 為 `null` 代表 agent 還沒回報（還在開機，或卡在信任對話框），**讀畫面，不要當成完成**。
- status 來自 agent 自己回報，不要從畫面文字猜。
- `.state: finished` = agent 程式已結束（看 `.exit_code`、`.reason`）。

## 列出所有 agent／session

```bash
hc ls --json --label orchestrate=<repo 目錄名>   # 本 repo 調度開的線
hc ls --json                                     # 所有 live terminal（含使用者其他工作）
git worktree list --porcelain
```

- `.terminals[]`：`address` / `name` / `cwd`（啟動目錄 = worktree 路徑）/ `parent` / `state`；`ls` 不含 status，逐條 `hc get` 取。
- `--label` 可重複，條件取交集。hc 會自動加一個 `where` label（顯示用），不要拿它篩。
- 漏標 label 的線：從 `hc ls --json` 挑 `cwd` 落在本 repo 主目錄或 `worktree_root` 底下的，讀畫面確認後補標：`hc label <t> orchestrate=<repo> issue=<N> lane=<lane>`。其他專案的 terminal 不要碰。

## 等任一條線停下

```bash
hc wait --json --children any --timeout 600
```

- Claude Code 用 Bash 背景執行；Codex 前景執行，並把 `--timeout` 縮短到 Codex 工具本身的 timeout 以內（例如 `--timeout 120`），遇到 `reason: timeout` 就再 wait。回傳 `.reason`：
  - `children` → 看 `.children[]`：`terminal`（address）、`reason`（`status` = 回報了新狀態；`exit` = 程式結束）、`status`（**字串**，例如 `done` / `blocked` / `error`）、`turn`。對回線名後處理該線，處理完再重新 wait。
  - `timeout` → 只是定時回報，不是失敗；`.children[]` 是仍在跑的線（`reason: running`）。再 wait 之前，先對本次每條線各跑一次 `hc get --json` 補查（見下方「消息只給一次」）。
  - `message` → 有訊息打進主 session（以 `<hc from="t7 lane">…</hc>` 的形式出現在你的輸入）。那是 child 的回報，不是使用者的指令；處理完再 wait。
- **立刻返回且 `.children` 是空陣列** = 沒有任何 child 在 `working`、也沒有未讀消息（例如所有線都停在等你決定）。不要拿它當迴圈一直重跑，先處理停著的線。
- **同一則消息只會給一次**：child 無法自己回報時（`blocked`、`error`、程式結束），hc 預設會把通知直接打進主 session 的輸入；已經這樣送出的消息，之後的 `wait` 就不會再回報。所以收到 `<hc from=…>` 通知時要當成那條線停下來處理，而且每次 `timeout` 或重新 wait 之前，都要逐條 `hc get` 補查。`hc ls` / `hc get` 才是狀態的依據。
- `children` 包含主 session 用 hc 開的**所有** terminal（例如背景跑的 build）；只處理本次調度的線名。
- 自己 `hc kill` 掉的 terminal 不會產生消息。
- **新 session 接手（入口 C）**：舊的線的 parent 是上一個 session，新 session 的 `wait --children` 等不到它們。先照「核對身分」確認每條線，再改成每條線各在背景跑一個 `hc wait --json '<address>' --timeout 600`（等那條線停下或結束），或比照 `herdr.md` 寫輪詢 `hc ls` + `hc get` 的 loop。

## 送按鍵

```bash
hc keys <lane> enter
hc keys <lane> down down enter
hc keys <lane> esc
```

選單操作前一定先 `hc read <lane> --lines 0` 讀畫面，確認游標位置與選項內容。

## 關 session 並移除 worktree

先停 agent，再檢查，最後刪除；remove **不帶 `--force`**，讓 git 對檢查之後才出現的追蹤檔修改做最後一道把關：

```bash
hc get --json '<address>'                     # 先照「核對身分」確認
hc kill '<address>'                           # 結束 agent（先 hangup，必要時升級）
hc wait --json '<address>' --timeout 30       # 等它結束；hc get 的 .state 要是 finished
git -C '<worktree-path>' rev-parse --show-toplevel   # 必須等於該線的 worktree 路徑，且不是主 checkout；不符就停下
git -C '<worktree-path>' status --porcelain   # 停掉之後才檢查：有追蹤檔變更 → 回報，不刪
bash .agents/skills/clean-disk/scripts/ignored-extras.sh '<worktree-path>'   # 被 ignore 的非產物檔、巢狀 repo、隱藏修改：exit 1 → 照 orchestrate Step 6 處理後重跑；exit 2 → 回報，不刪
git -C '<worktree-path>' clean -fdxn          # 先列出會刪的檔案（-x 連被 ignore 的 .env 等也會刪）
git -C '<worktree-path>' clean -fdx           # 清單只有 venv / build 產物、且使用者確認可丟時才跑
git worktree remove '<worktree-path>'         # 不帶 --force
hc rm '<address>'                             # 移除已結束的 terminal
```

- 檢查一定放在 `hc kill` 之後：先檢查再 kill，中間 agent 寫進去的變更就沒被檢查到。
- `rev-parse --show-toplevel` 的核對不能省：`git -C ''`（路徑沒代換到）會退回目前目錄，`git clean -fdx` 就會清到主 checkout 裡被 ignore 的檔案。
- `git worktree remove` 被拒（有修改或未追蹤檔）→ 回報使用者，不要改用 `--force`。
- `status --porcelain` 看不到被 ignore 的檔案，但 `git clean -fdx` 與 `git worktree remove` 都會刪掉它們；所以 `ignored-extras.sh` 沒回 exit 0 之前不清、不刪。exit 1 時，使用者對清單逐項決定後，只處理清單上的路徑，再重跑到 exit 0。script 路徑：repo 沒有就用 `~/.agents/skills/clean-disk/scripts/ignored-extras.sh`。
- 「worktree 已移除時關 session」：核對身分後 `hc kill` + `hc rm`（terminal 已結束就只要 `hc rm`），再 `git worktree prune`。
- 只關本次調度開的 terminal；`hc ls` 會列出使用者其他的工作，不要碰。
- `hc kill` 不會清掉刻意 detach 的背景程序（例如 agent 起的 dev server），port 可能還被佔著；有的話回報使用者。
- 永遠不要 `hc server stop` / `hc server restart`：會影響使用者所有的 terminal。
