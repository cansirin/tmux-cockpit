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
  selected="$( {
      find "${roots[@]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
      [[ ${#extra_dirs[@]} -gt 0 ]] && printf '%s\n' "${extra_dirs[@]}"
    } | sort -u | fzf --prompt='project ❯ ' --height=50% --reverse )"
fi
[[ -z "$selected" ]] && exit 0

name="$(cockpit_session_name "$selected")"

# Create the session (detached) if needed, then apply a layout (once, on create).
if ! _tm has-session -t="$name" 2>/dev/null; then
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

# Attach (outside tmux) or switch (inside / from the popup).
if [[ -z "${TMUX:-}" ]]; then
  _tm attach -t "$name"
else
  _tm switch-client -t "$name"
fi
