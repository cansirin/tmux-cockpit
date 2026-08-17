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
  # tmux, so a lone "app-sandbox" would otherwise answer a query for "app" and
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

# cockpit_zoxide_keep PATH -> 0 when PATH is worth offering as a project at all.
# zoxide tracks every directory you have visited, which is not the same set as
# your projects. Two kinds of entry are never a project:
#   - $HOME itself, and anything ABOVE it (/, /Users) — you don't open a cockpit
#     on your home dir, and a stray `cd /` should not earn a permanent slot
#   - anything with a dot-prefixed component ($HOME/.claude/skills, .config/b8e,
#     .local/share) — a hidden dir is tooling state, not work
# Everything else is left alone: a project has no obligation to be a git repo (a
# plain folder of coursework is still a project), so this deliberately does NOT
# filter on .git.
cockpit_zoxide_keep() {
  local p="${1%/}"
  [ -z "$p" ] && return 1
  [ "$p" = "$HOME" ] && return 1
  case "$HOME/" in "$p"/*) return 1 ;; esac   # p is an ancestor of $HOME
  case "$p" in */.*) return 1 ;; esac         # a dot-prefixed path component
  return 0
}

# cockpit_prune_nested — stdin: "<tag>\t<path>" lines, tag `e` for an explicitly
# configured candidate (a @cockpit-paths child or a @cockpit-extra dir) and `z`
# for one zoxide volunteered, with the `e` lines FIRST and the `z` lines in
# zoxide's own order (highest frecency first). stdout: the survivors, order kept.
#
# Collapses a zoxide nest to the ONE directory you work in: having visited eleven
# folders under ~/Desktop/sofia should offer sofia, not eleven near-identical rows
# that push the real one off the top.
#
# Two rules, and the narrowness of both is the point:
#
#   1. Only a `z` path suppresses, and only its own DESCENDANTS. An ancestor is
#      never dropped for arriving late — ~/Desktop simply stays on the list,
#      ranked where zoxide ranks it. Dropping ancestors also collapsed nests from
#      the wrong end: a `~/work` you cd into daily outranks the projects inside
#      it, and would have eaten every one of them.
#   2. An `e` path never suppresses and is never dropped. The depth-1 root scan
#      is a mechanical listing, not a claim that each child is the whole project
#      — letting `~/code/github.com` suppress would make `github.com/owner/repo`
#      unreachable, which is the exact config bug the zoxide source exists to
#      kill.
#
# Residual, and it is a real one: if you visit a CONTAINER more than the projects
# inside it, and that container is not configured, the container wins and its
# projects collapse into it. The fix is to name it in @cockpit-paths — its
# children then arrive as `e`, which nothing can suppress.
#
# Paths containing a literal tab are not supported (the tag separator).
cockpit_prune_nested() {
  awk -F'\t' '
    function norm(p) { sub(/\/+$/, "", p); return p }      # a trailing slash must not defeat inside()
    function inside(a, b) { return index(a, b "/") == 1 }   # a is strictly under b
    {
      tag = $1; p = norm($2)
      if (p == "") next                                     # a tab-less line would poison every compare
      if (p in seen) next                                   # same path, both sources
      if (tag != "e")
        for (i = 1; i <= n; i++)
          if (inside(p, keep[i])) next
      seen[p] = 1
      if (tag != "e") keep[++n] = p                         # only zoxide entries suppress
      print p
    }
  '
}
