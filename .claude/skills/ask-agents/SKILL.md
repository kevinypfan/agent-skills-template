---
name: ask-agents
description: 把一個問題或 review 打包丟給機器上「另一家」AI agent CLI（在 Claude Code 裡問 codex、在 Codex 裡問 claude；agy 點名才加）拿第二意見，再彙整共識與分歧。使用時機：(1) 使用者說「問 codex」「問 claude」「問 gemini/agy」「找別的 agent/model 看看」「second opinion」「交叉驗證」「會診」，(2) 卡在難題想要外部視角，(3) 想讓多個聰明 model 一起 review 一段 code 或一個設計決策，(4) 使用者明確呼叫 /ask-agents。
compatibility: Requires at least one of codex / claude / agy CLI on PATH (the one you are NOT running in)
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read `.agents/skills/ask-agents/SKILL.md` 並嚴格照其流程執行——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
