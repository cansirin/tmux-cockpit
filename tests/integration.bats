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
  [[ "$output" == *"hello extra"* ]]     # the user-supplied extra entry
}

@test "worktree helper creates a sibling worktree on a new branch" {
  repo="$BATS_TEST_TMPDIR/monorepo"
  git init -q -b main "$repo"
  git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
  run env WT_NO_OPEN=1 bash -c "cd '$repo' && '$SCRIPTS/worktree.sh' widget-fix"
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/monorepo-widget-fix" ]
  run git -C "$BATS_TEST_TMPDIR/monorepo-widget-fix" rev-parse --abbrev-ref HEAD
  [ "$output" = "widget-fix" ]
}

@test "worktree helper resolves the main repo from inside a linked worktree" {
  repo="$BATS_TEST_TMPDIR/mono2"
  git init -q -b main "$repo"
  git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
  git -C "$repo" worktree add -q -b first "$BATS_TEST_TMPDIR/mono2-first" >/dev/null
  # run from the linked worktree — sibling must still be named off the MAIN repo
  run env WT_NO_OPEN=1 bash -c "cd '$BATS_TEST_TMPDIR/mono2-first' && '$SCRIPTS/worktree.sh' second"
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/mono2-second" ]
}

@test "sessionizer creates a session from a path argument" {
  proj="$BATS_TEST_TMPDIR/myproj"
  mkdir -p "$proj"
  # TMUX set (to a dummy) forces the non-blocking switch-client branch, not attach
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" has-session -t myproj
  [ "$status" -eq 0 ]
}
