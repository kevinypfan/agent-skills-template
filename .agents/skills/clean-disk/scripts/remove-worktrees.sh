#!/usr/bin/env bash
# 移除使用者確認過的 worktree。刪之前對每一個重新檢查一次（掃描後 agent 可能又寫了東西），red 一律拒絕。
#
# 用法：remove-worktrees.sh [--dry-run] [--no-fetch] [<path> | --allow-untracked <path> | --trust-merged <path> | --orphan <path> | --prune <repo>]...
#   <path>                    green，或「已 push 未 merge」且沒有額外檔案的 yellow（commit 還在遠端，branch 保留）
#   --allow-untracked <path>  使用者已看過並同意丟掉這個 worktree 的未追蹤檔與被 ignore 的非產物檔（.env 等）
#   --trust-merged <path>     已用 tracker 確認 PR merged：本地偵測不到合併也刪 local branch
#   --orphan <path>           scan 列出的孤兒目錄（不在任何 worktree list），rm -rf
#   --prune <repo>            先檢查 prunable 項目（detached 且有獨有 commit、locked 的會拒絕），再 git worktree prune
#   --dry-run                 只印會做什麼（任何位置皆可）
#   --no-fetch                不 fetch；此時一律不刪 local branch（無法確認 base 是最新的）
# 旗標只套用在緊接的那一個 path；同一個 path 可以疊加多個旗標（例如 --allow-untracked P --trust-merged P）。
# local branch 只在「HEAD 是最新 base 的祖先」或帶 --trust-merged 時刪除，且以檢查當下的 OID 做條件式刪除；
# rebase／squash（patch 等價）判定的 branch 一律保留。remote branch 不動。
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

dry=0 fetch=1
W_PATHS=() W_FLAGS=() O_PATHS=() P_REPOS=()
add_wt() { # $1=path $2=flag
  local i=0
  # bash 3.2 + set -u：空陣列不能用 "${!arr[@]}" 展開，改用計數迴圈
  while [ "$i" -lt "${#W_PATHS[@]}" ]; do
    [ "${W_PATHS[$i]}" = "$1" ] && { W_FLAGS[$i]="${W_FLAGS[$i]} $2"; return; }
    i=$((i+1))
  done
  W_PATHS[${#W_PATHS[@]}]=$1; W_FLAGS[${#W_FLAGS[@]}]=$2
}
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --no-fetch) fetch=0 ;;
    --allow-untracked|--trust-merged|--orphan|--prune)
      case "${2:-}" in ''|-*) echo "$1 需要接一個路徑（不可以 - 開頭）" >&2; exit 2 ;; esac
      has_ctrl "$2" && { echo "路徑含換行或 tab：拒絕" >&2; exit 2; }
      case "$1" in
        --allow-untracked) add_wt "$2" allow-untracked ;;
        --trust-merged) add_wt "$2" trust-merged ;;
        --orphan) O_PATHS[${#O_PATHS[@]}]=$2 ;;
        --prune) P_REPOS[${#P_REPOS[@]}]=$2 ;;
      esac
      shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    -*) echo "不認得的參數：$1" >&2; exit 2 ;;
    *) has_ctrl "$1" && { echo "路徑含換行或 tab：拒絕" >&2; exit 2; }; add_wt "$1" plain ;;
  esac
  shift
done
run() { if [ "$dry" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
active_cwds > "$tmp/cwds"
: > "$tmp/fetched"; : > "$tmp/fetch_failed"
freed=0 ok=0 refused=0
refuse() { echo "REFUSE ${1}：$2"; refused=$((refused+1)); }

# 每個 repo 只 fetch 一次；失敗（或 --no-fetch）就不刪該 repo 的 branch
base_fresh() { # $1=repo
  [ "$fetch" = 1 ] || return 1
  grep -qxF "$1" "$tmp/fetched" && return 0
  grep -qxF "$1" "$tmp/fetch_failed" && return 1
  if fetch_repo "$1"; then echo "$1" >> "$tmp/fetched"; return 0; fi
  echo "$1" >> "$tmp/fetch_failed"; return 1
}

do_prune() {
  local repo p br locked head row
  repo=$(realdir "$1"); [ -n "$repo" ] && [ -d "$repo/.git" ] || { refuse "$1" "不是 main repo"; return; }
  list_worktrees "$repo" > "$tmp/wt" || { refuse "$repo" "無法列出 worktree"; return; }
  : > "$tmp/prunelist"
  while IFS=$'\t' read -r p br locked head; do
    [ -d "$p" ] && [ -e "$p/.git" ] && continue
    [ "$br" = - ] && br=""; [ "$head" = - ] && head=""
    row=$(inspect_worktree "$repo" "$p" "$br" "$locked" "$tmp/cwds" 0 "$head")
    if [ "$(printf '%s' "$row" | cut -f1)" = red ]; then refuse "$repo" "prunable 的 ${p}：$(printf '%s' "$row" | cut -f14)；不 prune 整個 repo"; return; fi
    echo "      將 prune：${p}（branch ${br:-detached}）" >> "$tmp/prunelist"
  done < "$tmp/wt"
  cat "$tmp/prunelist"
  run git -C "$repo" worktree prune && echo "ok    prune $repo"
}

do_orphan() {
  local arg p repo r nested sz wl
  arg=$(strip_slash "$1")
  [ -L "$arg" ] && { refuse "$arg" "是 symlink，不跟著刪"; return; }
  p=$(realdir "$arg"); [ -n "$p" ] || { refuse "$arg" "不是可進入的目錄"; return; }
  [ -d "$p/.git" ] && { refuse "$p" "是獨立的 git repo，不是孤兒目錄"; return; }
  repo=$(orphan_owner "$p")
  [ -n "$repo" ] || { refuse "$p" "判斷不出屬於哪個 repo 的 worktree_root 或 .claude/worktrees，--orphan 不處理"; return; }
  # GIT_CEILING_DIRECTORIES：不讓 git 往上找到 main repo 而誤以為它是 worktree
  if GIT_CEILING_DIRECTORIES=$(dirname "$p") git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    refuse "$p" "git 仍認得它是 worktree，走一般流程"; return
  fi
  for r in "$repo" $(sed -n 's|^gitdir: \(.*\)/\.git/worktrees/.*|\1|p' "$p/.git" 2>/dev/null); do
    [ -d "$r/.git" ] || continue
    # 列不出來就無法確認它沒登記，一律拒絕
    wl=$(list_worktrees "$r") || { refuse "$p" "無法列出 $r 的 worktree，不能確認它是孤兒"; return; }
    if printf '%s\n' "$wl" | cut -f1 | while IFS= read -r wp; do [ -n "$wp" ] && [ "$(realdir "$wp")" = "$p" ] && echo hit; done | grep -q hit; then
      refuse "$p" "仍登記在 $r 的 worktree list（metadata 斷裂）：先 git -C $r worktree repair $p 再重掃，不要硬刪"; return
    fi
  done
  nested=$(find "$p" -mindepth 1 -name .git -print 2>/dev/null | grep -vxF "$p/.git" | head -1)
  [ -n "$nested" ] && { refuse "$p" "裡面有巢狀的 repo：${nested%/.git}"; return; }
  is_active "$p" "$tmp/cwds" && { refuse "$p" "有 process 的 cwd 在裡面"; return; }
  sz=$(size_kb "$p")
  run rm -rf -- "$p" && { echo "ok    ${p}（$(human "$sz")）"; freed=$((freed+sz)); ok=$((ok+1)); }
}

do_worktree() { # $1=flags（plain／allow-untracked／trust-merged 的組合）$2=path
  local flags=" $1 " arg p repo line br locked head row tier sz tracked untracked merged why extras base_name others del msg cleaned=0
  arg=$(strip_slash "$2")
  [ -e "$arg" ] || { echo "skip  ${arg}：不存在（殘留 metadata 用 --prune <repo>）"; return; }
  [ -L "$arg" ] && { refuse "$arg" "是 symlink，請傳實際路徑"; return; }
  p=$(realdir "$arg"); [ -n "$p" ] || { refuse "$arg" "不是可進入的目錄"; return; }
  if ! GIT_CEILING_DIRECTORIES=$(dirname "$p") git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
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
  [ "$dry" = 1 ] || base_fresh "$repo" || true
  row=$(inspect_worktree "$repo" "$p" "$br" "$locked" "$tmp/cwds" 1 "$head")
  tier=$(printf '%s' "$row" | cut -f1); sz=$(printf '%s' "$row" | cut -f5)
  tracked=$(printf '%s' "$row" | cut -f7); untracked=$(printf '%s' "$row" | cut -f8)
  merged=$(printf '%s' "$row" | cut -f10); extras=$(printf '%s' "$row" | cut -f12)
  head=$(printf '%s' "$row" | cut -f13); why=$(printf '%s' "$row" | cut -f14)
  [ "$tier" = red ] && { refuse "$p" "$why"; return; }
  # 欄位不是整數（unborn、讀取失敗…）就不處理
  case "$tracked$untracked$extras" in *[!0-9]*|'') refuse "$p" "狀態欄位無法判讀：$why"; return ;; esac
  if [ $((untracked + extras)) -gt 0 ]; then
    case "$flags" in *" allow-untracked "*) ;; *) refuse "$p" "${why}（使用者確認可丟後，對這個 path 加 --allow-untracked）"; return ;; esac
    # 只清掉未追蹤／ignored 檔（不加第二個 -f：git clean 不碰巢狀 repo），之後的 remove 不帶 --force，
    # 讓 git 對「檢查之後才出現的追蹤檔修改」做最後一道把關
    run git -C "$p" clean -f -d -x -q || { echo "FAIL  ${p}：git clean 失敗"; refused=$((refused+1)); return; }
    cleaned=1
  fi
  if ! run git -C "$repo" worktree remove "$p"; then
    if [ "$cleaned" = 1 ]; then echo "FAIL  ${p}：git worktree remove 失敗（檢查之後又有修改，或含 submodule）；未追蹤／ignored 檔已清除，worktree 本體與追蹤檔保留"
    else echo "FAIL  ${p}：git worktree remove 失敗（檢查之後又有修改，或含 submodule）；內容未刪"; fi
    refused=$((refused+1)); return
  fi
  msg="ok    ${p}（$(human "$sz")）"
  if [ -n "$br" ]; then
    del=0; why=""
    case "$merged" in
      ancestor) del=1 ;;
      cherry|squash) why="patch 等價判定，請自行確認後 git branch -D $br" ;;
      *) why="未偵測到併進 base" ;;
    esac
    case "$flags" in *" trust-merged "*) del=1; why="" ;; esac
    base_name=$(base_ref "$repo"); base_name=${base_name#origin/}
    [ "$br" = "$base_name" ] && { del=0; why="是 base 分支"; }
    case "$flags" in *" trust-merged "*) ;; *)
      if [ "$del" = 1 ]; then
        if [ "$fetch" = 0 ]; then del=0; why="--no-fetch，無法確認 base 是最新的"
        elif [ "$dry" = 0 ] && ! base_fresh "$repo"; then del=0; why="fetch 失敗或不完整，無法確認 base 是最新的"; fi
      fi ;;
    esac
    # update-ref 不像 branch -D 會擋「正在使用的 branch」，自己查（含 main worktree）；dry-run 時這個 worktree 還在，排除它
    if others=$(git -C "$repo" for-each-ref --format='%(worktreepath)' "refs/heads/$br" 2>/dev/null); then
      others=$(printf '%s\n' "$others" | while IFS= read -r wp; do [ -n "$wp" ] && [ "$(realdir "$wp")" != "$p" ] && echo x; done)
      [ -n "$others" ] && { del=0; why="還有其他 worktree checkout 這個 branch"; }
    else
      del=0; why="無法確認 branch 是否還有 worktree 在用"
    fi
    if [ "$del" = 1 ] && [ "$dry" = 1 ]; then
      case "$flags" in *" trust-merged "*) msg="${msg}，local branch $br 將刪" ;; *) msg="${msg}，local branch $br 將刪（實際執行時需 fetch 成功）" ;; esac
      del=2
    fi
    if [ "$del" = 2 ]; then :
    elif [ "$del" = 1 ]; then
      # 條件式刪除：branch 仍指向檢查當下的 OID 才刪，期間有新 commit 就保留
      if run git -C "$repo" update-ref -d "refs/heads/$br" "$head"; then msg="${msg}，local branch $br 已刪"
      else msg="${msg}，local branch $br 保留（檢查後有變動）"; fi
    else msg="${msg}，local branch $br 保留（${why}）"; fi
  fi
  echo "$msg"; freed=$((freed+sz)); ok=$((ok+1))
}

i=0; while [ "$i" -lt "${#W_PATHS[@]}" ]; do do_worktree "${W_FLAGS[$i]}" "${W_PATHS[$i]}"; i=$((i+1)); done
i=0; while [ "$i" -lt "${#O_PATHS[@]}" ]; do do_orphan "${O_PATHS[$i]}"; i=$((i+1)); done
i=0; while [ "$i" -lt "${#P_REPOS[@]}" ]; do do_prune "${P_REPOS[$i]}"; i=$((i+1)); done

echo "# 移除 $ok 個、拒絕 $refused 個，釋放約 $(human "$freed")"
