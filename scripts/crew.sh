#!/usr/bin/env bash
# tmux-cockpit crew — launch the kampus pipeline-crew as a 3-window tmux session.
# Bound in the prefix+Space menu (key c); pass a path as $1 (defaults to the
# current pane's path). One session `<repo>-crew` with three windows — the intake,
# execution, and human seams — each launching @cockpit-main-cmd (default 'claude')
# AS its pipeline-crew agent def (`--agent`) on its model tier, so the shipped def
# drives the session natively — no typed brief. Idempotent: re-focuses an existing
# crew instead of spawning a second.
#
# Config seam: window names and per-role model tiers come from the pipeline-crew
# personalization file ($CREW_CONFIG, else <repo>/.claude/crew.config.jsonc) — the
# plugin's own seam, so tmux-cockpit stores none of it and nothing drifts. Absent
# config still launches (default window names). Tier -> model id is the one thing
# the plugin doesn't own, mapped once per tier via @cockpit-crew-model-<tier>.
#
# Options (set in ~/.tmux.conf):
#   @cockpit-main-cmd              command per window (default 'claude'; --agent needs claude)
#   @cockpit-crew-boot-wait        seconds to let the command boot before the kickoff (default 6)
#   @cockpit-crew-model-<tier>     model id for a config tier name (e.g.
#                                  @cockpit-crew-model-build-tier 'opus'); unset -> no --model
#   @cockpit-crew-agent-prefix     agent registry namespace (default 'pipeline-crew:')
#   @cockpit-crew-permission-mode  --permission-mode for every window (e.g. 'auto'); unset -> claude default
#   @cockpit-crew-autostart        type the intake/execution loop kickoffs (default on; '0'/'off' to skip)
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

# Agent registry namespace for `--agent`: installed plugin agents resolve as
# `<plugin>:<agent>`, so the shipped defs are `pipeline-crew:<def>`. Override if
# your registry surfaces them differently (e.g. vendored, bare names).
agent_prefix="$(_tm show-option -gqv @cockpit-crew-agent-prefix 2>/dev/null)"
[ -z "$agent_prefix" ] && agent_prefix="pipeline-crew:"

# --permission-mode for every window (unset -> claude's own default). 'auto' lets
# the crew run unattended.
perm="$(_tm show-option -gqv @cockpit-crew-permission-mode 2>/dev/null)"

# Whether to type the standing-loop kickoffs after boot (default on).
autostart="$(_tm show-option -gqv @cockpit-crew-autostart 2>/dev/null)"
[ -z "$autostart" ] && autostart="on"

# The pipeline-crew personalization seam. First launch in a repo that has none:
# run stand-up (install the plugins, scaffold + prefill this file, gitignore it),
# then continue — so one press of `c` does everything. Idempotent and only fires
# while the config is absent, so steady-state launches never re-run it.
config="${CREW_CONFIG:-$target/.claude/crew.config.jsonc}"
[ -f "$config" ] || "$SCRIPT_DIR/crew-init.sh" "$target" || true

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
  local tier model
  tier="$(cockpit_crew_config_get modelTiers "$1" "$config" 2>/dev/null)"
  [ -z "$tier" ] && return 0
  model="$(_tm show-option -gqv "@cockpit-crew-model-$tier" 2>/dev/null)"
  # Baked default so a plain install needs no ~/.tmux.conf model options; the two
  # standard tiers both resolve to opus (no downgrade), overridable per tier.
  if [ -z "$model" ]; then
    case "$tier" in planning-tier|build-tier) model="opus" ;; esac
  fi
  printf '%s' "$model"
}
model_triage="$(crew_model triage)"
model_em="$(crew_model engineeringManager)"
model_ea="$(crew_model ea)"

# Session with one window per seam, all in the repo. Intake first, then execution,
# then human — the crew's conveyor order.
# Capture each window's ID at creation and address it by ID thereafter — a config
# window name containing a `.` or `:` would otherwise be mis-parsed as a
# window.pane / session:window target by send-keys/select-window.
wid_triage="$(_tm new-session -dP -F '#{window_id}' -s "$name" -n "$win_triage" -c "$target")"
# Record the repo path so a same-basename repo elsewhere resolves to its own crew
# instead of re-focusing this one (cockpit_resolve_name reads this back).
_tm set -t "$name" @cockpit-path "$target"
wid_em="$(_tm new-window -t "$name" -n "$win_em" -c "$target" -PF '#{window_id}')"
wid_ea="$(_tm new-window -t "$name" -n "$win_ea" -c "$target" -PF '#{window_id}')"

# Launch each window AS its pipeline-crew agent def, on its tier's model. --agent
# binds the session to the shipped def natively (the def resolves the rest of the
# personalization seam itself); --permission-mode lets the crew run unattended.
boot() {  # WINDOW_ID ROLE MODEL
  local run
  run="$cmd --agent $agent_prefix$(cockpit_crew_agent_def "$2")"
  [ -n "$3" ] && run="$run --model $3"
  [ -n "$perm" ] && run="$run --permission-mode $perm"
  _tm send-keys -t "$1" "$run" Enter
}
boot "$wid_triage" triage "$model_triage"
boot "$wid_em" em "$model_em"
boot "$wid_ea" ea "$model_ea"

# Kick off the standing loops. --agent primes the persona, but a session waits for
# a turn to act, so the intake + execution seams get a one-line "begin" typed in
# after boot; the EA has no kickoff — it waits for you. The deferred send goes to
# the tmux SERVER via run-shell -b: NOT a shell `&` job, which the prefix+Space
# display-popup would kill on close before boot-wait elapses. Kickoffs are single
# -line, so the tab delimiter is safe.
case "$autostart" in
  0|off|false|no) ;;
  *)
    kicks="$(mktemp "${TMPDIR:-/tmp}/cockpit-crew-kick.XXXXXX")"
    tab="$(printf '\t')"
    kick_one() {  # WINDOW_ID ROLE
      local pane line
      line="$(cockpit_crew_kickoff "$2")"
      [ -z "$line" ] && return
      pane="$(_tm list-panes -t "$1" -F '#{pane_id}' | head -1)"
      printf '%s%s%s\n' "$pane" "$tab" "$line" >> "$kicks"
    }
    kick_one "$wid_triage" triage
    kick_one "$wid_em" em
    if [ -s "$kicks" ]; then
      _tm run-shell -b "'$SCRIPT_DIR/crew-seed.sh' '$kicks' '$boot_wait'"
    else
      rm -f "$kicks"
    fi
    ;;
esac

# Land on the EA window — the human's single point of contact into the crew.
_tm select-window -t "$wid_ea"
focus
