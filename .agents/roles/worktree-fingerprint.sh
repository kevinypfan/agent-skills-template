#!/usr/bin/env bash
# 印出 worktree 目前內容的指紋（一行 hash）：已追蹤檔相對 HEAD 的改動 + 未追蹤（未 ignore）檔的路徑與內容。
# 用途：runner 在測試前後各算一次，主線 commit 前再算一次；三者一致，綠燈才算測到要 commit 的內容。
# `git status` 做不到這件事：已是 modified 的檔案再被改一次，status 前後完全一樣。
# 唯讀：hash-object 不加 -w，不寫入任何 object；ignored 的建置產物不計入。
#
# 用法：worktree-fingerprint.sh [<worktree 路徑>]（預設目前目錄）
set -euo pipefail
cd "${1:-.}"
git rev-parse --verify -q HEAD >/dev/null || { echo "worktree-fingerprint：HEAD 不存在（尚無 commit），無法計算" >&2; exit 1; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
{
  git diff HEAD --binary
  git ls-files -o --exclude-standard
  git ls-files -o --exclude-standard -z | xargs -0 git hash-object --
} > "$tmp"
git hash-object --stdin < "$tmp"
