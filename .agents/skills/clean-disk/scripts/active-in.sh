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

# 每行：<pid>\t<cwd>\t<指令名>（cwd 放在指令名前面：指令名可能含 tab，放最後才不會擠動 cwd 那一欄）
# 「沒列到」不等於「沒有」：收集器失敗或部分失敗時一律回 exit 2，不能當成乾淨
if command -v lsof >/dev/null 2>&1; then
  # stderr 常有與本次無關的 warning（例如 NFS 掛載點），不拿來判斷；只看 exit code
  raw=$(lsof -a -d cwd -u "$(id -u)" -Fpcn 2>/dev/null) || { echo "lsof 失敗（exit 非 0），結果可能不完整" >&2; exit 2; }
  all=$(printf '%s\n' "$raw" | awk '
    /^p/ { pid=substr($0,2); cmd="" } /^c/ { cmd=substr($0,2) } /^n/ { printf "%s\t%s\t%s\n", pid, substr($0,2), cmd }')
elif [ -d /proc/self ]; then
  all=$(for c in /proc/[0-9]*/cwd; do
    p=${c#/proc/}; p=${p%/cwd}
    [ -O "/proc/$p" ] || continue   # 只看自己 UID 的 process（與 lsof 分支的 -u 一致）；讀不到別人的 cwd 是常態
    if ! w=$(readlink "$c" 2>/dev/null); then
      # zombie 已經結束、只是還沒被回收，cwd 本來就讀不到，不會再寫檔。狀態欄在 stat 最後一個 ')' 之後（指令名可能含空白或括號）
      st=$(sed 's/.*) //' "/proc/$p/stat" 2>/dev/null | cut -d' ' -f1)
      [ "$st" = Z ] && continue
      [ -e "/proc/$p" ] && { echo "__UNREADABLE__ $p"; continue; }   # process 還在卻讀不到 cwd
      continue                                                        # 讀的當下已經結束
    fi
    printf '%s\t%s\t%s\n' "$p" "$w" "$(tr '\t' ' ' < "/proc/$p/comm" 2>/dev/null)"
  done)
  case "$all" in *__UNREADABLE__*) echo "有 process 讀不到 cwd：$(printf '%s\n' "$all" | sed -n 's/^__UNREADABLE__ //p' | tr '\n' ' ')" >&2; exit 2 ;; esac
else
  all=""
fi
# 執行本 script 的 shell 一定有 cwd，空清單代表偵測失敗（sandbox、權限），不代表沒人在用
[ -n "$all" ] || { echo "無法偵測哪些 process 在用這個目錄（沒有 lsof／proc，或輸出為空）" >&2; exit 2; }

hits=$(printf '%s\n' "$all" | D="$dir" awk -F'\t' '$2==ENVIRON["D"] || index($2, ENVIRON["D"] "/")==1 { print $1 " " $3 " " $2 }')
[ -z "$hits" ] && exit 0
printf '%s\n' "$hits"
exit 1
