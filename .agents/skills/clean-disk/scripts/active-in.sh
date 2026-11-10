#!/usr/bin/env bash
# 列出 cwd 在某個目錄（含子目錄）底下的 process。
# 用途：hc 收尾 kill 掉 agent 之後、檢查與移除 worktree 之前，確認沒有殘留的 process 還在裡面寫檔
# （例如 Codex 把每個指令放進獨立的 process group，hc kill 碰不到它們）。
#
# 用法：active-in.sh <目錄>
# exit 0 = 沒有
# exit 1 = 有，逐行印出 `<pid> <指令名> <cwd>`
# exit 2 = 參數錯、目錄不存在、或無法偵測（沒有 lsof／proc，或讀不到任何 process；一律當成不能移除）
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

[ $# -eq 1 ] && [ -n "$1" ] || { echo "用法：active-in.sh <目錄>" >&2; exit 2; }
has_ctrl "$1" && { echo "路徑含換行或 tab：拒絕" >&2; exit 2; }
dir=$(realdir "$1")
[ -n "$dir" ] || { echo "目錄不存在：$1" >&2; exit 2; }
cd / || exit 2   # 自己不要待在目標目錄裡，免得列到自己

# 每行：<pid>\t<指令名>\t<cwd>
if command -v lsof >/dev/null 2>&1; then
  all=$(lsof -a -d cwd -u "$(id -u)" -Fpcn 2>/dev/null | awk '
    /^p/ { pid=substr($0,2); cmd="" } /^c/ { cmd=substr($0,2) } /^n/ { printf "%s\t%s\t%s\n", pid, cmd, substr($0,2) }')
elif [ -d /proc/self ]; then
  all=$(for c in /proc/[0-9]*/cwd; do
    p=${c#/proc/}; p=${p%/cwd}; w=$(readlink "$c" 2>/dev/null) || continue
    printf '%s\t%s\t%s\n' "$p" "$(cat "/proc/$p/comm" 2>/dev/null)" "$w"
  done)
else
  all=""
fi
# 執行本 script 的 shell 一定有 cwd，空清單代表偵測失敗（sandbox、權限），不代表沒人在用
[ -n "$all" ] || { echo "無法偵測哪些 process 在用這個目錄（沒有 lsof／proc，或輸出為空）" >&2; exit 2; }

hits=$(printf '%s\n' "$all" | D="$dir" awk -F'\t' '$3==ENVIRON["D"] || index($3, ENVIRON["D"] "/")==1 { print $1 " " $2 " " $3 }')
[ -z "$hits" ] && exit 0
printf '%s\n' "$hits"
exit 1
