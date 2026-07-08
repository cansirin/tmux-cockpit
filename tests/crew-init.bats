#!/usr/bin/env bats
# Tests for crew-init.sh — the config scaffold + gitignore (plugin install is
# skipped under COCKPIT_SOCKET, so no real registry is touched).

export COCKPIT_SOCKET="cockpit_crewinit_$$"   # signals crew-init to skip plugins
SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"

setup() {
  repo="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.name "Test Operator"
  git -C "$repo" config user.email "top@example.com"
  # a stand-in for the plugin's template, with the real placeholder tokens
  tmpl="$BATS_TEST_TMPDIR/tmpl.jsonc"
  cat > "$tmpl" <<'JSON'
{
  "operator": { "name": "<operator-name>", "handle": "<operator-handle>" },
  "controlPlaneApprover": { "name": "<control-plane-approver-name>", "login": "<control-plane-approver-login>" },
  "notification": { "channel": "<notification-channel>", "handle": "<notification-handle>" },
  "tmux": { "session": "<tmux-session-name>", "windows": { "ea": "<ea-window-name>", "engineeringManager": "<em-window-name>", "triage": "<triage-window-name>" } },
  "modelTiers": { "ea": "<ea-model-tier>", "engineeringManager": "<em-model-tier>", "triage": "<triage-model-tier>" },
  "wipCaps": { "productLanes": "<wip-cap-product-lanes>", "platformLanes": "<wip-cap-platform-lanes>" }
}
JSON
  export COCKPIT_CREW_TEMPLATE="$tmpl"
}

@test "scaffolds a prefilled config from git identity + defaults" {
  run bash "$SCRIPTS/crew-init.sh" "$repo"
  [ "$status" -eq 0 ]
  cfg="$repo/.claude/crew.config.jsonc"
  [ -f "$cfg" ]
  # identity-derived
  grep -q '"name": "Test Operator"' "$cfg"
  grep -qE '"handle": "@[^<>"]+"' "$cfg"     # gh login, or email localpart when gh is absent
  # window + tier defaults
  grep -q '"engineeringManager": "em"' "$cfg"
  grep -q '"engineeringManager": "build-tier"' "$cfg"
  grep -q '"triage": "planning-tier"' "$cfg"
  # numeric caps land unquoted
  grep -q '"productLanes": 2' "$cfg"
  # the one field left for the human
  grep -q 'fill-me' "$cfg"
  # no placeholder survived except the intentional fill-me
  ! grep -qE '<(operator|em|ea|triage|wip|control|tmux)[^>]*>' "$cfg"
}

@test "gitignores the config" {
  bash "$SCRIPTS/crew-init.sh" "$repo"
  grep -qxF ".claude/crew.config.jsonc" "$repo/.gitignore"
}

@test "is idempotent — a second run leaves the filled config untouched" {
  bash "$SCRIPTS/crew-init.sh" "$repo"
  before="$(cat "$repo/.claude/crew.config.jsonc")"
  run bash "$SCRIPTS/crew-init.sh" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaving"* ]]
  [ "$(cat "$repo/.claude/crew.config.jsonc")" = "$before" ]
  # gitignore not doubled
  [ "$(grep -c 'crew.config.jsonc' "$repo/.gitignore")" -eq 1 ]
}