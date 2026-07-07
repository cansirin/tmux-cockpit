#!/usr/bin/env bats
# Unit tests for the duo helpers — pure logic, no tmux required.

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
}

@test "duo name is the session name plus a -duo suffix" {
  run cockpit_duo_name /home/u/code/webapp
  [ "$status" -eq 0 ]
  [ "$output" = "webapp-duo" ]
}

@test "duo name inherits the monorepo collision fix" {
  run cockpit_duo_name /home/u/acme/monorepo
  [ "$output" = "acme-monorepo-duo" ]
}

@test "two different monorepos get distinct duo names" {
  a="$(cockpit_duo_name /home/u/acme/monorepo)"
  b="$(cockpit_duo_name /home/u/globex/monorepo)"
  [ "$a" = "acme-monorepo-duo" ]
  [ "$b" = "globex-monorepo-duo" ]
  [ "$a" != "$b" ]
}

@test "the brief names the pane, its sibling, the sibling's id, and the protocol" {
  run cockpit_duo_brief 1.1 /tmp/duo-protocol.md 1.2 %12
  [ "$status" -eq 0 ]
  [[ "$output" == *"pane 1.1"* ]]
  [[ "$output" == *"Sibling: 1.2"* ]]
  [[ "$output" == *"%12"* ]]
  [[ "$output" == *"/tmp/duo-protocol.md"* ]]
}

@test "the brief tells the pane to read the protocol first" {
  run cockpit_duo_brief 1.2 /x/p.md 1.1 %7
  [[ "$output" == *"Read /x/p.md and follow it"* ]]
  [[ "$output" == *"Greet your sibling"* ]]
}

@test "1.1 is briefed as the leader" {
  run cockpit_duo_brief 1.1 /tmp/p.md 1.2 %12
  [[ "$output" == *"the leader"* ]]
  [[ "$output" == *"delegate"* ]]
}

@test "a non-leader pane is briefed to execute and review" {
  run cockpit_duo_brief 1.2 /tmp/p.md 1.1 %7
  [[ "$output" == *"execute and review"* ]]
  [[ "$output" != *"the leader"* ]]
}

@test "the brief points reviewers at the ring, not at everyone" {
  # the brief must agree with protocol §4 (a directed ring), not tell a worker
  # to review all siblings — the contradiction the 3-pane design review caught.
  run cockpit_duo_brief 1.2 /tmp/p.md 1.1 %7 1.3 %9
  [[ "$output" == *"review ring"* ]]
  [[ "$output" != *"siblings' changes"* ]]
}

@test "every pane is told to leave durable notes to survive a compaction" {
  run cockpit_duo_brief 1.1 /tmp/p.md 1.2 %12
  [[ "$output" == *"durable notes"* ]]
  [[ "$output" == *"compaction"* ]]
}

@test "a three-pane brief names both siblings and their ids" {
  run cockpit_duo_brief 1.1 /tmp/p.md 1.2 %13 1.3 %14
  [[ "$output" == *"Sibling: 1.2 at %13"* ]]
  [[ "$output" == *"Sibling: 1.3 at %14"* ]]
}

@test "the heartbeat line names the pane and its state" {
  run cockpit_duo_heartbeat 1.2 "reviewing PR 42"
  [ "$status" -eq 0 ]
  [ "$output" = "heartbeat 1.2: reviewing PR 42" ]
}

@test "the heartbeat state defaults to alive" {
  run cockpit_duo_heartbeat 1.1
  [ "$output" = "heartbeat 1.1: alive" ]
}

# --- registry: label -> tmux-safe option key ---

@test "pane key encodes the label's dot as a hyphen" {
  run cockpit_duo_pane_key 1.2
  [ "$status" -eq 0 ]
  [ "$output" = "cockpit-duo-pane-1-2" ]
}

@test "pane key handles a two-digit index" {
  run cockpit_duo_pane_key 1.10
  [ "$output" = "cockpit-duo-pane-1-10" ]
}

# --- review ring: n=2 (collapses to the pair) ---

@test "n=2 ring: each pane reviews the other" {
  [ "$(cockpit_duo_reviewed_by 1.1 2)" = "1.2" ]
  [ "$(cockpit_duo_reviewed_by 1.2 2)" = "1.1" ]
  [ "$(cockpit_duo_reviews 1.1 2)" = "1.2" ]
  [ "$(cockpit_duo_reviews 1.2 2)" = "1.1" ]
}

@test "a sub-ring N (<2) is refused, not a silent self-review edge" {
  run cockpit_duo_reviewed_by 1.1 1
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run cockpit_duo_reviews 1.1 1
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# --- review ring: n=3, the full directed ring 1.2 -> 1.3 -> 1.1 -> 1.2 ---

@test "n=3 ring: reviewed_by follows 1.2->1.3->1.1->1.2" {
  [ "$(cockpit_duo_reviewed_by 1.2 3)" = "1.3" ]
  [ "$(cockpit_duo_reviewed_by 1.3 3)" = "1.1" ]
  [ "$(cockpit_duo_reviewed_by 1.1 3)" = "1.2" ]
}

@test "n=3 ring: reviews is the inverse edge" {
  # reviewed_by(1.2)=1.3 means 1.3 reviews 1.2, so reviews(1.3)=1.2, etc.
  [ "$(cockpit_duo_reviews 1.3 3)" = "1.2" ]
  [ "$(cockpit_duo_reviews 1.1 3)" = "1.3" ]
  [ "$(cockpit_duo_reviews 1.2 3)" = "1.1" ]
}

@test "n=3 ring: reviewed_by and reviews are consistent inverses" {
  # if X reviews Y then Y is reviewed_by X, for every pane
  for k in 1 2 3; do
    r="$(cockpit_duo_reviews "1.$k" 3)"          # 1.k reviews r
    [ "$(cockpit_duo_reviewed_by "$r" 3)" = "1.$k" ]
  done
}

# --- integration: duo.sh stamps the topology registry on the session ---

@test "duo.sh writes npanes, the label->pane map, and each pane's label" {
  command -v tmux >/dev/null || skip "tmux not installed"
  export COCKPIT_SOCKET="cockpit-bats-$$"
  repo="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$repo"
  # Start the server with a throwaway session FIRST: `set-option -g` errors with
  # no running server (it won't auto-start one), so the globals below must land
  # on an already-live server or duo.sh reads only its defaults.
  tmux -L "$COCKPIT_SOCKET" new-session -ds _boot -c "$repo"
  # Cheap per-pane command so nothing external boots; skip the brief-seed wait.
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-main-cmd "true"
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-panes 3
  tmux -L "$COCKPIT_SOCKET" set-option -g @cockpit-duo-boot-wait 0

  # Redirect duo.sh's output so the tmux server it spawns doesn't inherit bats'
  # capture pipe — an inherited-and-held fd on the daemon hangs `run` forever.
  run bash -c "'${BATS_TEST_DIRNAME}/../scripts/duo.sh' '$repo' >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  name="$(cockpit_duo_name "$repo")"
  [ "$(tmux -L "$COCKPIT_SOCKET" show-option -t "$name" -qv @cockpit-duo-npanes)" = "3" ]

  # session map: every label resolves to a live pane id
  for k in 1 2 3; do
    key="@$(cockpit_duo_pane_key "1.$k")"
    pid="$(tmux -L "$COCKPIT_SOCKET" show-option -t "$name" -qv "$key")"
    [[ "$pid" == %* ]]
    # and that pane carries its own label
    [ "$(tmux -L "$COCKPIT_SOCKET" show-option -p -t "$pid" -qv @cockpit-duo-label)" = "1.$k" ]
  done

  tmux -L "$COCKPIT_SOCKET" kill-server 2>/dev/null || true
}

@test "tmsg refuses a label target when it can't tell which pane it's in" {
  # Without $TMUX_PANE a label can't be scoped to the caller's duo — resolving it
  # anyway would misroute to the active session. It must error, not guess.
  run env -u TMUX_PANE bash "${BATS_TEST_DIRNAME}/../scripts/tmsg.sh" 1.2 hello
  [ "$status" -ne 0 ]
  [[ "$output" == *"can't resolve label"* ]]
}
