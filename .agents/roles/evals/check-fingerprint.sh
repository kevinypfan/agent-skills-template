#!/usr/bin/env bash
# worktree-fingerprint.sh 的斷言測試：每種改動都要讓指紋變、沒改動時要穩定、ignored 檔不計入、各種未追蹤項目不讓它失敗。
# 手動：bash .agents/roles/evals/check-fingerprint.sh
set -u
fp="$(cd "$(dirname "$0")/.." && pwd)/worktree-fingerprint.sh"
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_NOSYSTEM=1 HOME="$R/home"; mkdir -p "$HOME"
g() { git -c user.email=t@example.com -c user.name=t "$@"; }
pass=0 fail=0
bad() { fail=$((fail+1)); echo "✗ $1"; }
cd "$R" && mkdir w && cd w && g init -q && echo a > a && printf 'ignored/\n' > .gitignore && g add a .gitignore && g commit -qm init
last=$(bash "$fp") || { echo "✗ 乾淨 repo 計算失敗"; exit 1; }
# 每一步都要讓指紋改變：<說明> <指令>
changes() {
  local what=$1 now; shift
  "$@" >/dev/null 2>&1
  if now=$(bash "$fp" 2>&1); then
    [ "$now" != "$last" ] && pass=$((pass+1)) || bad "指紋沒變：$what"
    last=$now
  else
    bad "計算失敗：${what}（${now}）"
  fi
}
changes "修改已追蹤檔"              sh -c 'echo b >> a'
changes "已 modified 的檔再改一次"   sh -c 'echo c >> a'
changes "新增未追蹤檔"              sh -c 'echo u > u'
changes "未追蹤檔內容改變"           sh -c 'echo v > u'
changes "新增 symlink"              ln -s /tmp linkdir
changes "symlink 改指向"            ln -sfn /var linkdir
changes "新增未追蹤的巢狀 repo"       sh -c 'mkdir sub && cd sub && git init -q && echo x > x && git -c user.email=t@example.com -c user.name=t add x && git -c user.email=t@example.com -c user.name=t commit -qm i'
changes "巢狀 repo 內改檔"           sh -c 'echo y >> sub/x'
changes "未追蹤檔名含空白" sh -c 'echo s > "with space"'
# 「stage」那步刻意不改內容：git diff HEAD 涵蓋 staged 與 unstaged，指紋不應變
g add a; now=$(bash "$fp"); [ "$now" = "$last" ] && pass=$((pass+1)) || bad "只 stage 不改內容，指紋卻變了"
last=$now
# ignored 檔不計入
mkdir -p ignored && echo junk > ignored/out; now=$(bash "$fp"); [ "$now" = "$last" ] && pass=$((pass+1)) || bad "ignored 檔被計入"
# 沒改動時穩定
[ "$(bash "$fp")" = "$(bash "$fp")" ] && pass=$((pass+1)) || bad "沒改動時指紋不穩定"
# 唯讀：不寫入 object
before=$(find .git/objects -type f | wc -l); bash "$fp" >/dev/null; after=$(find .git/objects -type f | wc -l)
[ "$before" = "$after" ] && pass=$((pass+1)) || bad "計算指紋寫入了 object（${before} → ${after}）"
# 沒有 commit 的 repo：明確失敗
mkdir "$R/empty" && (cd "$R/empty" && git init -q); bash "$fp" "$R/empty" >/dev/null 2>&1 && bad "unborn HEAD 應失敗" || pass=$((pass+1))
echo "worktree-fingerprint：${pass} 通過，${fail} 失敗"
[ "$fail" = 0 ]
