#!/usr/bin/env bash
# tmux-cockpit — render all sessions for the status bar.
#   ● (cyan) = attached / current     ○ (grey) = running in background
tmux list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null | \
while read -r attached name; do
  if [ "${attached:-0}" -gt 0 ]; then
    printf '#[fg=cyan,bold]●%s #[default]' "$name"
  else
    printf '#[fg=colour244]○%s #[default]' "$name"
  fi
done
