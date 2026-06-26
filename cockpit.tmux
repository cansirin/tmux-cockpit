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
  "edit reminders"    e  "display-popup -E -w 70% -h 60% '$SCRIPTS/edit-reminders.sh'"
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

# Two-row labelled status. The main row spreads three groups space-between
# (status-justify centre, set in user config): [S] sessions on the left, the
# window list centred, the prefix/menu hint (status-right) on the right. The
# current window stays orange — that is the "windows" accent, so no separate [W]
# chip is needed once the list is centred on its own. Reminders get their OWN row
# (row 1), marked by the [R] tag. Coloured tags read as a legend; content tinted.
s_tag="#[fg=colour235,bg=colour111,bold] S #[default]"
r_tag="#[fg=colour235,bg=colour150,bold] R #[default]"
_tm set -g status-left "$s_tag #($SCRIPTS/session-list.sh)"
_tm set -g status-left-length 400

# reminders row (row 1) — only when configured; the [R] tag makes it self-evident
if [ -n "$(_tm show-option -gqv @cockpit-reminders-file 2>/dev/null)$(_tm show-option -gqv @cockpit-reminders 2>/dev/null)" ]; then
  _tm set -g status 2
  _tm set -g status-format[1] "#[align=left]$r_tag #($SCRIPTS/topbar.sh)"
else
  _tm set -g status on
fi
