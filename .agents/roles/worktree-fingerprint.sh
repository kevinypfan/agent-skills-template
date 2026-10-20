#!/usr/bin/env bash
# 印出 worktree 目前內容的指紋（一行 hash）：已追蹤檔相對 HEAD 的改動 + 未追蹤（未 ignore）項目的路徑與內容。
# 用途：runner 在測試前後各算一次，主線 commit 前再算一次；三者一致，綠燈才算測到要 commit 的內容。
# `git status` 做不到這件事：已是 modified 的檔案再被改一次，status 前後完全一樣。
# 唯讀：hash-object 不加 -w，不寫入任何 object；ignored 的建置產物不計入。
# 未追蹤項目：一般檔案算內容；symlink 算指向；巢狀 repo 算它的 HEAD 與未 commit 改動；其他類型只算路徑與類型。
#
# 用法：worktree-fingerprint.sh [<worktree 路徑>]（預設目前目錄）
set -euo pipefail
cd "${1:-.}"
git rev-parse --verify -q HEAD >/dev/null || { echo "worktree-fingerprint：HEAD 不存在（尚無 commit），無法計算" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
: > "$tmp/files"
{
  git diff HEAD --binary
  git ls-files -o --exclude-standard -z | while IFS= read -r -d '' p; do
    q=${p%/}
    if [ -L "$q" ]; then
      printf 'L\t%s\t%s\n' "$q" "$(readlink "$q")"
    elif [ -d "$q" ]; then
      if h=$(git -C "$q" rev-parse --verify -q HEAD 2>/dev/null); then
        printf 'R\t%s\t%s\n' "$q" "$h"
        git -C "$q" diff HEAD --binary
        git -C "$q" ls-files -o --exclude-standard
      else
        printf 'D\t%s\n' "$q"
      fi
    elif [ -f "$q" ]; then
      case "$q" in
        *$'\n'*) printf 'F\t%s\t%s\n' "$q" "$(git hash-object -- "$q")" ;;
        *) printf 'F\t%s\n' "$q"; printf '%s\n' "$q" >> "$tmp/files" ;;   # 內容 hash 批次算，量大時才不會慢
      esac
    else
      printf '?\t%s\n' "$q"
    fi
  done
} > "$tmp/all"
git hash-object --stdin-paths < "$tmp/files" >> "$tmp/all"
git hash-object --stdin < "$tmp/all"
