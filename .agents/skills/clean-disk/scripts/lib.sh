# clean-disk 共用函式（被 scan-*.sh / remove-*.sh source，不單獨執行）
# 相容 macOS 內建 bash 3.2：不用 associative array / mapfile。
# 原則：任何檢查失敗都往「保留」的方向判，絕不把「讀不到」當成「乾淨」。

# 呼叫端環境不可改變 git 看的 repo／index，也不可讓 cd 跳到 CDPATH 底下
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES CDPATH
export GIT_TERMINAL_PROMPT=0

# 可重建目錄白名單（scan-artifacts / remove-artifacts / worktree 內 ignored 檔判斷共用）
ARTIFACT_NAMES=" node_modules .venv venv .tox target dist build out .next .nuxt .svelte-kit .turbo .parcel-cache .angular .gradle .pytest_cache .mypy_cache .ruff_cache coverage .terraform DerivedData Pods __pycache__ .DS_Store "
# 套件管理器的目錄裡出現 .git 是正常的（git 依賴），不當成 nested repo
PKG_DIR_NAMES=" node_modules .venv venv .tox Pods "

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
size_kb() { du -sk "$1" 2>/dev/null | cut -f1; }
human() { # KB → 人看的大小
  awk -v k="${1:-0}" 'BEGIN{ if (k>=1048576) printf "%.1fG", k/1048576; else if (k>=1024) printf "%.0fM", k/1024; else printf "%dK", k }'
}
realdir() { [ -n "${1:-}" ] || return 0; (cd -- "$1" 2>/dev/null && pwd -P); }  # 目錄的實際路徑；失敗回空字串
expand_tilde() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#\~/}" ;; *) echo "$1" ;; esac; }
is_artifact_name() { case "$ARTIFACT_NAMES" in *" $1 "*) return 0 ;; esac; case "$1" in *.pyc) return 0 ;; esac; return 1; }
has_ctrl() { case "$1" in *$'\n'*|*$'\t'*) return 0 ;; esac; return 1; }  # 路徑含換行／tab 一律拒絕

# conventions 的「明確設定」：專案本專案值（（同預設）取預設欄）> 個人 ~/.agents/conventions.local.md
# 沒有明確設定回空字串，由呼叫端依 conventions「repo 沒有本檔時」的推斷規則處理——不拿 template 預設值頂替
_conv_col() { # $1=file $2=key $3=欄位序號（awk -F'|'）
  awk -F'|' -v k="\`$2\`" -v c="$3" '{ x=$2; gsub(/ /,"",x) } x==k { v=$c; gsub(/^ +| +$/,"",v); print v; exit }' "$1"
}
conv_explicit() { # $1=repo $2=key
  local v="" f="$1/.agents/conventions.md"
  if [ -f "$f" ]; then
    v=$(_conv_col "$f" "$2" 4)
    case "$v" in *同預設*) v=$(_conv_col "$f" "$2" 3) ;; esac
  fi
  [ -z "$v" ] && [ -f "$HOME/.agents/conventions.local.md" ] && v=$(_conv_col "$HOME/.agents/conventions.local.md" "$2" 3)
  printf '%s' "$v" | tr -d '`'
}

# repo 的 base ref：明確設定的 base_branch > origin/HEAD > origin/main > origin/master
base_ref() {
  local repo=$1 b
  b=$(conv_explicit "$repo" base_branch)
  if [ -n "$b" ] && git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then echo "origin/$b"; return; fi
  b=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$b" ]; then echo "$b"; return; fi
  for b in main master; do
    git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null && { echo "origin/$b"; return; }
  done
  echo ""
}

# 放 worktree 的目錄：明確設定的 worktree_root（相對路徑以 repo 為基準）；沒有就是 <repo 父目錄>/<repo 名>-worktrees
worktree_root() {
  local repo=$1 w
  w=$(conv_explicit "$repo" worktree_root)
  case "$w" in ''|*'<'*) echo "$(dirname "$repo")/$(basename "$repo")-worktrees"; return ;; esac
  w=$(expand_tilde "$w")
  case "$w" in /*) echo "$w" ;; *) echo "$repo/$w" ;; esac
}

# 孤兒目錄的所屬 repo（scan 與 remove 共用，兩邊判斷才會一致）；判斷不出來回空字串
orphan_owner() { # $1=目錄（實際路徑）
  local d=$1 parent g r sib
  parent=$(dirname "$d")
  case "$parent" in */.claude/worktrees) dirname "$(dirname "$parent")"; return ;; esac
  # .git 檔指向的 repo 還在：<repo>/.git/worktrees/<name>
  if [ -f "$d/.git" ]; then
    g=$(sed -n 's/^gitdir: //p' "$d/.git" | head -1)
    case "$g" in */.git/worktrees/*) r=${g%/.git/worktrees/*}; [ -d "$r/.git" ] && { echo "$r"; return; } ;; esac
  fi
  # 預設命名 <repo>-worktrees，或同層有 repo 把 worktree_root 設成這個目錄
  case "$parent" in *-worktrees) r=${parent%-worktrees}; [ -d "$r/.git" ] && [ "$(realdir "$(worktree_root "$r")")" = "$(realdir "$parent")" ] && { echo "$r"; return; } ;; esac
  for sib in "$(dirname "$parent")"/*; do
    [ -d "$sib/.git" ] || continue
    [ "$(realdir "$(worktree_root "$sib")")" = "$(realdir "$parent")" ] && { echo "$sib"; return; }
  done
  echo ""
}

# fetch 只更新 refs/remotes/origin/*（明確 refspec，不跟使用者設定的修剪範圍、不動 tag）；不可卡在 prompt
fetch_repo() { # $1=repo；成功回 0
  local ssh
  git -C "$1" remote get-url origin >/dev/null 2>&1 || return 1
  ssh=$(git -C "$1" config core.sshCommand 2>/dev/null || echo ssh)
  GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-$ssh -o BatchMode=yes -o ConnectTimeout=10}" \
    git -C "$1" fetch --quiet --no-tags --prune origin '+refs/heads/*:refs/remotes/origin/*' 2>/dev/null
}

# head 的內容是否已進 base：ancestor / cherry（rebase merge）/ squash / no / no-base
# cherry、squash 是 patch 等價判定（git 比對時會忽略 whitespace 與行號），只用來判斷 worktree 可刪，不用來刪 branch
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

# 目前所有 process 的 cwd（只看自己的 process），一行一個；偵測不到時只寫 __UNKNOWN__（之後一律當作使用中）
active_cwds() {
  local out=""
  if command -v lsof >/dev/null 2>&1; then
    out=$(lsof -a -d cwd -u "$(id -u)" -Fn 2>/dev/null | sed -n 's/^n//p' | sort -u)
  elif [ -d /proc/self ]; then
    out=$(for c in /proc/[0-9]*/cwd; do readlink "$c" 2>/dev/null; done | sort -u)
  fi
  # 執行本 script 的 shell 一定有 cwd，空清單代表偵測失敗（sandbox、權限），不代表沒人在用
  if [ -z "$out" ]; then
    echo "__UNKNOWN__"
    echo "警告：無法偵測哪些目錄還有 process 在用（沒有 lsof／proc，或輸出為空）；一律當作使用中" >&2
  else
    printf '%s\n' "$out"
  fi
}

is_active() { # $1=path（實際路徑）$2=active_cwds 檔；無法偵測時回 true（保守）
  grep -qx '__UNKNOWN__' "$2" && return 0
  P="$1" awk '$0==ENVIRON["P"] || index($0, ENVIRON["P"] "/")==1 { found=1; exit } END { exit !found }' "$2"
}

# $1 底下（不含 $1/.git 本身）的 .git：巢狀 repo／worktree，刪 $1 會連它們一起刪；印前幾個
nested_gits() {
  find "$1" -mindepth 2 \( -name node_modules -o -name .venv -o -name venv -o -name .tox -o -name Pods \) -prune \
    -o -name .git -print 2>/dev/null | head -3
}

# worktree 裡被 ignore、但不在可重建白名單的檔案（.env、*.local、*.log、筆記…）——git worktree remove 會不經確認刪掉它們
ignored_extras() { # $1=worktree；一行一個，失敗只印 __ERR__
  local out f b
  out=$(git --no-optional-locks -C "$1" status --porcelain=v1 --ignored=matching -unormal 2>/dev/null) || { echo __ERR__; return; }
  printf '%s\n' "$out" | sed -n 's/^!! //p' | while IFS= read -r f; do
    b=${f%/}; b=${b##*/}
    is_artifact_name "$b" || echo "$f"
  done
}

# 檢查一個 worktree，印一行 TSV（欄位見 TSV_HEADER）
# $1=repo(main worktree) $2=path $3=branch（detached 為空）$4=locked(0/1) $5=active_cwds 檔 $6=是否算大小(1/0)
# $7=worktree list 記錄的 HEAD sha（目錄已不存在時用來判斷 commit 會不會隨 prune 遺失）
TSV_HEADER='tier\trepo\tpath\tbranch\tsize_kb\tidle_days\ttracked\tuntracked\tunpushed\tmerged\tupstream\textras\thead\treasons'
inspect_worktree() {
  local repo=$1 p=$2 br=$3 locked=$4 cwds=$5 do_size=$6 wt_head=${7:-}
  local base head st tracked untracked unpushed merged upstream="-" sz=0 idle gd t ct extras n_extras=0 reasons="" tier n rp nested hidden f
  add() { reasons="${reasons:+$reasons; }$1"; }
  row() { # tier size idle tracked untracked unpushed merged upstream extras head
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$1" "$repo" "$p" "${br:-detached}" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "$reasons"
  }

  if [ ! -d "$p" ] || [ ! -e "$p/.git" ]; then
    tier=green; add "目錄（或其 .git）已不存在，只剩 metadata（git worktree prune）"
    [ "$locked" = 1 ] && { tier=red; add "worktree 被 lock"; }
    if [ -z "$br" ]; then
      n=$(git -C "$repo" rev-list --count "$wt_head" --not --branches --remotes 2>/dev/null) || n="?"
      if [ "$n" != 0 ]; then tier=red; add "detached HEAD 有 ${n} 個 commit 只被這個 worktree 指著，prune 後就找不回來"; fi
    fi
    add "路徑若在外接磁碟上，先確認已掛載"
    row "$tier" 0 - - - - - - - "${wt_head:--}"; return
  fi
  rp=$(realdir "$p")
  [ "$do_size" = 1 ] && sz=$(size_kb "$p")
  if ! gd=$(git -C "$p" rev-parse --absolute-git-dir 2>/dev/null); then
    add "worktree metadata 斷裂（.git 指向不存在的位置，常見於 repo 搬過目錄）：git 讀不到狀態，無法判斷有沒有未保存的改動；先 git worktree repair 再重掃，不要用 --orphan"
    row yellow "$sz" "$(( ( $(date +%s) - $(mtime "$p") ) / 86400 ))" - - - - - - -; return
  fi
  # 閒置時間要在跑 status 之前量；status 加 --no-optional-locks 才不會改寫 index
  t=$(mtime "$gd/index"); ct=$(git -C "$p" log -1 --format=%ct 2>/dev/null || echo 0)
  [ "$ct" -gt "$t" ] && t=$ct
  idle=$(( ( $(date +%s) - t ) / 86400 ))
  if ! head=$(git -C "$p" rev-parse -q --verify HEAD 2>/dev/null); then
    add "HEAD 沒有 commit（unborn branch）或已損毀：內容全是未保存的檔案"
    row red "$sz" "$idle" - - - - - - -; return
  fi
  base=$(base_ref "$repo")

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
  is_active "$rp" "$cwds" && { tier=red; add "有 process 的 cwd 在裡面（agent／shell 還開著）"; }
  [ "$tracked" != "?" ] && [ "$tracked" -gt 0 ] && { tier=red; add "${tracked} 個追蹤檔有未 commit 變更"; }
  # assume-unchanged（小寫）／skip-worktree（S）的檔案，修改不會出現在 status
  hidden=$(git -C "$p" ls-files -v 2>/dev/null | grep -E '^([a-z]|S) ' | head -3 | cut -c3- | tr '\n' ' ')
  [ -n "$hidden" ] && { tier=red; add "有 assume-unchanged／skip-worktree 的檔案，git status 看不到它們的修改：${hidden}"; }
  for f in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    [ -e "$gd/$f" ] && { tier=red; add "有進行中的 git 操作（${f}）"; break; }
  done
  nested=$(nested_gits "$p")
  [ -n "$nested" ] && { tier=red; add "裡面有巢狀的 repo／worktree，刪除會連它一起刪：$(printf '%s\n' "$nested" | sed "s|^$p/||; s|/\.git$||" | tr '\n' ' ')"; }
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
  extras=$(ignored_extras "$p")
  if [ "$extras" = __ERR__ ]; then n_extras="?"; tier=red; add "無法列出 ignored 檔"
  elif [ -n "$extras" ]; then
    n_extras=$(printf '%s\n' "$extras" | wc -l | tr -d ' ')
    [ "$tier" = green ] && tier=yellow
    add "${n_extras} 個被 ignore 的非產物檔，刪除時會一起消失：$(printf '%s\n' "$extras" | head -3 | tr '\n' ' ')"
  fi
  [ "$tier" = green ] && case "$merged" in
    ancestor) add "已併進 $base" ;;
    cherry) add "已以 rebase 併進 ${base}（patch 等價判定，只刪 worktree、保留 local branch）" ;;
    squash) add "已以 squash 併進 ${base}（patch 等價判定，只刪 worktree、保留 local branch）" ;;
  esac
  [ -z "$br" ] && add "detached HEAD"
  row "$tier" "$sz" "$idle" "$tracked" "$untracked" "$unpushed" "$merged" "$upstream" "$n_extras" "$head"
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

# 可重建產物目錄的安全檢查；$1 必須已是實際路徑（呼叫端只解析一次，檢查與刪除用同一個值）
# 可刪印空字串，否則印理由
artifact_refusal() { # $1=實際路徑 $2=active_cwds 檔
  local d=$1 name parent top v src pat last
  [ -n "$d" ] && [ -d "$d" ] && [ ! -L "$d" ] || { echo "不是一般目錄"; return; }
  name=$(basename "$d")
  is_artifact_name "$name" || { echo "名稱不在可重建目錄白名單"; return; }
  [ -e "$d/.git" ] && { echo "本身是 git repo／worktree，可能有未保存的工作"; return; }
  case "$PKG_DIR_NAMES" in *" $name "*) ;; *)
    [ -n "$(find "$d" -name .git -print 2>/dev/null | head -1)" ] && { echo "裡面有巢狀的 git repo／worktree，可能有未保存的工作"; return; } ;;
  esac
  parent=$(dirname "$d")
  top=$(git -C "$parent" rev-parse --show-toplevel 2>/dev/null) || { echo "不在 git repo 內，無法確認可重建"; return; }
  [ "$(realdir "$top")" = "$(realdir "$HOME")" ] && { echo "所屬 repo 是家目錄（dotfiles 類），ignore 規則不代表可重建"; return; }
  git -C "$parent" check-ignore -q -- "$d" 2>/dev/null || { echo "沒被 gitignore，可能是原始碼"; return; }
  v=$(git -C "$parent" check-ignore -v -- "$d" 2>/dev/null | cut -f1)
  src=$(printf '%s' "$v" | sed -E 's/^(.*):[0-9]+:.*$/\1/')
  pat=$(printf '%s' "$v" | sed -E 's/^.*:[0-9]+:(.*)$/\1/')
  case "$src" in /*|.git/*|*/.git/*|'') echo "命中的 ignore 規則來自個人設定（${src:-未知}），不代表專案可重建"; return ;; esac
  [ "$(basename "$src")" = .gitignore ] || { echo "命中的 ignore 規則不是來自 repo 的 .gitignore（${src}）"; return; }
  case "$pat" in '!'*) echo "命中的是否定規則（${pat}），這個目錄被刻意取消 ignore"; return ;; esac
  last=${pat%/}; last=${last##*/}
  [ "$last" = "$name" ] || { echo "命中的 ignore 規則（${pat}）沒有指名這個目錄，可能是上層目錄或萬用規則"; return; }
  [ -n "$(git -C "$parent" ls-files -- "$d" | head -1)" ] && { echo "裡面有被追蹤的檔案（git add -f）"; return; }
  is_active "$d" "$2" && { echo "有 process 的 cwd 在裡面"; return; }
  echo ""
}
