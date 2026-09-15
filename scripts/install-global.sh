#!/usr/bin/env bash
# 把本 repo 的角色與 skill 以 symlink 裝到家目錄，讓所有專案共用（全域安裝）。
# 預設 dry-run 只列計畫；--apply 才動手；--uninstall 只移除「指回本 repo」的 symlink。
#
#   ~/.agents/roles            → .agents/roles            角色本體（stub 找不到 repo 版時讀這裡）
#   ~/.agents/conventions.md   → .agents/conventions.md   repo 無 conventions 時的推斷規則
#   ~/.agents/skills/<s>       → .agents/skills/<s>       skill 真身（Codex 直接掃；含 _tracker）
#   ~/.claude/skills/<s>       → .claude/skills/<s>       Claude skill stub
#   ~/.claude/agents/<r>.md    → .claude/agents/<r>.md    Claude agent stub
#   ~/.codex/agents/<r>.toml   → .codex/agents/<r>.toml   Codex agent stub（--no-codex 略過）
#
# 同名優先序（為什麼 skill 要有讓位段）：
#   Claude agent：專案 > 全域（專案版自動生效）
#   Claude skill：全域 > 專案（全域會蓋掉專案版 → 真身開頭的讓位段改讀 repo 版）
#   Codex skill ：兩份並列；Codex agent：官方未說明
# 已存在且不是指回本 repo 的目標一律跳過並回報，不覆寫。
# symlink 指向本 repo 的 working tree：本 repo 切到哪個分支，全域就生效哪個版本。
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
mode=plan; codex=1
for a in "$@"; do
  case "$a" in
    --apply) mode=apply ;;
    --uninstall) mode=uninstall ;;
    --no-codex) codex=0 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知參數：$a（可用 --apply / --uninstall / --no-codex）" >&2; exit 2 ;;
  esac
done

pairs=()
add() { pairs+=("$1|$2"); }
add "$repo/.agents/roles" "$HOME/.agents/roles"
add "$repo/.agents/conventions.md" "$HOME/.agents/conventions.md"
for d in "$repo"/.agents/skills/*/; do d=${d%/}; add "$d" "$HOME/.agents/skills/${d##*/}"; done
for d in "$repo"/.claude/skills/*/; do d=${d%/}; add "$d" "$HOME/.claude/skills/${d##*/}"; done
for f in "$repo"/.claude/agents/*.md; do add "$f" "$HOME/.claude/agents/${f##*/}"; done
if [ "$codex" = 1 ]; then
  for f in "$repo"/.codex/agents/*.toml; do add "$f" "$HOME/.codex/agents/${f##*/}"; done
fi

n_new=0; n_ok=0; n_conflict=0; n_rm=0
for p in "${pairs[@]}"; do
  src=${p%%|*}; dst=${p#*|}; show=${dst/#$HOME/\~}
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    if [ "$mode" = uninstall ]; then
      rm "$dst"; n_rm=$((n_rm+1)); echo "- 移除  $show"
    else
      n_ok=$((n_ok+1)); echo "= 已裝  $show"
    fi
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    [ "$mode" = uninstall ] && continue
    n_conflict=$((n_conflict+1)); echo "! 衝突  $show 已存在且不是指回本 repo，跳過"
  else
    [ "$mode" = uninstall ] && continue
    n_new=$((n_new+1)); echo "+ 建立  $show → ${src#"$repo"/}"
    if [ "$mode" = apply ]; then mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; fi
  fi
done

case "$mode" in
  plan)      echo; echo "dry-run：將建立 ${n_new}、已裝 ${n_ok}、衝突 ${n_conflict}。確認後加 --apply 執行。" ;;
  apply)     echo; echo "完成：建立 ${n_new}、已裝 ${n_ok}、衝突跳過 ${n_conflict}。" ;;
  uninstall) echo; echo "完成：移除 ${n_rm} 個指回本 repo 的 symlink。" ;;
esac
