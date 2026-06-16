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

session="$1"
dir="$2"
main_cmd="$3"
win="$session:1"

tmux rename-window -t "$win" dev

tmux split-window -t "$win" -c "$dir"
tmux split-window -t "$win" -c "$dir"
tmux split-window -t "$win" -c "$dir"

tmux set-window-option -t "$win" main-pane-width 60%
tmux select-layout    -t "$win" main-vertical

tmux set-window-option -t "$win" pane-border-status top
tmux set-window-option -t "$win" pane-border-format \
  ' #P #{?#{==:#P,1},main,#{?#{==:#P,2},dev,#{?#{==:#P,3},git,logs}}} '

# launch the configured command in the main pane (e.g. claude), if any
[[ -n "$main_cmd" ]] && tmux send-keys -t "$win".1 "$main_cmd" Enter

tmux select-pane -t "$win".1
