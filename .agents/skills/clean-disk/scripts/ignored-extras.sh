#!/usr/bin/env bash
# 移除 linked worktree 之前，列出 git status --porcelain 看不到、但 git worktree remove（帶不帶 --force 都一樣）會刪掉的東西：
#   - 被 ignore、但不是可重建產物的檔案（.env、*.local、*.log、筆記…）——判斷沿用 lib.sh 的 ignored_extras / ARTIFACT_NAMES
#   - 巢狀的 repo／worktree（例如 .venv/src/ 底下的 editable install）——lib.sh 的 nested_gits
#   - assume-unchanged／skip-worktree 的檔案（修改不會出現在 status）
#
# 用法：ignored-extras.sh <linked worktree 根目錄>
# exit 0 = 都沒有（可以移除）
# exit 1 = 有，逐行印出：被 ignore 的檔案印相對路徑；其他兩類印 `nested-repo: <路徑>`、`hidden-change: <路徑>`（要先問使用者）
# exit 2 = 參數錯、路徑不是 linked worktree 的根目錄（含主 checkout）、或讀取失敗（一律當成不能移除）
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

[ $# -eq 1 ] && [ -n "$1" ] || { echo "用法：ignored-extras.sh <linked worktree 根目錄>" >&2; exit 2; }
has_ctrl "$1" && { echo "路徑含換行或 tab：拒絕" >&2; exit 2; }

# 路徑必須就是某個 worktree 的根目錄：空字串或子目錄會讓 git 退回到別的 repo／上層，判斷就失準
want=$(realdir "$1")
top=$(git --no-optional-locks -C "$1" rev-parse --show-toplevel 2>/dev/null)
top=$(realdir "$top")
[ -n "$want" ] && [ -n "$top" ] && [ "$want" = "$top" ] || { echo "不是 worktree 根目錄：$1" >&2; exit 2; }
# 主 checkout 的 git-dir 等於 common-dir；它不是調度建立的 linked worktree，不該走移除流程
# rev-parse 可能回相對路徑（主 checkout 是 .git），要在 worktree 裡解析，不能依賴呼叫端的 cwd
gd=$(cd -- "$want" 2>/dev/null && realdir "$(git rev-parse --git-dir 2>/dev/null)")
cd_=$(cd -- "$want" 2>/dev/null && realdir "$(git rev-parse --git-common-dir 2>/dev/null)")
[ -n "$gd" ] && [ -n "$cd_" ] || { echo "讀不到 git-dir：$1" >&2; exit 2; }
[ "$gd" != "$cd_" ] || { echo "這是主 checkout，不是 linked worktree：$1" >&2; exit 2; }

out=$(ignored_extras "$want")
case "$out" in *__ERR__*) echo "讀取 git status 失敗：$1" >&2; exit 2 ;; esac

nested=$(nested_gits "$want" | while IFS= read -r g; do g=${g#"$want"/}; printf '%s\n' "${g%/.git}"; done)
hidden=$(git -C "$want" ls-files -v 2>/dev/null) || { echo "讀取 git ls-files 失敗：$1" >&2; exit 2; }
hidden=$(printf '%s\n' "$hidden" | grep -E '^([a-z]|S) ' | cut -c3-)

found=0
[ -n "$out" ] && { printf '%s\n' "$out"; found=1; }
[ -n "$nested" ] && { printf '%s\n' "$nested" | sed 's/^/nested-repo: /'; found=1; }
[ -n "$hidden" ] && { printf '%s\n' "$hidden" | sed 's/^/hidden-change: /'; found=1; }
exit $found
