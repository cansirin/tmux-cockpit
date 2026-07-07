#!/usr/bin/env bash
# tmux-cockpit duo-revive — reconstruct a cold pane after a compaction (§8).
#   duo-revive
#
# Pure composition of the pieces a revived pane needs, in order: who it is in the
# duo (duo-whoami), the tail of the durable notes file, the repo handoff brief
# (duo-handoff — HEAD/commits/PRs/worktrees), and the raw worktree list. Each
# piece is best-effort: a missing notes file or a non-repo dir degrades to a note,
# never a hard stop, so a partly-set-up duo still revives what it can.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

section() { printf '\n===== %s =====\n' "$1"; }

section "WHO AM I"
"$SCRIPT_DIR/duo-whoami.sh" || echo "(duo-whoami unavailable)"

notes="${COCKPIT_DUO_NOTES:-$(cockpit_opt @cockpit-duo-notes "$PWD/duo-notes.md")}"
section "NOTES ($notes)"
if [ -f "$notes" ]; then
  tail -n 40 "$notes"
else
  echo "(no notes file yet at $notes)"
fi

section "HANDOFF"
"$SCRIPT_DIR/duo-handoff.sh" 2>&1 || echo "(duo-handoff unavailable — not a git repo?)"

section "WORKTREES"
git worktree list 2>/dev/null || echo "(git worktree list unavailable — not a git repo?)"
