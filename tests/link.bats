#!/usr/bin/env bats
# Tests for link.sh — symlinking is idempotent, obeys the glob convention, and
# never clobbers a real file. No tmux server needed: the bin dir is passed as $1.

# Normalized (no ../) so it matches the target link.sh writes, which it derives
# via `cd && pwd`.
SCRIPTS="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"

setup() {
  BIN="$BATS_TEST_TMPDIR/bin"
}

@test "links the wt-* scripts and tmsg, stripping the .sh" {
  run bash "$SCRIPTS/link.sh" "$BIN"
  [ "$status" -eq 0 ]
  [ -L "$BIN/wt-status" ]
  [ -L "$BIN/wt-prune" ]
  [ -L "$BIN/tmsg" ]
  # the symlink resolves to the absolute source script
  [ "$(readlink "$BIN/wt-status")" = "$SCRIPTS/wt-status.sh" ]
}

@test "does NOT link crew.sh (invoked by path, not a bare command)" {
  bash "$SCRIPTS/link.sh" "$BIN"
  [ ! -e "$BIN/crew" ]
}

@test "does NOT link lib.sh (not in the convention set)" {
  bash "$SCRIPTS/link.sh" "$BIN"
  [ ! -e "$BIN/lib" ]
}

@test "is idempotent — running twice leaves the same links" {
  bash "$SCRIPTS/link.sh" "$BIN"
  before="$(ls "$BIN" | sort)"
  run bash "$SCRIPTS/link.sh" "$BIN"
  [ "$status" -eq 0 ]
  after="$(ls "$BIN" | sort)"
  [ "$before" = "$after" ]
  [[ "$output" == *"ok "* ]]   # second pass reports the existing link as ok
}

@test "repoints a stale symlink to the correct source" {
  mkdir -p "$BIN"
  ln -s /somewhere/else/wt-status "$BIN/wt-status"
  bash "$SCRIPTS/link.sh" "$BIN"
  [ "$(readlink "$BIN/wt-status")" = "$SCRIPTS/wt-status.sh" ]
}

@test "refuses to clobber a real (non-symlink) file" {
  mkdir -p "$BIN"
  printf 'i am real\n' > "$BIN/tmsg"
  run bash "$SCRIPTS/link.sh" "$BIN"
  [ "$status" -eq 0 ]
  [ ! -L "$BIN/tmsg" ]                       # still a real file, not replaced
  [ "$(cat "$BIN/tmsg")" = "i am real" ]
  [[ "$output" == *"skip"* ]]
}

@test "creates the bin dir when missing" {
  deep="$BATS_TEST_TMPDIR/a/b/c/bin"
  run bash "$SCRIPTS/link.sh" "$deep"
  [ "$status" -eq 0 ]
  [ -d "$deep" ]
  [ -L "$deep/tmsg" ]
}
