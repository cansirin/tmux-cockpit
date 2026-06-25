#!/usr/bin/env bash
# tmux-cockpit tmsg — send a one-shot line to another pane, in ONE call.
#   tmsg <pane> <message...>
#
# Wraps the two-step you do constantly when coordinating agents across panes —
#   tmux send-keys -t <pane> -l "<msg>"   # type it literally
#   tmux send-keys -t <pane> Enter        # submit it
# — into a single command, so you can't fumble the -l or forget the Enter.
# <pane> is any tmux target (e.g. %12, or session:win.pane). Everything after
# it is the message (joined with spaces); it is sent LITERALLY, then submitted.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

pane="${1:-}"
shift 2>/dev/null || true
if [ -z "$pane" ] || [ "$#" -eq 0 ]; then
  echo "usage: tmsg <pane> <message...>" >&2
  exit 2
fi

msg="$*"
_tm send-keys -t "$pane" -l "$msg"
_tm send-keys -t "$pane" Enter
