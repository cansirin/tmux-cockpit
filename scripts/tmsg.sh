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

# A duo label (1.2) is resolved through this session's registry to a pane id;
# any other target (%12, session:win.pane) is passed to tmux untouched.
if [[ "$pane" =~ ^1\.[0-9]+$ ]]; then
  # Resolve the label off THIS pane's session ($TMUX_PANE identifies it robustly).
  sess="$(_tm display-message -t "${TMUX_PANE:-}" -p '#{session_name}' 2>/dev/null)"
  resolved="$(_tm show-option -t "$sess" -qv "@$(cockpit_duo_pane_key "$pane")" 2>/dev/null)"
  [ -n "$resolved" ] && pane="$resolved"
fi

_tm send-keys -t "$pane" -l "$msg"
_tm send-keys -t "$pane" Enter
