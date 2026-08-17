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

@test "session-list honors @cockpit-color-sessions" {
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-color-sessions colour99
  run bash "$SCRIPTS/session-list.sh"
  [[ "$output" == *"fg=colour99"* ]]   # the configured accent, not the default
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
  [[ "$output" == *"JUMP to project"* ]] # the built-in project picker entry
  [[ "$output" == *"edit reminders"* ]]  # the reminders editor entry
  [[ "$output" == *"add reminder"* ]]    # the quick-capture entry
  [[ "$output" == *"hello extra"* ]]     # the user-supplied extra entry
}

@test "status-left wires in the [G] git context" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-left
  [[ "$output" == *"git-context.sh"* ]]
}

@test "sessionizer creates a session from a path argument" {
  proj="$BATS_TEST_TMPDIR/myproj"
  mkdir -p "$proj"
  # TMUX set (to a dummy) forces the non-blocking switch-client branch, not attach
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" has-session -t myproj
  [ "$status" -eq 0 ]
}

@test "sessionizer re-focuses the same repo path instead of duplicating it" {
  proj="$BATS_TEST_TMPDIR/reuse/app"
  mkdir -p "$proj"
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  names="$(tmux -L "$COCKPIT_SOCKET" list-sessions -F '#{session_name}')"
  [ "$(printf '%s\n' "$names" | grep -c '^app$')" -eq 1 ]
  # the repo path is recorded so a same-basename repo elsewhere can tell them apart
  run tmux -L "$COCKPIT_SOCKET" show-option -t app -qv @cockpit-path
  [ "$output" = "$proj" ]
}

@test "two same-basename repos in different paths get distinct sessions" {
  a="$BATS_TEST_TMPDIR/one/app"
  b="$BATS_TEST_TMPDIR/two/app"
  mkdir -p "$a" "$b"
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$a" 2>/dev/null || true
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$b" 2>/dev/null || true
  names="$(tmux -L "$COCKPIT_SOCKET" list-sessions -F '#{session_name}')"
  # first keeps the pretty base; second is disambiguated with a -<hash> tag
  [ "$(printf '%s\n' "$names" | grep -c '^app$')" -eq 1 ]
  [ "$(printf '%s\n' "$names" | grep -cE '^app-[0-9a-f]{6}$')" -eq 1 ]
}

@test "a prefix sibling (foo-sandbox) does not steal the plain foo session name" {
  # regression: tmux prefix-matches a bare target, so has-session for "foo" used
  # to answer true when only "foo-sandbox" existed — wrongly disambiguating "foo".
  # The resolver anchors with "=foo", so a plain foo still gets its plain name.
  proj="$BATS_TEST_TMPDIR/plain/foo"
  mkdir -p "$proj"
  tmux -L "$COCKPIT_SOCKET" new-session -ds foo-sandbox
  tmux -L "$COCKPIT_SOCKET" set -t foo-sandbox @cockpit-path "/somewhere/else/foo"
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" has-session -t "=foo"
  [ "$status" -eq 0 ]   # a session named exactly "foo" was created, not "foo-<hash>"
}

@test "a legacy unstamped session is claimed on touch, not left a hijack magnet" {
  # a session made before this fix (or by hand) has no @cockpit-path; opening its
  # repo must stamp it, so a later same-basename repo disambiguates instead of
  # silently reusing it.
  proj="$BATS_TEST_TMPDIR/legacy/bar"
  mkdir -p "$proj"
  tmux -L "$COCKPIT_SOCKET" new-session -ds bar   # no @cockpit-path set
  TMUX="fake" bash "$SCRIPTS/sessionizer.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" show-option -t bar -qv @cockpit-path
  [ "$output" = "$proj" ]
}

@test "picker unions the depth-1 scan, @cockpit-extra, and zoxide's frecency list" {
  # The picker is normally interactive, so stub fzf (echo the candidate list to a
  # file, pick nothing) and zoxide (a fixed frecency list) onto PATH.
  root="$BATS_TEST_TMPDIR/roots"; mkdir -p "$root/inroot"
  loose="$BATS_TEST_TMPDIR/elsewhere/loose"; mkdir -p "$loose"
  visited="$BATS_TEST_TMPDIR/desktop/visited by hand"; mkdir -p "$visited"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" "/gone/stale"\n' "$visited" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-extra "$loose"
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" == *"$root/inroot"* ]]   # 1. a child of a configured root
  [[ "$output" == *"$loose"* ]]         # 2. a literal @cockpit-extra dir
  [[ "$output" == *"$visited"* ]]       # 3. a zoxide-visited dir, in no root
  [[ "$output" != *"/gone/stale"* ]]    # zoxide's stale entries are filtered out
}

@test "@cockpit-zoxide off drops the frecency source, keeping the configured roots" {
  root="$BATS_TEST_TMPDIR/roots"; mkdir -p "$root/inroot"
  visited="$BATS_TEST_TMPDIR/desktop/visited"; mkdir -p "$visited"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$visited" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-zoxide off
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" == *"$root/inroot"* ]]
  [[ "$output" != *"$visited"* ]]
}

@test "a non-numeric @cockpit-zoxide-limit falls back, never leaking head's error into the picker" {
  root="$BATS_TEST_TMPDIR/roots"; mkdir -p "$root/inroot"
  visited="$BATS_TEST_TMPDIR/desktop/visited"; mkdir -p "$visited"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$visited" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-zoxide-limit 'not-a-number'
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" == *"$visited"* ]]     # zoxide source survives the bad value
  [[ "$output" != *"illegal"* ]]      # and head's usage error never lands in the list
  [[ "$output" != *"usage"* ]]
}

@test "picker offers the project, not the folder it sits in nor its subfolders" {
  # end-to-end shape of the sofia case: the container and the subfolders are all
  # in zoxide, and only the project itself should reach the picker.
  root="$BATS_TEST_TMPDIR/roots"; mkdir -p "$root/inroot"
  proj="$BATS_TEST_TMPDIR/desk/sofia - master"
  mkdir -p "$proj/machine-learning/assignments" "$proj/security"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  # zoxide's own order: the project outranks the container it lives in
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" "%s" "%s" "%s"\n' \
    "$proj" "$proj/machine-learning/assignments" "$proj/security" \
    "$BATS_TEST_TMPDIR/desk" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" == *"$proj"* ]]                      # the project is offered
  [[ "$output" != *"$proj/machine-learning"* ]]     # its subfolders are not
  [[ "$output" != *"$proj/security"* ]]
  [[ "$output" == *"$root/inroot"* ]]               # configured roots unaffected
  # the project outranks the container it sits in, so it comes first — the
  # container is kept but ranked below, which is fzf's problem and not ours
  first_zoxide="$(printf '%s\n' "$output" | grep "^$BATS_TEST_TMPDIR/desk" | head -1)"
  [ "$first_zoxide" = "$proj" ]
}

@test "picker drops hidden dirs and anything at or above \$HOME" {
  # HOME is redirected into the test tmpdir: cockpit_zoxide_keep is defined
  # relative to $HOME, and nothing here may touch the developer's real home.
  export HOME="$BATS_TEST_TMPDIR/home"
  root="$BATS_TEST_TMPDIR/roots"; mkdir -p "$root/inroot"
  mkdir -p "$HOME/.cockpit-test-hidden"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" "%s" "/"\n' \
    "$HOME/.cockpit-test-hidden" "$HOME" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" != *".cockpit-test-hidden"* ]]
  [ "$(printf '%s\n' "$output" | grep -cx "$HOME")" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cx "/")" -eq 0 ]
  [[ "$output" == *"$root/inroot"* ]]
}

@test "picker sorts the configured block instead of leaving it in dirent order" {
  # `find` returns raw filesystem order; the section you curated must not arrive
  # as an arbitrary shuffle. The zoxide block below it stays in frecency order.
  root="$BATS_TEST_TMPDIR/sortroot"
  mkdir -p "$root"/zebra "$root"/apple "$root"/mango "$root"/banana

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nexit 0\n' > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  names="$(printf '%s\n' "$output" | sed 's|.*/||')"
  [ "$names" = "$(printf 'apple\nbanana\nmango\nzebra')" ]
}

@test "the zoxide cap applies to filtered entries, not raw history" {
  # a history whose head is all hidden dirs must not spend the whole budget
  # before reaching a real project
  root="$BATS_TEST_TMPDIR/caproot"; mkdir -p "$root/inroot"
  real="$BATS_TEST_TMPDIR/caphome/realproject"
  export HOME="$BATS_TEST_TMPDIR/caphome"
  mkdir -p "$real" "$HOME/.junk1" "$HOME/.junk2" "$HOME/.junk3"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" "%s" "%s" "%s"\n' \
    "$HOME/.junk1" "$HOME/.junk2" "$HOME/.junk3" "$real" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-zoxide-limit 1
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" == *"$real"* ]]   # the only survivor of the filter, so it fits in 1
}

@test "a configured root is never offered as a project, however often it is visited" {
  # you named it as the place projects live IN, so it is a container by your own
  # declaration — its children are the projects, it is not one
  root="$BATS_TEST_TMPDIR/devroot"; mkdir -p "$root/realproj"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" "%s"\n' "$root" "$root/realproj" > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [ "$(printf '%s\n' "$output" | grep -cx "$root")" -eq 0 ]
  [[ "$output" == *"$root/realproj"* ]]
}

@test "the root scan skips dot-dirs — .claude under a root is not a project" {
  root="$BATS_TEST_TMPDIR/dotroot"
  mkdir -p "$root/realproj" "$root/.claude" "$root/.github"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/sh\ncat > "%s/candidates"\n' "$BATS_TEST_TMPDIR" > "$stub/fzf"
  printf '#!/bin/sh\nexit 0\n' > "$stub/zoxide"
  chmod +x "$stub/fzf" "$stub/zoxide"

  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-paths "$root"
  PATH="$stub:$PATH" TMUX="fake" bash "$SCRIPTS/sessionizer.sh" 2>/dev/null || true

  run cat "$BATS_TEST_TMPDIR/candidates"
  [[ "$output" == *"$root/realproj"* ]]
  [[ "$output" != *".claude"* ]]
  [[ "$output" != *".github"* ]]
}
