#!/usr/bin/env sh
# pre-commit 片段：只在碰到 skill / agent 定義時才跑守門（其餘 commit 零成本）。
# 安裝方式見 README（husky：在 .husky/pre-commit 加一行 `sh scripts/pre-commit-skill-guard.sh`；
# 無 husky：`git config core.hooksPath .githooks` 並在 .githooks/pre-commit 呼叫本檔）。
guard='^(\.agents/|\.claude/(skills|agents)/|\.codex/agents/|global/|scripts/(check|generate)-skill-stubs\.sh)'
if git diff --cached --name-only | grep -qE "$guard"; then
  t=$(mktemp -d) || exit 1
  trap 'rm -rf "$t"' EXIT
  git diff --cached --name-only | grep -E "$guard" | sort > "$t/staged"
  # 守門檢查讀檔案內容，要檢查的是「即將 commit 的內容」而不是 working tree：
  # 沒 stage 的修改、未追蹤的半成品都不該影響結果。所以把 index 匯出成快照，在快照裡跑全部檢查。
  # checkout-index 要沿用 git 傳給 hook 的環境（GIT_INDEX_FILE 指向這次 commit 的 index，`git commit <path>` 時是暫時 index）。
  git checkout-index --all --prefix="$t/snap/" || exit 1
  # 快照裡的檢查會呼叫 git（rev-parse、grep、init），先清掉 hook 環境變數，免得作用到真正的 repo。
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX
    cd "$t/snap" || exit 1
    git init -q && git add -A || exit 1
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
