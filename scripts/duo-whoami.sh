#!/usr/bin/env bash
# tmux-cockpit duo-whoami — re-locate this pane in the duo from the tmux registry.
#   duo-whoami
#
# What a pane runs to re-orient itself, especially post-compaction: it prints its
# own label, the pane count, every sibling's label + pane id, its assigned
# reviewer and who it reviews (the §4 ring slice), and the durable notes path.
# Reads only the identity registry duo.sh stamped at launch — no chat, no guessing.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# $TMUX_PANE is the pane this process runs in — the trusted identity even when
# it isn't the client's active pane (a display-message with no -t would guess).
me="${TMUX_PANE:-$(_tm display-message -p '#{pane_id}' 2>/dev/null)}"
sess="$(_tm display-message -t "$me" -p '#{session_name}' 2>/dev/null)"

# The pane-local label survives claude's OSC title clobber, so it's the trusted
# source for "who am I" even after a compaction.
label="$(_tm show-option -p -t "$me" -qv @cockpit-duo-label 2>/dev/null)"
npanes="$(_tm show-option -t "$sess" -qv @cockpit-duo-npanes 2>/dev/null)"

if [ -z "$label" ] || [ -z "$npanes" ]; then
  echo "duo-whoami: no duo registry on this session (not launched by duo.sh?)" >&2
  exit 1
fi

notes="${COCKPIT_DUO_NOTES:-$(cockpit_opt @cockpit-duo-notes "$PWD/duo-notes.md")}"

printf 'You are %s of %s panes (session %s, pane %s).\n' "$label" "$npanes" "$sess" "$me"

printf 'Panes:\n'
i=1
while [ "$i" -le "$npanes" ]; do
  lbl="1.$i"
  pane="$(_tm show-option -t "$sess" -qv "@$(cockpit_duo_pane_key "$lbl")" 2>/dev/null)"
  if [ "$lbl" = "$label" ]; then
    printf -- '  %s %s (you)\n' "$lbl" "$pane"
  else
    printf -- '  %s %s\n' "$lbl" "$pane"
  fi
  i=$((i + 1))
done

printf 'Review ring: you are reviewed by %s; you review %s.\n' \
  "$(cockpit_duo_reviewed_by "$label" "$npanes")" \
  "$(cockpit_duo_reviews "$label" "$npanes")"
printf 'Notes file: %s\n' "$notes"
