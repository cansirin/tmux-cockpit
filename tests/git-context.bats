#!/usr/bin/env bats
# [G] git-context tests. Isolated tmux socket (cockpit_opt reads colour options
# off it) + throwaway git repos in BATS_TEST_TMPDIR.

export COCKPIT_SOCKET="cockpit_git_test_$$"
SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

setup() {
  tmux -L "$COCKPIT_SOCKET" -f /dev/null new-session -d -s base -x 200 -y 50
}

teardown() {
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
}

# a committed repo on branch <name> at <dir>
_mkrepo() {
  git -C "$1" init -q -b "$2"
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

@test "git-context is empty outside a work tree" {
  run bash "$SCRIPTS/git-context.sh" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git-context shows the branch inside a repo" {
  r="$BATS_TEST_TMPDIR/repo"; mkdir -p "$r"
  _mkrepo "$r" trunk
  run bash "$SCRIPTS/git-context.sh" "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *trunk* ]]
  [[ "$output" == *"#["* ]]   # the [G] chip is styled
}

@test "git-context flags a dirty work tree" {
  r="$BATS_TEST_TMPDIR/dirty"; mkdir -p "$r"
  _mkrepo "$r" trunk
  touch "$r/newfile"
  run bash "$SCRIPTS/git-context.sh" "$r"
  [[ "$output" == *"*1"* ]]   # one dirty (untracked) file
}

@test "git-context honors @cockpit-color-git" {
  r="$BATS_TEST_TMPDIR/colored"; mkdir -p "$r"
  _mkrepo "$r" trunk
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-git colour99
  run bash "$SCRIPTS/git-context.sh" "$r"
  [[ "$output" == *"colour99"* ]]
}
