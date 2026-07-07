#!/usr/bin/env bash
# tmux-cockpit shared helpers — sourced by the other scripts, unit-tested in tests/.

# _tm [...] — run tmux, honoring an optional isolated socket so tests never touch
# the user's real server. Set COCKPIT_SOCKET to use `tmux -L <socket>`.
_tm() {
  if [ -n "${COCKPIT_SOCKET:-}" ]; then
    tmux -L "$COCKPIT_SOCKET" "$@"
  else
    tmux "$@"
  fi
}

# cockpit_opt @option DEFAULT -> the global option's value, or DEFAULT when it is
# unset or empty. The single source of truth for a tunable, so cockpit.tmux and
# the render scripts read the same value (and the same default) for a given knob.
cockpit_opt() {
  local v
  v="$(_tm show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${v:-$2}"
}

# cockpit_session_name PATH -> a readable, tmux-safe *base* name for PATH.
# Keeps the basename so sessions read as their project. Folders named monorepo*
# would otherwise all read as "monorepo", so those gain their parent dir for
# legibility. ' ' '.' ':' become '_'. This is NOT guaranteed unique across paths
# (two repos with the same basename produce the same base) — cockpit_resolve_name
# is what enforces the path<->session bijection at create/switch time.
cockpit_session_name() {
  local path="$1" base name
  base="$(basename "$path")"
  case "$base" in
    monorepo*) name="$(basename "$(dirname "$path")")-$base" ;;
    *)         name="$base" ;;
  esac
  printf '%s' "$name" | tr ' .:' '___'
}

# cockpit_duo_name PATH -> the base name for a Claude "duo" on PATH: a "-duo"
# suffix on the normal base name, so a duo never collides with the project's
# regular cockpit session.
cockpit_duo_name() {
  printf '%s-duo' "$(cockpit_session_name "$1")"
}

# cockpit_name_hash PATH -> a short, stable hex tag derived from PATH. Pure and
# deterministic (CRC32 via cksum, low 24 bits) — same path always yields the same
# tag, distinct paths practically never collide. Used only to disambiguate two
# repos that share a base name; the readable base stays out front.
cockpit_name_hash() {
  local crc
  crc="$(printf '%s' "$1" | cksum | awk '{print $1}')"
  printf '%06x' "$((crc & 0xFFFFFF))"
}

# cockpit_resolve_name BASE PATH -> the session name to actually use for PATH.
# Enforces the path<->session bijection: reuse BASE only when it's free or is
# already this exact PATH (matched via the session's stored @cockpit-path); if
# BASE is taken by a *different* path, fall back to "BASE-<hash>" so the two
# never clobber each other. Callers must `set @cockpit-path PATH` on create for
# the match to work (a legacy session with no recorded path is treated as ours).
cockpit_resolve_name() {
  local base="$1" path="$2"
  # "=$base" forces an EXACT session-name match. A bare target prefix-matches in
  # tmux, so a lone "app-duo" would otherwise answer a query for "app" and
  # wrongly disambiguate the plain session — anchor it.
  if ! _tm has-session -t "=$base" 2>/dev/null; then
    printf '%s' "$base"; return
  fi
  local recorded
  recorded="$(_tm show-option -t "$base" -qv @cockpit-path 2>/dev/null)"
  if [ -z "$recorded" ] || [ "$recorded" = "$path" ]; then
    printf '%s' "$base"; return
  fi
  printf '%s-%s' "$base" "$(cockpit_name_hash "$path")"
}

# cockpit_duo_pane_key LABEL -> the tmux option name (sans @) that maps LABEL to
# a pane id in the session registry: `1.2` -> `cockpit-duo-pane-1-2`. tmux option
# names allow letters/digits/hyphen/underscore but reject a dot, so the label's
# dot is encoded as a hyphen. Callers prepend '@'.
cockpit_duo_pane_key() {
  printf 'cockpit-duo-pane-%s' "$(printf '%s' "$1" | tr '.' '-')"
}

# cockpit_duo_reviewed_by SELF_LABEL NPANES -> the label of the pane that reviews
# SELF, per the directed ring `1.2 -> 1.3 -> 1.1 -> 1.2` (§4). For numeric k in
# 1..N: reviewed_by(k) = (k mod N) + 1. Collapses to the pair at N=2.
cockpit_duo_reviewed_by() {
  local k="${1#1.}" n="$2"
  printf '1.%d' "$(( (k % n) + 1 ))"
}

# cockpit_duo_reviews SELF_LABEL NPANES -> the label of the pane whose changes
# SELF reviews — the inverse of the ring edge: reviews(k) = ((k-2+N) mod N) + 1.
cockpit_duo_reviews() {
  local k="${1#1.}" n="$2"
  printf '1.%d' "$(( ((k - 2 + n) % n) + 1 ))"
}

# cockpit_duo_brief SELF PROTOCOL  SIB_LABEL SIB_PANE [SIB_LABEL SIB_PANE ...]
#   -> the bootstrap prompt seeded into one duo pane: its label, its role (1.1
#   leads and coordinates; the others execute and review), how to reach each
#   sibling, and the protocol to read. Variadic in the sibling pairs so a
#   three-pane duo works (a pane then has two siblings). Pure string assembly
#   (unit-tested); the caller send-keys it.
cockpit_duo_brief() {
  local self="$1" protocol="$2" role reach=""
  shift 2
  case "$self" in
    1.1) role="You are the leader: track the work pipeline, split it into lanes, and delegate. Stay on the shared base and keep your tree clean. You are in the review ring too." ;;
    *)   role="You execute and review: take a lane, do the work in its own worktree, and review the sibling the protocol's review ring assigns you." ;;
  esac
  while [ "$#" -ge 2 ]; do
    reach="$reach Sibling: $1 at $2 — reach it with: tmux send-keys -t $2 -l \"$self: <msg>\" Enter."
    shift 2
  done
  printf '%s' "You are pane $self in a Claude duo. Read $protocol and follow it. \
$role$reach \
Default to subagents in worktrees for all real work; orchestrate, not execute. \
Leave durable notes on the issue/PR or a handoff file so you can revive yourself after a compaction. \
Greet your sibling, then wait for the human."
}

# cockpit_duo_heartbeat SELF STATE -> a one-line heartbeat a pane posts so a
# stalled or silently-compacted sibling gets noticed (§8 of the protocol). The
# timestamp is prepended by the caller (kept out so the line is unit-testable).
cockpit_duo_heartbeat() {
  printf 'heartbeat %s: %s' "$1" "${2:-alive}"
}
