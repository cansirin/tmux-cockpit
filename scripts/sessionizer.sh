#!/usr/bin/env bash
# tmux-cockpit sessionizer — fuzzy-find a project, create-or-switch its session.
# Bound to prefix+f and (no-prefix) Ctrl-f. Pass a path as $1 to skip the picker.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

if [[ $# -eq 1 ]]; then
  selected="$1"
else
  paths="$(_tm show-option -gqv @cockpit-paths 2>/dev/null)"
  [[ -z "$paths" ]] && paths="$HOME/code $HOME/dev $HOME/Documents/development"
  extra="$(_tm show-option -gqv @cockpit-extra 2>/dev/null)"
  eval "roots=($paths)"        # expand ~ and globs
  eval "extra_dirs=($extra)"   # literal dirs to include verbatim

  # Containers are declared, not guessed. Naming a dir in @cockpit-paths says
  # "projects live IN here", which makes it furniture — and so is anything ABOVE
  # it, since the same declaration puts your work strictly below. ~/Documents
  # holding only ~/Documents/development is the shape: you want the projects, and
  # a row for the folder they sit in is a row you will never pick.
  #
  # Roots are matched by filesystem identity, not by string, because a
  # case-insensitive filesystem gives one directory two names and zoxide records
  # both — ~/desktop and ~/Desktop are the same inode, and only one of them looks
  # like the root you configured.
  #
  # Defined out here rather than inside the candidate pipeline below: a function
  # body inside a $( ) is easy to break, and an apostrophe in a comment in there
  # is a parse error, not a typo.
  root_ids=()
  for _r in "${roots[@]}"; do
    _id="$(cockpit_dir_id "${_r%/}")"
    [[ -n "$_id" ]] && root_ids+=("$_id")
  done
  is_container() {
    local d="${1%/}" r id
    for r in "${roots[@]}"; do
      r="${r%/}"
      [[ "$r" == "$d" ]] && return 0        # the root itself
      [[ "$r" == "$d"/* ]] && return 0      # an ancestor of a root
    done
    id="$(cockpit_dir_id "$d")"
    [[ -z "$id" ]] && return 1
    for r in "${root_ids[@]}"; do
      [[ "$r" == "$id" ]] && return 0       # the root under another name
    done
    return 1
  }

  # Three sources, unioned:
  #   1. the depth-1 scan of @cockpit-paths — every child of a configured root
  #   2. @cockpit-extra — literal dirs, the explicit escape hatch for a one-off
  #      project that lives nowhere near a root
  #   3. zoxide's frecency list, when zoxide is installed — anything you have
  #      actually cd'd into is pickable with no config at all. This is what stops
  #      "why isn't my project in the list?" from being a config bug: a project
  #      outside every root becomes findable the moment you visit it once.
  # Sources 1 and 2 are what you CONFIGURED, so they are offered as-is. Source 3
  # is what you VISITED, which is a noisier set — zoxide entries are additionally
  # filtered to still-existing dirs (its db keeps stale paths), to plausible
  # projects (cockpit_zoxide_keep), and to the outermost of a nest
  # (cockpit_prune_nested), then capped so one huge history can't drown the
  # curated roots. Set @cockpit-zoxide off to opt out; @cockpit-zoxide-limit
  # tunes the cap. Each line is tagged e/z for the nesting prune, which never
  # drops something you configured.
  selected="$( {
      # The configured block is sorted: `find` returns raw dirent order, which
      # would put the section you curated into an arbitrary shuffle at the top of
      # the picker. The zoxide block below must NOT be sorted — its order IS the
      # frecency ranking, which is what decides a nest.
      {
        # -name '.*' excluded: a root scan turns up .claude / .github / .git as
        # "projects" otherwise, which has been true since the first version and is
        # the same junk the zoxide filter drops.
        find "${roots[@]}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null
        [[ ${#extra_dirs[@]} -gt 0 ]] && printf '%s\n' "${extra_dirs[@]}"
      } | sort -u | sed 's/^/e\t/'
      if [[ "$(cockpit_opt @cockpit-zoxide on)" != off ]] && command -v zoxide >/dev/null 2>&1; then
        # A non-numeric limit would make `head` fail and print its usage error
        # INTO the picker (this whole block is a command substitution feeding
        # fzf), so a bad value falls back to the default rather than corrupting
        # the candidate list.
        limit="$(cockpit_opt @cockpit-zoxide-limit 200)"
        [[ "$limit" =~ ^[0-9]+$ ]] || limit=200
        # Cap AFTER the filters, never before: a history full of hidden dirs and
        # dead paths would otherwise spend the whole budget on entries that can
        # never render, and the 201st real project would go unseen.
        zoxide query -l 2>/dev/null \
          | while IFS= read -r d; do
              [[ -d "$d" ]] && ! is_container "$d" && cockpit_zoxide_keep "$d" \
                && printf 'z\t%s\n' "$d"
            done \
          | head -n "$limit"
      fi
    } | cockpit_prune_nested | fzf --prompt='project ❯ ' --height=50% --reverse )"
fi
[[ -z "$selected" ]] && exit 0

base="$(cockpit_session_name "$selected")"
name="$(cockpit_resolve_name "$base" "$selected")"

# Create the session (detached) if needed, then apply a layout (once, on create).
# "=$name" forces an exact match so a prefix sibling can't answer for this name.
if ! _tm has-session -t "=$name" 2>/dev/null; then
  _tm new-session -ds "$name" -c "$selected"

  layouts_dir="$(_tm show-option -gqv @cockpit-layouts 2>/dev/null)"
  layouts_dir="${layouts_dir/#\~/$HOME}"
  if [[ -n "$layouts_dir" && -x "$layouts_dir/$name.sh" ]]; then
    "$layouts_dir/$name.sh" "$name" "$selected"
  elif [[ -f "$selected/package.json" && -x "$SCRIPT_DIR/layout-default.sh" ]]; then
    main_cmd="$(_tm show-option -gqv @cockpit-main-cmd 2>/dev/null)"
    "$SCRIPT_DIR/layout-default.sh" "$name" "$selected" "$main_cmd"
  fi
fi

# Record the repo path — on create AND on reuse, so a session made before this
# existed (or by hand) gets claimed on first touch instead of staying a nameless
# hijack magnet for a same-basename repo. cockpit_resolve_name only ever returns
# a name that is free, ours, or unstamped, so this never overwrites another
# repo's stamp.
_tm set -t "$name" @cockpit-path "$selected"

# Attach (outside tmux) or switch (inside / from the popup).
if [[ -z "${TMUX:-}" ]]; then
  _tm attach -t "$name"
else
  _tm switch-client -t "$name"
fi
