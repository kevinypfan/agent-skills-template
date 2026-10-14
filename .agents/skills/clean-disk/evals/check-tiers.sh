#!/usr/bin/env bash
# script 層的自動斷言：建 fixture → 跑 scan／remove（含實際刪除）→ 逐項比對預期。改 scripts/ 後必跑。
# 用法：bash .agents/skills/clean-disk/evals/check-tiers.sh   （全過 exit 0）
# 一律用 macOS 內建的 bash 3.2（有的話）跑 script，HOME 指到暫存目錄，不受執行者的 conventions 影響。
set -u
here=$(cd "$(dirname "$0")" && pwd); S="$here/../scripts"
B=/bin/bash; [ -x "$B" ] || B=bash
fail=0
check() { if [ "$2" = "$3" ]; then echo "✓ $1"; else echo "✗ $1：預期 $2，實際 $3"; fail=1; fi; }
first() { awk '{print $1; exit}'; }

# bash 3.2 會把緊接在變數名後的非 ASCII 字元（全形標點）當成變數名的一部分 → set -u 下 unbound variable
hits=$(perl -CSD -ne 'print "$ARGV:$.\n" if /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]/; close ARGV if eof' "$S"/*.sh "$here"/*.sh)
check "script 內沒有 \$var 緊接全形字元（要寫 \${var}）" "" "$hits"

sleeper=""
R=$(mktemp -d); R=$(cd "$R" && pwd -P); trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$R"' EXIT
export HOME="$R/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$HOME/.config"
bash "$here/make-fixture.sh" "$R/fx" >/dev/null 2>&1 || { echo "✗ make-fixture 失敗"; exit 1; }
F="$R/fx"; W="$F/app-worktrees"
(cd "$W/issue-10-active" && exec sleep 600) & sleeper=$!
sleep 1

# ---- 分級 ----
scan=$($B "$S/scan-worktrees.sh" --no-fetch "$F")
tier_of() { printf '%s\n' "$scan" | awk -F'\t' -v n="/$1" 'length($3) >= length(n) && substr($3, length($3) - length(n) + 1) == n { print $1; exit }'; }
for pair in issue-1-merged:green issue-2-squashed:green issue-3-dirty:red issue-4-unpushed:red issue-5-open:yellow \
            issue-6-notes:yellow issue-7-empty:green issue-8-orphan:yellow issue-9-gone:green issue-10-active:red \
            issue-11-broken:yellow issue-12-env:yellow issue-13-detached-locked:red issue-14-gone-detached:red \
            issue-15-merge-extra:red app/dist:yellow issue-17-nested-outer:red issue-18-cherry:green issue-19-assume:red \
            issue-20-unborn:red issue-21-merging:red orph-nogit:yellow issue-23-pr-env:yellow issue-24-log:yellow \
            issue-25-venv:red; do
  check "分級 ${pair%%:*}" "${pair#*:}" "$(tier_of "${pair%%:*}")"
done
check "symlink 不列為孤兒" "" "$(tier_of issue-16-symlink)"
check "worktree list 失敗的 repo 出現在摘要" yes "$(printf '%s\n' "$scan" | grep -q '^# 無法列出 worktree.*brk' && echo yes || echo no)"
check "worktree list 失敗時不把它的 worktree 列成孤兒" "" "$(tier_of brk-worktrees/w)"
check "繼承的 GIT_INDEX_FILE 不影響分級" red "$(GIT_INDEX_FILE="$R/none" $B "$S/scan-worktrees.sh" --no-fetch --no-size "$F" | awk -F'\t' '$3 ~ /issue-3-dirty$/ { print $1; exit }')"
check "detached 的 branch 欄" "detached" "$(printf '%s\n' "$scan" | awk -F'\t' '$3 ~ /issue-13-detached-locked$/ { print $4 }')"

# ---- 產物掃描 ----
art=$($B "$S/scan-artifacts.sh" --min-mb 0 "$F" | cut -f5)
has() { printf '%s\n' "$art" | grep -qx "$1" && echo yes || echo no; }
check "產物：worktree 裡的 node_modules 列出" yes "$(has "$W/issue-5-open/node_modules")"
check "產物：nested worktree 的 dist 不列" no "$(has "$F/app/dist")"
check "產物：有追蹤檔的 build 不列" no "$(has "$F/app/build")"
check "產物：.gitignore 寫 * 的 repo 不列" no "$(has "$F/dotfiles/proj/build")"
check "產物：被 !keep/build/ 取消 ignore 的不列" no "$(has "$F/app/keep/build")"
check "產物：底下有巢狀 repo 的 coverage 不列" no "$(has "$F/app/coverage")"
check "產物：只有上層規則命中的 out 不列" no "$(has "$F/tools/build-tools/out")"
check "產物：info/exclude 命中的 out 不列" no "$(has "$F/excl/out")"
check "產物：裡面有 editable 套件 repo 的 .venv 不列" no "$(has "$F/app/.venv")"

# ---- remove-artifacts ----
out=$($B "$S/remove-artifacts.sh" "$W/issue-5-open/node_modules" --dry-run)
check "remove-artifacts：--dry-run 放最後也生效" "(dry-run)" "$(printf '%s\n' "$out" | first)"
check "remove-artifacts：dry-run 後目錄還在" yes "$([ -d "$W/issue-5-open/node_modules" ] && echo yes || echo no)"
mkdir -p "$HOME/proj/node_modules"; (cd "$HOME" && git init -q . && printf 'node_modules/\n' > .gitignore)
check "remove-artifacts：家目錄 repo 拒絕" REFUSE "$($B "$S/remove-artifacts.sh" --dry-run "$HOME/proj/node_modules" | first)"
check "remove-artifacts：路徑含換行拒絕" REFUSE "$($B "$S/remove-artifacts.sh" --dry-run "$W/issue-5-open/node_modules
$F/app/keep/build" | first)"

check "remove-artifacts：開頭有空白的路徑不會指到別的目錄" yes "$($B "$S/remove-artifacts.sh" " $W/issue-5-open/node_modules" >/dev/null; [ -d "$W/issue-5-open/node_modules" ] && echo yes || echo no)"
$B "$S/remove-artifacts.sh" "$W/issue-7-empty/node_modules" >/dev/null
check "remove-artifacts：實際刪除" yes "$([ -e "$W/issue-7-empty/node_modules" ] && echo no || echo yes)"

# ---- remove-worktrees：拒絕 ----
rw() { $B "$S/remove-worktrees.sh" --dry-run --no-fetch "$@" 2>/dev/null; }
check "remove：metadata 斷裂不可 --orphan" REFUSE "$(rw --orphan "$W/issue-11-broken" | first)"
mkdir -p "$F/stray/x"
check "remove：不屬於任何 repo 的目錄不可 --orphan" REFUSE "$(rw --orphan "$F/stray/x" | first)"
check "remove：symlink 不可 --orphan" REFUSE "$(rw --orphan "$W/issue-16-symlink" | first)"
check "remove：有 .env 的要 --allow-untracked" REFUSE "$(rw "$W/issue-12-env" | first)"
out=$(rw --allow-untracked "$W/issue-12-env" "$W/issue-6-notes")
check "remove：--allow-untracked 套用在指定 path" yes "$(printf '%s\n' "$out" | grep -q '^ok.*issue-12-env' && echo yes || echo no)"
check "remove：--allow-untracked 不蓋到別的 path" REFUSE "$(printf '%s\n' "$out" | grep 'issue-6-notes' | first)"
check "remove：red 一律拒絕" REFUSE "$(rw --allow-untracked "$W/issue-3-dirty" | first)"
check "remove：巢狀 worktree 的外層拒絕" REFUSE "$(rw "$W/issue-17-nested-outer" | first)"
check "remove：unborn 拒絕" REFUSE "$(rw --allow-untracked "$W/issue-20-unborn" | first)"
check "remove：detached 有獨有 commit 時拒絕 prune" 0 "$(rw --prune "$F/app" | grep -c '^ok')"
check "remove：旗標後接 --dry-run 時 exit 2" 2 "$($B "$S/remove-worktrees.sh" --allow-untracked --dry-run "$W/issue-1-merged" >/dev/null 2>&1; echo $?)"
check "remove：路徑含換行 exit 2" 2 "$($B "$S/remove-worktrees.sh" --dry-run "$W/issue-1-merged
$W/issue-7-empty" >/dev/null 2>&1; echo $?)"
check "remove：worktree list 失敗時 --orphan 拒絕" REFUSE "$(rw --orphan "$F/brk-worktrees/w" | first)"
check "remove：worktree list 失敗時 --prune 拒絕" REFUSE "$(rw --prune "$F/brk" | first)"
check "remove：.venv 裡有 repo 的 worktree 拒絕" REFUSE "$(rw "$W/issue-25-venv" | first)"
check "remove：不認得的參數 exit 2" 2 "$($B "$S/remove-worktrees.sh" --bogus >/dev/null 2>&1; echo $?)"

# ---- remove-worktrees：實際刪除（不加 --dry-run；fixture 的 origin 是本機 bare repo，fetch 會成功）----
br_exists() { git -C "$F/app" rev-parse -q --verify "refs/heads/$1" >/dev/null && echo yes || echo no; }
gone() { [ -e "$1" ] && echo no || echo yes; }
rr() { $B "$S/remove-worktrees.sh" "$@" 2>/dev/null; }
rr "$W/issue-1-merged" >/dev/null
check "實刪：green 被移除" yes "$(gone "$W/issue-1-merged")"
check "實刪：ancestor 的 branch 已刪" no "$(br_exists feat/1-merged)"
rr "$W/issue-18-cherry" >/dev/null
check "實刪：cherry 的 worktree 被移除" yes "$(gone "$W/issue-18-cherry")"
check "實刪：cherry 的 branch 保留" yes "$(br_exists feat/18-cherry)"
rr --allow-untracked "$W/issue-23-pr-env" --trust-merged "$W/issue-23-pr-env" >/dev/null
check "實刪：同一 path 疊加兩個旗標可移除" yes "$(gone "$W/issue-23-pr-env")"
check "實刪：--trust-merged 刪 branch" no "$(br_exists feat/23-pr-env)"
rr --orphan "$F/app/.claude/worktrees/orph-nogit" >/dev/null
check "實刪：.claude/worktrees 下沒有 .git 的孤兒可刪" yes "$(gone "$F/app/.claude/worktrees/orph-nogit")"
rr "$W/issue-3-dirty" "$W/issue-17-nested-outer" "$W/issue-19-assume" >/dev/null
check "實刪：dirty 的修改還在" yes "$(grep -q changed "$W/issue-3-dirty/a.txt" && echo yes || echo no)"
check "實刪：巢狀 worktree 的修改還在" yes "$(grep -q dirty "$W/issue-17-nested-outer/dist/a.txt" && echo yes || echo no)"
check "實刪：assume-unchanged 的修改還在" yes "$(grep -q hidden "$W/issue-19-assume/a.txt" && echo yes || echo no)"
check "實刪：remote branch 沒被刪" yes "$(git -C "$F/origin.git" rev-parse -q --verify refs/heads/feat/23-pr-env >/dev/null && echo yes || echo no)"

# fetch 失敗時 worktree 照刪、branch 保留
git -C "$F/app" remote set-url origin "$R/nonexistent.git"
rr "$W/issue-7-empty" >/dev/null
check "實刪：fetch 失敗時 worktree 照刪" yes "$(gone "$W/issue-7-empty")"
check "實刪：fetch 失敗時 branch 保留" yes "$(br_exists chore/7-empty)"
git -C "$F/app" remote set-url origin "$F/origin.git"
# --prune 成功：先手動移除 issue-14 的 metadata（它有獨有 commit，會擋 prune），剩下 issue-9 可 prune
rm -rf "$F/app/.git/worktrees/issue-14-gone-detached"
rr --prune "$F/app" >/dev/null
check "實刪：--prune 成功清掉殘留 metadata" no "$(git -C "$F/app" worktree list --porcelain | grep -q 'issue-9-gone' && echo yes || echo no)"

[ "$fail" = 0 ] && echo "全部通過" || echo "有失敗"
exit "$fail"
