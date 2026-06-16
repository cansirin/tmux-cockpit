#!/usr/bin/env bash
# tmux-cockpit — fuzzy project sessionizer + live session list in the status bar
# + per-project "cockpit" layouts + a discoverable command menu.
#
# Install with TPM:
#   set -g @plugin 'cansirin/tmux-cockpit'
# then press prefix + I.
#
# Options (set in ~/.tmux.conf before `run '~/.tmux/plugins/tpm/tpm'`):
#   @cockpit-paths     dirs to scan for projects (space-separated, ~ and globs ok)
#                      default: "$HOME/code $HOME/dev $HOME/Documents/development"
#   @cockpit-main-cmd  command launched in the cockpit's main pane (e.g. 'claude')
#                      default: empty (plain shell)
#   @cockpit-layouts   optional dir of per-project layouts (<session-name>.sh)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"
chmod +x "$SCRIPTS"/*.sh 2>/dev/null

# prefix + Space → menu of everything (no memorization needed)
tmux bind Space display-menu -T "#[align=centre fg=green]« cockpit »" -x C -y C \
  "split right"     "|" "split-window -h -c '#{pane_current_path}'" \
  "split down"      "-" "split-window -v -c '#{pane_current_path}'" \
  "zoom pane"        z  "resize-pane -Z" \
  "" \
  "JUMP to project"  f  "display-popup -E -w 60% -h 50% '$SCRIPTS/sessionizer.sh'" \
  "switch session"   s  "choose-tree -Zs" \
  "detach"           d  "detach-client" \
  "" \
  "all keys"         ?  "list-keys"

# project picker: prefix + f, and Ctrl-f with NO prefix (works inside programs)
tmux bind f display-popup -E -w 60% -h 50% "$SCRIPTS/sessionizer.sh"
tmux bind -n C-f display-popup -E -w 60% -h 50% "$SCRIPTS/sessionizer.sh"

# live session list in the status bar — ● attached, ○ detached
tmux set -g status-left " #($SCRIPTS/session-list.sh)"
tmux set -g status-left-length 160
