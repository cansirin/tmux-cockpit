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

# cockpit_session_name PATH -> a unique, tmux-safe session name.
# Folders named monorepo* collide across projects (csirin/monorepo vs
# Binclusive/monorepo), so prefix those with their parent dir; everything else
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
