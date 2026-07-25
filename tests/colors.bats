#!/usr/bin/env bats
# Theme-aware default colour tests. The DEFAULTS must stay NAMED ansi slots, which
# the terminal resolves from its active theme, so cockpit's accents follow a
# light/dark flip. A fixed colour<N> default cannot — on a light theme the pastel
# 256-palette accents cockpit used to ship became unreadable as foreground text.
# These lock the defaults in place so nobody silently re-pins a fixed value.
# Isolated tmux socket (COCKPIT_SOCKET) + -f /dev/null → no user config, so the
# scripts really do fall through to their built-in defaults.

export COCKPIT_SOCKET="cockpit_colors_test_$$"
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

@test "session-list defaults to the named 'blue' slot, not a fixed colour<N>" {
  run bash "$SCRIPTS/session-list.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg=blue"* ]]
  [[ ! "$output" =~ colour[0-9] ]]
}

@test "git-context defaults to the named 'magenta' slot, not a fixed colour<N>" {
  r="$BATS_TEST_TMPDIR/repo"; mkdir -p "$r"
  _mkrepo "$r" trunk
  run bash "$SCRIPTS/git-context.sh" "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg=magenta"* ]]
  [[ ! "$output" =~ colour[0-9] ]]
}

@test "topbar defaults to the named 'green' slot, not a fixed colour<N>" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "ship the PR"
  run bash "$SCRIPTS/topbar.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg=green"* ]]
  [[ ! "$output" =~ colour[0-9] ]]
}

@test "the [S] and [R] tag chips use reverse video, with no fixed ink colour" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-left
  [[ "$output" == *"fg=blue,reverse,bold"* ]]
  [[ ! "$output" =~ colour[0-9] ]]

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "ship it"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv 'status-format[1]'
  [[ "$output" == *"fg=green,reverse,bold"* ]]
  [[ ! "$output" =~ colour[0-9] ]]
}

@test "the git chip uses reverse video, with no fixed ink colour" {
  r="$BATS_TEST_TMPDIR/chip"; mkdir -p "$r"
  _mkrepo "$r" trunk
  run bash "$SCRIPTS/git-context.sh" "$r"
  [[ "$output" == *"fg=magenta,reverse,bold"* ]]
}

@test "the accents are still pinnable to a fixed colour" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-sessions colour111
  run bash "$SCRIPTS/session-list.sh"
  [[ "$output" == *"fg=colour111"* ]]
}
