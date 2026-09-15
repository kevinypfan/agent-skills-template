#!/usr/bin/env bash
# 把本 repo 的角色與 skill 裝到家目錄，讓所有專案共用（全域安裝）。
# 預設 dry-run 只列計畫；--apply 才動手；--uninstall 只移除本腳本裝的東西。
#
#   ~/.agents/roles            → .agents/roles            symlink  角色本體（stub 找不到 repo 版時讀這裡）
#   ~/.agents/conventions.md   → .agents/conventions.md   symlink  repo 無 conventions 時的推斷規則
#   ~/.agents/skills/<s>       → .agents/skills/<s>       symlink  skill 真身（Codex 直接掃；含 _tracker）
#   ~/.claude/skills/<s>       → .claude/skills/<s>       symlink  Claude skill stub
#   ~/.claude/agents/<r>.md    → .claude/agents/<r>.md    symlink  Claude agent stub
#   ~/.codex/agents/<r>.toml   ← .codex/agents/<r>.toml   **複製**  Codex agent stub（--no-codex 略過）
#
# Codex 不載入 symlink 形式的 agent toml（實測：symlink → "agent type is currently not available"，實體檔正常），
# 所以這組用複製，首行加標記；改了 .codex/agents/*.toml 之後要重跑 --apply 同步（dry-run 會列「過期」）。
#
# 同名優先序（為什麼 skill 要有讓位段）：
#   Claude agent：專案 > 全域（專案版自動生效）
#   Claude skill：全域 > 專案（全域會蓋掉專案版 → 真身開頭的讓位段改讀 repo 版）
#   Codex skill ：兩份並列；Codex agent：官方未說明
# 已存在且不是本腳本裝的目標一律跳過並回報，不覆寫。
# symlink 指向本 repo 的 working tree：本 repo 切到哪個分支，全域就生效哪個版本。
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
mode=plan; codex=1
for a in "$@"; do
  case "$a" in
    --apply) mode=apply ;;
    --uninstall) mode=uninstall ;;
    --no-codex) codex=0 ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知參數：$a（可用 --apply / --uninstall / --no-codex）" >&2; exit 2 ;;
  esac
done

pairs=()   # kind|src|dst
add() { pairs+=("$1|$2|$3"); }
add link "$repo/.agents/roles" "$HOME/.agents/roles"
add link "$repo/.agents/conventions.md" "$HOME/.agents/conventions.md"
for d in "$repo"/.agents/skills/*/; do d=${d%/}; add link "$d" "$HOME/.agents/skills/${d##*/}"; done
for d in "$repo"/.claude/skills/*/; do d=${d%/}; add link "$d" "$HOME/.claude/skills/${d##*/}"; done
for f in "$repo"/.claude/agents/*.md; do add link "$f" "$HOME/.claude/agents/${f##*/}"; done
if [ "$codex" = 1 ]; then
  for f in "$repo"/.codex/agents/*.toml; do add copy "$f" "$HOME/.codex/agents/${f##*/}"; done
fi

marker() { echo "# installed-by agent-skills-template/scripts/install-global.sh from $1 — 勿手改：改 source 後重跑 --apply"; }
render() { marker "$1"; cat "$1"; }
ours_copy() { [ -f "$2" ] && [ ! -L "$2" ] && [ "$(head -n1 "$2")" = "$(marker "$1")" ]; }

n_new=0; n_ok=0; n_upd=0; n_conflict=0; n_rm=0
for p in "${pairs[@]}"; do
  kind=${p%%|*}; rest=${p#*|}; src=${rest%%|*}; dst=${rest#*|}; show=${dst/#$HOME/\~}
  linked=0; [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && linked=1
  if [ "$mode" = uninstall ]; then
    if [ "$linked" = 1 ] || { [ "$kind" = copy ] && ours_copy "$src" "$dst"; }; then
      rm "$dst"; n_rm=$((n_rm+1)); echo "- 移除  ${show}"
    fi
    continue
  fi
  if [ "$kind" = link ]; then
    if [ "$linked" = 1 ]; then n_ok=$((n_ok+1)); echo "= 已裝  ${show}"
    elif [ -e "$dst" ] || [ -L "$dst" ]; then n_conflict=$((n_conflict+1)); echo "! 衝突  ${show} 已存在且不是指回本 repo，跳過"
    else
      n_new=$((n_new+1)); echo "+ 建立  ${show} → ${src#"$repo"/}"
      [ "$mode" = apply ] && { mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; }
    fi
  else
    if ours_copy "$src" "$dst"; then
      if [ "$(render "$src")" = "$(cat "$dst")" ]; then n_ok=$((n_ok+1)); echo "= 已裝  ${show}"
      else
        n_upd=$((n_upd+1)); echo "~ 過期  ${show}（source 已改，--apply 會更新）"
        [ "$mode" = apply ] && render "$src" > "$dst"
      fi
    elif [ "$linked" = 1 ]; then
      n_upd=$((n_upd+1)); echo "~ 更新  ${show}（舊版 symlink → 複製；Codex 不讀 symlink）"
      [ "$mode" = apply ] && { rm "$dst"; render "$src" > "$dst"; }
    elif [ -e "$dst" ] || [ -L "$dst" ]; then n_conflict=$((n_conflict+1)); echo "! 衝突  ${show} 已存在且不是本腳本裝的，跳過"
    else
      n_new=$((n_new+1)); echo "+ 複製  ${show} ← ${src#"$repo"/}"
      [ "$mode" = apply ] && { mkdir -p "$(dirname "$dst")"; render "$src" > "$dst"; }
    fi
  fi
done

case "$mode" in
  plan)      echo; echo "dry-run：將建立 ${n_new}、更新 ${n_upd}、已裝 ${n_ok}、衝突 ${n_conflict}。確認後加 --apply 執行。" ;;
  apply)     echo; echo "完成：建立 ${n_new}、更新 ${n_upd}、已裝 ${n_ok}、衝突跳過 ${n_conflict}。" ;;
  uninstall) echo; echo "完成：移除 ${n_rm} 個本腳本安裝的項目。" ;;
esac
