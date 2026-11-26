#!/usr/bin/env bash
# 外部 agent 額度冷卻紀錄：額度用完後記下「到什麼時候前不要再叫它」，之後的呼叫直接跳過、不再撞一次限制。
#   cooldown.sh check <agent>                冷卻中 → 印「<agent> 冷卻至 <時間>：<原因>」、exit 1；可用 → exit 0、不印；用法錯 → exit 2
#   cooldown.sh set <agent> <時間> [原因]     <時間>：時長（純數字為秒，或 90s / 30m / 5h / 1d）、本地時刻 HH:MM（已過就算明天）、
#                                             本地日期時刻 "YYYY-MM-DD HH:MM"、或 @epoch；最長 30 天
#   cooldown.sh clear <agent>                解除（使用者說額度回來了）
#   cooldown.sh list                         列出仍在冷卻中的
# 狀態檔：$ASK_AGENTS_STATE（預設 ~/.agents/state/agent-cooldown），每行 <agent>\t<到期 epoch>\t<原因>；過期的行讀到時忽略、寫入時清掉。
# 寫入用 mkdir 當鎖（bash 3.2 沒有 flock），平行呼叫多家同時額度用完也不會互相蓋掉；鎖存在超過 60 秒視為殘留（程序被 kill -9）並清掉。
set -euo pipefail
state=${ASK_AGENTS_STATE:-$HOME/.agents/state/agent-cooldown}
lock="$state.lock"
now=$(date +%s)
fmt() { date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$1" '+%Y-%m-%d %H:%M'; }   # GNU 的 -r 是讀檔案 mtime，先試 -d
local_epoch() { date -j -f '%Y-%m-%d %H:%M:%S' "$1:00" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null; }   # macOS（補秒數，否則取當下的秒）/ GNU
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }   # GNU 的 -f 是檔案系統資訊、會印到 stdout，先試 -c
live() { [ -f "$state" ] && awk -F'\t' -v n="$now" '$2 > n' "$state" || true; }
usage() { sed -n '3,7p' "$0" >&2; exit 2; }
digits() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "${#1}" -le 12 ]; }
stale() { local m; m=$(mtime "$1" 2>/dev/null) && [ -n "$m" ] && [ $(( $(date +%s) - m )) -gt 60 ]; }   # 目錄存在且超過 60 秒

rewrite() { # $1=要移除的 agent；$2=要加入的整行（可空）
  mkdir -p "$(dirname "$state")"
  [ -w "$(dirname "$state")" ] || { echo "$(dirname "$state") 不可寫，無法記錄冷卻" >&2; exit 3; }
  local i=0 tmp m
  until mkdir "$lock" 2>/dev/null; do
    i=$((i+1)); [ "$i" -ge 100 ] && { echo "等不到鎖 ${lock}（另一個程序持有中）" >&2; exit 3; }
    # 持有者可能剛好在這之間放掉鎖：stat 失敗就直接重試。
    # 清殘留鎖要先拿 $lock.reap 互斥並重新確認仍過期：否則兩個等待者交錯時，後到的會把先到者剛拿的新鎖當殘留清掉。
    if stale "$lock"; then
      stale "$lock.reap" && { rmdir "$lock.reap" 2>/dev/null || true; }   # 清鎖途中被 kill -9 留下的
      if mkdir "$lock.reap" 2>/dev/null; then
        if stale "$lock"; then mv "$lock" "$lock.stale.$$" 2>/dev/null && rmdir "$lock.stale.$$" 2>/dev/null || true; fi
        rmdir "$lock.reap" 2>/dev/null || true
      fi
      continue
    fi
    sleep 0.1
  done
  trap 'rmdir "${lock}" 2>/dev/null' EXIT
  tmp=$(mktemp "$state.XXXXXX")
  {
    live | awk -F'\t' -v a="$1" '$1 != a'
    if [ -n "${2:-}" ]; then printf '%s\n' "$2"; fi
  } > "$tmp"
  mv "$tmp" "$state"
}

case "${1:-}" in
  check)
    [ $# -eq 2 ] || usage
    line=$(live | awk -F'\t' -v a="$2" '$1 == a' | tail -1)
    [ -z "$line" ] && exit 0
    IFS=$'\t' read -r a until reason <<< "$line"
    echo "$a 冷卻至 $(fmt "$until")：${reason:-額度用完}"; exit 1 ;;
  set)
    [ $# -ge 3 ] || usage
    v=$3 mult=1
    case "$v" in
      @*) v=${v#@}; digits "$v" || usage; until=$((10#$v)) ;;
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9])
        until=$(local_epoch "$v") || usage ;;
      [0-9]:[0-9][0-9]|[0-9][0-9]:[0-9][0-9])
        until=$(local_epoch "$(date +%Y-%m-%d) $v") || usage
        [ "$until" -gt "$now" ] || until=$((until + 86400)) ;;   # 已過就算明天；DST 切換日會差一小時，冷卻用途可以接受
      *) case "$v" in
           *s) v=${v%s} ;;
           *m) v=${v%m}; mult=60 ;;
           *h) v=${v%h}; mult=3600 ;;
           *d) v=${v%d}; mult=86400 ;;
         esac
         digits "$v" || usage; until=$((now + 10#$v * mult)) ;;
    esac
    [ "$until" -gt "$now" ] || { echo "到期時間已過，不記錄" >&2; exit 2; }
    [ "$until" -le $((now + 30 * 86400)) ] || { echo "冷卻超過 30 天，不記錄（多半是時間換算錯）" >&2; exit 2; }
    reason=$(printf '%s' "${4:-}" | tr '\t\n' '  ')
    rewrite "$2" "$(printf '%s\t%s\t%s' "$2" "$until" "$reason")"
    echo "$2 冷卻至 $(fmt "$until")" ;;
  clear)
    [ $# -eq 2 ] || usage
    rewrite "$2" ;;
  list)
    live | while IFS=$'\t' read -r a until reason; do echo "$a 冷卻至 $(fmt "$until")：${reason:-額度用完}"; done ;;
  *) usage ;;
esac
