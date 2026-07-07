#!/usr/bin/env bats
# Tests for wt-new.sh and wt-prune.sh against a REAL throwaway git repo built in
# $BATS_TEST_TMPDIR, so worktree add/remove exercise git for real.

SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

# A repo on `main` with one commit. Committer identity is set locally so the
# suite doesn't depend on the developer's global git config.
setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email cockpit@test
  git -C "$REPO" config user.name cockpit
  echo one > "$REPO/f"
  git -C "$REPO" add f
  git -C "$REPO" commit -qm init
}

# --- wt-new -----------------------------------------------------------------

@test "wt-new creates a sibling worktree on a new branch" {
  run bash -c "cd '$REPO' && '$SCRIPTS/wt-new.sh' feature-x"
  [ "$status" -eq 0 ]
  # git worktree add prints progress on stderr, which `run` merges in — the
  # created path is the script's final stdout line.
  path="${lines[${#lines[@]}-1]}"
  [ -d "$path" ]
  # sibling of the repo, not nested inside it. Resolve the toplevel the way the
  # script does (git canonicalizes /var -> /private/var on macOS).
  top="$(git -C "$REPO" rev-parse --show-toplevel)"
  [ "$(dirname "$path")" = "$(dirname "$top")" ]
  case "$path" in "$top"/*) false ;; *) true ;; esac
  [ "$(git -C "$path" rev-parse --abbrev-ref HEAD)" = "feature-x" ]
}

@test "wt-new sanitizes slashes in the branch for the path" {
  run bash -c "cd '$REPO' && '$SCRIPTS/wt-new.sh' can/foo"
  [ "$status" -eq 0 ]
  path="${lines[${#lines[@]}-1]}"
  [[ "$path" == *"repo-can-foo" ]]
  [ "$(git -C "$path" rev-parse --abbrev-ref HEAD)" = "can/foo" ]
}

@test "wt-new refuses a branch that already exists" {
  git -C "$REPO" branch dup
  run bash -c "cd '$REPO' && '$SCRIPTS/wt-new.sh' dup"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

# --- wt-prune ---------------------------------------------------------------

# Adds a `merged` worktree (branch folded back into main → prune candidate) and
# an `unmerged` worktree (one commit ahead → must be kept).
_two_worktrees() {
  git -C "$REPO" worktree add -q -b merged "$BATS_TEST_TMPDIR/merged" >/dev/null
  echo m > "$BATS_TEST_TMPDIR/merged/f2"
  git -C "$BATS_TEST_TMPDIR/merged" add f2
  git -C "$BATS_TEST_TMPDIR/merged" commit -qm merged-work
  git -C "$REPO" merge -q merged

  git -C "$REPO" worktree add -q -b unmerged "$BATS_TEST_TMPDIR/unmerged" >/dev/null
  echo u > "$BATS_TEST_TMPDIR/unmerged/f3"
  git -C "$BATS_TEST_TMPDIR/unmerged" add f3
  git -C "$BATS_TEST_TMPDIR/unmerged" commit -qm unmerged-work
}

@test "wt-prune dry-run lists only the merged worktree and removes nothing" {
  _two_worktrees
  run bash "$SCRIPTS/wt-prune.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"* ]]
  [[ "$output" == *"merged"* ]]
  [[ "$output" != *"would remove unmerged"* ]]
  # nothing actually gone
  [ -d "$BATS_TEST_TMPDIR/merged" ]
  [ -d "$BATS_TEST_TMPDIR/unmerged" ]
}

@test "wt-prune --force removes the merged worktree and keeps the unmerged one" {
  _two_worktrees
  run bash "$SCRIPTS/wt-prune.sh" --force "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed"* ]]
  [ ! -d "$BATS_TEST_TMPDIR/merged" ]
  [ -d "$BATS_TEST_TMPDIR/unmerged" ]
  # the merged branch is deleted; unmerged survives
  run git -C "$REPO" show-ref --verify --quiet refs/heads/merged
  [ "$status" -ne 0 ]
  git -C "$REPO" show-ref --verify --quiet refs/heads/unmerged
}

@test "wt-prune never removes a dirty merged worktree" {
  _two_worktrees
  echo dirty >> "$BATS_TEST_TMPDIR/merged/f"   # uncommitted change
  run bash "$SCRIPTS/wt-prune.sh" --force "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty"* ]]
  [ -d "$BATS_TEST_TMPDIR/merged" ]
}
