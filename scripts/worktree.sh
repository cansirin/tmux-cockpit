#!/usr/bin/env bash
# tmux-cockpit — create (or reuse) a git worktree for a feature branch as a
# sibling of the MAIN repo, then open its cockpit session.
#
#   wt <name> [base-ref]
#
# Works from the main clone or from any existing worktree — it always resolves
# the main repo, so the new worktree is named  <main-repo>-<name>  (e.g. from
# anywhere under .../monorepo*,  wt widget-fix → .../monorepo-widget-fix).
# Set WT_NO_OPEN=1 to only create + print the path (used by tests).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

name="$1"
base="$2"
if [ -z "$name" ]; then
  echo "usage: wt <name> [base-ref]" >&2
  exit 1
fi

# resolve the MAIN repo from wherever we are (main worktree or a linked one)
common="$(git rev-parse --git-common-dir 2>/dev/null)"
if [ -z "$common" ]; then
  echo "wt: not inside a git repository" >&2
  exit 1
fi
common="$(cd "$(dirname "$common")" && pwd -P)/$(basename "$common")"
main_repo="$(dirname "$common")"
main_base="$(basename "$main_repo")"
parent="$(dirname "$main_repo")"

dirslug="$(printf '%s' "$name" | tr '/ ' '-_')"   # slashes/spaces are unsafe in dir names
dir="$parent/${main_base}-${dirslug}"

if [ ! -d "$dir" ]; then
  if git -C "$main_repo" show-ref --verify --quiet "refs/heads/$name"; then
    git -C "$main_repo" worktree add "$dir" "$name" || exit 1          # existing branch
  elif [ -n "$base" ]; then
    git -C "$main_repo" worktree add -b "$name" "$dir" "$base" || exit 1
  else
    git -C "$main_repo" worktree add -b "$name" "$dir" || exit 1       # new branch off HEAD
  fi
fi

if [ -n "$WT_NO_OPEN" ]; then
  printf '%s\n' "$dir"
  exit 0
fi

# open (create-or-switch) its cockpit session
exec "$SCRIPT_DIR/sessionizer.sh" "$dir"
