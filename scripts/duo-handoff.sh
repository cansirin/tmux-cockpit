#!/usr/bin/env bash
# tmux-cockpit duo-handoff — print a re-orientation brief for the current repo.
#   duo-handoff [repo-dir]
#
# Run before a context reset / handoff so the next agent (or your sibling pane)
# re-orients fast. Emits the five things you'd otherwise gather by hand: branch
# + HEAD state, recent commits, open PRs, and worktrees. Pipe to a file if you
# like:  duo-handoff > HANDOFF.md
set -uo pipefail

repo="${1:-$PWD}"
if ! cd "$repo" 2>/dev/null; then
  echo "duo-handoff: not a directory: $repo" >&2
  exit 1
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "duo-handoff: not a git repo: $repo" >&2
  exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
head="$(git rev-parse --short HEAD)"
dirty="$(git status --porcelain | wc -l | tr -d ' ')"

printf '# Handoff — %s @ %s\n\n' "$(basename "$repo")" "$branch"

printf '## State\n'
printf -- '- HEAD: %s — %s\n' "$head" "$(git log -1 --pretty=%s)"
printf -- '- working tree: %s uncommitted change(s)\n\n' "$dirty"

printf '## Recent commits\n'
git log --oneline -8 | sed 's/^/- /'
printf '\n'

printf '## Open PRs\n'
if command -v gh >/dev/null 2>&1; then
  gh pr list --state open --limit 20 \
     --json number,title,headRefName \
     --jq '.[] | "- #\(.number) [\(.headRefName)] \(.title)"' 2>/dev/null \
     || printf -- '- (gh unavailable or not authenticated)\n'
else
  printf -- '- (gh not installed)\n'
fi
printf '\n'

printf '## Worktrees\n'
git worktree list | sed 's/^/- /'
