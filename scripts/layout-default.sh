#!/usr/bin/env bash
# tmux-cockpit default layout — a "cockpit" for any project with a package.json.
# Big main pane on the left, dev/git/logs stacked on the right.
# Args: $1 = session name, $2 = project path, $3 = optional main-pane command
#
#   ┌──────────────────┬─────────────┐
#   │                  │  2  dev     │
#   │   1  main        ├─────────────┤
#   │   ($3, e.g.      │  3  git     │
#   │    claude)       ├─────────────┤
#   │                  │  4  logs    │
#   └──────────────────┴─────────────┘
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

session="$1"
dir="$2"
main_cmd="$3"
win="$session:1"

_tm rename-window -t "$win" dev

_tm split-window -t "$win" -c "$dir"
_tm split-window -t "$win" -c "$dir"
_tm split-window -t "$win" -c "$dir"

_tm set-window-option -t "$win" main-pane-width 60%
_tm select-layout    -t "$win" main-vertical

_tm set-window-option -t "$win" pane-border-status top
_tm set-window-option -t "$win" pane-border-format \
  ' #P #{?#{==:#P,1},main,#{?#{==:#P,2},dev,#{?#{==:#P,3},git,logs}}} '

# launch the configured command in the main pane (e.g. claude), if any
[[ -n "$main_cmd" ]] && _tm send-keys -t "$win".1 "$main_cmd" Enter

_tm select-pane -t "$win".1
