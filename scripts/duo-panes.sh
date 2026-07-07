#!/usr/bin/env bash
# tmux-cockpit duo-panes — pick how many panes a duo launches with (2 or 3).
#   duo-panes.sh
#
# The launch-time override for @cockpit-duo-panes: a single-select fzf of the two
# supported topologies (2 side-by-side, or 3 = leader + 2 workers). Prints ONLY
# the chosen digit on stdout for duo.sh's --panes to consume; the label is display
# sugar, stripped before printing. Empty output -> the caller keeps the configured
# @cockpit-duo-panes default.
set -uo pipefail
# Resolve through symlinks so `lib.sh` is found even when this is invoked via a
# symlink on PATH (the `duo-*` install glob links it into ~/.local/bin). `readlink
# -f` isn't portable to old macOS, so walk the link chain by hand.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$dir/$SOURCE" ;; esac  # relative → absolute
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Pre-select the configured default so the picker opens on the current setting;
# validate to 2|3 (fall back 2) exactly as duo.sh does, so an odd option value
# can't preselect a phantom row.
default="$(_tm show-option -gqv @cockpit-duo-panes 2>/dev/null)"
case "$default" in 2|3) ;; *) default=2 ;; esac

# TEST-ONLY bypass: a fixed selection so tests need no tty/fzf. Gated on
# COCKPIT_SOCKET (tests always run on an isolated socket, real launches never set
# it) so a value left in a real shell can't silently override the picker. Strip
# any label the same way the fzf path does, so the bypass matches the real output.
if [ -n "${COCKPIT_DUO_PANES_PICK:-}" ] && [ -n "${COCKPIT_SOCKET:-}" ]; then
  printf '%s\n' "${COCKPIT_DUO_PANES_PICK%% *}"
  exit 0
fi

# Need the controlling terminal to draw the picker. Do NOT gate on stdout being a
# tty: the caller captures our stdout (`panes=$(duo-panes.sh)`), so stdout is a
# pipe by design. fzf renders on /dev/tty and writes only the selection to stdout,
# so gate on /dev/tty being usable. No terminal (headless) -> keep the default.
{ [ -r /dev/tty ] && [ -w /dev/tty ]; } || exit 0
command -v fzf >/dev/null 2>&1 || exit 0

# Two rows, readable labels but the digit leads so stripping the label yields just
# the number. --query seeds the current default so it's the highlighted row.
sel="$(printf '%s\n' '2  ·  side-by-side' '3  ·  leader + 2 workers' \
  | fzf --prompt='panes ❯ ' --height=40% --reverse --query="$default" --select-1)"

# Print only the leading digit (strip the label); empty selection -> print nothing
# so the caller keeps the configured default.
[ -z "$sel" ] && exit 0
printf '%s' "${sel%% *}"
