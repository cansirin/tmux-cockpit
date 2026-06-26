#!/usr/bin/env bats
# Integration tests. Everything runs on an isolated tmux socket (COCKPIT_SOCKET)
# so a developer's real sessions are never touched.

export COCKPIT_SOCKET="cockpit_test_$$"
SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

setup() {
  # -f /dev/null → start the server with NO user config, so base-index is the
  # default 0 (matches a fresh install / CI). This guards against assuming the
  # developer's own base-index 1.
  tmux -L "$COCKPIT_SOCKET" -f /dev/null new-session -d -s base -x 200 -y 50
}

teardown() {
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
}

@test "session-list renders every session, styled" {
  tmux -L "$COCKPIT_SOCKET" new-session -d -s alpha
  run bash "$SCRIPTS/session-list.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *base* ]]
  [[ "$output" == *alpha* ]]
  [[ "$output" == *"#["* ]]   # rendered with tmux style tags (the [S] accent)
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
  # capture the main pane by id (index-agnostic)
  main="$(tmux -L "$COCKPIT_SOCKET" list-panes -t withcmd -F '#{pane_id}' | head -1)"
  run tmux -L "$COCKPIT_SOCKET" capture-pane -t "$main" -p
  [[ "$output" == *hello-cockpit* ]]
}

@test "menu has the full default entries and honors @cockpit-menu-extra" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-menu-extra '"hello extra" H "display hi"'
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" list-keys -T prefix
  [[ "$output" == *"rename window"* ]]   # a restored default entry
  [[ "$output" == *"reload config"* ]]   # another restored default entry
  [[ "$output" == *"launch DUO here"* ]] # the built-in duo launcher entry
  [[ "$output" == *"edit reminders"* ]]  # the reminders editor entry
  [[ "$output" == *"hello extra"* ]]     # the user-supplied extra entry
}

@test "duo launches a two-pane session in the given repo" {
  proj="$BATS_TEST_TMPDIR/duoproj"
  mkdir -p "$proj"
  # harmless per-pane command + no boot wait, so the test doesn't launch claude
  # or block; TMUX set (dummy) forces the non-blocking switch-client branch.
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-duo-boot-wait 0
  TMUX="fake" bash "$SCRIPTS/duo.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" list-panes -t duoproj-duo
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  # panes are labeled 1.1 / 1.2 on their borders
  run tmux -L "$COCKPIT_SOCKET" list-panes -t duoproj-duo -F '#{pane_title}'
  [[ "$output" == *"1.1"* ]]
  [[ "$output" == *"1.2"* ]]
}

@test "duo re-focuses an existing session instead of spawning a second" {
  proj="$BATS_TEST_TMPDIR/dup"
  mkdir -p "$proj"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-duo-boot-wait 0
  TMUX="fake" bash "$SCRIPTS/duo.sh" "$proj" 2>/dev/null || true
  TMUX="fake" bash "$SCRIPTS/duo.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" list-sessions -F '#{session_name}'
  [[ "$(printf '%s\n' "$output" | grep -c '^dup-duo$')" -eq 1 ]]
}

@test "sessionizer creates a session from a path argument" {
  proj="$BATS_TEST_TMPDIR/myproj"
  mkdir -p "$proj"
  # TMUX set (to a dummy) forces the non-blocking switch-client branch, not attach
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" has-session -t myproj
  [ "$status" -eq 0 ]
}
