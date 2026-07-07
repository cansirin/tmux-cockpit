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
#   @cockpit-duo-panes       how many panes: 2 (default) or 3 — 1.1 leads, the rest execute
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

# How many panes: 2 (default) or 3 — 1.1 leads, the rest execute + review. The
# protocol caps a duo at three; anything else falls back to 2.
npanes="$(_tm show-option -gqv @cockpit-duo-panes 2>/dev/null)"
case "$npanes" in 2|3) ;; *) npanes=2 ;; esac

# Side-by-side panes, all in the repo (one new-session + npanes-1 splits).
_tm new-session -ds "$name" -c "$target"
i=1
while [ "$i" -lt "$npanes" ]; do
  _tm split-window -h -t "$name" -c "$target"
  i=$((i + 1))
done
_tm select-layout -t "$name" even-horizontal

# Pane ids in creation order (bash 3.2-safe — no mapfile/arrays needed).
panes="$(_tm list-panes -t "$name" -F '#{pane_id}')"

# Label each pane 1.<n> on its border (scoped to this session) and boot the
# command in it — so you always know which pane is which and that a duo is live.
i=1
while [ "$i" -le "$npanes" ]; do
  pane="$(printf '%s\n' "$panes" | sed -n "${i}p")"
  _tm select-pane -t "$pane" -T "1.$i"
  _tm send-keys -t "$pane" "$cmd" Enter
  i=$((i + 1))
done
_tm set -t "$name" pane-border-status top
_tm set -t "$name" pane-border-format " duo #{pane_title} "

# duo_siblings SELF_INDEX -> "1.<j> <pane-j> ..." for every pane but SELF_INDEX,
# the variadic sibling pairs cockpit_duo_brief expects.
duo_siblings() {
  local self="$1" j=1 out=""
  while [ "$j" -le "$npanes" ]; do
    if [ "$j" -ne "$self" ]; then
      out="$out 1.$j $(printf '%s\n' "$panes" | sed -n "${j}p")"
    fi
    j=$((j + 1))
  done
  printf '%s' "$out"
}

# Seed the briefs once the command has booted. BACKGROUNDED so we never block
# the caller — when launched from the prefix+Space menu (a run-shell), a
# foreground sleep would freeze tmux for the whole boot wait. Sent literally
# (-l) so nothing mangles the text; submitted with a separate Enter.
{
  sleep "$boot_wait"
  i=1
  while [ "$i" -le "$npanes" ]; do
    pane="$(printf '%s\n' "$panes" | sed -n "${i}p")"
    # shellcheck disable=SC2046  # word-splitting the sibling pairs is intentional
    _tm send-keys -t "$pane" -l "$(cockpit_duo_brief "1.$i" "$protocol" $(duo_siblings "$i"))"
    _tm send-keys -t "$pane" Enter
    i=$((i + 1))
  done
} >/dev/null 2>&1 &

focus
