#!/usr/bin/env bash
# 移除使用者確認過的 worktree。刪之前對每一個重新檢查一次（掃描後 agent 可能又寫了東西），red 一律拒絕。
# 內容已併進 base（或該 path 帶 --trust-merged）時一併刪 local branch；remote branch 不動。
#
# 用法：remove-worktrees.sh [--dry-run] [<path> | --allow-untracked <path> | --trust-merged <path> | --orphan <path>]...
#   <path>                    green，或「已 push 未 merge」且沒有額外檔案的 yellow（commit 還在遠端，branch 保留）
#   --allow-untracked <path>  使用者已看過並同意丟掉這個 worktree 的未追蹤檔與被 ignore 的非產物檔（.env 等）
#   --trust-merged <path>     已用 tracker 確認 PR merged：本地偵測不到合併也刪 local branch
#   --orphan <path>           scan 列出的孤兒目錄（worktree_root 或 .claude/worktrees 底下、不在任何 worktree list），rm -rf
#   --prune <repo>            先檢查 prunable 項目（detached 且有獨有 commit 的會拒絕），再 git worktree prune
#   --dry-run                 只印會做什麼（任何位置皆可）
# 旗標只套用在緊接的那一個 path，避免一個授權蓋到整批。
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

dry=0 jobs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --allow-untracked|--trust-merged|--orphan|--prune)
      [ $# -ge 2 ] || { echo "$1 需要接一個路徑" >&2; exit 2; }
      jobs="$jobs
${1#--}	$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    -*) echo "不認得的參數：$1" >&2; exit 2 ;;
    *) jobs="$jobs
plain	$1" ;;
  esac
  shift
done
run() { if [ "$dry" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
active_cwds > "$tmp/cwds"
freed=0 ok=0 refused=0
refuse() { echo "REFUSE ${1}：$2"; refused=$((refused+1)); }

# 孤兒目錄所屬 repo：<repo>-worktrees/<x> → <repo>；<repo>/.claude/worktrees/<x> → <repo>
orphan_repo() {
  local parent; parent=$(dirname "$1")
  case "$parent" in
    */.claude/worktrees) dirname "$(dirname "$parent")" ;;
    *-worktrees) echo "${parent%-worktrees}" ;;
    *) echo "" ;;
  esac
}

do_prune() {
  local repo p br locked head row tier
  repo=$(realdir "$1"); [ -n "$repo" ] && [ -d "$repo/.git" ] || { refuse "$1" "不是 main repo"; return; }
  list_worktrees "$repo" > "$tmp/wt"
  while IFS=$'\t' read -r p br locked head; do
    [ -d "$p" ] && continue
    [ "$br" = - ] && br=""; [ "$head" = - ] && head=""
    row=$(inspect_worktree "$repo" "$p" "$br" "$locked" "$tmp/cwds" 0 "$head"); tier=$(printf '%s' "$row" | cut -f1)
    if [ "$tier" = red ]; then refuse "$repo" "prunable 的 ${p}：$(printf '%s' "$row" | cut -f12)；不 prune 整個 repo"; return; fi
    echo "      將 prune：${p}（branch ${br:-detached}）"
  done < "$tmp/wt"
  run git -C "$repo" worktree prune && echo "ok    prune $repo"
}

do_orphan() {
  local arg=${1%/} p repo
  [ -L "$arg" ] && { refuse "$arg" "是 symlink，不跟著刪"; return; }
  p=$(realdir "$arg"); [ -n "$p" ] || { refuse "$arg" "不是可進入的目錄"; return; }
  [ -d "$p/.git" ] && { refuse "$p" "是獨立的 git repo，不是孤兒目錄"; return; }
  repo=$(orphan_repo "$p")
  [ -n "$repo" ] && [ -d "$repo/.git" ] || { refuse "$p" "不在任何 repo 的 worktree_root 或 .claude/worktrees 底下，--orphan 不處理"; return; }
  if git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then refuse "$p" "git 仍認得它是 worktree，走一般流程"; return; fi
  if git -C "$repo" worktree list --porcelain | grep -qxF "worktree $p"; then
    refuse "$p" "仍登記在 $repo 的 worktree list（metadata 斷裂）：先 git -C $repo worktree repair $p 再重掃，不要硬刪"; return
  fi
  is_active "$p" "$tmp/cwds" && { refuse "$p" "有 process 的 cwd 在裡面"; return; }
  local sz; sz=$(size_kb "$p")
  run rm -rf "$p" && { echo "ok    ${p}（$(human "$sz")）"; freed=$((freed+sz)); ok=$((ok+1)); }
}

do_worktree() { # $1=mode(plain|allow-untracked|trust-merged) $2=path
  local mode=$1 arg=${2%/} p repo line br locked head row tier sz untracked merged why extras del msg
  [ -e "$arg" ] || { echo "skip  ${arg}：不存在（殘留 metadata 用 --prune <repo>）"; return; }
  p=$(realdir "$arg"); [ -n "$p" ] || { refuse "$arg" "不是可進入的目錄"; return; }
  if ! git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -f "$p/.git" ]; then refuse "$p" "git 讀不到這個 worktree（metadata 斷裂）：先對所屬 repo 跑 git worktree repair 再重掃，不要改用 --orphan"
    else refuse "$p" "不是 git worktree（scan 列為孤兒目錄的才用 --orphan）"; fi
    return
  fi
  repo=$(git -C "$p" worktree list --porcelain | sed -n '1s/^worktree //p')
  [ "$p" = "$(realdir "$repo")" ] && { refuse "$p" "是 main worktree"; return; }
  line=$(list_worktrees "$repo" | while IFS=$'\t' read -r wp wb wl wh; do [ "$(realdir "$wp")" = "$p" ] && { printf '%s\t%s\t%s\n' "$wb" "$wl" "$wh"; break; }; done)
  [ -n "$line" ] || { refuse "$p" "在 $repo 的 worktree list 裡找不到"; return; }
  br=$(printf '%s' "$line" | cut -f1); locked=$(printf '%s' "$line" | cut -f2); head=$(printf '%s' "$line" | cut -f3)
  [ "$br" = - ] && br=""
  row=$(inspect_worktree "$repo" "$p" "$br" "$locked" "$tmp/cwds" 1 "$head")
  tier=$(printf '%s' "$row" | cut -f1); sz=$(printf '%s' "$row" | cut -f5)
  untracked=$(printf '%s' "$row" | cut -f8); merged=$(printf '%s' "$row" | cut -f10); why=$(printf '%s' "$row" | cut -f12)
  [ "$tier" = red ] && { refuse "$p" "$why"; return; }
  extras=0; case "$why" in *"被 ignore 的非產物檔"*) extras=1 ;; esac
  if { [ "$untracked" -gt 0 ] || [ "$extras" = 1 ]; } && [ "$mode" != allow-untracked ]; then
    refuse "$p" "${why}（使用者確認可丟後，對這個 path 用 --allow-untracked）"; return
  fi
  if [ "$untracked" -gt 0 ] || [ "$extras" = 1 ]; then run git -C "$repo" worktree remove --force "$p"; else run git -C "$repo" worktree remove "$p"; fi \
    || { echo "FAIL  ${p}：git worktree remove 失敗（含 submodule 時需人工處理）"; refused=$((refused+1)); return; }
  msg="ok    ${p}（$(human "$sz")）"
  if [ -n "$br" ]; then
    case "$merged" in ancestor|cherry|squash) del=1 ;; *) del=0 ;; esac
    [ "$mode" = trust-merged ] && del=1
    if [ "$del" = 1 ] && ! git -C "$repo" worktree list --porcelain | grep -qxF "branch refs/heads/$br"; then
      run git -C "$repo" branch -D "$br" >/dev/null && msg="${msg}，local branch $br 已刪"
    else msg="${msg}，local branch $br 保留"; fi
  fi
  echo "$msg"; freed=$((freed+sz)); ok=$((ok+1))
}

while IFS=$'\t' read -r mode path; do
  [ -z "$mode" ] && continue
  case "$mode" in
    prune) do_prune "$path" ;;
    orphan) do_orphan "$path" ;;
    *) do_worktree "$mode" "$path" ;;
  esac
done <<EOF
$jobs
EOF

echo "# 移除 $ok 個、拒絕 $refused 個，釋放約 $(human "$freed")"
