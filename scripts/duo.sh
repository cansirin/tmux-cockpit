#!/usr/bin/env bash
# tmux-cockpit duo — launch a two-pane coordinated Claude "duo" in a repo.
# Bound in the prefix+Space menu; pass a path as $1 (defaults to the current
# pane's path). Two side-by-side panes each run @cockpit-main-cmd (default
# 'claude'), pre-seeded with a bootstrap brief: their label (1.1 / 1.2), their
# sibling's pane id, and a pointer to the duo protocol so they self-coordinate.
#
# Options (set in ~/.tmux.conf):
#   @cockpit-main-cmd        command per pane (default 'claude' — shared with cockpits)
#   @cockpit-duo-protocol    path to the working-agreement doc (default: shipped duo-protocol.md)
#   @cockpit-duo-boot-wait   seconds to let the command boot before seeding the brief (default 6)
#   @cockpit-duo-panes       how many panes: 2 (default) or 3 — 1.1 leads, the rest execute
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Selected startup layers (space-separated names): --layers "a b" wins over the
# $COCKPIT_DUO_SELECTED env, which duo-launch.sh exports from the picker. Both
# optional — no layers means the brief is byte-for-byte the pre-layers brief.
layers="${COCKPIT_DUO_SELECTED:-}"
# Launch-time pane-count override (duo-launch.sh's picker). Empty => fall through
# to the @cockpit-duo-panes option below; a value wins over it.
panes_arg=""
path_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --layers) layers="$2"; shift 2 ;;
    # Only consume $2 when it's a real pane count; a non-2|3 value (e.g. a path) is
    # NOT swallowed — drop the flag, leave the arg for the positional path.
    --panes)  case "${2:-}" in 2|3) panes_arg="$2"; shift 2 ;; *) shift ;; esac ;;
    *)        path_arg="$1"; shift ;;
  esac
done

target="${path_arg:-$PWD}"
if ! target="$(cd "$target" 2>/dev/null && pwd)"; then
  echo "duo: not a directory: ${path_arg:-$PWD}" >&2
  exit 1
fi

name="$(cockpit_resolve_name "$(cockpit_duo_name "$target")" "$target")"

cmd="$(_tm show-option -gqv @cockpit-main-cmd 2>/dev/null)"
[ -z "$cmd" ] && cmd="claude"

protocol="$(_tm show-option -gqv @cockpit-duo-protocol 2>/dev/null)"
protocol="${protocol/#\~/$HOME}"
[ -z "$protocol" ] && protocol="$SCRIPT_DIR/../duo-protocol.md"

boot_wait="$(_tm show-option -gqv @cockpit-duo-boot-wait 2>/dev/null)"
[ -z "$boot_wait" ] && boot_wait=6

# Focus the session if it already exists — never spin up a second.
focus() {
  if [ -z "${TMUX:-}" ] && [ -t 1 ]; then
    _tm attach -t "$name"
  else
    _tm switch-client -t "$name" 2>/dev/null \
      || echo "duo: '$name' is ready — switch with: tmux switch-client -t $name"
  fi
}
# "=$name" forces an exact match (a bare target prefix-matches in tmux).
if _tm has-session -t "=$name" 2>/dev/null; then
  # Claim a pre-existing/unstamped duo on re-focus so it isn't a hijack magnet;
  # harmless when it's already ours. resolve_name guarantees $name is ours here.
  _tm set -t "$name" @cockpit-path "$target"
  focus
  exit 0
fi

# How many panes: 2 (default) or 3 — 1.1 leads, the rest execute + review. The
# protocol caps a duo at three; anything else falls back to 2. --panes (launch-time
# picker) overrides the @cockpit-duo-panes option; absent it, the option is the
# default. Both run through the same 2|3 guard so an odd value falls back to 2.
npanes="${panes_arg:-$(_tm show-option -gqv @cockpit-duo-panes 2>/dev/null)}"
case "$npanes" in 2|3) ;; *) npanes=2 ;; esac

# Side-by-side panes, all in the repo (one new-session + npanes-1 splits).
_tm new-session -ds "$name" -c "$target"
# Record the repo path so a same-basename repo elsewhere resolves to its own duo
# instead of re-focusing this one (cockpit_resolve_name reads this back).
_tm set -t "$name" @cockpit-path "$target"
i=1
while [ "$i" -lt "$npanes" ]; do
  _tm split-window -h -t "$name" -c "$target"
  i=$((i + 1))
done
# 3 panes: leader (1.1, created first) is the wide main pane on the left, workers
# 1.2/1.3 stack on the right — even-horizontal thirds wrap diffs badly. 2 stays
# side-by-side.
if [ "$npanes" -eq 3 ]; then
  _tm set -t "$name" main-pane-width "60%"
  _tm select-layout -t "$name" main-vertical
else
  _tm select-layout -t "$name" even-horizontal
fi

# Pane ids in creation order (bash 3.2-safe — no mapfile/arrays needed).
panes="$(_tm list-panes -t "$name" -F '#{pane_id}')"

# Label each pane 1.<n> on its border (scoped to this session) and boot the
# command in it — so you always know which pane is which and that a duo is live.
# The same loop records the duo identity registry (see below) so every duo
# script can re-resolve label<->pane after claude's OSC clobbers the title.
_tm set -t "$name" @cockpit-duo-npanes "$npanes"
i=1
while [ "$i" -le "$npanes" ]; do
  pane="$(printf '%s\n' "$panes" | sed -n "${i}p")"
  _tm select-pane -t "$pane" -T "1.$i"
  # Session map (label -> pane id) plus a pane-local label. The pane option
  # survives the title clobber, so a compacted pane can still learn who it is.
  _tm set -t "$name" "@$(cockpit_duo_pane_key "1.$i")" "$pane"
  _tm set -p -t "$pane" @cockpit-duo-label "1.$i"
  _tm send-keys -t "$pane" "$cmd" Enter
  i=$((i + 1))
done
_tm set -t "$name" pane-border-status top
_tm set -t "$name" pane-border-format " duo #{pane_title} "

# duo_siblings SELF_INDEX -> "1.<j> <pane-j> ..." for every pane but SELF_INDEX,
# the variadic sibling pairs cockpit_duo_brief expects.
duo_siblings() {
  local self="$1" j=1 out=""
  while [ "$j" -le "$npanes" ]; do
    if [ "$j" -ne "$self" ]; then
      out="$out 1.$j $(printf '%s\n' "$panes" | sed -n "${j}p")"
    fi
    j=$((j + 1))
  done
  printf '%s' "$out"
}

# Resolve the selected layers to a single seed string, shared by every pane (a
# duo-wide axis, not per-pane in v1). Each name's seed is concatenated with "; ";
# an unknown name contributes nothing. Empty when no layers were selected, so
# cockpit_duo_compose_brief is a no-op and the brief is unchanged.
layer_dirs="$(cockpit_duo_layer_dirs)"
layer_seed=""
for lname in $layers; do
  s="$(cockpit_duo_layer_seed "$lname" $layer_dirs)" || continue
  [ -z "$s" ] && continue
  if [ -z "$layer_seed" ]; then layer_seed="$s"; else layer_seed="$layer_seed; $s"; fi
done

# Compute each pane's brief now (pane<TAB>brief per line) and hand the deferred
# send to the tmux SERVER via run-shell -b. NOT a shell `&` job: the prefix+Space
# launcher runs inside a display-popup, and a backgrounded shell job is killed
# when the popup closes — before boot-wait elapses — so nothing would reach the
# panes. A server-side run-shell job outlives the popup. Briefs are single-line,
# so the tab delimiter is safe.
briefs="$(mktemp "${TMPDIR:-/tmp}/cockpit-duo-briefs.XXXXXX")"
tab="$(printf '\t')"
i=1
while [ "$i" -le "$npanes" ]; do
  pane="$(printf '%s\n' "$panes" | sed -n "${i}p")"
  # shellcheck disable=SC2046  # word-splitting the sibling pairs is intentional
  brief="$(cockpit_duo_brief "1.$i" "$protocol" $(duo_siblings "$i"))"
  brief="$(cockpit_duo_compose_brief "$brief" "$layer_seed")"
  printf '%s%s%s\n' "$pane" "$tab" "$brief" >> "$briefs"
  i=$((i + 1))
done
_tm run-shell -b "'$SCRIPT_DIR/duo-seed.sh' '$briefs' '$boot_wait'"

focus
