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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

target="${1:-$PWD}"

# The picker prints the selection on stdout; capture it as the layer set. An
# empty selection (no layers exist, or none chosen) leaves COCKPIT_DUO_SELECTED
# empty, so duo.sh's brief is byte-for-byte the pre-layers brief.
COCKPIT_DUO_SELECTED="$("$SCRIPT_DIR/duo-layers.sh")"
export COCKPIT_DUO_SELECTED

# exec so duo.sh's focus() (switch-client/attach) runs as this popup's own
# process — a live client the switch can target — instead of an orphaned child.
exec "$SCRIPT_DIR/duo.sh" "$target"
