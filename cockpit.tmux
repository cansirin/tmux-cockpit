#!/usr/bin/env bash
# tmux-cockpit — fuzzy project sessionizer + live session list in the status bar
# + per-project "cockpit" layouts + a discoverable command menu.
#
# Install with TPM:
#   set -g @plugin 'cansirin/tmux-cockpit'
# then press prefix + I.
#
# Options (set in ~/.tmux.conf before `run '~/.tmux/plugins/tpm/tpm'`):
#   @cockpit-paths      dirs to scan for projects (space-separated, ~ and globs ok)
#   @cockpit-extra      literal dirs to include in the picker verbatim
#   @cockpit-main-cmd   command launched in the cockpit's main pane (e.g. 'claude')
#   @cockpit-layouts    optional dir of per-project layouts (<session-name>.sh)
#   @cockpit-menu-extra extra prefix+Space menu entries, as: '"label" key "command" ...'
#   @cockpit-topbar     'on' enables a second status line of reminders (top bar)
#   @cockpit-reminders-file  file of reminders, one per line (skip #/blank, ~ expands)
#   @cockpit-reminders  inline reminder(s) shown in the top bar

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"
chmod +x "$SCRIPTS"/*.sh 2>/dev/null
. "$SCRIPTS/lib.sh"

picker="display-popup -E -w 60% -h 50% '$SCRIPTS/sessionizer.sh'"

# prefix + Space → menu of everything. Built as an array so quoting stays sane
# and user-defined entries can be appended cleanly.
menu=(
  bind Space display-menu -T "#[align=centre fg=green]« cockpit »" -x C -y C
  "split right"      "|" "split-window -h -c '#{pane_current_path}'"
  "split down"       "-" "split-window -v -c '#{pane_current_path}'"
  "zoom pane"         z  "resize-pane -Z"
  ""
  "new window"        n  "new-window -c '#{pane_current_path}'"
  "rename window"     "," "command-prompt -I '#W' 'rename-window %%'"
  "next / prev win"   "." "next-window"
  ""
  "JUMP to project"   f  "$picker"
  "launch DUO here"   D  "run-shell '$SCRIPTS/duo.sh #{pane_current_path}'"
  "handoff brief"     H  "display-popup -E -d '#{pane_current_path}' '$SCRIPTS/duo-handoff.sh | less -R'"
  "worktree status"   w  "display-popup -E -d '#{pane_current_path}' '$SCRIPTS/wt-status.sh | less -R'"
  "switch session"    s  "choose-tree -Zs"
  "rename session"    R  "command-prompt -I '#S' 'rename-session %%'"
  "detach"            d  "detach-client"
  ""
  "reload config"     r  "source-file ~/.tmux.conf ; display 'config reloaded'"
)

# append user-defined entries: @cockpit-menu-extra '"deploy" D "run-shell deploy" ...'
extra_str="$(_tm show-option -gqv @cockpit-menu-extra 2>/dev/null)"
if [ -n "$extra_str" ]; then
  eval "extra=($extra_str)"
  menu+=("" "${extra[@]}")
fi

menu+=("" "list ALL keys" "?" "list-keys")
_tm "${menu[@]}"

# project picker: prefix + f, and Ctrl-f with NO prefix (works inside programs)
_tm bind f display-popup -E -w 60% -h 50% "$SCRIPTS/sessionizer.sh"
_tm bind -n C-f display-popup -E -w 60% -h 50% "$SCRIPTS/sessionizer.sh"

# live session list in the status bar — ● attached, ○ detached
_tm set -g status-left " #($SCRIPTS/session-list.sh)"
_tm set -g status-left-length 160

# opt-in reminder top bar: a SECOND status line (index 1) driven by topbar.sh.
# Gated on @cockpit-topbar on so unset is byte-identical to today — the bottom
# session-list bar is never touched for existing users.
if [ "$(_tm show-option -gqv @cockpit-topbar 2>/dev/null)" = "on" ]; then
  _tm set -g status 2
  _tm set -g status-format[1] "#[align=left]#($SCRIPTS/topbar.sh)"
fi
