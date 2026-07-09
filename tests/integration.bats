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
  [[ "$output" == *"launch CREW here"* ]] # the built-in crew launcher entry
  [[ "$output" == *"edit reminders"* ]]  # the reminders editor entry
  [[ "$output" == *"add reminder"* ]]    # the quick-capture entry
  [[ "$output" == *"hello extra"* ]]     # the user-supplied extra entry
}

@test "status-left wires in the [G] git context" {
  COCKPIT_SOCKET="$COCKPIT_SOCKET" bash "${BATS_TEST_DIRNAME}/../cockpit.tmux"
  run tmux -L "$COCKPIT_SOCKET" show-option -gv status-left
  [[ "$output" == *"git-context.sh"* ]]
}

@test "crew launches three panes in one window (default layout), all visible" {
  proj="$BATS_TEST_TMPDIR/crewproj"
  mkdir -p "$proj"
  # harmless per-pane command + no boot wait, so the test doesn't launch claude
  # or block; TMUX set (dummy) forces the non-blocking switch-client branch.
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-crew-boot-wait 0
  TMUX="fake" bash "$SCRIPTS/crew.sh" "$proj" 2>/dev/null || true
  # one window...
  run tmux -L "$COCKPIT_SOCKET" list-windows -t crewproj-crew
  [ "${#lines[@]}" -eq 1 ]
  # ...split into three panes, titled with the three seams
  run tmux -L "$COCKPIT_SOCKET" list-panes -t crewproj-crew -F '#{pane_title}'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"triage"* ]]
  [[ "$output" == *"em"* ]]
  [[ "$output" == *"ea"* ]]
}

@test "crew reads seam names from .claude/crew.config.jsonc (pane titles)" {
  proj="$BATS_TEST_TMPDIR/cfgproj"
  mkdir -p "$proj/.claude"
  cat > "$proj/.claude/crew.config.jsonc" <<'JSON'
{
  // fictional stand-up — names only, no real operator data
  "tmux": { "session": "crew", "windows": { "ea": "front", "engineeringManager": "build", "triage": "intake" } },
  "modelTiers": { "ea": "planning-tier", "engineeringManager": "build-tier", "triage": "planning-tier" }
}
JSON
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-crew-boot-wait 0
  TMUX="fake" bash "$SCRIPTS/crew.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" list-panes -t cfgproj-crew -F '#{pane_title}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"intake"* ]]
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"front"* ]]
}

@test "crew (panes) hands agents a runtime config whose windows.* are pane targets" {
  proj="$BATS_TEST_TMPDIR/rtproj"
  mkdir -p "$proj/.claude"
  cat > "$proj/.claude/crew.config.jsonc" <<'JSON'
{
  "tmux": { "session": "crew", "windows": { "ea": "ea", "engineeringManager": "em", "triage": "triage" } },
  "modelTiers": { "ea": "planning-tier", "engineeringManager": "build-tier", "triage": "planning-tier" }
}
JSON
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-crew-boot-wait 0
  rt="$BATS_TEST_TMPDIR/runtime.jsonc"
  COCKPIT_CREW_RUNTIME="$rt" TMUX="fake" bash "$SCRIPTS/crew.sh" "$proj" 2>/dev/null || true
  [ -f "$rt" ]
  # windows.* rewritten to win.pane targets (digits.digits), NOT the names
  run grep -E '"ea": "[0-9]+\.[0-9]+"' "$rt"
  [ "$status" -eq 0 ]
  grep -qE '"engineeringManager": "[0-9]+\.[0-9]+"' "$rt"
  grep -qE '"triage": "[0-9]+\.[0-9]+"' "$rt"
  # modelTiers untouched — the scoped rewrite must not bleed into it
  grep -q '"ea": "planning-tier"' "$rt"
  grep -q '"engineeringManager": "build-tier"' "$rt"
}

@test "crew @cockpit-crew-layout windows gives three windows instead" {
  proj="$BATS_TEST_TMPDIR/winproj"
  mkdir -p "$proj"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-crew-boot-wait 0
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-crew-layout windows
  TMUX="fake" bash "$SCRIPTS/crew.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" list-windows -t winproj-crew -F '#{window_name}'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"triage"* ]]
  [[ "$output" == *"em"* ]]
  [[ "$output" == *"ea"* ]]
  tmux -L "$COCKPIT_SOCKET" set -gu @cockpit-crew-layout   # reset for later tests
}

@test "crew re-focuses an existing session instead of spawning a second" {
  proj="$BATS_TEST_TMPDIR/dup"
  mkdir -p "$proj"
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-main-cmd 'true'
  tmux -L "$COCKPIT_SOCKET" set -g @cockpit-crew-boot-wait 0
  TMUX="fake" bash "$SCRIPTS/crew.sh" "$proj" 2>/dev/null || true
  TMUX="fake" bash "$SCRIPTS/crew.sh" "$proj" 2>/dev/null || true
  run tmux -L "$COCKPIT_SOCKET" list-sessions -F '#{session_name}'
  [[ "$(printf '%s\n' "$output" | grep -c '^dup-crew$')" -eq 1 ]]
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

@test "a prefix sibling (foo-crew) does not steal the plain foo session name" {
  # regression: tmux prefix-matches a bare target, so has-session for "foo" used
  # to answer true when only "foo-crew" existed — wrongly disambiguating "foo".
  # The resolver anchors with "=foo", so a plain foo still gets its plain name.
  proj="$BATS_TEST_TMPDIR/plain/foo"
  mkdir -p "$proj"
  tmux -L "$COCKPIT_SOCKET" new-session -ds foo-crew
  tmux -L "$COCKPIT_SOCKET" set -t foo-crew @cockpit-path "/somewhere/else/foo"
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
