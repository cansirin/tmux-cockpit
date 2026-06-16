#!/usr/bin/env bats
# Integration tests. Everything runs on an isolated tmux socket (COCKPIT_SOCKET)
# so a developer's real sessions are never touched.

export COCKPIT_SOCKET="cockpit_test_$$"
SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

setup() {
  tmux -L "$COCKPIT_SOCKET" new-session -d -s base -x 200 -y 50
}

teardown() {
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
}

@test "session-list shows every session with a marker" {
  tmux -L "$COCKPIT_SOCKET" new-session -d -s alpha
  run bash "$SCRIPTS/session-list.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *base* ]]
  [[ "$output" == *alpha* ]]
  [[ "$output" == *"●"* || "$output" == *"○"* ]]
}

@test "default layout builds a 4-pane cockpit" {
  tmux -L "$COCKPIT_SOCKET" new-session -d -s cockpit -c "$HOME"
  bash "$SCRIPTS/layout-default.sh" cockpit "$HOME" ""
  run tmux -L "$COCKPIT_SOCKET" list-panes -t cockpit
  [ "${#lines[@]}" -eq 4 ]
}

@test "layout runs the main-pane command when one is given" {
  tmux -L "$COCKPIT_SOCKET" new-session -d -s withcmd -c "$HOME"
  bash "$SCRIPTS/layout-default.sh" withcmd "$HOME" "echo hello-cockpit"
  sleep 0.5
  run tmux -L "$COCKPIT_SOCKET" capture-pane -t withcmd.1 -p
  [[ "$output" == *hello-cockpit* ]]
}

@test "sessionizer creates a session from a path argument" {
  proj="$BATS_TEST_TMPDIR/myproj"
  mkdir -p "$proj"
  # TMUX set (to a dummy) forces the non-blocking switch-client branch, not attach
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" has-session -t myproj
  [ "$status" -eq 0 ]
}
