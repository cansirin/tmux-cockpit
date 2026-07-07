#!/usr/bin/env bash
# tmux-cockpit duo-seed — deferred brief seeding for a duo, run on the tmux SERVER.
#   duo-seed.sh <briefs-file> <boot-wait>
#
# duo.sh dispatches this via `run-shell -b` instead of a plain `&` background job.
# Why: launched from the prefix+Space menu, duo.sh runs inside a display-popup,
# and a backgrounded shell job is torn down when the popup closes (before the
# boot-wait elapses) — so the brief would never reach the pane. A server-side
# run-shell job outlives the popup. Waits for the per-pane command to boot, then
# types each pane its brief. <briefs-file> holds one line per pane:
# "<pane-id><TAB><brief>" (briefs are single-line, so a tab split is safe).
set -uo pipefail
# Resolve through symlinks so lib.sh is found even via a ~/.local/bin symlink.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$dir/$SOURCE" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

briefs="${1:?usage: duo-seed.sh <briefs-file> <boot-wait>}"
boot_wait="${2:-6}"

sleep "$boot_wait"

tab="$(printf '\t')"
while IFS="$tab" read -r pane brief; do
  [ -n "$pane" ] || continue
  _tm send-keys -t "$pane" -l "$brief"
  _tm send-keys -t "$pane" Enter
done < "$briefs"

rm -f "$briefs"
