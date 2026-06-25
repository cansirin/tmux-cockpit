#!/usr/bin/env bash
# tmux-cockpit duo — launch a two-pane coordinated Claude "duo" in a repo.
# Bound in the prefix+Space menu; pass a path as $1 (defaults to the current
# pane's path). Two side-by-side panes each run @cockpit-main-cmd (default
# 'claude'), pre-seeded with a bootstrap brief: their label (1.1 / 1.2), their
# sibling's pane id, and a pointer to the duo protocol so they self-coordinate.
#
# Options (set in ~/.tmux.conf):
#   @cockpit-main-cmd        command per pane (default 'claude' — shared with cockpits)
#   @cockpit-duo-protocol    path to the working-agreement doc (default: shipped duo-protocol.md)
#   @cockpit-duo-boot-wait   seconds to let the command boot before seeding the brief (default 6)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

target="${1:-$PWD}"
if ! target="$(cd "$target" 2>/dev/null && pwd)"; then
  echo "duo: not a directory: ${1:-$PWD}" >&2
  exit 1
fi

name="$(cockpit_duo_name "$target")"

cmd="$(_tm show-option -gqv @cockpit-main-cmd 2>/dev/null)"
[ -z "$cmd" ] && cmd="claude"

protocol="$(_tm show-option -gqv @cockpit-duo-protocol 2>/dev/null)"
protocol="${protocol/#\~/$HOME}"
[ -z "$protocol" ] && protocol="$SCRIPT_DIR/../duo-protocol.md"

boot_wait="$(_tm show-option -gqv @cockpit-duo-boot-wait 2>/dev/null)"
[ -z "$boot_wait" ] && boot_wait=6

# Focus the session if it already exists — never spin up a second.
focus() {
  if [ -z "${TMUX:-}" ] && [ -t 1 ]; then
    _tm attach -t "$name"
  else
    _tm switch-client -t "$name" 2>/dev/null \
      || echo "duo: '$name' is ready — switch with: tmux switch-client -t $name"
  fi
}
if _tm has-session -t="$name" 2>/dev/null; then
  focus
  exit 0
fi

# Two side-by-side panes, both in the repo.
_tm new-session -ds "$name" -c "$target"
_tm split-window -h -t "$name" -c "$target"
_tm select-layout -t "$name" even-horizontal

# Pane ids in order (bash 3.2-safe — no mapfile).
panes="$(_tm list-panes -t "$name" -F '#{pane_id}')"
p1="$(printf '%s\n' "$panes" | sed -n '1p')"
p2="$(printf '%s\n' "$panes" | sed -n '2p')"

# Label the panes 1.1 / 1.2 on their borders, scoped to this session — so you
# always know which pane is which and that a duo is live. Other sessions are
# untouched (these are session-level options).
_tm select-pane -t "$p1" -T "1.1"
_tm select-pane -t "$p2" -T "1.2"
_tm set -t "$name" pane-border-status top
_tm set -t "$name" pane-border-format " duo #{pane_title} "

# Start the command in each pane.
_tm send-keys -t "$p1" "$cmd" Enter
_tm send-keys -t "$p2" "$cmd" Enter

# Seed the briefs once the command has booted. BACKGROUNDED so we never block
# the caller — when launched from the prefix+Space menu (a run-shell), a
# foreground sleep would freeze tmux for the whole boot wait. Sent literally
# (-l) so nothing mangles the text; submitted with a separate Enter.
{
  sleep "$boot_wait"
  _tm send-keys -t "$p1" -l "$(cockpit_duo_brief 1.1 1.2 "$p2" "$protocol")"
  _tm send-keys -t "$p1" Enter
  _tm send-keys -t "$p2" -l "$(cockpit_duo_brief 1.2 1.1 "$p1" "$protocol")"
  _tm send-keys -t "$p2" Enter
} >/dev/null 2>&1 &

focus
