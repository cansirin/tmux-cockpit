#!/usr/bin/env bats
# A parse gate over every shipped script. Cheap, and it catches the class of
# break that otherwise only shows up as a pile of unrelated test failures — an
# apostrophe inside a comment inside a $( ) is an unterminated quote, not a typo,
# and it takes the whole file down.

@test "every script parses" {
  for f in "${BATS_TEST_DIRNAME}"/../scripts/*.sh "${BATS_TEST_DIRNAME}"/../cockpit.tmux; do
    run bash -n "$f"
    [ "$status" -eq 0 ] || {
      echo "parse error in $f:"
      echo "$output"
      return 1
    }
  done
}
