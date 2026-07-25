#!/usr/bin/env bash
# tmux-cockpit — render all sessions for the status bar.
#   active = filled chip   ·   background sessions = plain accent text
#
# The section is tinted with the [S] legend colour so it reads as one group.
# Contrast follows the terminal's theme, it isn't pinned against it:
#   - the accent defaults to a NAMED ansi slot, which the terminal resolves from
#     its active theme — so it flips with a light/dark theme switch, instead of
#     staying a fixed pastel that goes unreadable on a light background.
#   - the active session is a filled chip drawn with `reverse`, which swaps
#     fg/bg: an accent block whose letter is the terminal's own background
#     colour. Contrast is guaranteed without a second "ink" colour.
# WCAG 1.4.1 (not by hue alone): active = filled chip + bold; inactive = plain
# accent text — the chip vs no-chip is a structural difference, not just hue.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

accent="$(cockpit_opt @cockpit-color-sessions blue)"   # the [S] legend colour

_tm list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null | \
while read -r attached name; do
  if [ "${attached:-0}" -gt 0 ]; then
    printf '#[fg=%s,reverse,bold] %s #[default]  ' "$accent" "$name"
  else
    printf '#[fg=%s]%s#[default]  ' "$accent" "$name"
  fi
done
