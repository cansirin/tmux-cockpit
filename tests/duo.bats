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
  run cockpit_duo_brief 1.1 1.2 %12 /tmp/duo-protocol.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"pane 1.1"* ]]
  [[ "$output" == *"Sibling: 1.2"* ]]
  [[ "$output" == *"%12"* ]]
  [[ "$output" == *"/tmp/duo-protocol.md"* ]]
}

@test "the brief tells the pane to read the protocol first" {
  run cockpit_duo_brief 1.2 1.1 %7 /x/p.md
  [[ "$output" == *"Read /x/p.md and follow it"* ]]
  [[ "$output" == *"Greet your sibling"* ]]
}
