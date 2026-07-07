#!/usr/bin/env bash
# tmux-cockpit wt-new — create a git worktree for a NEW branch off a base.
#   wt-new <branch> [base]
#
# The worktree lands in a SIBLING of the repo: <repo>/../<repo-basename>-<branch>
# (branch slashes/spaces → '-'). Sibling, never nested, so it stays out of the
# repo's own status and file watchers. Base defaults to the repo's current branch,
# then main. Prints the created path. Composable on purpose — it does NOT open a
# tmux session; a caller can chain `wt-new … && sessionizer <path>`.
set -uo pipefail

branch="${1:-}"
base="${2:-}"
if [ -z "$branch" ]; then
  echo "usage: wt-new <branch> [base]" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "wt-new: not a git repo" >&2
  exit 1
fi

repo="$(git rev-parse --show-toplevel)"
parent="$(dirname "$repo")"
repo_base="$(basename "$repo")"

if [ -z "$base" ]; then
  base="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # A brand-new repo on an unborn branch reports HEAD; fall back to main.
  { [ -z "$base" ] || [ "$base" = "HEAD" ]; } && base="main"
fi

# Sanitize the branch for a filesystem path: any run of non [A-Za-z0-9._-] → '-'.
slug="$(printf '%s' "$branch" | tr -cs 'A-Za-z0-9._-' '-')"
path="$parent/$repo_base-$slug"

if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "wt-new: branch '$branch' already exists" >&2
  exit 1
fi
if [ -e "$path" ]; then
  echo "wt-new: target path already exists: $path" >&2
  exit 1
fi

git worktree add -b "$branch" "$path" "$base"
echo "$path"
