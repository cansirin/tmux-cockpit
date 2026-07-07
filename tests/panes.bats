#!/usr/bin/env bats
# Tests for launch-time pane-count selection: the duo-panes.sh picker (bypass +
# label strip) and duo.sh's --panes override of the @cockpit-duo-panes option.

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
}

# --- duo-panes.sh: test bypass returns the digit, strips any label ---

@test "duo-panes.sh COCKPIT_DUO_PANES_PICK bypass returns the chosen digit" {
  COCKPIT_SOCKET="cockpit-panes-$$" COCKPIT_DUO_PANES_PICK="3" \
    run "${BATS_TEST_DIRNAME}/../scripts/duo-panes.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "duo-panes.sh bypass strips a label, printing only the leading digit" {
  COCKPIT_SOCKET="cockpit-panes-$$" COCKPIT_DUO_PANES_PICK="2  ·  side-by-side" \
    run "${BATS_TEST_DIRNAME}/../scripts/duo-panes.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "duo-panes.sh invoked through a symlink still finds lib.sh" {
  # `make install` symlinks duo-* into ~/.local/bin; the link-walk must resolve
  # SCRIPT_DIR back to the real scripts dir so lib.sh sources.
  ln -s "${BATS_TEST_DIRNAME}/../scripts/duo-panes.sh" "$BATS_TEST_TMPDIR/duo-panes.sh"
  COCKPIT_SOCKET="cockpit-panes-symlink-$$" COCKPIT_DUO_PANES_PICK="3" \
    run "$BATS_TEST_TMPDIR/duo-panes.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

# --- duo.sh --panes: overrides the option, both directions + a regression ---

# Count the panes duo.sh created for $repo on the isolated socket.
_panecount() {
  local repo="$1" name
  name="$(cockpit_duo_name "$repo")"
  tmux -L "$COCKPIT_SOCKET" list-panes -t "$name" -F '#{pane_id}' | grep -c .
}

@test "--panes 3 makes a 3-pane session even when @cockpit-duo-panes is 2" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-panes-3over2-$$"
  repo="$BATS_TEST_TMPDIR/p3"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 2
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' --panes 3 '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  n="$(_panecount "$repo")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [ "$n" -eq 3 ]
}

@test "--panes 2 makes a 2-pane session even when @cockpit-duo-panes is 3" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-panes-2over3-$$"
  repo="$BATS_TEST_TMPDIR/p2"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 3
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' --panes 2 '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  n="$(_panecount "$repo")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [ "$n" -eq 2 ]
}

@test "no --panes flag honors the @cockpit-duo-panes option (regression)" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-panes-opt-$$"
  repo="$BATS_TEST_TMPDIR/popt"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 3
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  n="$(_panecount "$repo")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [ "$n" -eq 3 ]
}

@test "an invalid --panes value falls back to 2" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-panes-bad-$$"
  repo="$BATS_TEST_TMPDIR/pbad"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 3
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' --panes 9 '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  n="$(_panecount "$repo")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [ "$n" -eq 2 ]
}

@test "--panes with a non-digit next arg does not swallow the path" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-panes-noswallow-$$"
  repo="$BATS_TEST_TMPDIR/pnoswallow"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  # `--panes <repo>` with no digit: the flag is dropped, the path is NOT eaten, so
  # the duo still launches at the repo (its <basename>-duo session exists) with the
  # default pane count.
  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' --panes '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  name="$(cockpit_duo_name "$repo")"
  run tmux -L "$COCKPIT_SOCKET" has-session -t "=$name"
  saved="$status"
  n="$(_panecount "$repo")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [ "$saved" -eq 0 ]
  [ "$n" -eq 2 ]
}
