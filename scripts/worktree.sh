#!/usr/bin/env bash
# tmux-cockpit — create (or reuse) a git worktree, then open its cockpit session.
#
#   wt <name> [extra args…]
#
# Creation is DELEGATED to a `git wte` command if you have one (a richer worktree
# creator — copies gitignored env files, installs deps, runs repo setup); wt just
# adds the cockpit on top, and passes every extra arg straight through to it
# (e.g. wt feat/foo --from origin/main). Without `git wte`, wt falls back to a
# basic `git worktree add` as a sibling  <main-repo>-<name>.
#
# Env: WT_NO_OPEN=1 → only create + print the path (used by tests).
#      WT_NO_DELEGATE=1 → force the basic fallback even if `git wte` exists.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ $# -ge 1 ] || { echo "usage: wt <name> [args…]" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "wt: not inside a git repository" >&2; exit 1; }

_worktrees() { git worktree list --porcelain | sed -n 's/^worktree //p' | sort; }

has_wte() {
  [ -z "$WT_NO_DELEGATE" ] && {
    git config --get alias.wte >/dev/null 2>&1 || command -v git-wte >/dev/null 2>&1
  }
}

if has_wte; then
  # Delegate to `git wte` (streams its output live). Capture the new worktree by
  # diffing the worktree list around it — format-independent, no output parsing.
  before="$(_worktrees)"
  git wte "$@" || exit 1
  dir="$(comm -13 <(printf '%s\n' "$before") <(_worktrees) | tail -1)"
else
  # Basic fallback: sibling <main-repo>-<name>, new branch off HEAD.
  name="$1"
  common="$(git rev-parse --git-common-dir 2>/dev/null)"
  common="$(cd "$(dirname "$common")" && pwd -P)/$(basename "$common")"
  main_repo="$(dirname "$common")"
  dirslug="$(printf '%s' "$name" | tr '/ ' '-_')"
  dir="$(dirname "$main_repo")/$(basename "$main_repo")-${dirslug}"
  if [ ! -d "$dir" ]; then
    if git -C "$main_repo" show-ref --verify --quiet "refs/heads/$name"; then
      git -C "$main_repo" worktree add "$dir" "$name" || exit 1
    else
      git -C "$main_repo" worktree add -b "$name" "$dir" || exit 1
    fi
  fi
fi

[ -n "$dir" ] && [ -d "$dir" ] || { echo "wt: couldn't determine the worktree path" >&2; exit 1; }
[ -n "$WT_NO_OPEN" ] && { printf '%s\n' "$dir"; exit 0; }

# open (create-or-switch) its cockpit session
exec "$SCRIPT_DIR/sessionizer.sh" "$dir"
