#!/usr/bin/env bats
# Unit tests for cockpit_session_name — pure logic, no tmux required.

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
}

@test "a normal project keeps its basename" {
  run cockpit_session_name /home/u/code/kampus
  [ "$status" -eq 0 ]
  [ "$output" = "kampus" ]
}

@test "monorepo is prefixed with its parent (collision fix)" {
  run cockpit_session_name /home/u/csirin/monorepo
  [ "$output" = "csirin-monorepo" ]
}

@test "two different monorepos get distinct names" {
  a="$(cockpit_session_name /home/u/csirin/monorepo)"
  b="$(cockpit_session_name /home/u/Binclusive/monorepo)"
  [ "$a" = "csirin-monorepo" ]
  [ "$b" = "Binclusive-monorepo" ]
  [ "$a" != "$b" ]
}

@test "a monorepo worktree keeps its suffix and gains the parent" {
  run cockpit_session_name /home/u/Binclusive/monorepo-widget-cdn
  [ "$output" = "Binclusive-monorepo-widget-cdn" ]
}

@test "spaces, dots and colons are sanitized to underscores" {
  run cockpit_session_name "/home/u/My Project.v2"
  [ "$output" = "My_Project_v2" ]
}
