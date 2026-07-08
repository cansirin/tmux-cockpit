#!/usr/bin/env bash
# tmux-cockpit crew-seed — deferred spawn-prompt seeding for a crew, run on the
# tmux SERVER.
#   crew-seed.sh <briefs-file> <boot-wait>
#
# crew.sh dispatches this via `run-shell -b` instead of a plain `&` background job.
# Why: launched from the prefix+Space menu, crew.sh runs inside a display-popup,
# and a backgrounded shell job is torn down when the popup closes (before the
# boot-wait elapses) — so the prompt would never reach the window. A server-side
# run-shell job outlives the popup. Waits for the per-window command to boot, then
# types each window its prompt. <briefs-file> holds one line per window:
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

briefs="${1:?usage: crew-seed.sh <briefs-file> <boot-wait>}"
boot_wait="${2:-6}"

sleep "$boot_wait"

tab="$(printf '\t')"
while IFS="$tab" read -r pane brief; do
  [ -n "$pane" ] || continue
  _tm send-keys -t "$pane" -l "$brief"
  _tm send-keys -t "$pane" Enter
done < "$briefs"

rm -f "$briefs"
