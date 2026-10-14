#!/usr/bin/env bash
# 刪除使用者確認過的可重建目錄。刪之前用 artifact_refusal 重新檢查（白名單、repo 的 .gitignore 明確指名該目錄、
# 不是否定規則、沒有巢狀 repo、沒有追蹤檔、不在家目錄 repo、沒有 process 在用），任一不符就拒絕。
# 路徑只解析一次：檢查與 rm 用同一個實際路徑，中途被換成 symlink 也不會刪到別處。
#
# 用法：remove-artifacts.sh [--dry-run] [--] <path>...（--dry-run 可放任何位置）
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

dry=0 paths=() n=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --) shift; while [ $# -gt 0 ]; do paths[${#paths[@]}]=$1; shift; done; break ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    -*) echo "不認得的參數：$1（以 - 開頭的路徑請放在 -- 之後）" >&2; exit 2 ;;
    *) paths[${#paths[@]}]=$1 ;;
  esac
  shift
done

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
active_cwds > "$tmp/cwds"; : > "$tmp/seen"
freed=0 ok=0 refused=0

while [ "$n" -lt "${#paths[@]}" ]; do
  arg=${paths[$n]}; n=$((n+1))
  if has_ctrl "$arg"; then echo "REFUSE 路徑含換行或 tab"; refused=$((refused+1)); continue; fi
  arg=${arg%/}
  [ -e "$arg" ] || [ -L "$arg" ] || { echo "skip  ${arg}：不存在"; continue; }
  [ -L "$arg" ] && { echo "REFUSE ${arg}：是 symlink"; refused=$((refused+1)); continue; }
  d=$(realdir "$arg")
  [ -n "$d" ] || { echo "REFUSE ${arg}：不是可進入的目錄"; refused=$((refused+1)); continue; }
  grep -qxF "$d" "$tmp/seen" && { echo "skip  ${d}：重複"; continue; }
  echo "$d" >> "$tmp/seen"
  why=$(artifact_refusal "$d" "$tmp/cwds")
  [ -n "$why" ] && { echo "REFUSE ${d}：$why"; refused=$((refused+1)); continue; }
  sz=$(size_kb "$d")
  if [ "$dry" = 1 ]; then echo "  (dry-run) rm -rf ${d}（$(human "$sz")）"
  else rm -rf -- "$d" && echo "ok    ${d}（$(human "$sz")）"; fi
  freed=$((freed+sz)); ok=$((ok+1))
done
echo "# 刪除 $ok 個、拒絕 $refused 個，釋放約 $(human "$freed")"
