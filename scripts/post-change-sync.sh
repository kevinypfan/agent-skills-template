#!/usr/bin/env sh
# git hook（post-commit / post-merge / post-checkout / post-rewrite）呼叫：本機已全域安裝本 repo 時，自動同步。
# 判斷「已安裝」= ~/.agents/roles 是指回本 repo 的 symlink；沒裝過就什麼都不做（不會替 clone 的人偷裝）。
# symlink 項目本來就即時生效，這裡主要補「複製 / 區塊」項目（Codex agent、~/.codex/AGENTS.md）與新增的 skill。
repo=$(cd "$(dirname "$0")/.." && pwd -P)
[ -L "$HOME/.agents/roles" ] && [ "$(readlink "$HOME/.agents/roles")" = "$repo/.agents/roles" ] || exit 0
out=$(bash "$repo/scripts/install-global.sh" --apply --quiet 2>&1) || { echo "⚠ install-global 同步失敗：" >&2; echo "$out" >&2; exit 0; }
[ -n "$out" ] && { echo "↻ 全域安裝已同步："; echo "$out"; }
exit 0
