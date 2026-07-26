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

@test "the prompt bar inherits the terminal's own fg/bg, not tmux's yellow default" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv message-style
  [[ "$output" == *"bg=default"* ]]
  [[ "$output" == *"fg=default"* ]]
  [[ "$output" == *"reverse"* ]]
  [[ ! "$output" =~ yellow ]]

  run tmux -L "$COCKPIT_SOCKET" show-option -gv message-command-style
  [[ "$output" == *"bg=default"* ]]
  [[ "$output" == *"fg=default"* ]]
  [[ ! "$output" =~ yellow ]]
}

@test "copy-mode and the menu keep their hue but drop the pinned black ink" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  for opt in mode-style copy-mode-match-style copy-mode-current-match-style \
             copy-mode-mark-style menu-selected-style; do
    run tmux -L "$COCKPIT_SOCKET" show-option -gv "$opt"
    [[ "$output" == *"reverse"* ]]
    [[ ! "$output" =~ fg=black ]]
    [[ ! "$output" =~ colour[0-9] ]]
  done
}

@test "the menu selection follows the [S] accent, pin included" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-sessions colour111
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv menu-selected-style
  [[ "$output" == *"fg=colour111"* ]]
}

# These are NATIVE tmux options, so the restyle must be a repair of tmux's own
# default and never a land-grab over a value the user chose.
@test "a style the user set themselves is left untouched" {
  tmux -L "$COCKPIT_SOCKET" set -g message-style "bg=colour53,fg=colour231"
  tmux -L "$COCKPIT_SOCKET" set -g mode-style "bg=colour24,fg=white"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"

  run tmux -L "$COCKPIT_SOCKET" show-option -gv message-style
  [ "$output" = "bg=colour53,fg=colour231" ]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv mode-style
  [ "$output" = "bg=colour24,fg=white" ]
}

@test "@cockpit-fix-tmux-defaults off leaves every tmux default in place" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-fix-tmux-defaults off
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  for opt in message-style message-command-style mode-style menu-selected-style \
             copy-mode-match-style copy-mode-current-match-style copy-mode-mark-style \
             status-style; do
    run tmux -L "$COCKPIT_SOCKET" show-option -gv "$opt"
    [[ "$output" == *"yellow"* || "$output" == *"fg=black"* ]]
  done
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-justify
  [ "$output" = left ]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-right
  [[ "$output" == *"pane_title"* ]]     # still tmux's title-and-clock
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-right-length
  [ "$output" = 40 ]
}

# The chips are drawn ON the status bar, so they can only resolve to the terminal's
# theme if the bar underneath them is the terminal's own colours, not tmux's green.
@test "the status bar cockpit draws on is the terminal's own, and the list is centred" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-style
  [ "$output" = "bg=default,fg=default" ]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-justify
  [ "$output" = centre ]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv window-status-current-style
  [[ "$output" == *"fg=blue,reverse,bold"* ]]
}

# `white` is ansi slot 7, which a light theme may resolve to a mid GREY (GitHub
# Light: #6e7781) — so bg=red,fg=white renders as grey-on-red mud. The chip has to
# take its ink from the terminal via reverse, like every other chip in the plugin.
@test "the PREFIX chip takes its ink from the terminal, not a hardcoded white" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-right
  [[ "$output" == *"PREFIX"* ]]
  [[ "$output" == *"fg=red"* ]]
  [[ "$output" == *"reverse"* ]]
  [[ ! "$output" =~ fg=white ]]
  [[ ! "$output" =~ bg=red ]]
  [[ "$output" == *"Space = menu"* ]]   # the menu stays advertised
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-right-length
  [ "$output" = 80 ]
}

# The chip lives inside a #{?client_prefix,…} conditional, so its commas must be
# escaped or tmux reads them as the conditional's own argument separator and the
# style leaks into the bar as literal text.
@test "the status-right hint renders, and follows a rebound prefix" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" display -p '#{T:status-right}'
  [[ "$output" == *"C-b Space = menu"* ]]
  [[ ! "$output" =~ PREFIX ]]           # only while the prefix is actually held

  tmux -L "$COCKPIT_SOCKET" set -g prefix C-a
  run tmux -L "$COCKPIT_SOCKET" display -p '#{T:status-right}'
  [[ "$output" == *"C-a Space = menu"* ]]
}

@test "a status-right the user wrote themselves is left untouched" {
  tmux -L "$COCKPIT_SOCKET" set -g status-right "%H:%M mine"
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-right
  [ "$output" = "%H:%M mine" ]
}

@test "a status bar the user styled themselves is left untouched" {
  tmux -L "$COCKPIT_SOCKET" set -g status-style "bg=colour235,fg=colour250"
  tmux -L "$COCKPIT_SOCKET" set -g status-justify right
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"

  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-style
  [ "$output" = "bg=colour235,fg=colour250" ]
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-justify
  [ "$output" = right ]
}

@test "a re-pinned accent still lands on a style cockpit already restyled" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-sessions colour111
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv menu-selected-style
  [[ "$output" == *"fg=colour111"* ]]
}

@test "the accents are still pinnable to a fixed colour" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-sessions colour111
  run bash "$SCRIPTS/session-list.sh"
  [[ "$output" == *"fg=colour111"* ]]
}
