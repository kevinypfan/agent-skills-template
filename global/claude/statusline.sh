#!/bin/bash
# Claude Code status line — minimal
# Format: DIRECTORY ⎇ BRANCH | MODEL | ctx:N%

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)
case "$cwd" in
  "$HOME"|"$HOME"/*) cwd_display="~${cwd#"$HOME"}" ;;
  *) cwd_display="$cwd" ;;
esac

model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)

git_seg=""
[ -n "$branch" ] && git_seg=" \033[0;36m⎇ ${branch}\033[0m"

model_seg=""
[ -n "$model" ] && model_seg=" | ${model}"

ctx_seg=""
[ -n "$used_pct" ] && ctx_seg=" | ctx:$(printf '%.0f' "$used_pct")%"

printf "\033[1;33m%s\033[0m%b%s%s" "$cwd_display" "$git_seg" "$model_seg" "$ctx_seg"
