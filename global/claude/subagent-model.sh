#!/usr/bin/env bash
# SubagentStop hook: show which model a sub agent actually ran on.
input=$(cat)
agent=$(jq -r '.agent_type // "agent"' <<<"$input")
effort=$(jq -r '.effort.level // empty' <<<"$input")
transcript=$(jq -r '.agent_transcript_path // empty' <<<"$input")
[ -f "$transcript" ] || exit 0
models=$(jq -r 'select(.type == "assistant") | .message.model // empty' "$transcript" 2>/dev/null \
  | grep -v '^<synthetic>$' | awk '!seen[$0]++' | paste -sd, -)
[ -n "$models" ] || exit 0
msg="🤖 ${agent} → ${models}${effort:+ (effort: ${effort})}"
jq -n --arg m "$msg" '{systemMessage: $m}'
