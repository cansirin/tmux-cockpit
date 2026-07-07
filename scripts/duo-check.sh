#!/usr/bin/env bash
# tmux-cockpit duo-check — read-only liveness check on this pane's siblings (§8).
#   duo-check
#
# tmux already tracks each pane's last-activity time, dead flag, and running
# command — so a stalled or silently-compacted sibling is visible for free, with
# no background heartbeat daemon. This reads that signal for every sibling and
# prints one line each: label, pane, seconds since last activity, and OK / STALL
# (silent past @cockpit-duo-stall-secs, default 300) / DEAD (the pane exited).
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
  echo "duo-check: no duo registry on this session (not launched by duo.sh?)" >&2
  exit 1
fi

threshold="$(cockpit_opt @cockpit-duo-stall-secs 300)"
# A non-numeric knob would crash the `-gt` comparison below with "integer
# expression expected" — fall back to the default rather than blow up.
case "$threshold" in *[!0-9]*|'') threshold=300 ;; esac
now="$(date +%s)"

i=1
while [ "$i" -le "$npanes" ]; do
  lbl="1.$i"
  if [ "$lbl" = "$label" ]; then i=$((i + 1)); continue; fi

  pane="$(_tm show-option -t "$sess" -qv "@$(cockpit_duo_pane_key "$lbl")" 2>/dev/null)"
  # One read, tab-separated so an empty command can't collapse the columns.
  # pane_activity is the free per-pane liveness epoch; on a detached server some
  # tmux builds leave it empty, so fall back to the window's activity epoch.
  info="$(_tm display-message -p -t "$pane" '#{pane_activity}	#{window_activity}	#{pane_dead}	#{pane_current_command}' 2>/dev/null)"
  if [ -z "$info" ]; then
    printf '%s\t%s\t-\t-\tGONE\n' "$lbl" "$pane"
    i=$((i + 1)); continue
  fi

  activity="${info%%	*}";       rest="${info#*	}"
  wactivity="${rest%%	*}";      rest="${rest#*	}"
  dead="${rest%%	*}";           cmd="${rest#*	}"
  [ -n "$activity" ] || activity="$wactivity"

  # A non-numeric/empty epoch means we can't age it — report '?' rather than a
  # bogus "silent since the epoch".
  case "$activity" in
    ''|*[!0-9]*) age="?" ;;
    *)           age="$((now - activity))" ;;
  esac

  if [ "$dead" = "1" ]; then
    status=DEAD
  elif [ "$age" = "?" ]; then
    status=OK
  elif [ "$age" -gt "$threshold" ]; then
    status=STALL
  else
    status=OK
  fi
  printf '%s\t%s\t%ss\t%s\t%s\n' "$lbl" "$pane" "$age" "$cmd" "$status"
  i=$((i + 1))
done
