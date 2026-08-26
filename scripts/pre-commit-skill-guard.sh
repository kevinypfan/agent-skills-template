#!/usr/bin/env sh
# pre-commit 片段：只在碰到 skill 定義時才跑守門（其餘 commit 零成本）。
# 安裝方式見 README（husky：在 .husky/pre-commit 加一行 `sh scripts/pre-commit-skill-guard.sh`；
# 無 husky：`git config core.hooksPath .githooks` 並在 .githooks/pre-commit 呼叫本檔）。
guard='^(\.agents/|\.claude/skills/|scripts/(check|generate)-skill-stubs\.sh)'
if git diff --cached --name-only | grep -qE "$guard"; then
  # 守門讀的是 working tree：同一個守門檔「既 staged 又有未 stage 的變更」時，檢查對象與即將 commit 的內容不同，拒絕
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  git diff --cached --name-only | grep -E "$guard" | sort > "$t/staged"
  git diff --name-only | grep -E "$guard" | sort > "$t/dirty" || true
  if both=$(comm -12 "$t/staged" "$t/dirty") && [ -n "$both" ]; then
    echo "✗ 下列守門檔既已 stage 又有未 stage 的變更，請補 stage 或 stash 後再 commit："; echo "$both" | sed 's/^/    /'; exit 1
  fi
  bash scripts/check-skill-stubs.sh
fi
