#!/usr/bin/env bash
# 把本 repo 的角色、skill 與派工政策裝到家目錄，讓所有專案共用（全域安裝）。
# 預設 dry-run 只列計畫；--apply 才動手；--uninstall 只移除本腳本裝的東西；--quiet 只印有變動的項目（給 git hook 用）。
#
#   ~/.agents/roles            → .agents/roles            symlink  角色本體（stub 找不到 repo 版時讀這裡）
#   ~/.agents/conventions.md   → .agents/conventions.md   symlink  repo 無 conventions 時的推斷規則
#   ~/.agents/conventions.local.md                       不碰     個人覆寫層（使用者 / skill 自建；不建立、--uninstall 也不刪）
#   （不裝）.agents/extensions                            擴充點是專案流程，只讀當前 repo 根；~/.agents/extensions 不會存在，skill 也不讀它
#   ~/.agents/skills/<s>       → .agents/skills/<s>       symlink  skill 真身（Codex 直接掃；含 _tracker）
#   ~/.claude/skills/<s>       → .claude/skills/<s>       symlink  Claude skill stub
#   ~/.claude/agents/<r>.md    → .claude/agents/<r>.md    symlink  Claude agent stub
#   ~/.claude/AGENT-ROLES.md   → global/AGENT-ROLES.md    symlink  派工政策；~/.claude/CLAUDE.md 加一行 @AGENT-ROLES.md
#   ~/.claude/agent-skills-template/<f>.sh → global/claude/<f>.sh  symlink  subagent-model.sh（SubagentStop hook：顯示 sub agent 實際 model）、statusline.sh
#   ~/.claude/settings.json                               **合併**  加 hooks.SubagentStop 一筆、statusLine（已有別的 statusLine 就不動；需要 jq）
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
# 指回本 repo 但目標已不存在的 symlink（skill／角色改名或移除後留下的）會被清掉；切回舊分支時再依當時的清單重建。
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
    -h|--help) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "未知參數：${a}（可用 --apply / --uninstall / --no-codex / --quiet）" >&2; exit 2 ;;
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
# 放專屬目錄：~/.claude/statusline.sh 是 Claude Code /statusline 的預設檔名，用它會撞到使用者自己的
hook_src="$repo/global/claude/subagent-model.sh"; hook_dst="$HOME/.claude/agent-skills-template/subagent-model.sh"
sl_src="$repo/global/claude/statusline.sh";      sl_dst="$HOME/.claude/agent-skills-template/statusline.sh"
add link "$hook_src" "$hook_dst"
add link "$sl_src" "$sl_dst"
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

# ---- ~/.claude/settings.json：SubagentStop hook 與 statusLine ----
# 只增刪本腳本那兩筆，其他設定原樣保留。寫回用 cat > 而非 mv：settings.json 是 symlink（dotfiles）時才不會被換成實體檔。
# 指令寫字面的 "$HOME"（執行時由 shell 展開），dotfiles 跨機器共用、各機 HOME 不同時仍比對得到；
# script 不存在（主 checkout 切到舊分支、別台機器沒裝本 repo）就安靜結束，不讓每次 sub agent 結束都報錯。
# 「使用者自己的選擇」（已有別的 statusLine、沒有 jq、claude_settings: false）用 skip：不算衝突、--quiet 不印，否則 git hook 每次 commit 都會吵。
cs="$HOME/.claude/settings.json"; show_cs="~/.claude/settings.json"; cs_lock="$HOME/.claude/.agent-skills-template.lock"
hook_cmd='[ ! -f "$HOME/.claude/agent-skills-template/subagent-model.sh" ] || bash "$HOME/.claude/agent-skills-template/subagent-model.sh"'
sl_cmd='[ ! -f "$HOME/.claude/agent-skills-template/statusline.sh" ] || bash "$HOME/.claude/agent-skills-template/statusline.sh"'
keep_links=0   # uninstall 時 settings 沒清乾淨 → 保留兩個 script，不留下指向不存在檔案的 hook
skip() { say "= 跳過  $1"; }
# 設定指向的檔案是本 repo 的 symlink（dry-run 時則是尚不存在、會被建立）才算數；symlink 段已經報過衝突，這裡不重複計
ready() { { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; } || { [ "$mode" = plan ] && [ ! -e "$1" ] && [ ! -L "$1" ]; }; }
# 個人 conventions（~/.agents/conventions.local.md）設 claude_settings 為 false → 不碰 settings.json；表格列與 `key: value` 兩種寫法都認
settings_opt_out() {
  local f="$HOME/.agents/conventions.local.md"; [ -f "$f" ] || return 1
  awk -F'|' '
    { k = $2; v = $3; gsub(/[ `]/, "", k); gsub(/[ `]/, "", v); if (k == "claude_settings" && v == "false") found = 1 }
    /^[[:space:]]*claude_settings:[[:space:]]*`?false`?[[:space:]]*$/ { found = 1 }
    END { exit !found }' "$f"
}
# 同時只讓一個 install-global.sh 改 settings.json（例如手動 --apply 碰上 git hook 的自動同步）；拿不到鎖就跳過
cs_lock_take() {
  local i=0; mkdir -p "$(dirname "$cs_lock")"
  until mkdir "$cs_lock" 2>/dev/null; do i=$((i + 1)); [ "$i" -ge 50 ] && return 1; sleep 0.1; done
  trap 'rmdir "$cs_lock" 2>/dev/null || true' EXIT
}
# $1 = 動作描述，其餘參數交給 jq；成功回 0，失敗報衝突並回 1
cs_write() {
  local what=$1 tmp; shift
  if [ -e "$cs" ] && [ ! -w "$cs" ]; then conflict "${show_cs} 不可寫入（${what}），跳過"; return 1; fi
  if [ ! -s "$cs" ]; then
    # 讀的時候還有內容、現在卻是空的 → 有別的程式正在寫，不能當成 {} 重寫（會把使用者整份設定清掉）
    if [ "$cs_empty" = 0 ]; then conflict "${show_cs} 在處理中被清空（${what}），跳過"; return 1; fi
    mkdir -p "$(dirname "$cs")"; echo '{}' > "$cs"
  fi
  tmp=$(mktemp "$cs.XXXXXX") || { conflict "${show_cs} 無法建立暫存檔（${what}），跳過"; return 1; }
  # jq 讀到空檔會輸出空字串並回傳 0，所以結果一定要驗證是 JSON 物件才寫回
  if jq "$@" "$cs" > "$tmp" 2>/dev/null && jq -e 'type == "object"' "$tmp" >/dev/null 2>&1 && cat "$tmp" > "$cs"; then
    rm -f "$tmp"; cs_empty=0; return 0
  fi
  rm -f "$tmp"; conflict "${show_cs} 寫入失敗（${what}），跳過"; return 1
}
# 型別不符（例如 hooks 是陣列、statusLine 是字串）時視為沒有，不讓 jq 在 set -e 下中止整支腳本
q_hook='[(.hooks | objects | .SubagentStop | arrays)[]? | objects | (.hooks | arrays)[]? | objects | select(.command == $c)] | length > 0'
# statusLine 有任何值（就算格式不對）都算使用者自己的，不覆寫；沒有 command 字串時回傳佔位字
q_sl='.statusLine | if . == null then "" elif type == "object" then ((.command | strings) // "(其他)") else "(其他)" end'
f_add='.hooks.SubagentStop += [{hooks: [{type: "command", command: $c, timeout: 10}]}]'
f_rm='
  .hooks.SubagentStop |= map(
    if type == "object" and (.hooks | type) == "array"
    then .hooks |= map(select(type != "object" or .command != $c)) | select((.hooks | length) > 0)
    else . end)
  | if (.hooks.SubagentStop | length) == 0 then del(.hooks.SubagentStop) else . end
  | if (.hooks | length) == 0 then del(.hooks) else . end'
claude_settings() {
  if settings_opt_out && [ "$mode" != uninstall ]; then skip "${show_cs}（conventions.local.md 設了 claude_settings: false）"; return 0; fi
  if ! command -v jq >/dev/null 2>&1; then
    if [ "$mode" = uninstall ]; then say "! 沒有 jq：${show_cs} 若有本腳本加的 SubagentStop hook / statusLine 請手動刪除，script 先保留"; keep_links=1
    else skip "${show_cs} 的 hook / statusLine（需要 jq）"; fi
    return 0
  fi
  if [ "$mode" != plan ] && ! cs_lock_take; then
    conflict "${show_cs} 被另一個 install-global.sh 鎖住；確定沒有在跑就刪掉 $(tilde "$cs_lock")"
    [ "$mode" = uninstall ] && keep_links=1
    return 0
  fi
  if [ -s "$cs" ] && ! jq -e 'type == "object"' "$cs" >/dev/null 2>&1; then
    if [ "$mode" = uninstall ]; then say "! ${show_cs} 不是合法的 JSON 物件，未處理，script 先保留"; keep_links=1
    else conflict "${show_cs} 不是合法的 JSON 物件，跳過"; fi
    return 0
  fi
  cs_empty=1; cs_json='{}'
  if [ -s "$cs" ]; then cs_empty=0; cs_json=$(cat "$cs"); fi
  has_hook=$(jq --arg c "$hook_cmd" "$q_hook" <<<"$cs_json")
  cur_sl=$(jq -r "$q_sl" <<<"$cs_json")
  if [ "$mode" = uninstall ]; then
    if [ "$has_hook" = true ]; then
      if cs_write "移除 SubagentStop hook" --arg c "$hook_cmd" "$f_rm"; then removed "${show_cs} 的 SubagentStop hook"; else keep_links=1; fi
    fi
    if [ "$cur_sl" = "$sl_cmd" ]; then
      if cs_write "移除 statusLine" 'del(.statusLine)'; then removed "${show_cs} 的 statusLine"; else keep_links=1; fi
    fi
    return 0
  fi
  if ! ready "$hook_dst" "$hook_src"; then skip "${show_cs} 的 SubagentStop hook（$(tilde "$hook_dst") 不是本 repo 的 symlink）"
  elif [ "$has_hook" = true ]; then ok "${show_cs} 的 SubagentStop hook"
  elif [ "$mode" = plan ] || cs_write "加入 SubagentStop hook" --arg c "$hook_cmd" "$f_add"; then
    new "加入  ${show_cs} 的 SubagentStop hook → $(tilde "$hook_dst")"
  fi
  if [ -n "$cur_sl" ] && [ "$cur_sl" != "$sl_cmd" ]; then skip "${show_cs} 的 statusLine（已有自己的；要改用本 repo 的請先刪掉該設定）"
  elif ! ready "$sl_dst" "$sl_src"; then skip "${show_cs} 的 statusLine（$(tilde "$sl_dst") 不是本 repo 的 symlink）"
  elif [ "$cur_sl" = "$sl_cmd" ]; then ok "${show_cs} 的 statusLine"
  elif [ "$mode" = plan ] || cs_write "加入 statusLine" --arg c "$sl_cmd" '.statusLine = {type: "command", command: $c}'; then
    new "加入  ${show_cs} 的 statusLine → $(tilde "$sl_dst")"
  fi
}
# uninstall：先清 settings 再刪 symlink，清不掉就保留 script
[ "$mode" = uninstall ] && claude_settings

# ---- symlink / copy ----
for p in "${pairs[@]}"; do
  kind=${p%%|*}; rest=${p#*|}; src=${rest%%|*}; dst=${rest#*|}; show=$(tilde "$dst")
  linked=0; [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && linked=1
  if [ "$mode" = uninstall ]; then
    if [ "$keep_links" = 1 ] && [ "$linked" = 1 ] && { [ "$dst" = "$hook_dst" ] || [ "$dst" = "$sl_dst" ]; }; then
      say "! 保留  ${show}（${show_cs} 裡的設定沒清掉，先不刪）"; continue
    fi
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

# ---- 指回本 repo 但已不在安裝清單的 symlink（skill／角色改名或移除後留下的斷連結）----
# --apply 只清目標已不存在的；--uninstall 清所有指回本 repo 的（清單內的上面已移除，剩下的都是舊的）。
for l in "$HOME/.agents/skills"/* "$HOME/.claude/skills"/* "$HOME/.claude/agents"/*; do
  [ -L "$l" ] || continue
  case "$(readlink "$l")" in "$repo"/*) ;; *) continue ;; esac
  [ "$mode" = uninstall ] || [ ! -e "$l" ] || continue
  removed "$(tilde "$l")（指回本 repo 但目標已不存在）"
  [ "$mode" = plan ] || rm "$l"
done
[ "$mode" = uninstall ] && { rmdir "$HOME/.claude/agent-skills-template" 2>/dev/null || true; }

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

[ "$mode" = uninstall ] || claude_settings   # apply／dry-run：symlink 建好之後才寫設定（ready 要看得到 symlink）

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
  plan)      echo; echo "dry-run：將建立 ${n_new}、更新 ${n_upd}、移除 ${n_rm}、已裝 ${n_ok}、衝突 ${n_conflict}。確認後加 --apply 執行。" ;;
  apply)     echo; echo "完成：建立 ${n_new}、更新 ${n_upd}、移除 ${n_rm}、已裝 ${n_ok}、衝突跳過 ${n_conflict}。" ;;
  uninstall) echo; echo "完成：移除 ${n_rm} 個本腳本安裝的項目。" ;;
esac
