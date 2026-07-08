#!/usr/bin/env bats
# Unit tests for the crew helpers — pure logic, no tmux required.

setup() {
  . "${BATS_TEST_DIRNAME}/../scripts/lib.sh"
}

@test "cockpit_crew_name suffixes the base name with -crew" {
  [ "$(cockpit_crew_name /home/me/projects/app)" = "app-crew" ]
}

# A filled (fictional) config to read window names and tiers from.
mk_config() {
  cat > "$1" <<'JSON'
{
  // fictional stand-up — no real operator data
  "operator": { "name": "Robin Operator", "handle": "@robin" },
  "tmux": {
    "session": "crew",
    "windows": { "ea": "front", "engineeringManager": "build", "triage": "intake" }
  },
  "modelTiers": { "ea": "planning-tier", "engineeringManager": "build-tier", "triage": "planning-tier" }
}
JSON
}

@test "cockpit_crew_config_get reads a window name scoped to its parent object" {
  cfg="$BATS_TEST_TMPDIR/crew.config.jsonc"
  mk_config "$cfg"
  [ "$(cockpit_crew_config_get windows triage "$cfg")" = "intake" ]
  [ "$(cockpit_crew_config_get windows engineeringManager "$cfg")" = "build" ]
  [ "$(cockpit_crew_config_get windows ea "$cfg")" = "front" ]
}

@test "cockpit_crew_config_get disambiguates a key that repeats across objects" {
  cfg="$BATS_TEST_TMPDIR/crew.config.jsonc"
  mk_config "$cfg"
  # `ea` lives in both windows and modelTiers — parent scoping keeps them apart.
  [ "$(cockpit_crew_config_get windows ea "$cfg")" = "front" ]
  [ "$(cockpit_crew_config_get modelTiers ea "$cfg")" = "planning-tier" ]
  [ "$(cockpit_crew_config_get modelTiers engineeringManager "$cfg")" = "build-tier" ]
}

@test "cockpit_crew_config_get does NOT leak a same-named key from a later object" {
  # regression: a key absent from its parent must fall back (exit 1), not return
  # a same-named key from a later object. Here `triage` is dropped from windows
  # but still present in modelTiers.
  cfg="$BATS_TEST_TMPDIR/partial.jsonc"
  cat > "$cfg" <<'JSON'
{
  "tmux": { "windows": { "ea": "front", "engineeringManager": "build" } },
  "modelTiers": { "ea": "planning-tier", "engineeringManager": "build-tier", "triage": "planning-tier" }
}
JSON
  run cockpit_crew_config_get windows triage "$cfg"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  # the keys that ARE in windows still resolve correctly
  [ "$(cockpit_crew_config_get windows ea "$cfg")" = "front" ]
  [ "$(cockpit_crew_config_get modelTiers triage "$cfg")" = "planning-tier" ]
}

@test "cockpit_crew_config_get fails on a missing key or missing file" {
  cfg="$BATS_TEST_TMPDIR/crew.config.jsonc"
  mk_config "$cfg"
  run cockpit_crew_config_get windows nope "$cfg"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run cockpit_crew_config_get windows ea "$BATS_TEST_TMPDIR/absent.jsonc"
  [ "$status" -ne 0 ]
}

@test "cockpit_crew_agent_def maps each role to its shipped def name" {
  [ "$(cockpit_crew_agent_def triage)" = "triage-guy" ]
  [ "$(cockpit_crew_agent_def em)" = "engineering-manager" ]
  [ "$(cockpit_crew_agent_def ea)" = "exec-assistant" ]
}

@test "cockpit_crew_kickoff gives the intake + execution seams a begin line" {
  [[ "$(cockpit_crew_kickoff triage)" == Begin* ]]
  [[ "$(cockpit_crew_kickoff em)" == Begin* ]]
}

@test "cockpit_crew_kickoff leaves the EA idle (it waits for the operator)" {
  [ -z "$(cockpit_crew_kickoff ea)" ]
}
