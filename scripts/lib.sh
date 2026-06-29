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

# cockpit_duo_brief SELF SIBLING_LABEL SIBLING_PANE PROTOCOL -> the bootstrap
# prompt seeded into one duo pane: its label, how to reach its sibling, and the
# protocol to read. Pure string assembly (unit-tested); the caller send-keys it.
cockpit_duo_brief() {
  local self="$1" sib="$2" sibpane="$3" protocol="$4"
  printf '%s' "You are pane $self in a Claude duo. Read $protocol and follow it. \
Sibling: $sib at $sibpane — reach it with: tmux send-keys -t $sibpane -l \"$self: <msg>\" Enter. \
Default to subagents for all real work; your job is to orchestrate, not execute. \
Greet your sibling, then wait for the human."
}
