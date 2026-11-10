#!/usr/bin/env bash
# 列出 worktree 裡被 ignore、但不在可重建白名單的檔案（.env、*.local、*.log、筆記…）。
# git status --porcelain 看不到這些檔案，而 git worktree remove（帶不帶 --force 都一樣）會不經確認刪掉它們。
# 白名單與判斷沿用 lib.sh 的 ignored_extras / ARTIFACT_NAMES，不另寫一套。
#
# 用法：ignored-extras.sh <worktree 根目錄>
# exit 0 = 沒有這類檔案（可以移除）
# exit 1 = 有，逐行印出相對路徑（要先問使用者）
# exit 2 = 參數錯、路徑不是 worktree 根目錄、或讀取失敗（一律當成不能移除）
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

[ $# -eq 1 ] && [ -n "$1" ] || { echo "用法：ignored-extras.sh <worktree 根目錄>" >&2; exit 2; }
has_ctrl "$1" && { echo "路徑含換行或 tab：拒絕" >&2; exit 2; }

# 路徑必須就是某個 worktree 的根目錄：空字串或子目錄會讓 git 退回到別的 repo／上層，判斷就失準
want=$(realdir "$1")
top=$(git --no-optional-locks -C "$1" rev-parse --show-toplevel 2>/dev/null)
top=$(realdir "$top")
[ -n "$want" ] && [ -n "$top" ] && [ "$want" = "$top" ] || { echo "不是 worktree 根目錄：$1" >&2; exit 2; }

out=$(ignored_extras "$want")
case "$out" in *__ERR__*) echo "讀取 git status 失敗：$1" >&2; exit 2 ;; esac
[ -z "$out" ] && exit 0
printf '%s\n' "$out"
exit 1
