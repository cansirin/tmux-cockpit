#!/usr/bin/env bash
# tmux-cockpit default layout — a "cockpit" for any project with a package.json.
# Big main pane on the left, dev/git/logs stacked on the right.
# Args: $1 = session name, $2 = project path, $3 = optional main-pane command
#
#   ┌──────────────────┬─────────────┐
#   │                  │  dev        │
#   │   main           ├─────────────┤
#   │   ($3, e.g.      │  git        │
#   │    claude)       ├─────────────┤
#   │                  │  logs       │
#   └──────────────────┴─────────────┘
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

session="$1"
dir="$2"
main_cmd="$3"

# Resolve the window + panes by ID — never assume base-index/pane-base-index.
# (Hardcoding :1 / .1 breaks on the default base-index 0, i.e. most setups.)
win="$(_tm display-message -p -t "$session" '#{window_id}')"

_tm rename-window -t "$win" dev
_tm split-window -t "$win" -c "$dir"
_tm split-window -t "$win" -c "$dir"
_tm split-window -t "$win" -c "$dir"

_tm set-window-option -t "$win" main-pane-width 60%
_tm select-layout    -t "$win" main-vertical

# label panes by position: main, then dev / git / logs (via stable pane ids)
labels=(main dev git logs)
i=0
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  _tm select-pane -t "$pid" -T "${labels[$i]:-pane}"
  i=$((i + 1))
done < <(_tm list-panes -t "$win" -F '#{pane_id}')

_tm set-window-option -t "$win" pane-border-status top
_tm set-window-option -t "$win" pane-border-format ' #{pane_index} #{pane_title} '

# main pane = the first one; run the command there (if any), then focus it
main="$(_tm list-panes -t "$win" -F '#{pane_id}' | head -1)"
[ -n "$main_cmd" ] && _tm send-keys -t "$main" "$main_cmd" Enter
_tm select-pane -t "$main"
