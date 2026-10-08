---
name: address-pr-review
description: 處理 PR / MR 收到的 review 意見：收集未解決 thread、review 總結 comment 與 pre-merge 擴充點未通過項目，統一成 finding 去重，分級（Must / Should / Discuss / Skip）後與使用者確認、實作、跑測試與 lint，經 commit-push-pr 推上去，再逐條回覆或 resolve thread，最後回報不做的事項與理由。使用時機：(1) 使用者說「處理 review 意見」「回應 review」「address review」「套用 review 建議」「修 review」，(2) review-pr 選「發佈並處理」後串接，(3) orchestrate-issues 的 PR 關卡請原線處理 review 結果，(4) 使用者明確呼叫 /address-pr-review。
compatibility: Requires git and glab (GitLab) or gh (GitHub)
---

## User Input

````text
$ARGUMENTS
````

本檔由 `scripts/generate-skill-stubs.sh` 產生，勿手改。Read 真身並嚴格照其流程執行：repo 根有 `.agents/skills/address-pr-review/SKILL.md` 就讀它，沒有就讀 `~/.agents/skills/address-pr-review/SKILL.md`（全域安裝）——該檔「User Input／使用者參數」所指即上方內容；附屬檔一律用該檔內寫的 repo 相對路徑。
