#!/usr/bin/env bash
# tmux-cockpit wt-prune — remove worktrees whose branch is fully MERGED into the
# base, then delete the merged branch and `git worktree prune`.
#   wt-prune [--force] [repo]
#
# The actionable other-half of the read-only wt-status: it reuses the same
# merge-base classification to pick candidates. DRY-RUN BY DEFAULT — without
# --force it prints exactly what it WOULD remove and changes nothing. It NEVER
# touches the main worktree, the worktree you're standing in, or a dirty one —
# each is skipped with a reason. Base defaults to origin/main, then main, then
# the current branch (same precedence as wt-status).
set -uo pipefail

force=0
repo=""
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    *)       repo="$arg" ;;
  esac
done

[ -n "$repo" ] && cd "$repo" 2>/dev/null || true
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "wt-prune: not a git repo" >&2
  exit 1
fi

if git rev-parse --verify -q origin/main >/dev/null; then
  base="origin/main"
elif git rev-parse --verify -q main >/dev/null; then
  base="main"
else
  base="$(git rev-parse --abbrev-ref HEAD)"
fi

# The main worktree holds the common git dir; never remove it. And never remove
# the worktree we're currently inside (git refuses, but we skip it cleanly).
main_wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
here="$(git rev-parse --show-toplevel)"

if [ "$force" -eq 1 ]; then
  echo "# pruning worktrees merged into $base"
else
  echo "# DRY RUN — worktrees merged into $base (pass --force to remove)"
fi

git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  br="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -z "$br" ] && continue

  # Only merged branches are candidates — the wt-status MERGED test, verbatim.
  git merge-base --is-ancestor "$br" "$base" 2>/dev/null || continue

  if [ "$wt" = "$main_wt" ]; then
    printf 'skip     %-28s main worktree\n' "$br"; continue
  fi
  if [ "$wt" = "$here" ]; then
    printf 'skip     %-28s current worktree\n' "$br"; continue
  fi
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    printf 'skip     %-28s dirty (uncommitted changes)\n' "$br"; continue
  fi

  if [ "$force" -eq 1 ]; then
    if git worktree remove "$wt" 2>/dev/null; then
      git branch -d "$br" >/dev/null 2>&1 || git branch -D "$br" >/dev/null 2>&1 || true
      printf 'removed  %-28s %s\n' "$br" "$wt"
    else
      printf 'skip     %-28s could not remove (%s)\n' "$br" "$wt"
    fi
  else
    printf 'would remove %-28s %s\n' "$br" "$wt"
  fi
done

[ "$force" -eq 1 ] && git worktree prune
exit 0
