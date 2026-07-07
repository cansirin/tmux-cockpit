#!/usr/bin/env bash
# tmux-cockpit duo-launch — pick startup layers (with a tty) then launch the duo.
#   duo-launch.sh [repo-dir]
#
# The tty half of the launch: the prefix+Space → D menu points a display-popup
# here so the layer picker has a real terminal (duo.sh runs headless on the
# server and can't prompt). Runs duo-layers.sh, exports the chosen layers, and
# hands off to duo.sh — which does the actual create/re-focus/switch-client.
# Zero layers -> the picker prints nothing and we launch a plain duo unchanged.
set -uo pipefail
# Resolve through symlinks so the sibling scripts are found even when this is
# invoked via a symlink on PATH (the `duo-*` install glob links it into
# ~/.local/bin). `readlink -f` isn't portable to old macOS, so walk by hand.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$dir/$SOURCE" ;; esac  # relative → absolute
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

target="${1:-$PWD}"

# Pane count first: the picker prints just a digit (2/3) on stdout, or nothing to
# keep the configured @cockpit-duo-panes default. Passed to duo.sh as --panes only
# when non-empty, so an empty pick leaves duo.sh's option-read path untouched.
panes="$("$SCRIPT_DIR/duo-panes.sh")"

# The picker prints the selection on stdout; capture it as the layer set. An
# empty selection (no layers exist, or none chosen) leaves COCKPIT_DUO_SELECTED
# empty, so duo.sh's brief is byte-for-byte the pre-layers brief.
COCKPIT_DUO_SELECTED="$("$SCRIPT_DIR/duo-layers.sh")"
export COCKPIT_DUO_SELECTED

# exec so duo.sh's focus() (switch-client/attach) runs as this popup's own
# process — a live client the switch can target — instead of an orphaned child.
# ${panes:+…} expands to nothing when empty; the digit is a single numeric token,
# so no quoting hazard.
exec "$SCRIPT_DIR/duo.sh" ${panes:+--panes "$panes"} "$target"
