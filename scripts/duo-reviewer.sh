#!/usr/bin/env bash
# tmux-cockpit duo-reviewer — print just this pane's §4 review-ring slice.
#   duo-reviewer
#
# The one-line answer to "who reviews me, whom do I review": your assigned
# reviewer and your review target, computed from the directed ring. A thin cut of
# duo-whoami for when that's all you need.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# $TMUX_PANE is the pane this process runs in — the trusted identity even when
# it isn't the client's active pane (a display-message with no -t would guess).
me="${TMUX_PANE:-$(_tm display-message -p '#{pane_id}' 2>/dev/null)}"
sess="$(_tm display-message -t "$me" -p '#{session_name}' 2>/dev/null)"
label="$(_tm show-option -p -t "$me" -qv @cockpit-duo-label 2>/dev/null)"
npanes="$(_tm show-option -t "$sess" -qv @cockpit-duo-npanes 2>/dev/null)"

if [ -z "$label" ] || [ -z "$npanes" ]; then
  echo "duo-reviewer: no duo registry on this session (not launched by duo.sh?)" >&2
  exit 1
fi

printf 'you are reviewed by %s; you review %s\n' \
  "$(cockpit_duo_reviewed_by "$label" "$npanes")" \
  "$(cockpit_duo_reviews "$label" "$npanes")"
