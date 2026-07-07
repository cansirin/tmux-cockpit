#!/usr/bin/env bash
# tmux-cockpit duo-heartbeat — a pane signals it's alive (§8 of the protocol).
#   duo-heartbeat SELF SIBLING_PANE [STATE]
#
# Posts a timestamped heartbeat two ways so a stalled or *silently* compacted
# pane gets noticed and can self-revive: it appends the line to a durable notes
# file (survives a reset) and messages the sibling pane (may be delayed, so the
# file is the source of truth). STATE is a short current-status note; defaults
# to 'alive'. The notes file is @cockpit-duo-notes / $COCKPIT_DUO_NOTES, else
# duo-notes.md in the current repo.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

self="${1:?usage: duo-heartbeat SELF SIBLING_PANE [STATE]}"
sibpane="${2:?usage: duo-heartbeat SELF SIBLING_PANE [STATE]}"
state="${3:-alive}"

notes="${COCKPIT_DUO_NOTES:-$(cockpit_opt @cockpit-duo-notes "$PWD/duo-notes.md")}"
line="$(cockpit_duo_heartbeat "$self" "$state")"

printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$notes"

# Message the sibling — best-effort; a mid-turn pane sees it late, which is why
# the notes file above is the durable channel.
_tm send-keys -t "$sibpane" -l "$self: $line" 2>/dev/null \
  && _tm send-keys -t "$sibpane" Enter 2>/dev/null || true
