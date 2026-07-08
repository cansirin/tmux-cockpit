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

@test "cockpit_crew_config_get fails on a missing key or missing file" {
  cfg="$BATS_TEST_TMPDIR/crew.config.jsonc"
  mk_config "$cfg"
  run cockpit_crew_config_get windows nope "$cfg"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run cockpit_crew_config_get windows ea "$BATS_TEST_TMPDIR/absent.jsonc"
  [ "$status" -ne 0 ]
}

@test "cockpit_crew_brief names the right agent def per role" {
  triage="$(cockpit_crew_brief triage /r/.claude/crew.config.jsonc em)"
  [[ "$triage" == *"triage-guy"* ]]
  [[ "$triage" == *"status:needs-triage"* ]]

  em="$(cockpit_crew_brief em /r/.claude/crew.config.jsonc em)"
  [[ "$em" == *"engineering-manager"* ]]
  [[ "$em" == *"coder"* ]]

  ea="$(cockpit_crew_brief ea /r/.claude/crew.config.jsonc em)"
  [[ "$ea" == *"exec-assistant"* ]]
}

@test "cockpit_crew_brief interpolates the execution window name for the seams that route to it" {
  # a non-default em window name must reach the intake + human prompts
  triage="$(cockpit_crew_brief triage /r/cfg build)"
  [[ "$triage" == *"\`build\` window"* ]]
  ea="$(cockpit_crew_brief ea /r/cfg build)"
  [[ "$ea" == *"\`build\` window"* ]]
}

@test "cockpit_crew_brief resolves the config path it was given" {
  b="$(cockpit_crew_brief ea /custom/path/crew.config.jsonc em)"
  [[ "$b" == *"/custom/path/crew.config.jsonc"* ]]
}
