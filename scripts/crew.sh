#!/usr/bin/env bash
# tmux-cockpit crew — launch the kampus pipeline-crew as a tmux session.
# Bound in the prefix+Space menu (key c); pass a path as $1 (defaults to the
# current pane's path). One session `<repo>-crew` with the intake, execution, and
# human seams as three PANES in one row (all visible at once) — or three windows
# with @cockpit-crew-layout windows — each launching @cockpit-main-cmd
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
#   @cockpit-crew-layout           'panes' (default; all 3 visible in one window) or 'windows'
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

# Layout: three PANES in one window (default) so all three seams are visible at
# once, or three WINDOWS (@cockpit-crew-layout windows) if you'd rather tab between
# them / your crew defs coordinate by window name. Each seam's PANE id is captured
# at creation and addressed by id thereafter — immune to a config name containing
# a `.`/`:`, which send-keys/select-* would otherwise mis-parse as a target.
layout="$(_tm show-option -gqv @cockpit-crew-layout 2>/dev/null)"
[ -z "$layout" ] && layout="panes"

# The config the AGENTS resolve. In windows mode it's the repo config unchanged
# (real windows named ea/em/triage exist). In panes mode the crew defs' relay —
# `send-keys -t <session>:<tmux.windows.ea>` — has no window to hit, so the agents
# get a RUNTIME copy whose windows.* are the panes' `win.pane` index targets (which
# `<session>:1.1` resolves to). The repo's own config stays readable, untouched.
crew_config="$config"

if [ "$layout" = "windows" ]; then
  id_triage="$(_tm new-session -dP -F '#{pane_id}' -s "$name" -n "$win_triage" -c "$target")"
  # Record the repo path so a same-basename repo elsewhere resolves to its own crew
  # instead of re-focusing this one (cockpit_resolve_name reads this back).
  _tm set -t "$name" @cockpit-path "$target"
  id_em="$(_tm new-window -t "$name" -n "$win_em" -c "$target" -PF '#{pane_id}')"
  id_ea="$(_tm new-window -t "$name" -n "$win_ea" -c "$target" -PF '#{pane_id}')"
  focus_sel="select-window"   # a pane id resolves to its window for select-window
else
  # Three equal columns in one row (ea | triage | em), so all seams sit side by
  # side and are readable at a glance.
  id_ea="$(_tm new-session -dP -F '#{pane_id}' -s "$name" -c "$target")"
  _tm set -t "$name" @cockpit-path "$target"
  id_triage="$(_tm split-window -t "$id_ea" -h -c "$target" -PF '#{pane_id}')"
  id_em="$(_tm split-window -t "$id_triage" -h -c "$target" -PF '#{pane_id}')"
  _tm select-layout -t "$name" even-horizontal
  # Title each pane with its (config) role name so the borders read ea/triage/em.
  _tm select-pane -t "$id_triage" -T "$win_triage"
  _tm select-pane -t "$id_em" -T "$win_em"
  _tm select-pane -t "$id_ea" -T "$win_ea"
  _tm set -t "$name" pane-border-status top
  _tm set -t "$name" pane-border-format " #{pane_title} "
  focus_sel="select-pane"

  # Rewrite windows.* → live `win.pane` targets so a peer relay resolves to the
  # pane. Only the windows block is touched (modelTiers keeps its tier names).
  if [ -f "$config" ]; then
    t_ea="$(_tm display-message -p -t "$id_ea" '#{window_index}.#{pane_index}')"
    t_triage="$(_tm display-message -p -t "$id_triage" '#{window_index}.#{pane_index}')"
    t_em="$(_tm display-message -p -t "$id_em" '#{window_index}.#{pane_index}')"
    rt="${COCKPIT_CREW_RUNTIME:-$(mktemp "${TMPDIR:-/tmp}/cockpit-crew-rt.XXXXXX")}"
    if awk -v ea="$t_ea" -v em="$t_em" -v tr="$t_triage" '
        /"windows"[[:space:]]*:[[:space:]]*\{/ {inw=1}
        inw {
          sub(/"ea"[[:space:]]*:[[:space:]]*"[^"]*"/,                 "\"ea\": \"" ea "\"")
          sub(/"engineeringManager"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"engineeringManager\": \"" em "\"")
          sub(/"triage"[[:space:]]*:[[:space:]]*"[^"]*"/,             "\"triage\": \"" tr "\"")
          if (/}/) inw=0
        }
        {print}
      ' "$config" > "$rt"; then
      crew_config="$rt"
    else
      rm -f "$rt"
    fi
  fi
fi

# Launch each seam AS its pipeline-crew agent def, on its tier's model. --agent
# binds the session to the shipped def natively (the def resolves the rest of the
# personalization seam itself); --permission-mode lets the crew run unattended.
boot() {  # PANE_ID ROLE MODEL
  local run
  run="$cmd --agent $agent_prefix$(cockpit_crew_agent_def "$2")"
  [ -n "$3" ] && run="$run --model $3"
  [ -n "$perm" ] && run="$run --permission-mode $perm"
  # Point the agent at the resolved config (the runtime copy in panes mode) so its
  # relay targets the right seam; harmless in windows mode where it equals $config.
  _tm send-keys -t "$1" "CREW_CONFIG='$crew_config' $run" Enter
}
boot "$id_triage" triage "$model_triage"
boot "$id_em" em "$model_em"
boot "$id_ea" ea "$model_ea"

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
    kick_one() {  # PANE_ID ROLE
      local line
      line="$(cockpit_crew_kickoff "$2")"
      [ -z "$line" ] && return
      printf '%s%s%s\n' "$1" "$tab" "$line" >> "$kicks"
    }
    kick_one "$id_triage" triage
    kick_one "$id_em" em
    if [ -s "$kicks" ]; then
      _tm run-shell -b "'$SCRIPT_DIR/crew-seed.sh' '$kicks' '$boot_wait'"
    else
      rm -f "$kicks"
    fi
    ;;
esac

# Land on the EA seam — the human's single point of contact into the crew.
_tm "$focus_sel" -t "$id_ea"
focus
