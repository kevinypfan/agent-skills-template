# 委派角色（sub agents）

全域安裝自 `agent-skills-template`（`scripts/install-global.sh`）：角色本體在 `~/.agents/roles/`。
專案有同名角色（`.agents/roles/`、`.claude/agents/`、`.codex/agents/`）時以專案版為準；專案的 `CLAUDE.md` / `AGENTS.md` 對派工另有規定時，也以專案為準。

scout 找、runner 跑、reviewer 挑、worker 做、architect 判（見 `~/.agents/roles/README.md`）。

**主動派工，不必等使用者點名**：
- 跨多檔／多目錄的搜尋、找同一份邏輯的其他實作 → `scout`
- 會吐大量輸出或耗時超過一兩分鐘的指令 → `runner`（輸出不進主 context 是重點）
- 改動達 3 檔以上、或動到對外契約的 diff → `reviewer`
- spec 已明確且與主線討論脫鉤的實作 → `worker`
- 要動 API 形狀 / schema / 部署順序，或有多個做法要取捨 → `architect`

**不要派**：已知檔案的單點查詢、一兩行的改動、需要當下對話脈絡才判斷得出來的問題——sub agent 拿不到這段對話，把背景重打一遍比自己做還慢，而且它只回摘要、細節會遺失。
