#!/usr/bin/env bash
# 掃根目錄底下所有 git repo 的 worktree，逐個分級（green 可刪 / yellow 要看 / red 保留）。不刪任何東西。
# （預設會 git fetch --prune 更新 remote-tracking ref；squash 偵測會寫入暫時的 git object，不動任何 ref）
#
# 用法：scan-worktrees.sh [--no-fetch] [--no-size] [--depth N] <根目錄或 repo>...
# 輸出：TSV，欄位見表頭；# 開頭為摘要行。依 tier（red → yellow → green）與大小排序。
# 環境變數 CLEAN_DISK_JOBS：平行 du 的數量（預設 8）。
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

fetch=1 do_size=1 depth=5 roots=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-fetch) fetch=0 ;; --no-size) do_size=0 ;;
    --depth) depth=$2; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    -*) echo "不認得的參數：$1" >&2; exit 2 ;;
    *) r=$(realdir "$(expand_tilde "$1")"); [ -n "$r" ] || { echo "不是目錄：$1" >&2; exit 2; }
       roots="$roots
$r" ;;
  esac
  shift
done
[ -z "$roots" ] && { echo "用法：scan-worktrees.sh [--no-fetch] [--no-size] [--depth N] <根目錄>..." >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
active_cwds > "$tmp/cwds"
: > "$tmp/registered"; : > "$tmp/fetch_failed"

# main repo = .git 是目錄（linked worktree 的 .git 是檔案）；不鑽進 worktree 目錄與依賴目錄
printf '%s\n' "$roots" | sed '/^$/d' | while read -r root; do
  find "$root" -maxdepth "$depth" \( -name node_modules -o -name .venv -o -name target -o -name '*-worktrees' -o -path '*/.claude/worktrees' \) -prune \
    -o -name .git -type d -print 2>/dev/null
done | sed 's|/\.git$||' | sort -u > "$tmp/repos"

while read -r repo; do
  if [ "$fetch" = 1 ] && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo" fetch --prune --quiet origin 2>/dev/null || echo "$repo" >> "$tmp/fetch_failed"
  fi
  list_worktrees "$repo" | while IFS=$'\t' read -r p br locked head; do
    [ "$br" = - ] && br=""
    [ "$head" = - ] && head=""
    rp=$(realdir "$p"); echo "${rp:-$p}" >> "$tmp/registered"
    inspect_worktree "$repo" "$p" "$br" "$locked" "$tmp/cwds" 0 "$head"
  done
done < "$tmp/repos" > "$tmp/rows"

# 孤兒目錄：放 worktree 的目錄（worktree_root、.claude/worktrees）底下，卻不在任何 repo 的 worktree list
while read -r repo; do
  for parent in "$(worktree_root "$repo")" "$repo/.claude/worktrees"; do
    [ -d "$parent" ] || continue
    for d in "$parent"/*; do
      [ -d "$d" ] && [ ! -L "$d" ] || continue
      rd=$(realdir "$d")
      grep -qxF "$rd" "$tmp/registered" && continue
      [ -d "$d/.git" ] && continue   # 獨立 clone 的 repo，不是 worktree
      idle=$(( ( $(date +%s) - $(mtime "$d") ) / 86400 ))
      why="孤兒目錄：不在任何 worktree list（.git 指向已不存在的 metadata，或根本不是 git 目錄）；git 無法判斷裡面有沒有未保存的改動"
      printf 'yellow\t%s\t%s\t-\t0\t%s\t-\t-\t-\t-\t-\t%s\n' "$repo" "$rd" "$idle" "$why"
    done
  done
done < "$tmp/repos" | sort -u >> "$tmp/rows"

# 大小最花時間（大型 target／node_modules），統一在最後平行算
if [ "$do_size" = 1 ]; then
  cut -f3 "$tmp/rows" | while read -r p; do [ -d "$p" ] && printf '%s\0' "$p"; done |
    xargs -0 -n 1 -P "${CLEAN_DISK_JOBS:-8}" du -sk 2>/dev/null > "$tmp/sizes"
  awk -F'\t' 'BEGIN{OFS="\t"} NR==FNR { kb[$2]=$1; next } { if ($3 in kb) $5=kb[$3]; print }' "$tmp/sizes" "$tmp/rows" > "$tmp/rows2" && mv "$tmp/rows2" "$tmp/rows"
fi

printf 'tier\trepo\tpath\tbranch\tsize_kb\tidle_days\ttracked\tuntracked\tunpushed\tmerged\tupstream\treasons\n'
awk -F'\t' 'BEGIN{OFS="\t"} { o=($1=="red")?0:($1=="yellow")?1:2; print o, $0 }' "$tmp/rows" | sort -t$'\t' -k1,1n -k6,6nr | cut -f2-
for t in green yellow red; do
  kb=$(awk -F'\t' -v t="$t" '$1==t{s+=$5; n++} END{printf "%d %d", n, s}' "$tmp/rows")
  printf '# %s: %s 個，共 %s\n' "$t" "${kb% *}" "$(human "${kb#* }")"
done
printf '# repos 掃到 %s 個\n' "$(wc -l < "$tmp/repos" | tr -d ' ')"
if [ -s "$tmp/fetch_failed" ]; then
  printf '# fetch 失敗（remote ref 可能過期，分級偏保守）：%s\n' "$(tr '\n' ' ' < "$tmp/fetch_failed")"
fi
if grep -qx '__UNKNOWN__' "$tmp/cwds"; then echo "# 警告：無法偵測使用中的目錄（沒有 lsof／proc），所有 worktree 都當作可能在用"; fi
exit 0
