#!/usr/bin/env bats
# Unit tests for cockpit_session_name — pure logic, no tmux required.

setup() {
  source "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
}

@test "a normal project keeps its basename" {
  run cockpit_session_name /home/u/code/webapp
  [ "$status" -eq 0 ]
  [ "$output" = "webapp" ]
}

@test "monorepo is prefixed with its parent (collision fix)" {
  run cockpit_session_name /home/u/acme/monorepo
  [ "$output" = "acme-monorepo" ]
}

@test "two different monorepos get distinct names" {
  a="$(cockpit_session_name /home/u/acme/monorepo)"
  b="$(cockpit_session_name /home/u/globex/monorepo)"
  [ "$a" = "acme-monorepo" ]
  [ "$b" = "globex-monorepo" ]
  [ "$a" != "$b" ]
}

@test "a monorepo worktree keeps its suffix and gains the parent" {
  run cockpit_session_name /home/u/globex/monorepo-widget-cdn
  [ "$output" = "globex-monorepo-widget-cdn" ]
}

@test "spaces, dots and colons are sanitized to underscores" {
  run cockpit_session_name "/home/u/My Project.v2"
  [ "$output" = "My_Project_v2" ]
}

@test "the base name is NOT unique across same-basename paths (resolver's job)" {
  # documents the boundary: cockpit_session_name is readable, not injective —
  # cockpit_resolve_name is what disambiguates at create time.
  a="$(cockpit_session_name /home/u/work/app)"
  b="$(cockpit_session_name /home/u/side/app)"
  [ "$a" = "app" ]
  [ "$a" = "$b" ]
}

@test "cockpit_name_hash is a stable 6-char hex tag" {
  run cockpit_name_hash /home/u/work/app
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{6}$ ]]
}

@test "cockpit_name_hash is deterministic per path and differs across paths" {
  a="$(cockpit_name_hash /home/u/work/app)"
  a2="$(cockpit_name_hash /home/u/work/app)"
  b="$(cockpit_name_hash /home/u/side/app)"
  [ "$a" = "$a2" ]
  [ "$a" != "$b" ]
}
