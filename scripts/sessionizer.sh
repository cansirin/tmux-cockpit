#!/usr/bin/env bash
# tmux-cockpit sessionizer — fuzzy-find a project, create-or-switch its session.
# Bound to prefix+f and (no-prefix) Ctrl-f. Pass a path as $1 to skip the picker.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 1 ]]; then
  selected="$1"
else
  paths="$(tmux show-option -gqv @cockpit-paths 2>/dev/null)"
  [[ -z "$paths" ]] && paths="$HOME/code $HOME/dev $HOME/Documents/development"
  eval "roots=($paths)"   # expand ~ and globs
  selected="$(find "${roots[@]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
              | sort -u | fzf --prompt='project ❯ ' --height=50% --reverse)"
fi
[[ -z "$selected" ]] && exit 0

# Unique, tmux-safe session name. Folders named monorepo* collide across
# projects, so prefix those with their parent dir; everything else keeps base.
base="$(basename "$selected")"
case "$base" in
  monorepo*) name="$(basename "$(dirname "$selected")")-$base" ;;
  *)         name="$base" ;;
esac
name="$(printf '%s' "$name" | tr ' .:' '___')"

# Create the session (detached) if needed, then apply a layout (once, on create).
if ! tmux has-session -t="$name" 2>/dev/null; then
  tmux new-session -ds "$name" -c "$selected"

  layouts_dir="$(tmux show-option -gqv @cockpit-layouts 2>/dev/null)"
  layouts_dir="${layouts_dir/#\~/$HOME}"
  if [[ -n "$layouts_dir" && -x "$layouts_dir/$name.sh" ]]; then
    "$layouts_dir/$name.sh" "$name" "$selected"
  elif [[ -f "$selected/package.json" && -x "$SCRIPT_DIR/layout-default.sh" ]]; then
    main_cmd="$(tmux show-option -gqv @cockpit-main-cmd 2>/dev/null)"
    "$SCRIPT_DIR/layout-default.sh" "$name" "$selected" "$main_cmd"
  fi
fi

# Attach (outside tmux) or switch (inside / from the popup).
if [[ -z "$TMUX" ]]; then
  tmux attach -t "$name"
else
  tmux switch-client -t "$name"
fi
