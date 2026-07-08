#!/usr/bin/env bash
# tmux-cockpit crew — launch the kampus pipeline-crew as a 3-window tmux session.
# Bound in the prefix+Space menu (key c); pass a path as $1 (defaults to the
# current pane's path). One session `<repo>-crew` with three windows — the intake,
# execution, and human seams — each running @cockpit-main-cmd (default 'claude')
# on its configured model tier, pre-seeded with its role spawn-prompt so the crew
# self-coordinates. Idempotent: re-focuses an existing crew instead of spawning a
# second.
#
# Config seam: window names and per-role model tiers come from the pipeline-crew
# personalization file ($CREW_CONFIG, else <repo>/.claude/crew.config.jsonc) — the
# plugin's own seam, so tmux-cockpit stores none of it and nothing drifts. Absent
# config still launches (default window names); the crew defs then self-prompt for
# stand-up. Tier -> model id is the one thing the plugin doesn't own, mapped once
# per tier via @cockpit-crew-model-<tier>; unset -> plain @cockpit-main-cmd.
#
# Options (set in ~/.tmux.conf):
#   @cockpit-main-cmd            command per window (default 'claude')
#   @cockpit-crew-boot-wait      seconds to let the command boot before seeding (default 6)
#   @cockpit-crew-model-<tier>   model id for a tier name from the config (e.g.
#                                @cockpit-crew-model-build-tier 'opus'); unset -> no --model
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

target="${1:-$PWD}"
if ! target="$(cd "$target" 2>/dev/null && pwd)"; then
  echo "crew: not a directory: ${1:-$PWD}" >&2
  exit 1
fi

name="$(cockpit_resolve_name "$(cockpit_crew_name "$target")" "$target")"

cmd="$(_tm show-option -gqv @cockpit-main-cmd 2>/dev/null)"
[ -z "$cmd" ] && cmd="claude"

boot_wait="$(_tm show-option -gqv @cockpit-crew-boot-wait 2>/dev/null)"
[ -z "$boot_wait" ] && boot_wait=6

# The pipeline-crew personalization seam — may be absent (launch degrades to
# default window names and the defs prompt for stand-up).
config="${CREW_CONFIG:-$target/.claude/crew.config.jsonc}"

# Focus the session if it already exists — never spin up a second.
focus() {
  if [ -z "${TMUX:-}" ] && [ -t 1 ]; then
    _tm attach -t "$name"
  else
    _tm switch-client -t "$name" 2>/dev/null \
      || echo "crew: '$name' is ready — switch with: tmux switch-client -t $name"
  fi
}
# "=$name" forces an exact match (a bare target prefix-matches in tmux).
if _tm has-session -t "=$name" 2>/dev/null; then
  # Claim a pre-existing/unstamped crew on re-focus so it isn't a hijack magnet;
  # harmless when it's already ours. resolve_name guarantees $name is ours here.
  _tm set -t "$name" @cockpit-path "$target"
  focus
  exit 0
fi

# Window names — the config value the crew defs address each other by, or the
# shipped default. The config key for the execution window is `engineeringManager`
# (the def's role name); its default display name is `em`.
win_triage="$(cockpit_crew_config_get windows triage "$config" 2>/dev/null)"
[ -z "$win_triage" ] && win_triage="triage"
win_em="$(cockpit_crew_config_get windows engineeringManager "$config" 2>/dev/null)"
[ -z "$win_em" ] && win_em="em"
win_ea="$(cockpit_crew_config_get windows ea "$config" 2>/dev/null)"
[ -z "$win_ea" ] && win_ea="ea"

# tier -> model id: read the role's logical tier from the config, then map it to a
# concrete --model through the tmux option for that tier. No option -> plain cmd,
# so a role never silently downgrades on a made-up model.
crew_model() {  # ROLE_KEY (config modelTiers key)
  local tier
  tier="$(cockpit_crew_config_get modelTiers "$1" "$config" 2>/dev/null)"
  [ -z "$tier" ] && return 0
  _tm show-option -gqv "@cockpit-crew-model-$tier" 2>/dev/null
}
model_triage="$(crew_model triage)"
model_em="$(crew_model engineeringManager)"
model_ea="$(crew_model ea)"

# Session with one window per seam, all in the repo. Intake first, then execution,
# then human — the crew's conveyor order.
_tm new-session -ds "$name" -n "$win_triage" -c "$target"
# Record the repo path so a same-basename repo elsewhere resolves to its own crew
# instead of re-focusing this one (cockpit_resolve_name reads this back).
_tm set -t "$name" @cockpit-path "$target"
_tm new-window -t "$name" -n "$win_em" -c "$target"
_tm new-window -t "$name" -n "$win_ea" -c "$target"

# Boot the command in each window on its tier's model.
boot() {  # WINDOW MODEL
  local run="$cmd"
  [ -n "$2" ] && run="$cmd --model $2"
  _tm send-keys -t "$name:$1" "$run" Enter
}
boot "$win_triage" "$model_triage"
boot "$win_em" "$model_em"
boot "$win_ea" "$model_ea"

# Compute each window's spawn-prompt now (pane<TAB>brief per line) and hand the
# deferred send to the tmux SERVER via run-shell -b. NOT a shell `&` job: the
# prefix+Space launcher runs inside a display-popup, and a backgrounded shell job
# is killed when the popup closes — before boot-wait elapses — so nothing would
# reach the windows. A server-side run-shell job outlives the popup. Briefs are
# single-line, so the tab delimiter is safe.
briefs="$(mktemp "${TMPDIR:-/tmp}/cockpit-crew-briefs.XXXXXX")"
tab="$(printf '\t')"
seed_one() {  # WINDOW ROLE
  local pane brief
  pane="$(_tm list-panes -t "$name:$1" -F '#{pane_id}' | head -1)"
  brief="$(cockpit_crew_brief "$2" "$config" "$win_em")"
  printf '%s%s%s\n' "$pane" "$tab" "$brief" >> "$briefs"
}
seed_one "$win_triage" triage
seed_one "$win_em" em
seed_one "$win_ea" ea
_tm run-shell -b "'$SCRIPT_DIR/crew-seed.sh' '$briefs' '$boot_wait'"

# Land on the EA window — the human's single point of contact into the crew.
_tm select-window -t "$name:$win_ea"
focus
