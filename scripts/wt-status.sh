#!/usr/bin/env bash
# tmux-cockpit wt-status — classify git worktrees so stale ones get noticed.
#   wt-status [base-ref]
#
# For each worktree, prints whether its branch is fully MERGED into the base
# (safe to prune) or UNMERGED (still holds N commits). Base defaults to
# origin/main, then main, then the current branch. Run it from any worktree of
# the repo. Pruning stays manual — this just surfaces the candidates.
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "wt-status: not a git repo" >&2
  exit 1
fi

base="${1:-}"
if [ -z "$base" ]; then
  if git rev-parse --verify -q origin/main >/dev/null; then
    base="origin/main"
  elif git rev-parse --verify -q main >/dev/null; then
    base="main"
  else
    base="$(git rev-parse --abbrev-ref HEAD)"
  fi
fi
echo "# worktrees vs $base"

git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  br="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -z "$br" ] && continue
  if git merge-base --is-ancestor "$br" "$base" 2>/dev/null; then
    printf 'MERGED    %-32s %s\n' "$br" "$wt"
  else
    n="$(git rev-list --count "$base..$br" 2>/dev/null || echo '?')"
    printf 'UNMERGED  %-32s (+%s)  %s\n' "$br" "$n" "$wt"
  fi
done
