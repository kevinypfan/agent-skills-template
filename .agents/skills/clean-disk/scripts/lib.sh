# clean-disk 共用函式（被 scan-*.sh / remove-*.sh source，不單獨執行）
# 相容 macOS 內建 bash 3.2：不用 associative array / mapfile。
# 原則：任何 git 指令失敗都往「保留」的方向判，絕不把「讀不到」當成「乾淨」。

# 可重建目錄白名單（scan-artifacts / remove-artifacts / worktree 內 ignored 檔判斷共用）
ARTIFACT_NAMES=" node_modules .venv venv .tox target dist build out .next .nuxt .svelte-kit .turbo .parcel-cache .angular .gradle .pytest_cache .mypy_cache .ruff_cache coverage .terraform DerivedData Pods __pycache__ .DS_Store "

# fetch 不可卡在帳密或 SSH passphrase prompt
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
size_kb() { du -sk "$1" 2>/dev/null | cut -f1; }
human() { # KB → 人看的大小
  awk -v k="${1:-0}" 'BEGIN{ if (k>=1048576) printf "%.1fG", k/1048576; else if (k>=1024) printf "%.0fM", k/1024; else printf "%dK", k }'
}
realdir() { (cd "$1" 2>/dev/null && pwd -P); }  # 目錄的實際路徑；失敗回空字串
expand_tilde() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#\~/}" ;; *) echo "$1" ;; esac; }
is_artifact_name() { case "$ARTIFACT_NAMES" in *" $1 "*) return 0 ;; esac; case "$1" in *.pyc|*.log) return 0 ;; esac; return 1; }

# conventions 取值，依「設定來源與優先序」：專案本專案值 > 個人 ~/.agents/conventions.local.md > 預設欄
# （專案檔沒有該列時，預設取 ~/.agents/conventions.md）
_conv_col() { # $1=file $2=key $3=欄位序號（awk -F'|'）
  awk -F'|' -v k="\`$2\`" -v c="$3" '{ x=$2; gsub(/ /,"",x) } x==k { v=$c; gsub(/^ +| +$/,"",v); print v; exit }' "$1"
}
conv_get() { # $1=repo $2=key
  local repo=$1 key=$2 v="" f
  f="$repo/.agents/conventions.md"
  if [ -f "$f" ]; then
    v=$(_conv_col "$f" "$key" 4)
    case "$v" in *同預設*) v=$(_conv_col "$f" "$key" 3) ;; esac
  fi
  [ -z "$v" ] && [ -f "$HOME/.agents/conventions.local.md" ] && v=$(_conv_col "$HOME/.agents/conventions.local.md" "$key" 3)
  if [ -z "$v" ]; then
    for f in "$repo/.agents/conventions.md" "$HOME/.agents/conventions.md"; do
      [ -f "$f" ] && v=$(_conv_col "$f" "$key" 3)
      [ -n "$v" ] && break
    done
  fi
  printf '%s' "$v" | tr -d '`'
}

# repo 的 base ref：conventions 的 base_branch > origin/HEAD > origin/main > origin/master
base_ref() {
  local repo=$1 b
  b=$(conv_get "$repo" base_branch)
  if [ -n "$b" ] && git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then echo "origin/$b"; return; fi
  b=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$b" ]; then echo "$b"; return; fi
  for b in main master; do
    git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null && { echo "origin/$b"; return; }
  done
  echo ""
}

# 放 worktree 的目錄：conventions 的 worktree_root；預設（含 <…> 佔位）＝ <repo 父目錄>/<repo 名>-worktrees
worktree_root() {
  local repo=$1 w
  w=$(conv_get "$repo" worktree_root)
  case "$w" in ''|*'<'*|*同預設*) w="$(dirname "$repo")/$(basename "$repo")-worktrees" ;; esac
  expand_tilde "$w"
}

# head 的內容是否已進 base：ancestor / cherry（rebase merge）/ squash / no / no-base
merged_state() {
  local repo=$1 head=$2 base=$3 mb tree tmp out
  [ -z "$base" ] && { echo no-base; return; }
  # 含「開了 worktree 但一個 commit 都沒做」的情況
  git -C "$repo" merge-base --is-ancestor "$head" "$base" 2>/dev/null && { echo ancestor; return; }
  # git cherry 不比對 merge commit；分支上有 merge commit（可能夾帶解衝突時的新改動）就不走 patch 等價判斷
  [ "$(git -C "$repo" rev-list --count --merges "$base..$head" 2>/dev/null || echo x)" = 0 ] || { echo no; return; }
  out=$(git -C "$repo" cherry "$base" "$head" 2>/dev/null) || { echo no; return; }
  if ! printf '%s\n' "$out" | grep -q '^+'; then echo cherry; return; fi
  # squash merge：把整條分支壓成一個暫時 commit（只寫入 object，不動任何 ref），看 base 上有沒有等價 patch
  mb=$(git -C "$repo" merge-base "$base" "$head" 2>/dev/null) || { echo no; return; }
  tree=$(git -C "$repo" rev-parse "$head^{tree}" 2>/dev/null) || { echo no; return; }
  tmp=$(GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=x GIT_COMMITTER_NAME=x GIT_COMMITTER_EMAIL=x \
        git -C "$repo" commit-tree "$tree" -p "$mb" -m clean-disk-squash-check 2>/dev/null) || { echo no; return; }
  out=$(git -C "$repo" cherry "$base" "$tmp" 2>/dev/null) || { echo no; return; }
  if ! printf '%s\n' "$out" | grep -q '^+'; then echo squash; else echo no; fi
}

# 目前所有 process 的 cwd（只看自己的 process），一行一個；兩種方法都沒有時只寫 __UNKNOWN__
active_cwds() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -a -d cwd -u "$(id -u)" -Fn 2>/dev/null | sed -n 's/^n//p' | sort -u
  elif [ -d /proc/self ]; then
    for c in /proc/[0-9]*/cwd; do readlink "$c" 2>/dev/null; done | sort -u
  else
    echo "__UNKNOWN__"
    echo "警告：沒有 lsof 也沒有 /proc，無法偵測哪些目錄還有 process 在用；一律當作可能在用（red）" >&2
  fi
}

is_active() { # $1=path $2=active_cwds 檔；無法偵測時回 true（保守）
  grep -qx '__UNKNOWN__' "$2" && return 0
  awk -v p="$1" '$0==p || index($0, p"/")==1 { found=1; exit } END { exit !found }' "$2"
}

# worktree 裡被 ignore、但不在可重建白名單的檔案（.env、*.local、筆記…）——git worktree remove 會不經確認刪掉它們
ignored_extras() { # $1=worktree；一行一個，失敗只印 __ERR__
  local out f b
  out=$(git --no-optional-locks -C "$1" status --porcelain=v1 --ignored=matching -unormal 2>/dev/null) || { echo __ERR__; return; }
  printf '%s\n' "$out" | sed -n 's/^!! //p' | while read -r f; do
    b=${f%/}; b=${b##*/}
    is_artifact_name "$b" || echo "$f"
  done
}

# 檢查一個 worktree，印一行 TSV：
# tier repo path branch size_kb idle_days tracked untracked unpushed merged upstream reasons
# $1=repo(main worktree) $2=path $3=branch（detached 為空）$4=locked(0/1) $5=active_cwds 檔 $6=是否算大小(1/0)
# $7=worktree list 記錄的 HEAD sha（目錄已不存在時用來判斷 commit 會不會隨 prune 遺失）
inspect_worktree() {
  local repo=$1 p=$2 br=$3 locked=$4 cwds=$5 do_size=$6 wt_head=${7:-}
  local base head st tracked untracked unpushed merged upstream="-" sz=0 idle gd t ct extras reasons="" tier n
  add() { reasons="${reasons:+$reasons; }$1"; }

  if [ ! -d "$p" ]; then
    tier=green; add "目錄已不存在，只剩 metadata（git worktree prune）"
    if [ -z "$br" ]; then
      n=$(git -C "$repo" rev-list --count "$wt_head" --not --branches --remotes 2>/dev/null) || n="?"
      if [ "$n" != 0 ]; then tier=red; add "detached HEAD 有 ${n} 個 commit 只被這個 worktree 指著，prune 後就找不回來"; fi
    fi
    add "路徑若在外接磁碟上，先確認已掛載"
    printf '%s\t%s\t%s\t%s\t0\t-\t0\t0\t0\t-\t-\t%s\n' "$tier" "$repo" "$p" "${br:-detached}" "$reasons"
    return
  fi
  [ "$do_size" = 1 ] && sz=$(size_kb "$p")
  if ! head=$(git -C "$p" rev-parse -q --verify HEAD 2>/dev/null); then
    printf 'yellow\t%s\t%s\t%s\t%s\t%s\t-\t-\t-\t-\t-\t%s\n' "$repo" "$p" "${br:-detached}" "$sz" \
      "$(( ( $(date +%s) - $(mtime "$p") ) / 86400 ))" \
      "worktree metadata 斷裂（.git 指向不存在的位置，常見於 repo 搬過目錄）：git 讀不到狀態，無法判斷有沒有未保存的改動；先 git worktree repair 再重掃，不要用 --orphan"
    return
  fi
  base=$(base_ref "$repo")
  # 閒置時間要在跑 status 之前量；status 加 --no-optional-locks 才不會改寫 index
  gd=$(git -C "$p" rev-parse --absolute-git-dir 2>/dev/null)
  t=$(mtime "$gd/index"); ct=$(git -C "$p" log -1 --format=%ct 2>/dev/null || echo 0)
  [ "$ct" -gt "$t" ] && t=$ct
  idle=$(( ( $(date +%s) - t ) / 86400 ))

  tier=green
  if st=$(git --no-optional-locks -C "$p" status --porcelain=v1 -unormal 2>/dev/null); then
    tracked=$(printf '%s' "$st" | grep -c '^[^?]')
    untracked=$(printf '%s' "$st" | grep -c '^??')
  else
    tracked="?"; untracked="?"; tier=red; add "git status 失敗（index 損毀？），無法確認有沒有未 commit 變更"
  fi
  unpushed=$(git -C "$repo" rev-list --count "$head" --not --remotes 2>/dev/null) || unpushed="?"
  merged=$(merged_state "$repo" "$head" "$base")
  if [ -n "$br" ]; then
    upstream=$(git -C "$repo" for-each-ref --format='%(upstream:short)%(upstream:track)' "refs/heads/$br")
    [ -z "$upstream" ] && upstream="none"
  fi

  [ "$locked" = 1 ] && { tier=red; add "worktree 被 lock"; }
  is_active "$p" "$cwds" && { tier=red; add "有 process 的 cwd 在裡面（agent／shell 還開著）"; }
  [ "$tracked" != "?" ] && [ "$tracked" -gt 0 ] && { tier=red; add "${tracked} 個追蹤檔有未 commit 變更"; }
  [ "$unpushed" = "?" ] && { tier=red; add "無法計算沒 push 的 commit"; }
  if [ "$merged" = no ] || [ "$merged" = no-base ]; then
    if [ "$unpushed" != "?" ] && [ "$unpushed" -gt 0 ]; then tier=red; add "${unpushed} 個 commit 沒 push 也沒進 base"
    elif [ "$unpushed" = 0 ]; then
      [ "$tier" = green ] && tier=yellow
      case "$upstream" in *gone*) add "已 push、遠端分支已刪，但 base 上找不到等價改動（查 PR 狀態）" ;;
        *) add "已 push 但未進 base（查 PR 狀態）" ;; esac
    fi
    [ "$merged" = no-base ] && add "找不到 base ref"
  fi
  if [ "$untracked" != "?" ] && [ "$untracked" -gt 0 ]; then
    [ "$tier" = green ] && tier=yellow; add "${untracked} 個未追蹤檔（非 ignored）"
  fi
  if [ "$tier" != red ]; then
    extras=$(ignored_extras "$p")
    if [ "$extras" = __ERR__ ]; then tier=red; add "無法列出 ignored 檔"
    elif [ -n "$extras" ]; then
      [ "$tier" = green ] && tier=yellow
      n=$(printf '%s\n' "$extras" | wc -l | tr -d ' ')
      add "${n} 個被 ignore 的非產物檔，刪除時會一起消失：$(printf '%s\n' "$extras" | head -3 | tr '\n' ' ')"
    fi
  fi
  [ "$tier" = green ] && case "$merged" in
    ancestor) add "已併進 $base" ;; cherry) add "已以 rebase 併進 $base" ;; squash) add "已以 squash 併進 $base" ;;
  esac
  [ -z "$br" ] && add "detached HEAD"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$tier" "$repo" "$p" "${br:-detached}" "$sz" "$idle" "$tracked" "$untracked" "$unpushed" "$merged" "$upstream" "$reasons"
}

# worktree list --porcelain → 一行一個 linked worktree：path<TAB>branch<TAB>locked<TAB>head
# 空欄一律用 - 佔位：IFS=$'\t' 會把連續 tab 合併，空欄會讓後面的欄位錯位
list_worktrees() {
  git -C "$1" worktree list --porcelain | awk '
    function out() { if (p != "" && n > 1) print p "\t" (b == "" ? "-" : b) "\t" l "\t" (h == "" ? "-" : h) }
    /^worktree /{ out(); p=substr($0,10); b=""; l=0; h=""; n++ }
    /^HEAD /{ h=substr($0,6) }
    /^branch /{ b=substr($0,8); sub(/^refs\/heads\//,"",b) }
    /^locked/{ l=1 }
    END{ out() }'
}

# 可重建產物目錄的安全檢查；可刪印空字串，否則印理由
artifact_refusal() { # $1=原始路徑 $2=active_cwds 檔
  local arg=${1%/} d parent top pat
  [ -L "$arg" ] && { echo "是 symlink"; return; }
  d=$(realdir "$arg")
  [ -n "$d" ] || { echo "不是可進入的目錄"; return; }
  is_artifact_name "$(basename "$d")" || { echo "名稱不在可重建目錄白名單"; return; }
  [ -e "$d/.git" ] && { echo "裡面是另一個 git repo／worktree，可能有未保存的工作"; return; }
  parent=$(dirname "$d")
  top=$(git -C "$parent" rev-parse --show-toplevel 2>/dev/null) || { echo "不在 git repo 內，無法確認可重建"; return; }
  [ "$(realdir "$top")" = "$(realdir "$HOME")" ] && { echo "所屬 repo 是家目錄（dotfiles 類），ignore 規則不代表可重建"; return; }
  pat=$(git -C "$parent" check-ignore -v -- "$d" 2>/dev/null | cut -f1 | sed 's/^.*:[0-9][0-9]*://')
  [ -n "$pat" ] || { echo "沒被 gitignore，可能是原始碼"; return; }
  case "$pat" in *"$(basename "$d")"*) ;; *) echo "命中的 ignore 規則（${pat}）沒有指名這個目錄，可能是 * 之類的全域規則"; return ;; esac
  [ -n "$(git -C "$parent" ls-files -- "$d" | head -1)" ] && { echo "裡面有被追蹤的檔案（git add -f）"; return; }
  is_active "$d" "$2" && { echo "有 process 的 cwd 在裡面"; return; }
  echo ""
}
