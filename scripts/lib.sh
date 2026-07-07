#!/usr/bin/env bash
# tmux-cockpit shared helpers — sourced by the other scripts, unit-tested in tests/.

# _tm [...] — run tmux, honoring an optional isolated socket so tests never touch
# the user's real server. Set COCKPIT_SOCKET to use `tmux -L <socket>`.
_tm() {
  if [ -n "${COCKPIT_SOCKET:-}" ]; then
    tmux -L "$COCKPIT_SOCKET" "$@"
  else
    tmux "$@"
  fi
}

# cockpit_opt @option DEFAULT -> the global option's value, or DEFAULT when it is
# unset or empty. The single source of truth for a tunable, so cockpit.tmux and
# the render scripts read the same value (and the same default) for a given knob.
cockpit_opt() {
  local v
  v="$(_tm show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${v:-$2}"
}

# cockpit_session_name PATH -> a unique, tmux-safe session name.
# Folders named monorepo* collide across projects (acme/monorepo vs
# globex/monorepo), so prefix those with their parent dir; everything else
# keeps its basename. ' ' '.' ':' are replaced with '_'.
cockpit_session_name() {
  local path="$1" base name
  base="$(basename "$path")"
  case "$base" in
    monorepo*) name="$(basename "$(dirname "$path")")-$base" ;;
    *)         name="$base" ;;
  esac
  printf '%s' "$name" | tr ' .:' '___'
}

# cockpit_duo_name PATH -> the session name for a two-pane Claude "duo" on PATH.
# A "-duo" suffix on the normal session name, so a duo never collides with the
# project's regular cockpit session.
cockpit_duo_name() {
  printf '%s-duo' "$(cockpit_session_name "$1")"
}

# cockpit_duo_brief SELF PROTOCOL  SIB_LABEL SIB_PANE [SIB_LABEL SIB_PANE ...]
#   -> the bootstrap prompt seeded into one duo pane: its label, its role (1.1
#   leads and coordinates; the others execute and review), how to reach each
#   sibling, and the protocol to read. Variadic in the sibling pairs so a
#   three-pane duo works (a pane then has two siblings). Pure string assembly
#   (unit-tested); the caller send-keys it.
cockpit_duo_brief() {
  local self="$1" protocol="$2" role reach=""
  shift 2
  case "$self" in
    1.1) role="You are the leader: track the work pipeline, split it into lanes, and delegate. Stay on the shared base and keep your tree clean." ;;
    *)   role="You execute and review: take a lane, do the work in its own worktree, and review your siblings' changes." ;;
  esac
  while [ "$#" -ge 2 ]; do
    reach="$reach Sibling: $1 at $2 — reach it with: tmux send-keys -t $2 -l \"$self: <msg>\" Enter."
    shift 2
  done
  printf '%s' "You are pane $self in a Claude duo. Read $protocol and follow it. \
$role$reach \
Default to subagents in worktrees for all real work; orchestrate, not execute. \
Leave durable notes on the issue/PR or a handoff file so you can revive yourself after a compaction. \
Greet your sibling, then wait for the human."
}

# cockpit_duo_heartbeat SELF STATE -> a one-line heartbeat a pane posts so a
# stalled or silently-compacted sibling gets noticed (§8 of the protocol). The
# timestamp is prepended by the caller (kept out so the line is unit-testable).
cockpit_duo_heartbeat() {
  printf 'heartbeat %s: %s' "$1" "${2:-alive}"
}
