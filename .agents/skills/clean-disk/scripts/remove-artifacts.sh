#!/usr/bin/env bash
# 刪除使用者確認過的可重建目錄。刪之前用 artifact_refusal 重新檢查（白名單、ignore 規則指名該目錄、
# 不是 nested repo／worktree、沒有追蹤檔、不在家目錄 repo、沒有 process 在用），任一不符就拒絕。
#
# 用法：remove-artifacts.sh [--dry-run] <path>...（--dry-run 可放任何位置）
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

dry=0 paths=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    -*) echo "不認得的參數：$1" >&2; exit 2 ;;
    *) paths="$paths
$1" ;;
  esac
  shift
done

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
active_cwds > "$tmp/cwds"
freed=0 ok=0 refused=0

while read -r d; do
  [ -z "$d" ] && continue
  [ -e "$d" ] || [ -L "$d" ] || { echo "skip  ${d}：不存在"; continue; }
  why=$(artifact_refusal "$d" "$tmp/cwds")
  [ -n "$why" ] && { echo "REFUSE ${d}：$why"; refused=$((refused+1)); continue; }
  d=$(realdir "$d"); sz=$(size_kb "$d")
  if [ "$dry" = 1 ]; then echo "  (dry-run) rm -rf ${d}（$(human "$sz")）"
  else rm -rf "$d" && echo "ok    ${d}（$(human "$sz")）"; fi
  freed=$((freed+sz)); ok=$((ok+1))
done <<EOF
$paths
EOF
echo "# 刪除 $ok 個、拒絕 $refused 個，釋放約 $(human "$freed")"
