#!/usr/bin/env bats
# Tests for the cross-window ergonomics helpers: tmsg, wt-status.
# tmux bits run on an isolated socket; git bits run in throwaway repos.

export COCKPIT_SOCKET="cockpit_ergo_$$"
SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

teardown() {
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
}

# a throwaway git repo with one commit and a fixed identity (CI-safe)
mk_repo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit --allow-empty -qm "init"
}

@test "tmsg delivers a line to another pane in one call" {
  tmux -L "$COCKPIT_SOCKET" new-session -d -s msgtest -x 200 -y 50
  pane="$(tmux -L "$COCKPIT_SOCKET" list-panes -t msgtest -F '#{pane_id}' | head -1)"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "$SCRIPTS/tmsg.sh" "$pane" echo cockpit-tmsg-ok
  sleep 0.4
  run tmux -L "$COCKPIT_SOCKET" capture-pane -t "$pane" -p
  [[ "$output" == *cockpit-tmsg-ok* ]]
}

@test "tmsg errors out without a message" {
  run bash "$SCRIPTS/tmsg.sh" %0
  [ "$status" -eq 2 ]
  [[ "$output" == *usage* ]]
}

@test "tmsg works invoked through a symlink (PATH install)" {
  ln -s "$SCRIPTS/tmsg.sh" "$BATS_TEST_TMPDIR/tmsg"
  tmux -L "$COCKPIT_SOCKET" new-session -d -s linktest -x 200 -y 50
  pane="$(tmux -L "$COCKPIT_SOCKET" list-panes -t linktest -F '#{pane_id}' | head -1)"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" "$BATS_TEST_TMPDIR/tmsg" "$pane" echo via-symlink-ok
  sleep 0.4
  run tmux -L "$COCKPIT_SOCKET" capture-pane -t "$pane" -p
  [[ "$output" == *via-symlink-ok* ]]
}

@test "wt-status marks an unmerged worktree UNMERGED and the base MERGED" {
  repo="$BATS_TEST_TMPDIR/wtrepo"
  mk_repo "$repo"
  git -C "$repo" worktree add -q "$BATS_TEST_TMPDIR/wt2" -b feature
  git -C "$BATS_TEST_TMPDIR/wt2" -c user.email=t@t -c user.name=t commit --allow-empty -qm "work"
  run bash -c "cd '$repo' && '$SCRIPTS/wt-status.sh' main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MERGED"* ]]     # the main worktree, vs itself
  [[ "$output" == *"UNMERGED"* ]]   # the feature worktree (ahead of main)
  [[ "$output" == *"feature"* ]]
}
