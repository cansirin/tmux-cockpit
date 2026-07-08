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

# cockpit_crew_name PATH -> the base name for a pipeline-crew on PATH: a "-crew"
# suffix on the normal base name, so the crew never collides with the project's
# regular cockpit session.
cockpit_crew_name() {
  printf '%s-crew' "$(cockpit_session_name "$1")"
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
  # tmux, so a lone "app-crew" would otherwise answer a query for "app" and
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

# cockpit_crew_config_get PARENT KEY FILE -> the string value of KEY inside the
# PARENT object of a crew.config.jsonc (the pipeline-crew personalization seam),
# e.g. `windows engineeringManager` -> "em". Scoping the read to PARENT is what
# disambiguates keys that repeat across objects (`ea` lives in both `windows` and
# `modelTiers`). Empty output + non-zero status when absent. This reads only the
# handful of keys tmux-cockpit needs to stand up the windows — the crew defs read
# the rest of the file themselves at spawn, so there is no second parser to keep
# in sync. `//` line comments are stripped; a value must therefore not contain
# `//` (the keys we read — window names, tier names — never do).
cockpit_crew_config_get() {
  local parent="$1" key="$2" file="$3"
  [ -f "$file" ] || return 1
  awk -v parent="$parent" -v key="$key" '
    { line=$0; sub(/\/\/.*/, "", line) }
    !inblk && line ~ "\"" parent "\"[[:space:]]*:[[:space:]]*\\{" { inblk=1 }
    inblk && match(line, "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"") {
      v=substr(line, RSTART, RLENGTH)
      sub(/^[^:]*:[[:space:]]*"/, "", v); sub(/"$/, "", v)
      print v; found=1; exit
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

# cockpit_crew_brief ROLE CONFIG EM_WINDOW -> the spawn prompt seeded into one
# crew window: it tells the session which pipeline-crew agent def to follow, its
# seam behaviour, and to resolve the personalization seam at CONFIG. ROLE is one
# of triage|em|ea. The intake and human seams reference the execution window by
# name (EM_WINDOW) since that is where they hand work / route execution. Pure
# string assembly (unit-tested); crew.sh send-keys it. Kept single-line so the
# crew-seed.sh tab split stays safe.
cockpit_crew_brief() {
  local role="$1" config="$2" em_win="$3"
  case "$role" in
    triage)
      printf '%s' "You are the pipeline-crew intake session. Follow the \`triage-guy\` agent def. Run the report → triage loop over the \`status:needs-triage\` queue and plan freshly-triaged epics (spawning the \`planner\`). Resolve the personalization seam from $config before acting; hand triaged issues to the \`$em_win\` window." ;;
    em)
      printf '%s' "You are the pipeline-crew execution conductor. Follow the \`engineering-manager\` agent def. Drive triaged issues to landed merges by spawning \`coder\` → \`reviewer\` → \`shipper\` (\`isolation:worktree\`) under the configured WIP caps, verify each merge landed, and bank §CP PRs for the control-plane approver. Resolve the personalization seam from $config first." ;;
    ea)
      printf '%s' "You are the pipeline-crew EA / chief-of-staff. Follow the \`exec-assistant\` agent def. Give me situational-awareness reads, route execution to the \`$em_win\` window (never run the pipeline yourself), own the single-owner notification protocol, and run §CP bank-and-relay for control-plane PRs. Resolve the personalization seam from $config first." ;;
  esac
}
