# 委派角色（sub agents）

全域安裝自 `agent-skills-template`（`scripts/install-global.sh`）：角色本體在 `~/.agents/roles/`。
專案有同名角色（`.agents/roles/`、`.claude/agents/`、`.codex/agents/`）時以專案版為準；專案的 `CLAUDE.md` / `AGENTS.md` 對派工另有規定時，也以專案為準。

scout 找、runner 跑、reviewer 挑、worker 做、architect 判（見 `~/.agents/roles/README.md`）。

**主動派工，不必等使用者點名**：
- 跨多檔／多目錄的搜尋、找同一份邏輯的其他實作 → `scout`
- 會吐大量輸出或耗時超過一兩分鐘的指令 → `runner`（輸出不進主 context 是重點）；改完 code 後的 test／lint／build 一律派，不因為指令小就自己跑
- 改動達 3 檔以上、或動到對外契約的 diff → `reviewer`
- spec 已明確且與主線討論脫鉤的實作 → `worker`
- 要動 API 形狀 / schema / 部署順序，或有多個做法要取捨 → `architect`

**派出去就不等**：派工前用一行告訴使用者派了什麼、為什麼（不必等回覆；使用者回「你做」就收回自己做）。派出去後主線繼續做不依賴結果的事——self-review diff、草擬 commit message／PR 描述、讀下一步要動的檔案；結果回來再判讀。主線在等待期間**不改交辦範圍內的檔案**（runner 正在測的、worker 正在改的）；真的要改就先等它回來。

**交辦要給齊**：objective、必要 context、可改範圍、禁止碰的範圍、完成條件、驗證指令（模板見 `~/.agents/roles/README.md`「交辦模板」）。結果由主線複核：worker 的 diff 要親自看過、runner 的失敗由主線判讀；角色不 commit / push。

**多 issue 調度**：一次處理多個 issue、要開多條 agent 線時，主 session 用 skill `orchestrate-issues`（各線跑 `fix-issue`）；主 session 自己的 sub agent 仍依上面的政策派。

**不要派**：已知檔案的單點查詢、一兩行的改動、需要當下對話脈絡才判斷得出來的問題——sub agent 拿不到這段對話，把背景重打一遍比自己做還慢，而且它只回摘要、細節會遺失。
