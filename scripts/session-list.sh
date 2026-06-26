#!/usr/bin/env bash
# tmux-cockpit — render all sessions for the status bar.
#   active = filled chip   ·   background sessions = plain accent text
#
# The section is tinted with the [S] legend colour so it reads as one group.
# Contrast is controlled, not left to chance:
#   - the accent is a fixed 256-palette colour (NOT a 0–15 slot, which themes
#     remap — that trap once rendered a `fg=black` chip slate-on-teal), and the
#     status bar bg is pinned dark, so the accent-on-bar stays legible.
#   - the active session is a filled chip: dark ink (colour235) on the accent,
#     so its contrast is guaranteed regardless of the bar bg, identical to the
#     [S] tag chip.
# WCAG 1.4.1 (not by hue alone): active = filled chip + bold; inactive = plain
# accent text — the chip vs no-chip is a structural difference, not just hue.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

accent=colour111   # the [S] legend colour — keep in sync with the S tag in cockpit.tmux

_tm list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null | \
while read -r attached name; do
  if [ "${attached:-0}" -gt 0 ]; then
    printf '#[fg=colour235,bg=%s,bold] %s #[default]  ' "$accent" "$name"
  else
    printf '#[fg=%s]%s#[default]  ' "$accent" "$name"
  fi
done
