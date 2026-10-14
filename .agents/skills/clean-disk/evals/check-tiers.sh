#!/usr/bin/env bash
# script 層的自動斷言：建 fixture → 跑 scan／remove（多數用 --dry-run）→ 逐項比對預期。改 scripts/ 後必跑。
# 用法：bash .agents/skills/clean-disk/evals/check-tiers.sh   （全過 exit 0）
set -u
here=$(cd "$(dirname "$0")" && pwd); S="$here/../scripts"
R=$(mktemp -d); trap 'kill "$sleeper" 2>/dev/null; rm -rf "$R"' EXIT
bash "$here/make-fixture.sh" "$R/fx" >/dev/null 2>&1 || { echo "✗ make-fixture 失敗"; exit 1; }
F=$(cd "$R/fx" && pwd -P); W="$F/app-worktrees"
(cd "$W/issue-10-active" && exec sleep 600) & sleeper=$!; disown 2>/dev/null || true
sleep 1
fail=0
check() { if [ "$2" = "$3" ]; then echo "✓ $1"; else echo "✗ $1：預期 $2，實際 $3"; fail=1; fi; }

scan=$(bash "$S/scan-worktrees.sh" --no-fetch "$F")
tier_of() { printf '%s\n' "$scan" | awk -F'\t' -v n="$1" '{ p=$3; sub(/.*\//,"",p) } p==n { print $1; exit }'; }
for pair in issue-1-merged:green issue-2-squashed:green issue-3-dirty:red issue-4-unpushed:red issue-5-open:yellow \
            issue-6-notes:yellow issue-7-empty:green issue-8-orphan:yellow issue-9-gone:green issue-10-active:red \
            issue-11-broken:yellow issue-12-env:yellow issue-13-detached-locked:red issue-14-gone-detached:red \
            issue-15-merge-extra:red dist:yellow; do
  check "worktree ${pair%%:*}" "${pair#*:}" "$(tier_of "${pair%%:*}")"
done
check "symlink 不列為孤兒" "" "$(tier_of issue-16-symlink)"
check "detached 的 branch 欄" "detached" "$(printf '%s\n' "$scan" | awk -F'\t' '$3 ~ /issue-13-detached-locked$/ { print $4 }')"

art=$(bash "$S/scan-artifacts.sh" --min-mb 0 "$F" | cut -f5)
has() { printf '%s\n' "$art" | grep -qx "$1" && echo yes || echo no; }
check "產物：worktree 裡的 node_modules 列出" yes "$(has "$W/issue-5-open/node_modules")"
check "產物：nested worktree 的 dist 不列" no "$(has "$F/app/dist")"
check "產物：有追蹤檔的 build 不列" no "$(has "$F/app/build")"
check "產物：.gitignore 寫 * 的 repo 底下的 build 不列" no "$(has "$F/dotfiles/proj/build")"

out=$(bash "$S/remove-artifacts.sh" "$F/app/dist" --dry-run)
check "remove-artifacts：--dry-run 放最後也生效、nested worktree 拒絕" "REFUSE" "$(printf '%s' "$out" | head -1 | cut -d' ' -f1)"
check "remove-artifacts：dist 還在" yes "$([ -d "$F/app/dist/assets" ] && echo yes || echo no)"

rw() { bash "$S/remove-worktrees.sh" --dry-run "$@" 2>/dev/null | head -1 | awk '{print $1}'; }
check "remove：metadata 斷裂不可 --orphan" REFUSE "$(rw --orphan "$W/issue-11-broken")"
check "remove：worktree_root 以外不可 --orphan" REFUSE "$(rw --orphan "$F/dotfiles")"
check "remove：symlink 不可 --orphan" REFUSE "$(rw --orphan "$W/issue-16-symlink")"
check "remove：孤兒目錄可 --orphan" "(dry-run)" "$(rw --orphan "$W/issue-8-orphan")"
check "remove：有 .env 的要 --allow-untracked" REFUSE "$(rw "$W/issue-12-env")"
check "remove：--allow-untracked 只套用在指定 path" REFUSE "$(bash "$S/remove-worktrees.sh" --dry-run --allow-untracked "$W/issue-12-env" "$W/issue-6-notes" | sed -n 3p | awk '{print $1}')"
check "remove：red 一律拒絕" REFUSE "$(rw --allow-untracked "$W/issue-3-dirty")"
check "remove：detached 有獨有 commit 時拒絕 prune" REFUSE "$(rw --prune "$F/app")"
check "remove：不認得的參數 exit 2" 2 "$(bash "$S/remove-worktrees.sh" --bogus >/dev/null 2>&1; echo $?)"

[ "$fail" = 0 ] && echo "全部通過" || echo "有失敗"
exit "$fail"
