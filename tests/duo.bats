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
