#!/usr/bin/env bash
# 把本 repo 的角色、skill 與派工政策裝到家目錄，讓所有專案共用（全域安裝）。
# 預設 dry-run 只列計畫；--apply 才動手；--uninstall 只移除本腳本裝的東西；--quiet 只印有變動的項目（給 git hook 用）。
#
#   ~/.agents/roles            → .agents/roles            symlink  角色本體（stub 找不到 repo 版時讀這裡）
#   ~/.agents/conventions.md   → .agents/conventions.md   symlink  repo 無 conventions 時的推斷規則
#   ~/.agents/skills/<s>       → .agents/skills/<s>       symlink  skill 真身（Codex 直接掃；含 _tracker）
#   ~/.claude/skills/<s>       → .claude/skills/<s>       symlink  Claude skill stub
#   ~/.claude/agents/<r>.md    → .claude/agents/<r>.md    symlink  Claude agent stub
#   ~/.claude/AGENT-ROLES.md   → global/AGENT-ROLES.md    symlink  派工政策；~/.claude/CLAUDE.md 加一行 @AGENT-ROLES.md
#   ~/.codex/agents/<r>.toml   ← .codex/agents/<r>.toml   **複製**  Codex agent stub（--no-codex 略過以下兩項）
#   ~/.codex/AGENTS.md         ← global/AGENT-ROLES.md    **區塊**  標記框起的區塊，檔內其他內容不動
#
# Codex 不載入 symlink 形式的 agent toml（實測：symlink → "agent type is currently not available"，實體檔正常），
# AGENTS.md 也沒有 import 語法，所以這兩項用複製；改了 source 要重跑 --apply（dry-run 列「過期」）。
# 本 repo 的 .githooks（post-commit / post-merge / post-checkout / post-rewrite）已裝過全域時會自動 --apply --quiet。
#
# 同名優先序（為什麼 skill 要有讓位段）：
#   Claude agent：專案 > 全域（專案版自動生效）
#   Claude skill：全域 > 專案（全域會蓋掉專案版 → 真身開頭的讓位段改讀 repo 版）
#   Codex skill ：兩份並列；Codex agent：官方未說明
# 已存在且不是本腳本裝的目標一律跳過並回報，不覆寫。
# symlink 指向本 repo 的 working tree：本 repo 切到哪個分支，全域就生效哪個版本。
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
mode=plan; codex=1; quiet=0
for a in "$@"; do
  case "$a" in
    --apply) mode=apply ;;
    --uninstall) mode=uninstall ;;
    --no-codex) codex=0 ;;
    --quiet) quiet=1 ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知參數：$a（可用 --apply / --uninstall / --no-codex / --quiet）" >&2; exit 2 ;;
  esac
done

policy="$repo/global/AGENT-ROLES.md"
pairs=()   # kind|src|dst
add() { pairs+=("$1|$2|$3"); }
add link "$repo/.agents/roles" "$HOME/.agents/roles"
add link "$repo/.agents/conventions.md" "$HOME/.agents/conventions.md"
for d in "$repo"/.agents/skills/*/; do d=${d%/}; add link "$d" "$HOME/.agents/skills/${d##*/}"; done
for d in "$repo"/.claude/skills/*/; do d=${d%/}; add link "$d" "$HOME/.claude/skills/${d##*/}"; done
for f in "$repo"/.claude/agents/*.md; do add link "$f" "$HOME/.claude/agents/${f##*/}"; done
add link "$policy" "$HOME/.claude/AGENT-ROLES.md"
if [ "$codex" = 1 ]; then
  for f in "$repo"/.codex/agents/*.toml; do add copy "$f" "$HOME/.codex/agents/${f##*/}"; done
fi

n_new=0; n_ok=0; n_upd=0; n_conflict=0; n_rm=0
say() { case "$1" in "= "*) [ "$quiet" = 1 ] || echo "$1" ;; *) echo "$1" ;; esac; }
ok()       { n_ok=$((n_ok+1)); say "= 已裝  $1"; }
new()      { n_new=$((n_new+1)); say "+ $1"; }
upd()      { n_upd=$((n_upd+1)); say "~ $1"; }
conflict() { n_conflict=$((n_conflict+1)); say "! 衝突  $1"; }
removed()  { n_rm=$((n_rm+1)); say "- 移除  $1"; }
tilde()    { case "$1" in "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;; *) printf '%s\n' "$1" ;; esac; }

marker() { echo "# installed-by agent-skills-template/scripts/install-global.sh from $1 — 勿手改：改 source 後重跑 --apply"; }
render() { marker "$1"; cat "$1"; }
ours_copy() { [ -f "$2" ] && [ ! -L "$2" ] && [ "$(head -n1 "$2")" = "$(marker "$1")" ]; }

# ---- symlink / copy ----
for p in "${pairs[@]}"; do
  kind=${p%%|*}; rest=${p#*|}; src=${rest%%|*}; dst=${rest#*|}; show=$(tilde "$dst")
  linked=0; [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && linked=1
  if [ "$mode" = uninstall ]; then
    if [ "$linked" = 1 ] || { [ "$kind" = copy ] && ours_copy "$src" "$dst"; }; then rm "$dst"; removed "${show}"; fi
    continue
  fi
  if [ "$kind" = link ]; then
    if [ "$linked" = 1 ]; then ok "${show}"
    elif [ -e "$dst" ] || [ -L "$dst" ]; then conflict "${show} 已存在且不是指回本 repo，跳過"
    else
      new "建立  ${show} → ${src#"$repo"/}"
      if [ "$mode" = apply ]; then mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; fi
    fi
  else
    if ours_copy "$src" "$dst"; then
      if [ "$(render "$src")" = "$(cat "$dst")" ]; then ok "${show}"
      else
        upd "過期  ${show}（source 已改，--apply 會更新）"
        if [ "$mode" = apply ]; then render "$src" > "$dst"; fi
      fi
    elif [ "$linked" = 1 ]; then
      upd "更新  ${show}（舊版 symlink → 複製；Codex 不讀 symlink）"
      if [ "$mode" = apply ]; then rm "$dst"; render "$src" > "$dst"; fi
    elif [ -e "$dst" ] || [ -L "$dst" ]; then conflict "${show} 已存在且不是本腳本裝的，跳過"
    else
      new "複製  ${show} ← ${src#"$repo"/}"
      if [ "$mode" = apply ]; then mkdir -p "$(dirname "$dst")"; render "$src" > "$dst"; fi
    fi
  fi
done

# ---- ~/.claude/CLAUDE.md 的 import 行 ----
cm="$HOME/.claude/CLAUDE.md"; imp="@AGENT-ROLES.md"
has_imp=0; [ -f "$cm" ] && grep -qxF "$imp" "$cm" && has_imp=1
if [ "$mode" = uninstall ]; then
  if [ "$has_imp" = 1 ]; then
    grep -vxF "$imp" "$cm" > "$cm.tmp" || true; mv "$cm.tmp" "$cm"
    if ! grep -q '[^[:space:]]' "$cm"; then rm "$cm"; removed "~/.claude/CLAUDE.md（只剩 import 行，整檔刪除）"; else removed "~/.claude/CLAUDE.md 的 ${imp} 行"; fi
  fi
elif [ "$has_imp" = 1 ]; then ok "~/.claude/CLAUDE.md 的 ${imp} 行"
else
  new "加入  ~/.claude/CLAUDE.md 一行 ${imp}"
  if [ "$mode" = apply ]; then
    mkdir -p "$(dirname "$cm")"; touch "$cm"
    [ -s "$cm" ] && [ -n "$(tail -c1 "$cm")" ] && echo >> "$cm"
    echo "$imp" >> "$cm"
  fi
fi

# ---- ~/.codex/AGENTS.md 的管理區塊 ----
if [ "$codex" = 1 ]; then
  am="$HOME/.codex/AGENTS.md"
  begin="<!-- agent-skills-template:AGENT-ROLES begin — 由 scripts/install-global.sh 管理，勿手改 -->"
  end="<!-- agent-skills-template:AGENT-ROLES end -->"
  want=$(printf '%s\n' "$begin"; cat "$policy"; printf '%s\n' "$end")
  n_begin=0; n_end=0
  if [ -f "$am" ]; then n_begin=$(grep -cxF "$begin" "$am" || true); n_end=$(grep -cxF "$end" "$am" || true); fi
  strip_block() { awk -v b="$begin" -v e="$end" '$0==b{skip=1; next} $0==e{skip=0; next} !skip' "$am"; }
  if [ "$n_begin" != "$n_end" ] || [ "$n_begin" -gt 1 ]; then
    [ "$mode" = uninstall ] || conflict "~/.codex/AGENTS.md 的區塊標記不成對或重複（begin=${n_begin} end=${n_end}），跳過"
  elif [ "$mode" = uninstall ]; then
    if [ "$n_begin" = 1 ]; then
      # 去掉區塊，並收掉安裝時補的尾端空行
      strip_block | awk '{ l[NR]=$0 } END { n=NR; while (n>0 && l[n] ~ /^[[:space:]]*$/) n--; for (i=1;i<=n;i++) print l[i] }' > "$am.tmp"; mv "$am.tmp" "$am"
      if ! grep -q '[^[:space:]]' "$am"; then rm "$am"; removed "~/.codex/AGENTS.md（只剩本區塊，整檔刪除）"; else removed "~/.codex/AGENTS.md 的派工政策區塊"; fi
    fi
  elif [ "$n_begin" = 1 ]; then
    have=$(awk -v b="$begin" -v e="$end" '$0==b{on=1} on{print} $0==e{on=0}' "$am")
    if [ "$have" = "$want" ]; then ok "~/.codex/AGENTS.md 的派工政策區塊"
    else
      upd "過期  ~/.codex/AGENTS.md 的派工政策區塊（source 已改，--apply 會更新）"
      if [ "$mode" = apply ]; then
        printf '%s\n' "$want" > "$am.want"
        awk -v b="$begin" -v e="$end" -v wf="$am.want" '
          $0==b { while ((getline l < wf) > 0) print l; skip=1; next }
          $0==e { skip=0; next }
          !skip' "$am" > "$am.tmp"
        mv "$am.tmp" "$am"; rm "$am.want"
      fi
    fi
  else
    new "加入  ~/.codex/AGENTS.md 的派工政策區塊（檔內其他內容不動）"
    if [ "$mode" = apply ]; then
      mkdir -p "$(dirname "$am")"; touch "$am"
      [ -s "$am" ] && { [ -n "$(tail -c1 "$am")" ] && echo >> "$am"; echo >> "$am"; }
      printf '%s\n' "$want" >> "$am"
    fi
  fi
fi

changes=$((n_new+n_upd+n_conflict+n_rm))
[ "$quiet" = 1 ] && [ "$changes" = 0 ] && exit 0
case "$mode" in
  plan)      echo; echo "dry-run：將建立 ${n_new}、更新 ${n_upd}、已裝 ${n_ok}、衝突 ${n_conflict}。確認後加 --apply 執行。" ;;
  apply)     echo; echo "完成：建立 ${n_new}、更新 ${n_upd}、已裝 ${n_ok}、衝突跳過 ${n_conflict}。" ;;
  uninstall) echo; echo "完成：移除 ${n_rm} 個本腳本安裝的項目。" ;;
esac
