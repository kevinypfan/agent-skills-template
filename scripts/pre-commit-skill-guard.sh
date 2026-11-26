#!/usr/bin/env sh
# pre-commit 片段：只在碰到 skill / agent 定義時才跑守門（其餘 commit 零成本）。
# 安裝方式見 README（husky：在 .husky/pre-commit 加一行 `sh scripts/pre-commit-skill-guard.sh`；
# 無 husky：`git config core.hooksPath .githooks` 並在 .githooks/pre-commit 呼叫本檔）。
guard='^(\.agents/|\.claude/(skills|agents)/|\.codex/agents/|global/|scripts/(check|generate)-skill-stubs\.sh)'
# quotePath 關掉：否則含非 ASCII 字元的路徑會被加上引號，上面的 ^ 比對不到，整個守門被跳過
staged() { git -c core.quotePath=false diff --cached --name-only; }
if staged | grep -qE "$guard"; then
  t=$(mktemp -d) || exit 1
  trap 'rm -rf "$t"' EXIT
  staged | grep -E "$guard" | sort > "$t/staged"
  # 守門檢查讀檔案內容，要檢查的是「即將 commit 的內容」而不是 working tree：
  # 沒 stage 的修改、未追蹤的半成品都不該影響結果。所以把要 commit 的 tree 匯出成快照，在快照裡跑全部檢查。
  # 用 write-tree + 暫時 index 匯出，而不是直接 checkout-index 這次的 index：intent-to-add（git add -N）不會進 tree，
  # skip-worktree（sparse checkout）的檔也會照樣匯出。write-tree 讀 git 傳給 hook 的 GIT_INDEX_FILE（`git commit <path>` 時是暫時 index）。
  tree=$(git write-tree) || exit 1
  GIT_INDEX_FILE="$t/index" git read-tree "$tree" || exit 1
  GIT_INDEX_FILE="$t/index" git checkout-index --all --prefix="$t/snap/" || exit 1
  # 快照裡的檢查會呼叫 git（rev-parse、grep、init）：先清掉 hook 環境帶進來的 repo 相關變數與 pathspec 旗標，免得作用到真正的 repo 或改變比對結果。
  (
    # shellcheck disable=SC2046
    unset $(git rev-parse --local-env-vars) GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
    cd "$t/snap" || exit 1
    # -f：已追蹤但符合忽略規則的檔（git add -f 加進來的）也要進快照
    git init -q && git add -A -f || exit 1
    bash scripts/check-skill-stubs.sh || exit 1
    # 動到內容指紋 script 就跑它的斷言測試
    if grep -qE '^\.agents/roles/(worktree-fingerprint\.sh|evals/check-fingerprint\.sh)$' "$t/staged"; then
      bash .agents/roles/evals/check-fingerprint.sh || exit 1
    fi
    # 動到 secret 掃描器就跑它的斷言測試
    if grep -qE '^\.agents/skills/_tracker/(scan-secrets\.sh|evals/check-scan-secrets\.sh)$' "$t/staged"; then
      bash .agents/skills/_tracker/evals/check-scan-secrets.sh || exit 1
    fi
    # 動到外部 agent 冷卻紀錄就跑它的斷言測試
    if grep -qE '^\.agents/skills/ask-agents/(scripts/cooldown\.sh|evals/check-cooldown\.sh)$' "$t/staged"; then
      bash .agents/skills/ask-agents/evals/check-cooldown.sh || exit 1
    fi
  ) || exit 1
fi
