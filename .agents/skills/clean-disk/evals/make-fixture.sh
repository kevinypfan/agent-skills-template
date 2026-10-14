#!/usr/bin/env bash
# 建立含各種 worktree／產物狀態的假環境（給 check-tiers.sh 與 LLM eval 用）。
# 用法：make-fixture.sh <根目錄>   ——會先清空該目錄。issue-10-active 需要呼叫端自己在裡面起一個 process。
set -e
R=$1; rm -rf "$R"; mkdir -p "$R"; R=$(cd "$R" && pwd -P); cd "$R"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
blob() { mkdir -p "$1"; head -c "$2" /dev/zero > "$1/blob"; }
git init -q --bare origin.git
git clone -q origin.git app 2>/dev/null; cd app
git checkout -q -b main
printf 'node_modules/\n.venv/\n.env\ndist/\nbuild/\ncoverage/\n*.log\n!keep/build/\n' > .gitignore; echo base > a.txt; git add .; git commit -qm init; git push -q -u origin main
W="$R/app-worktrees"; mkdir -p "$W"
mk() { git worktree add -q -b "$1" "$W/$2" origin/main; }
# 1 一般 merge 進 main
mk feat/1-merged issue-1-merged; (cd "$W/issue-1-merged"; echo x > m.txt; git add .; git commit -qm m; git push -q -u origin feat/1-merged)
git merge -q --no-ff feat/1-merged -m "Merge 1"
# 2 squash 進 main，遠端分支已刪
mk fix/2-squashed issue-2-squashed; (cd "$W/issue-2-squashed"; echo s1 > s.txt; git add .; git commit -qm s1; echo s2 >> s.txt; git commit -qam s2; git push -q -u origin fix/2-squashed)
git merge -q --squash fix/2-squashed >/dev/null; git commit -qm "squash 2"; git push -q origin main; git push -q origin --delete fix/2-squashed
# 3 追蹤檔未 commit
mk feat/3-dirty issue-3-dirty; echo changed >> "$W/issue-3-dirty/a.txt"
# 4 commit 沒 push
mk feat/4-unpushed issue-4-unpushed; (cd "$W/issue-4-unpushed"; echo u > u.txt; git add .; git commit -qm u)
# 5 已 push、PR 還沒 merge；有大 node_modules
mk feat/5-open issue-5-open; (cd "$W/issue-5-open"; echo o > o.txt; git add .; git commit -qm o; git push -q -u origin feat/5-open)
blob "$W/issue-5-open/node_modules/x" 3000000
# 6 已 merge 但留了未追蹤筆記
mk feat/6-notes issue-6-notes; (cd "$W/issue-6-notes"; echo n > n.txt; git add .; git commit -qm n; git push -q -u origin feat/6-notes)
git merge -q --no-ff feat/6-notes -m "Merge 6"; git push -q origin main; echo "my notes" > "$W/issue-6-notes/NOTES.md"
# 7 開了但沒做事；裡面有 ignored 的 node_modules
mk chore/7-empty issue-7-empty; blob "$W/issue-7-empty/node_modules/pkg" 2000000
# 8 孤兒目錄
mkdir -p "$W/issue-8-orphan"; echo "gitdir: /nonexistent" > "$W/issue-8-orphan/.git"; echo w > "$W/issue-8-orphan/work.txt"
# 9 目錄被手動刪掉（有 branch，prune 不會掉 commit）
mk feat/9-gone issue-9-gone; rm -rf "$W/issue-9-gone"
# 10 有 process 在裡面（呼叫端自己起 sleep）
mk feat/10-active issue-10-active
# 11 metadata 斷裂（repo 搬過目錄）：還登記著，但 .git 指到不存在的地方；裡面有未保存的改動
mk feat/11-broken issue-11-broken; echo wip >> "$W/issue-11-broken/a.txt"; echo "gitdir: /nonexistent/.git/worktrees/x" > "$W/issue-11-broken/.git"
# 12 已 merge、乾淨，但有被 ignore 的 .env（git worktree remove 會不經確認刪掉）
mk chore/12-env issue-12-env; echo "SECRET=1" > "$W/issue-12-env/.env"
# 13 detached + locked
git worktree add -q --detach "$W/issue-13-detached-locked" origin/main; git worktree lock "$W/issue-13-detached-locked"
# 14 detached、有獨有 commit，目錄被刪掉（prune 後 commit 找不回來）
git worktree add -q --detach "$W/issue-14-gone-detached" origin/main; (cd "$W/issue-14-gone-detached"; echo d > d.txt; git add .; git commit -qm d); rm -rf "$W/issue-14-gone-detached"
# 15 rebase merge 過，之後把 main merge 回來、解衝突時夾帶新改動且沒 push（git cherry 看不到 merge commit）
mk feat/15-merge-extra issue-15-merge-extra; (cd "$W/issue-15-merge-extra"; echo r > r.txt; git add .; git commit -qm r; git push -q -u origin feat/15-merge-extra)
git cherry-pick "$(git -C "$W/issue-15-merge-extra" rev-parse HEAD)" >/dev/null; git push -q origin main
(cd "$W/issue-15-merge-extra"; git fetch -q origin; git merge -q --no-ff --no-commit origin/main 2>/dev/null || true; echo extra > extra.txt; git add .; git commit -qm "merge main + extra")
# 16 worktree 目錄下的 symlink（不可被當孤兒目錄）
ln -s "$R/app" "$W/issue-16-symlink"
# 產物：app/dist 其實是另一個 worktree（gh-pages），app/build 有 git add -f 的追蹤檔
git worktree add -q -b gh-pages "$R/app/dist" origin/main; blob "$R/app/dist/assets" 2000000
blob "$R/app/build" 2000000; echo keep > "$R/app/build/keep.txt"; git add -f build/keep.txt; git commit -qm "keep build file"
git push -q origin main
# 17 外層已 merge，但 ignored 的 dist/ 其實是另一個有未 commit 變更的 worktree（刪外層會連它一起刪）
mk chore/17-nested-outer issue-17-nested-outer
git worktree add -q -b nested-dist "$W/issue-17-nested-outer/dist" origin/main; echo dirty >> "$W/issue-17-nested-outer/dist/a.txt"
# 18 rebase merge（cherry-pick 進 main），本地 commit 沒 push：worktree 可刪，但 branch 要保留
mk feat/18-cherry issue-18-cherry; (cd "$W/issue-18-cherry"; echo c > c18.txt; git add .; git commit -qm c18)
git cherry-pick -x "$(git -C "$W/issue-18-cherry" rev-parse HEAD)" >/dev/null  # -x：commit 訊息不同，才不會產生同一個 OID
# 19 追蹤檔設了 assume-unchanged 後被修改（git status 看不到）
mk chore/19-assume issue-19-assume; (cd "$W/issue-19-assume"; git update-index --assume-unchanged a.txt; echo hidden >> a.txt)
# 20 unborn branch，裡面有 .env
mk chore/20-unborn issue-20-unborn; (cd "$W/issue-20-unborn"; git symbolic-ref HEAD refs/heads/does-not-exist; echo "K=1" > .env)
# 21 進行中的 merge（MERGE_HEAD）
mk chore/21-merging issue-21-merging; echo "$(git rev-parse HEAD)" > "$(git -C "$W/issue-21-merging" rev-parse --absolute-git-dir)/MERGE_HEAD"
# 22 .claude/worktrees 底下沒有 .git 的孤兒
mkdir -p "$R/app/.claude/worktrees/orph-nogit"; echo w > "$R/app/.claude/worktrees/orph-nogit/f.txt"
# 23 已 push 未進 base（PR 其實已 merge），裡面有 .env：要同一個 path 疊 --allow-untracked 與 --trust-merged
mk feat/23-pr-env issue-23-pr-env; (cd "$W/issue-23-pr-env"; echo p > p23.txt; git add .; git commit -qm p23; git push -q -u origin feat/23-pr-env); echo "K=2" > "$W/issue-23-pr-env/.env"
# 24 已 merge、乾淨，但有被 ignore 的 debug.log（*.log 不算可重建）
mk chore/24-log issue-24-log; echo trace > "$W/issue-24-log/debug.log"
git push -q origin main
# 25 已 merge、乾淨，但 .venv/src/pkg 是 pip install -e git+… 放的真 repo（有本地 commit）
mk chore/25-venv issue-25-venv; git init -q "$W/issue-25-venv/.venv/src/pkg"; (cd "$W/issue-25-venv/.venv/src/pkg"; echo x > x; git add .; git commit -qm local)
# 產物：主 repo 的 .venv 裡也有同樣的 editable 套件 repo
git init -q "$R/app/.venv/src/pkg"; blob "$R/app/.venv/lib" 2000000
# 產物：被 !keep/build/ 取消 ignore 的 build（原始碼）
mkdir -p "$R/app/keep/build"; echo "int main(){}" > "$R/app/keep/build/main.c"
# 產物：coverage/ 底下有巢狀 repo
mkdir -p "$R/app/coverage"; git init -q "$R/app/coverage/inner"; blob "$R/app/coverage" 2000000
# 產物：只有上層目錄規則（/build-tools/）命中的 out
cd "$R"; git init -q tools; printf '/build-tools/\n' > tools/.gitignore; blob "$R/tools/build-tools/out" 2000000
# 產物：規則來自 .git/info/exclude（個人設定）
git init -q excl; echo out > excl/.git/info/exclude; blob "$R/excl/out" 2000000
# 26 worktree list 失敗的 repo（config 壞掉），底下有一個真的 linked worktree
git init -q brk; (cd brk; echo b > b; git add .; git commit -qm b; git worktree add -q -b w ../brk-worktrees/w); echo w > "$R/brk-worktrees/w/note.txt"; printf '[broken\n' >> brk/.git/config
cd "$R/app"
# 產物：dotfiles 類 repo（.gitignore 寫 *），底下的 build 不是可重建產物
cd "$R"; git init -q dotfiles; printf '*\n' > dotfiles/.gitignore; blob "$R/dotfiles/proj/build" 2000000
