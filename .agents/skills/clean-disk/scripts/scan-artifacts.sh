#!/usr/bin/env bash
# 找根目錄底下「可重建」的大目錄（依賴、建置產物、測試快取）。只讀。
# 只列通過 artifact_refusal 檢查的：白名單名稱、被所屬 repo 的 ignore 規則「指名」、不是 nested repo、沒有追蹤檔。
#
# 用法：scan-artifacts.sh [--min-mb N] [--depth N] <根目錄>...
# 輸出：TSV（size_kb idle_days kind repo path），依大小排序；# 開頭為摘要行。
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

min_mb=50 depth=8 roots=""
while [ $# -gt 0 ]; do
  case "$1" in
    --min-mb) min_mb=$2; shift ;; --depth) depth=$2; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    -*) echo "不認得的參數：$1" >&2; exit 2 ;;
    *) r=$(realdir "$(expand_tilde "$1")"); [ -n "$r" ] || { echo "不是目錄：$1" >&2; exit 2; }
       roots="$roots
$r" ;;
  esac
  shift
done
[ -z "$roots" ] && { echo "用法：scan-artifacts.sh [--min-mb N] <根目錄>..." >&2; exit 2; }

expr=""; for n in $ARTIFACT_NAMES; do case "$n" in .DS_Store) continue ;; esac; expr="$expr -o -name $n"; done; expr=${expr# -o }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
active_cwds > "$tmp/cwds"
printf '%s\n' "$roots" | sed '/^$/d' | while read -r root; do
  # shellcheck disable=SC2086
  find "$root" -maxdepth "$depth" -name .git -prune -o -type d \( $expr \) -prune -print 2>/dev/null
done | while read -r d; do
  [ -z "$(artifact_refusal "$d" "$tmp/cwds")" ] || continue
  sz=$(size_kb "$d"); [ "${sz:-0}" -lt $((min_mb * 1024)) ] && continue
  idle=$(( ( $(date +%s) - $(mtime "$d") ) / 86400 ))
  printf '%s\t%s\t%s\t%s\t%s\n' "$sz" "$idle" "$(basename "$d")" "$(git -C "$(dirname "$d")" rev-parse --show-toplevel)" "$d"
done | sort -t$'\t' -k1,1nr > "$tmp/rows"

printf 'size_kb\tidle_days\tkind\trepo\tpath\n'
cat "$tmp/rows"
printf '# %s 個目錄（≥ %s MB），共 %s\n' "$(wc -l < "$tmp/rows" | tr -d ' ')" "$min_mb" "$(human "$(awk -F'\t' '{s+=$1} END{print s+0}' "$tmp/rows")")"
