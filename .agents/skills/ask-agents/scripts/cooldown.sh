#!/usr/bin/env bash
# 外部 agent 額度冷卻紀錄：額度用完後記下「到什麼時候前不要再叫它」，之後的呼叫直接跳過、不再撞一次限制。
#   cooldown.sh check <agent>                     冷卻中 → 印「<agent> 冷卻至 <時間>：<原因>」、exit 1；可用 → exit 0、不印
#   cooldown.sh set <agent> <時長|@epoch> [原因]   時長 = 從現在起冷卻多久：純數字為秒，或 90s / 30m / 5h / 1d；@epoch = 冷卻到該時間（錯誤訊息有給 reset 時間時用）；最長 30 天
#   cooldown.sh clear <agent>                     解除（使用者說額度回來了）
#   cooldown.sh list                              列出仍在冷卻中的
# 狀態檔：$ASK_AGENTS_STATE（預設 ~/.agents/state/agent-cooldown），每行 <agent>\t<到期 epoch>\t<原因>；過期的行讀到時忽略、寫入時清掉。
# 寫入用 mkdir 當鎖（bash 3.2 沒有 flock），平行呼叫多家同時額度用完也不會互相蓋掉。
set -euo pipefail
state=${ASK_AGENTS_STATE:-$HOME/.agents/state/agent-cooldown}
now=$(date +%s)
fmt() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M'; }
live() { [ -f "$state" ] && awk -F'\t' -v n="$now" '$2 > n' "$state" || true; }
usage() { sed -n '3,7p' "$0" >&2; exit 2; }
rewrite() { # $1=要移除的 agent；$2=要加入的整行（可空）
  mkdir -p "$(dirname "$state")"
  lock="$state.lock"; local i=0 tmp
  until mkdir "$lock" 2>/dev/null; do
    i=$((i+1)); [ "$i" -ge 50 ] && { echo "拿不到鎖 ${lock}（殘留的話手動刪掉）" >&2; exit 3; }
    sleep 0.1
  done
  trap 'rmdir "${lock}" 2>/dev/null' EXIT
  tmp=$(mktemp "$state.XXXXXX")
  { live | awk -F'\t' -v a="$1" '$1 != a'; [ -n "${2:-}" ] && printf '%s\n' "$2"; } > "$tmp"
  mv "$tmp" "$state"
}
digits() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "${#1}" -le 12 ]; }

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
