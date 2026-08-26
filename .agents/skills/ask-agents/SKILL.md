---
name: ask-agents
description: 把一個問題或 review 打包丟給機器上「另一家」AI agent CLI（在 Claude Code 裡問 codex、在 Codex 裡問 claude；agy 點名才加）拿第二意見，再彙整共識與分歧。使用時機：(1) 使用者說「問 codex」「問 claude」「問 gemini/agy」「找別的 agent/model 看看」「second opinion」「交叉驗證」「會診」，(2) 卡在難題想要外部視角，(3) 想讓多個聰明 model 一起 review 一段 code 或一個設計決策，(4) 使用者明確呼叫 /ask-agents。
compatibility: Requires at least one of codex / claude / agy CLI on PATH (the one you are NOT running in)
---

> This skill should only be invoked explicitly by the user or other skills.

## User Input

```text
<使用者參數（由呼叫端帶入）>
```

You **MUST** consider the user input before proceeding (if not empty). The user input may contain:
- 要問的問題 / 要 review 的目標（diff、檔案、設計決策）
- 點名哪些 agent（「也問 agy」「兩個都問」「只問 gemini」）
- 對輸出的期待（要結論、要風險清單、要投票…）

## 這個 skill 在做什麼、為什麼

同一個問題讓**不同家**的 model（Claude、GPT、Gemini）各自獨立看一次，價值在於**視角互補**：
訓練資料、盲點、預設偏好都不同，共識代表答案穩健，分歧往往正好指出問題裡沒說清楚的部分。
所以品質瓶頸在「prompt 打包得夠不夠自足」——外部 agent 看不到這個對話的上下文，只看得到你給它的 prompt 和它自己能讀到的 repo 檔案。

**預設組合依你所在的 host 決定**（問自家沒有意義——同一批盲點）：

| 你在哪個 host | 預設問 | 點名才加 | 不問 |
|---|---|---|---|
| Claude Code | codex（`gpt-5.6-sol`, high） | agy（`gemini-3.1-pro-high`） | claude |
| Codex | claude（`claude-fable-5`, high） | agy | codex |

使用者說「都問」「多方意見」= 另外兩家全上。所有外部 agent 都用**唯讀**模式——只能讀 repo、跑唯讀命令，不能改檔案。

## Workflow

### Step 1: 打包 prompt（品質關鍵）

把問題寫成一份自足的 prompt，存到 `$SCRATCHPAD/ask-agents/prompt.md`
（`$SCRATCHPAD` 指 system prompt 給的 scratchpad 目錄；沒有這個變數的環境（如 Codex）用 `mktemp -d` 建一個、後續步驟沿用同一路徑；走檔案是為了避免 shell quoting 地獄）。

寫 prompt 時記住外部 agent 的處境：
- **它在同一個 repo 的 cwd 下執行、可以自己讀檔案**——給「檔案路徑 + 該看哪裡」，不要把大段 code 或整包 diff 貼進 prompt。review 分支時給 base ref，讓它自己 `git diff <base>...HEAD`
- **它沒有這個對話的記憶**——一段話講清楚系統背景、問題本身、已知約束與已排除的選項
- **它只能用唯讀工具**——prompt 裡明講「你只能讀檔與跑 `git diff/log/show`、`rg`、`sed -n`，不要嘗試寫檔或跑測試」，免得它浪費回合去試被拒的指令
- **明確要求輸出形狀**——例如「先給結論，再列理由與風險，最後給具體建議；如果你認為前提有誤請直說」。鼓勵它反駁，不要只找附和
- 領域詞保持原文即可，三家 model 都讀得懂中文

### Step 2: 平行呼叫（背景執行）

high reasoning 可能跑好幾分鐘，一律背景執行；要問多家時**同一則訊息裡一起發**。

**codex**（在 Claude Code 裡預設必問）：

```bash
codex exec --sandbox read-only --skip-git-repo-check \
  -m gpt-5.6-sol -c model_reasoning_effort=high \
  -o "$SCRATCHPAD/ask-agents/codex-answer.md" \
  - < "$SCRATCHPAD/ask-agents/prompt.md"
```

- `-` = 從 stdin 讀 prompt；`-o` 把**乾淨的最終回覆**寫到檔案（stdout 混著 thinking 與 token 統計，不要從那裡撈答案）

**claude**（在 Codex 裡預設必問）：

```bash
claude -p --model claude-fable-5 --effort high \
  --tools "Read,Grep,Glob,Bash" \
  --allowedTools "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(rg:*)" "Bash(sed -n:*)" \
  --permission-mode dontAsk \
  --no-session-persistence \
  < "$SCRATCHPAD/ask-agents/prompt.md" > "$SCRATCHPAD/ask-agents/claude-answer.md"
```

- `-p` 從 stdin 讀 prompt，預設 text 輸出**只有最終回覆**（無 thinking），直接重導向即可
- 唯讀 = `--tools` 只給讀取工具 + `--allowedTools` 白名單只放 git 讀取與 rg + `dontAsk`（白名單外的 Bash **靜默拒絕**、不會卡在互動提示）。這是 permission 層的 best-effort，不是 OS sandbox
- `--no-session-persistence`：不在 `~/.claude` 留 session；要追問就拿掉它、改 `--resume <session_id>`
- ⚠ **若 host 端有改寫指令的 hook**（如把 `git log` 改成 `rtk git log`），白名單要同時放改寫後的形式（`"Bash(rtk git log:*)"` …），否則連唯讀指令都會被拒；用 `--output-format json` 看 `permission_denials[].tool_input.command` 就知道實際送出的指令長什麼樣

**agy**（被點名時才問）：

```bash
agy --model gemini-3.1-pro-high --sandbox=true --print-timeout 15m \
  -p "$(cat "$SCRATCHPAD/ask-agents/prompt.md")" \
  > "$SCRATCHPAD/ask-agents/agy-answer.md" 2>&1
```

- ⚠ **所有 flag 必須在 prompt 之前**：agy 是 Go 式 flag 解析，第一個 positional argument 之後的 flag 全部**靜默忽略**
- `--sandbox=true` 要用等號形式
- `--print-timeout` 預設 5m，pro-high 會超時，先拉到 15m

### Step 3: 彙整回報

等背景任務完成後讀回覆檔彙整。**不要照單全收**：外部 agent 的具體宣稱（「第 N 行有 bug」「這個 API 行為是 X」）先對照 code 驗證過再轉述，錯的就標明「此點經查不成立」。

```markdown
## 各家意見
### codex (gpt-5.6-sol, high)        ← 有問才有
### claude (claude-fable-5, high)    ← 有問才有
### agy (gemini-3.1-pro-high)        ← 有問才有
（各段：重點摘要，不是全文轉貼）

## 共識
## 分歧
（誰說了什麼、為什麼不同——分歧點通常值得使用者親自裁決）

## 我的評估
（綜合外部意見與自己對 code 的驗證）
```

只問一家時省略共識/分歧，改成「<agent> 的意見」+「我的評估（含驗證結果）」。

## Review 場景的後續流程（可選）

review 對象是一個 PR 且使用者要求「發布結果」時，走三段式（tracker 指令見 `.agents/skills/_tracker/README.md`）：

1. **發布 review comment**（[tracker] 留 PR 總結 comment）：外部 agent 的 verdict + 逐條 findings，**每條標注驗證狀態**（已確認屬實 / 經查不成立 / 維持原判＋理由）
2. **修正並 push**：只 commit 本次修正相關的檔案——逐一 `git add <file>`，commit 後 `git show --stat HEAD` 確認沒掃進無關檔案
3. **追加處置 comment**：逐條「finding → 處置」對照表 + 維持原判的理由 + known limitations

「維持原判」是合法處置——外部意見是輸入不是裁決。

## 常見陷阱

1. **Codex 底下跑本 skill 需要網路**：`claude -p` / `agy` 是 Codex sandbox 裡的子進程，`read-only` 與預設 `workspace-write` 都**無網路**、會直接連不上 API。Codex 端要以 `--sandbox danger-full-access`（或 config 開 `network_access`）啟動本回合；反向（Claude Code 裡跑 codex）沒有這個問題
2. **agy flag 順序**：flag 在前、prompt 在後（靜默失敗）
3. **成本意識**：三家都是最貴檔位。一份打包完整的 prompt 問一次，勝過來回好幾輪；追問用 `codex exec resume --last` / `claude --resume`
4. **model fallback**：`gpt-5.6-sol` 回 model not supported 時拿掉 `-m` 用預設 model；`claude-fable-5` 不可用時退 `claude-opus-5`；reasoning/effort high 保留
5. **唯讀的意思**：外部 agent 不能跑會寫檔的驗證（測試會寫 target/、node_modules cache…）。需要測試結果時自己跑完貼進 prompt
6. **別把外部意見直接當結論丟給使用者**：你擁有最完整的對話脈絡，彙整與把關是你的責任
