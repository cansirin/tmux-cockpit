#!/usr/bin/env bash
# tmux-cockpit tmsg — send a one-shot line to another pane, in ONE call.
#   tmsg <pane> <message...>
#
# Wraps the two-step you do constantly when coordinating agents across windows —
#   tmux send-keys -t <target> -l "<msg>"   # type it literally
#   tmux send-keys -t <target> Enter        # submit it
# — into a single command, so you can't fumble the -l or forget the Enter.
# <pane> is any tmux target (e.g. %12, or session:win) — the crew addresses its
# windows by the real session name (e.g. `<repo>-crew:em`). Everything after it is
# the message (joined with spaces); it is sent LITERALLY, then submitted.
# Resolve through symlinks so `lib.sh` is found even when tmsg is invoked via a
# symlink on PATH (e.g. ~/.local/bin/tmsg). `readlink -f` isn't portable to old
# macOS, so walk the link chain by hand.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$dir/$SOURCE" ;; esac  # relative → absolute
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

pane="${1:-}"
shift 2>/dev/null || true
if [ -z "$pane" ] || [ "$#" -eq 0 ]; then
  echo "usage: tmsg <pane> <message...>" >&2
  exit 2
fi

msg="$*"

_tm send-keys -t "$pane" -l -- "$msg"
_tm send-keys -t "$pane" Enter
