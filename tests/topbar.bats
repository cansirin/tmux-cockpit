#!/usr/bin/env bats
# Top-bar reminder tests. Run on an isolated tmux socket (COCKPIT_SOCKET) so the
# developer's real server is never touched. -f /dev/null → no user config.

export COCKPIT_SOCKET="cockpit_topbar_test_$$"
SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

setup() {
  tmux -L "$COCKPIT_SOCKET" -f /dev/null new-session -d -s base -x 200 -y 50
}

teardown() {
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
}

@test "topbar is empty when nothing is configured" {
  run bash "$SCRIPTS/topbar.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "topbar shows an inline reminder" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "ship the PR"
  run bash "$SCRIPTS/topbar.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship the PR"* ]]
}

@test "topbar honors @cockpit-color-reminders" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "ship the PR"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-reminders colour99
  run bash "$SCRIPTS/topbar.sh"
  [[ "$output" == *"fg=colour99"* ]]   # the configured accent, not the default
}

@test "topbar shows file reminders, skipping # comments and blank lines" {
  f="$BATS_TEST_TMPDIR/reminders.txt"
  printf '# a comment\nstandup at 10\n\ndeploy widget\n' > "$f"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders-file "$f"
  run bash "$SCRIPTS/topbar.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"standup at 10"* ]]
  [[ "$output" == *"deploy widget"* ]]
  [[ "$output" != *"a comment"* ]]
}

@test "topbar shows file and inline reminders together" {
  f="$BATS_TEST_TMPDIR/reminders.txt"
  printf 'from the file\n' > "$f"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders-file "$f"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "from inline"
  run bash "$SCRIPTS/topbar.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"from the file"* ]]
  [[ "$output" == *"from inline"* ]]
}

@test "cockpit.tmux adds a reminders row (status 2) when reminders are configured" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "ship it"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status
  [ "$output" = "2" ]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv 'status-format[1]'
  [ "$output" = "#[align=left]#{E:@cockpit-segment-reminders}" ]   # row 1 is the [R] line
  run tmux -L "$COCKPIT_SOCKET" show-option -gv @cockpit-segment-reminders
  [[ "$output" == *"topbar.sh"* ]]
}

@test "cockpit.tmux leaves a row 1 you set yourself alone, on every load" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders "ship it"
  tmux -L "$COCKPIT_SOCKET" set -g 'status-format[1]' "#{E:@cockpit-segment-reminders}#[align=right]mine"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv 'status-format[1]'
  [ "$output" = "#{E:@cockpit-segment-reminders}#[align=right]mine" ]
}

@test "cockpit.tmux keeps a single status row when no reminders are configured" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status
  [ "$output" = "on" ]
}

@test "cockpit.tmux publishes [S] and [G] as segments and lays them out on status-left" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv @cockpit-segment-sessions
  [[ "$output" == *'#{S:'* ]]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv @cockpit-segment-git
  [[ "$output" == *"git-context.sh"* ]]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-left
  [ "$output" = "#{E:@cockpit-segment-sessions}  #{E:@cockpit-segment-git}" ]
}

@test "cockpit.tmux leaves a status-left you set yourself alone, on every load" {
  tmux -L "$COCKPIT_SOCKET" set -g status-left "#{E:@cockpit-segment-sessions}"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-left
  [ "$output" = "#{E:@cockpit-segment-sessions}" ]
}

@test "cockpit.tmux moves the pre-segment status-left literal onto the segment form" {
  s="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"
  tmux -L "$COCKPIT_SOCKET" set -g status-left "#[fg=blue,reverse,bold] S #[default] #($s/session-list.sh)  #($s/git-context.sh '#{pane_current_path}')"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-left
  [[ "$output" == *"@cockpit-segment-sessions"* ]]
}

@test "edit-reminders creates the reminders file (so the menu entry can edit it)" {
  f="$BATS_TEST_TMPDIR/sub/reminders.txt"   # nested dir that does not exist yet
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders-file "$f"
  EDITOR=true bash "$SCRIPTS/edit-reminders.sh"
  [ -f "$f" ]
}

@test "add-reminder appends a captured line to the reminders file" {
  f="$BATS_TEST_TMPDIR/sub/reminders.txt"   # nested dir that does not exist yet
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders-file "$f"
  bash "$SCRIPTS/add-reminder.sh" call the bank
  run cat "$f"
  [[ "$output" == *"call the bank"* ]]
}

@test "add-reminder ignores empty input" {
  f="$BATS_TEST_TMPDIR/reminders.txt"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-reminders-file "$f"
  bash "$SCRIPTS/add-reminder.sh" "   "
  [ ! -s "$f" ]   # file stays empty (no whitespace-only line appended)
}
