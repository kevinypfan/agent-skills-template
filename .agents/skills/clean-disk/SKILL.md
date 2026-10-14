---
name: clean-disk
description: >
  清理本機開發空間：掃描根目錄底下所有 repo 的 git worktree（agent 平行處理 issue 後留下的）、
  可重建的依賴／建置產物（node_modules、.venv、target…）、全域開發快取（npm、pnpm、uv、Docker…），
  用 script 把每一項分成「可刪／要看／保留」三級並說明理由，使用者確認後才刪，回報釋放的空間。
  使用時機：(1) 使用者說「磁碟滿了」「空間不夠」「清一下空間」「disk full」「清理 worktree」「刪舊 worktree」「worktree 太多」，
  (2) 想知道哪些 worktree／branch 已經 merge 可以刪，(3) node_modules、快取、Docker 佔太多空間，
  (4) 使用者明確呼叫 /clean-disk。就算使用者只說「電腦快沒空間了」也適用。
compatibility: Requires git and bash; PR status lookup uses glab (GitLab) or gh (GitHub) when available. Scripts tested on macOS (bash 3.2) and Linux.
---

## 先決定照哪一份跑

本 skill 可能同時裝在 repo 與全域（`~/.agents/skills/`），開工前先做這兩件事：

1. 你正在讀的這份若**不在當前 repo 根（`git rev-parse --show-toplevel`）之內**，就是全域版——例如 `~/.agents/skills/clean-disk/SKILL.md`，或工具把 symlink 解析成實際路徑後顯示的其他目錄（全域安裝用 symlink，常見於 Codex）。全域版先看 repo 根：有 `.agents/skills/clean-disk/SKILL.md`，或有 `.claude/skills/clean-disk/SKILL.md` 且它不是只轉交到 `.agents/skills/clean-disk/SKILL.md` 的薄 stub → **改讀 repo 那份照做，本檔以下全部不適用**。專案版通常客製過（label、tracker、流程），全域版只在專案沒有時補位。
2. 下文所有 `.agents/…` 路徑：repo 根有該檔就用 repo 的，沒有就用 `~/.agents/…` 同名檔（`~` 展開成家目錄絕對路徑再讀）。不在任何 repo 裡執行時（例如從家目錄呼叫），一律用 `~/.agents/…`。

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

可能包含：要掃的根目錄、範圍（worktree／產物／快取）、「只看不刪」。

## 為什麼這樣設計

刪錯的代價（遺失沒 push 的工作）遠大於少刪一點的代價（晚一點再清），所以：

- **判斷交給 script**（`.agents/skills/clean-disk/scripts/`）：未 commit 變更、沒 push 的 commit、是否已併進 base（含 squash／rebase merge）、有沒有 process 還在裡面——這些是機械性檢查，script 做得快又一致，不要自己用一連串 git 指令重新推導。
- **刪除也交給 script**：`remove-*.sh` 在刪之前**重新檢查**一次，因為掃描到刪除之間 agent 可能又寫了檔案；red 一律拒絕。不要繞過它直接 `rm -rf` worktree——那會留下殘缺的 git metadata，而且跳過了最後一道檢查。
- **你負責的是**：選範圍、對 yellow 項目查 PR 狀態補資訊、用人看得懂的方式呈現、取得確認、回報結果。

## Step 0：讀設定與選範圍

1. **根目錄**：依 `.agents/conventions.md`「設定來源與優先序」取 `cleanup_roots`（通常在個人檔 `~/.agents/conventions.local.md`）。user input 有指定就用指定的。都沒有 → 問使用者要掃哪些目錄（建議放專案的總目錄，例如 `~/Project`），並問要不要存進個人檔（照 conventions「寫入規則」只寫該 key）。傳給 script 前把 `~` 展開成絕對路徑（script 也會展開開頭的 `~`，但帶引號傳入時 shell 不會）。
2. **範圍**：user input 沒說清楚就問，可複選（Claude Code 用 `AskUserQuestion` multiSelect；Codex 在對話中列選項請使用者回覆）：
   - **worktree**（預設勾）：已完成的 worktree ＋ 已併進 base 的 local branch
   - **可重建產物**：`node_modules`、`.venv`、`target`、`dist`…，只列「repo 裡被追蹤的 `.gitignore` 直接指名該目錄」的（`node_modules/*` 這類只 ignore 內容的規則、全域 excludes、`.git/info/exclude` 都不算，這些目錄不會出現），而且裡面不能有巢狀 repo；常見於還要保留的 worktree 與主 repo
   - **全域快取**：npm／pnpm／uv／pip／Homebrew／Docker／Xcode 等，只用各工具官方清理指令
3. 先用 Bash 記下目前可用空間（`df -h <根目錄>`），結尾要算實際釋放多少。

## Step 1：掃描

依選到的範圍跑對應 script（都不刪檔；`scan-worktrees.sh` 會 fetch 更新 `refs/remotes/origin/*`；根目錄可給多個）。大小用平行 `du` 計算（預設 8 個，環境變數 `CLEAN_DISK_JOBS` 調整）；上百個 worktree 又有大型 `target`／`node_modules` 時仍要幾分鐘，可以派給 `runner` agent 執行，輸出寫進暫存檔再彙總，不要把整份 TSV 讀進對話。

```bash
bash .agents/skills/clean-disk/scripts/scan-worktrees.sh <根目錄>...   # 加 --no-fetch 跳過 fetch（離線時）
bash .agents/skills/clean-disk/scripts/scan-artifacts.sh <根目錄>...   # 預設只列 ≥ 50 MB；--min-mb N 調整
bash .agents/skills/clean-disk/scripts/scan-caches.sh
```

`scan-worktrees.sh` 的 tier 規則（理解它才能向使用者解釋）：

| tier | 條件 | 意義 |
|---|---|---|
| red（保留） | 追蹤檔有未 commit 變更；有 assume-unchanged／skip-worktree 的檔案（status 看不到修改）；有 commit 沒 push 且沒進 base；有 process 的 cwd 在裡面（agent／shell 還開著；偵測不到時全部算）；worktree 被 lock；進行中的 rebase／merge／cherry-pick／bisect；裡面有巢狀的 repo／worktree；HEAD 沒有 commit（unborn）；目錄已不存在、但 detached HEAD 有只被它指著的 commit；status、rev-list、ignored 清單等檢查失敗 | 刪了會丟工作或打斷正在跑的東西；檢查不了就當有風險 |
| yellow（要看） | 已 push 但 base 上找不到等價改動（PR 可能還 open、被 close、或 merge 時改過內容；分支上有 merge commit 時一律算這類）；有未追蹤的非 ignored 檔；有被 ignore 但不在產物白名單的檔（`.env`、`*.local`、`*.log`、筆記——`git worktree remove` 會不經確認刪掉）；孤兒目錄；worktree metadata 斷裂（git 讀不到，歸 yellow 而非 red，因為修好 metadata 就能正常分級）；找不到 base ref | 不會丟 commit，但需要人判斷 |
| green（可刪） | 內容已併進 base（一般 merge、rebase、squash 都偵測得到），且沒有未追蹤檔、沒有被 ignore 的非產物檔；或目錄已不存在只剩 metadata（有 branch，或 commit 也在其他 ref 上） | 刪掉 worktree 不會遺失任何東西。rebase／squash 是 patch 等價判定（git 比對時忽略 whitespace 與行號），所以只刪 worktree、**保留 local branch** |

TSV 欄位：`tier repo path branch size_kb idle_days tracked untracked unpushed merged upstream extras head reasons`（`extras` = 被 ignore 的非產物檔數，`head` = 檢查當下的 HEAD OID）。

偵測不到的使用中情況：IDE／編輯器開著 worktree 裡的檔案、但沒有任何 process 的 cwd 在裡面時不會被判 red。呈現時對閒置 0–1 天的 green 提醒使用者確認沒有編輯器還開著。

## Step 2：補 yellow 的資訊

對「已 push 但未進 base」的 yellow 項目，**在該 worktree 目錄內**（不是 main repo 目錄，否則「目前分支」會是 main repo 的分支）依 `.agents/skills/_tracker/README.md` 判斷 tracker，執行 **[tracker] 查目前分支的 PR**：

- PR **merged** → 改列為可刪，標註「PR 已 merge（base 上內容與分支不同，可能 merge 時有調整）」；刪除時對該 path 加 `--trust-merged` 才會刪 local branch
- PR **closed 未 merge** → 仍是 yellow，標註「PR 已關閉未 merge；commit 還在遠端分支上」
- PR **open** → 改列 red 的「建議保留」，標註「PR 進行中」；worktree 可隨時從遠端分支重建，使用者堅持要刪也可以
- 查不到 PR／沒有 CLI 或沒登入 → 保持 yellow，標註「查不到 PR」，不要猜（tracker 的查詢若只找 open 的 PR，merged 的也會落在這裡，照樣不猜）

項目很多時（數十個），先依 repo 分組、只查各組 yellow，不必逐一查 green／red。

metadata 斷裂（常見於 repo 搬過目錄）：先問使用者要不要對所屬 repo 跑 `git worktree repair <path>`（只修正 `.git` 指標，不動內容），修好後重掃那個 repo，它就會得到正常分級。

孤兒目錄：git 已經不認得它，無法判斷有沒有未保存的東西。用 `ls -lt <dir>` 看裡面最近修改的幾個檔（目錄可能根本沒有 `.git`），把觀察寫進理由。

## Step 3：呈現與確認

用下面格式呈現，大小用人看的單位，路徑相對根目錄縮短：

```markdown
## 掃描結果（根目錄：<roots>，目前可用 <df 結果>）

### 🟢 可刪：<N> 個，約 <size>
| # | repo | worktree | branch | 大小 | 閒置 | 理由 |
|---|---|---|---|---|---|---|

### 🟡 要你決定：<N> 個，約 <size>
| # | repo | worktree | branch | 大小 | 閒置 | 狀況 | 建議 |
|---|---|---|---|---|---|---|---|

### 🔴 保留：<N> 個（不會動）
| repo | worktree | 理由 |
|---|---|---|

### 可重建產物：<N> 個，約 <size>（只列 gitignored；刪了下次 install／build 會重建）
| # | 路徑 | 類別 | 大小 | 閒置 |

### 全域快取（只用官方指令清）
| # | 工具 | 大小 | 清理指令 | 備註 |
```

- green 很多時（> 15 個）依 repo 彙總成一行（「repo-a：32 個，4.1G」），問使用者要不要展開。
- yellow 的「建議」欄要給明確意見（例：「閒置 40 天、PR 已關閉 → 建議刪」「untracked 是 NOTES.md → 建議先看一眼」），讓使用者能快速勾選。
- 產物建議優先刪「所屬 worktree 也要刪的」（會隨 worktree 一起消失，不用另外列）與閒置久的；正在開發的專案的 `node_modules` 刪了要重裝，提醒代價。
- Docker 的 `docker system prune --volumes` 會刪 volume（可能是資料庫資料），一律單獨確認，不跟其他項目打包。

**確認方式**：user input 已明確授權（例如「安全的直接刪，不用問我」）時，**只有 script 判為 green 的 worktree** 視同已確認、直接執行；Step 2 由 PR 狀態升級的項目、yellow、產物、快取仍只列出不刪。否則 green 一次確認整批（允許使用者排除幾個編號）；yellow、產物、快取請使用者回覆要刪的編號。「只看不刪」時到這裡就結束，跳到 Step 5 只回報掃描結果。

## Step 4：執行

只對使用者確認的項目執行。`remove-worktrees.sh` 的旗標**只套用在緊接的那一個 path**，每個 yellow 依使用者同意的內容各自標記，不要讓一個授權蓋到整批；同一個 path 需要兩種授權時重複寫（`--allow-untracked P --trust-merged P`）：

```bash
bash .agents/skills/clean-disk/scripts/remove-worktrees.sh \
  <green path> <green path> ... \
  <已 push 未 merge、使用者同意刪的 yellow path> \
  --allow-untracked <使用者看過並同意丟掉未追蹤檔／.env 等的 path> \
  --trust-merged <Step 2 查到 PR 已 merge 的 path> \
  --orphan <孤兒目錄> \
  --prune <有「目錄已不存在」項目的 repo>      # 會先檢查，有 detached 獨有 commit 或 locked 就整個拒絕
bash .agents/skills/clean-disk/scripts/remove-artifacts.sh <path>...
```

- 不確定時先加 `--dry-run` 看一遍（兩支 remove script 的 `--dry-run` 放在 `--` 之前的任何位置都生效；dry-run 不 fetch，branch 的預告會註明「實際執行時需 fetch 成功」）。
- metadata 斷裂的 worktree 會被拒絕：照理由先 `git worktree repair`，不要改用 `--orphan`。
- `--allow-untracked` 的做法是先 `git clean -fdx` 清掉未追蹤與 ignored 檔，再用不帶 `--force` 的 `git worktree remove`；檢查之後才出現的追蹤檔修改會讓 remove 失敗（`FAIL`，內容未刪）。
- remove 會先 fetch 該 repo；fetch 失敗、不完整（repo 有自訂 refspec，為了不修剪它們而沒 prune）或加了 `--no-fetch` 時一律不刪 local branch（無法確認 base 是最新的）。刪 branch 是條件式的（branch 仍指向檢查當下的 OID 才刪）。
- 回報中「local branch 保留（patch 等價判定…）」的 branch，使用者確認後可自行 `git branch -D`。
- script 回 `REFUSE` 代表刪除前的重新檢查發現狀態變了（例如 agent 又寫了檔案、又開了 shell）：**不要換旗標或改用 `rm -rf` 硬刪**，把理由轉告使用者。
- remote branch 一律不動（merge 時平台通常已刪；要刪是對外操作，另外問）。
- 快取：逐項執行使用者確認的官方清理指令（`scan-caches.sh` 的 `clean_command` 欄）。

## Step 5：回報

```markdown
## 清理結果

- 釋放：約 <size>（可用空間 <前> → <後>）
- worktree：移除 <N> 個、local branch 刪除 <M> 個、保留 <K> 個（列出保留原因：patch 等價判定／fetch 失敗／是 base 分支）
- 產物：<N> 個；快取：<清了哪些>
- 拒絕／失敗：<path — 理由>（沒有就寫「無」）
- 保留中的 red：<N> 個（主要原因：<例：5 個有沒 push 的 commit>）

### 建議
- <例：issue-412 有 3 個沒 push 的 commit、閒置 60 天，要嘛 push 開 PR、要嘛確認放棄>
```

## Important Notes

- 對話語言依 conventions 的 `language`。
- 不碰 main worktree、不碰 remote branch、不刪 Docker volume（除非單獨確認）。
- 改 `.agents/skills/clean-disk/scripts/` 後跑 `bash .agents/skills/clean-disk/evals/check-tiers.sh`（建 fixture 逐項斷言分級與拒絕行為，全過才 commit）。
- 多 issue 調度中的線（`orchestrate-issues`）由該 skill 自己收尾；本 skill 處理的是收尾時漏掉、或沒經過調度直接開的 worktree。
