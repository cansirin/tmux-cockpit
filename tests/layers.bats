#!/usr/bin/env bats
# Tests for the composable duo "layers" — pure helpers (no tmux) + one
# integration launch on an isolated socket asserting a layer reaches the pane.

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
}

# --- cockpit_duo_layer_seed: read, strip, join ---

@test "layer seed strips #-comments and blank lines and joins the rest with '; '" {
  dir="$BATS_TEST_TMPDIR/layers"
  mkdir -p "$dir"
  printf '# a comment\n\nfirst line\n\n# another\nsecond line\n' > "$dir/demo.layer"
  run cockpit_duo_layer_seed demo "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "first line; second line" ]
}

@test "layer seed of the shipped caveman layer is the /caveman command" {
  run cockpit_duo_layer_seed caveman "$COCKPIT_LIB_DIR/../layers"
  [ "$status" -eq 0 ]
  [ "$output" = "/caveman full" ]
}

@test "a missing layer returns non-zero and prints nothing" {
  run cockpit_duo_layer_seed nope "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "an indented comment line is stripped but a mid-line # is kept" {
  dir="$BATS_TEST_TMPDIR/layers"
  mkdir -p "$dir"
  printf '   # indented comment\nfix issue #42 now\n' > "$dir/hash.layer"
  run cockpit_duo_layer_seed hash "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "fix issue #42 now" ]
}

@test "a path-traversal name is refused (non-zero, no read)" {
  # NAME is interpolated into a path — a name with / or .. must never read a file
  # outside the layer dirs. The guard fires before any filesystem touch.
  run cockpit_duo_layer_seed "../../etc/passwd" "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run cockpit_duo_layer_seed "a/b" "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
}

@test "the first dir listed wins on a name clash (user shadows repo)" {
  a="$BATS_TEST_TMPDIR/a"; b="$BATS_TEST_TMPDIR/b"
  mkdir -p "$a" "$b"
  printf 'from a\n' > "$a/x.layer"
  printf 'from b\n' > "$b/x.layer"
  run cockpit_duo_layer_seed x "$a" "$b"
  [ "$output" = "from a" ]
}

# --- cockpit_duo_compose_brief: append when seeded, no-op when empty ---

@test "compose appends a delimited startup instruction when the seed is present" {
  run cockpit_duo_compose_brief "BASE." "/caveman full"
  [ "$status" -eq 0 ]
  [[ "$output" == "BASE."* ]]
  [[ "$output" == *"Startup layers"* ]]
  [[ "$output" == *"/caveman full"* ]]
}

@test "compose is a byte-for-byte no-op when the seed is empty" {
  run cockpit_duo_compose_brief "BASE BRIEF unchanged" ""
  [ "$output" = "BASE BRIEF unchanged" ]
}

# --- cockpit_duo_layer_dirs: repo dir + user override precedence ---

@test "layer dirs include the repo's layers/ dir" {
  run cockpit_duo_layer_dirs
  [[ "$output" == *"/layers"* ]]
}

@test "layer dirs put the user dir (@cockpit-duo-layers / \$COCKPIT_DUO_LAYERS) first" {
  COCKPIT_DUO_LAYERS="/my/layers" run cockpit_duo_layer_dirs
  # first line is the user dir, so it shadows the repo dir on a name clash
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "/my/layers" ]
  [[ "$output" == *"/layers"* ]]
}

# --- symlink resolution: invoked via a PATH symlink, lib.sh still resolves ---

@test "duo-layers.sh invoked through a symlink still finds lib.sh" {
  # `make install` symlinks duo-* into ~/.local/bin; a naive SCRIPT_DIR would look
  # for lib.sh there. The link-walk must resolve back to the real scripts dir.
  ln -s "${BATS_TEST_DIRNAME}/../scripts/duo-layers.sh" "$BATS_TEST_TMPDIR/duo-layers.sh"
  # The test-only bypass proves the whole flow ran (dirs computed from lib.sh,
  # names listed) without erroring on a missing lib.sh.
  COCKPIT_SOCKET="cockpit-symlink-$$" COCKPIT_DUO_LAYERS_PICK="caveman" \
    run "$BATS_TEST_TMPDIR/duo-layers.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "caveman" ]
}

# --- integration: a selected layer reaches every pane's seeded brief ---

# A `cat` per pane keeps the seeded brief ON SCREEN (echoed, never executed), and
# capture-pane -J rejoins tmux's line-wrapping so a substring can't fall across a
# wrap boundary — together they make the assertion robust, not timing-fragile.

@test "COCKPIT_DUO_SELECTED=caveman seeds the caveman layer into the pane" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-layers-$$"
  repo="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 2
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  COCKPIT_DUO_SELECTED="caveman" \
    run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  name="$(cockpit_duo_name "$repo")"
  pane="$(tmux -L "$COCKPIT_SOCKET" show-option -t "$name" -qv "@$(cockpit_duo_pane_key 1.1)")"

  # The brief is seeded from a BACKGROUNDED subshell, so poll the pane content.
  found=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if tmux -L "$COCKPIT_SOCKET" capture-pane -pJ -t "$pane" | grep -q "Startup layers"; then
      found=1; break
    fi
    sleep 0.5
  done
  cap="$(tmux -L "$COCKPIT_SOCKET" capture-pane -pJ -t "$pane")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [ -n "$found" ]
  [[ "$cap" == *"/caveman full"* ]]
}

@test "with no layers selected the pane brief carries no startup-layers line" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-layers-none-$$"
  repo="$BATS_TEST_TMPDIR/proj2"
  mkdir -p "$repo"
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "cat"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 2
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 1

  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  name="$(cockpit_duo_name "$repo")"
  pane="$(tmux -L "$COCKPIT_SOCKET" show-option -t "$name" -qv "@$(cockpit_duo_pane_key 1.1)")"

  # Wait for the (unlayered) brief to land, then assert the layer line is absent.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    tmux -L "$COCKPIT_SOCKET" capture-pane -pJ -t "$pane" | grep -q "Claude duo" && break
    sleep 0.5
  done
  cap="$(tmux -L "$COCKPIT_SOCKET" capture-pane -pJ -t "$pane")"
  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
  [[ "$cap" != *"Startup layers"* ]]
}
