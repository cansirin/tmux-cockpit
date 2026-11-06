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
#   @cockpit-zoxide     'off' drops zoxide's frecency list from the picker. On by
#                       default (when zoxide is installed): anything you've cd'd
#                       into is pickable, so a project outside every root needs
#                       no config at all. Those entries are filtered — no hidden
#                       dirs, nothing at or above $HOME, and a nest collapses to
#                       the one dir you actually work in (by frecency, so the
#                       project beats the folder it sits in)
#   @cockpit-zoxide-limit  how many zoxide entries to take (default 200)
#   @cockpit-main-cmd   command launched in the cockpit's main pane (e.g. 'claude')
#   @cockpit-layouts    optional dir of per-project layouts (<session-name>.sh)
#   @cockpit-menu-extra extra prefix+Space menu entries, as: '"label" key "command" ...'
#   @cockpit-reminders-file  file of reminders, one per line (skip #/blank, ~ expands);
#                       shows them on the [R] row. Edit via prefix+Space → e.
#   @cockpit-reminders  inline reminder(s) shown on the [R] row alongside the file's
#   Segments cockpit publishes for your own layout (use as #{E:@name}):
#     @cockpit-segment-sessions  [S] chip + live session list; click a name to
#                                switch to it, click [S] for the picker
#     @cockpit-segment-sessions-list  the same, trimmed to fit with < > around
#                                the current session (for a row with no window list)
#     @cockpit-segment-git       [G] chip + branch (empty outside a git repo)
#     @cockpit-segment-reminders [R] chip + reminders
#   cockpit sets status-left ("[S] [G]") and status-format[1] ("[R]") only while
#   each is tmux's default or cockpit's own; set one yourself and it stays yours.
#   @cockpit-color-sessions  [S] accent: tag + session text + active chip (default blue)
#   @cockpit-color-reminders [R] accent: tag + reminder text              (default green)
#   @cockpit-color-git  [G] accent: tag + branch text                     (default magenta)
#   Defaults are NAMED ansi slots, which the terminal resolves from its ACTIVE
#   theme — so the accents follow a light/dark flip for free. Any tmux colour
#   works if you'd rather pin one (e.g. colour111).
#   @cockpit-fix-tmux-defaults  'off' leaves tmux's own theme-blind styles alone —
#                       the status bar, prompt bar, copy-mode and menus (default:
#                       on, and it only ever replaces a value tmux shipped —
#                       never one you set)

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
  "switch session"    s  "choose-tree -Zs"
  "rename session"    R  "command-prompt -I '#S' 'rename-session %%'"
  "detach"            d  "detach-client"
  ""
  "add reminder"      a  "command-prompt -p 'reminder:' \"run-shell '$SCRIPTS/add-reminder.sh %%'\""
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

# Titled pane borders for every session. Global default (lowest priority), so the
# default cockpit layout's own window-scoped format wins where it applies and
# everything else falls back to this one. #{session_name} is read live from the
# format, so no per-pane select-pane -T seed is needed.
_tm set -g pane-border-status top
_tm set -g pane-border-format ' #{session_name} · #{pane_title} '

# Two-row labelled status. The main row spreads three groups space-between
# (status-justify centre, repaired below when tmux's `left` is still in place):
# [S] sessions on the left, the window list centred, the prefix/menu hint
# (status-right) on the right. The current window carries the [S] accent, so no
# separate [W] chip is needed once the list is centred on its own. Reminders get
# their OWN row (row 1), marked by the [R] tag. Coloured tags read as a legend;
# content tinted. Section colours are tunable (@cockpit-color-*); the render
# scripts read the same options + defaults, so tag and content stay in sync.
c_sessions="$(cockpit_opt @cockpit-color-sessions blue)"
c_reminders="$(cockpit_opt @cockpit-color-reminders green)"
# `reverse` swaps fg/bg, so a chip is an accent-coloured block whose letter is
# painted in the TERMINAL'S OWN background — dark on a dark theme, light on a
# light one, with no second "ink" colour to keep in agreement with the accent.
s_tag="#[fg=$c_sessions,reverse,bold] S #[default]"
r_tag="#[fg=$c_reminders,reverse,bold] R #[default]"
# [S] sessions and [G] git context for the active pane's repo (git-context.sh
# self-renders its [G] chip only inside a work tree, so it vanishes elsewhere).
# Each is published as a segment option, so a config can place it anywhere with
# #{E:@cockpit-segment-…}; cockpit's own status-left is just the default layout.
# The session list is tmux's own #{S:…} loop, not a script: each name is its own
# click target (range=session → tmux's MouseDown1Status `switch-client -t =`
# jumps straight there), while the [S] chip keeps range=left (→ StatusLeft, the
# picker). WCAG 1.4.1 (not by hue alone): attached = filled chip + bold, the rest
# = plain accent text, so chip vs no-chip is structural, not just colour.
# `reverse` paints the chip's ink in the terminal's own background, so it follows
# a light/dark theme flip with no second colour to keep in agreement.
s_name="#{?session_attached,#[fg=$c_sessions#,reverse#,bold] #{session_name} #[default],#[fg=$c_sessions]#{session_name}#[default]}"
s_item="#[range=session|#{session_id}]$s_name#[norange default]  "
s_head="#[range=left]$s_tag#[norange default] "
_tm set -g @cockpit-segment-sessions "$s_head#{S:$s_item}"
# The -list variant trims to fit, keeping the current session (list=focus) in view
# with < > where names were cut. A row holds ONE tmux list, and `list=on` outside
# a list starts one, so only place it on a row with no window list.
# The focus is picked with a conditional on client_session, NOT tmux's two-branch
# #{S:item,current} form: on tmux 3.6a that form crashes the server when expanded
# with no client attached (e.g. `display -p`), taking every session down with it.
s_focus="#[range=session|#{session_id} list=focus]$s_name#[norange list=on default]  "
s_pick="#{?#{==:#{session_name},#{client_session}},$s_focus,$s_item}"
_tm set -g @cockpit-segment-sessions-list "$s_head#[list=on align=left]#[list=left-marker]<#[list=right-marker]>#[list=on]#{S:$s_pick}#[nolist]"
_tm set -g @cockpit-segment-git "#($SCRIPTS/git-context.sh '#{pane_current_path}')"
_tm set -g status-left-length 400

# cockpit_own OPTION NEW TMUX_DEFAULT... — write NEW only when OPTION still
# reads as one of the listed tmux defaults, or as what cockpit itself last wrote
# (remembered in @cockpit-restyled-OPTION, so a config reload or a re-pinned
# accent still lands). Any other value is the user's own and is left untouched.
cockpit_own() {
  local opt="$1" new="$2" cur mine d
  shift 2
  cur="$(_tm show-option -gqv "$opt" 2>/dev/null)"
  # an array index (status-format[1]) can't sit in a user option's name
  local marker="@cockpit-restyled-${opt//[\[\]]/_}"
  mine="$(_tm show-option -gqv "$marker" 2>/dev/null)"
  for d in "$@" ${mine:+"$mine"}; do
    [ "$cur" = "$d" ] || continue
    _tm set -g "$opt" "$new"
    _tm set -g "$marker" "$new"
    return 0
  done
}

# The default main-row layout: [S] then [G] on the left. A status-left of your
# own (e.g. sessions left, git moved into status-right) is left alone. The second
# default is the literal cockpit wrote before segments existed (session-list.sh
# is gone, but an old config still holds the string), so an upgrade
# still moves onto the segment form.
cockpit_own status-left "#{E:@cockpit-segment-sessions}  #{E:@cockpit-segment-git}" \
  '[#{session_name}] ' \
  "$s_tag #($SCRIPTS/session-list.sh)  #($SCRIPTS/git-context.sh '#{pane_current_path}')"

# reminders row (row 1) — only when configured; the [R] tag makes it self-evident
# [R] is published as a segment too, and row 1 is cockpit's only while it still
# holds tmux's built-in default (read from a throwaway server, so it is right for
# whichever tmux runs this), cockpit's own value, or the pre-segment literal.
_tm set -g @cockpit-segment-reminders "$r_tag #($SCRIPTS/topbar.sh)"
if [ -n "$(_tm show-option -gqv @cockpit-reminders-file 2>/dev/null)$(_tm show-option -gqv @cockpit-reminders 2>/dev/null)" ]; then
  _tm set -g status 2
  tmux_row1="$(tmux -L "cockpit-defaults-$$" -f /dev/null start-server \; show-option -gv 'status-format[1]' \; kill-server 2>/dev/null)"
  cockpit_own 'status-format[1]' "#[align=left]#{E:@cockpit-segment-reminders}" \
    "$tmux_row1" \
    "#[align=left]$r_tag #($SCRIPTS/topbar.sh)"
else
  _tm set -g status on
fi

# ── theme-blind tmux defaults ──────────────────────────────────────────────────
# tmux paints its prompt bar, copy-mode and menus as `<ansi hue> on fg=black`,
# which assumes those hues are bright pastels. On a theme whose ansi palette is
# dark (GitHub Dark's yellow is #9e6a03, cyan #1b7c83) that is dark-on-dark and
# the text is unreadable. cockpit repaints them with the same trick as the
# [S]/[R]/[G] chips: `reverse`, so the ink is the TERMINAL'S OWN background —
# dark on a dark theme, light on a light one, following a theme flip for free.
#
# These are NATIVE tmux options, not cockpit's, so cockpit only ever replaces a
# value tmux itself shipped. Anything you set stays yours, and
# `@cockpit-fix-tmux-defaults off` opts out of the whole section.
fix_defaults="$(cockpit_opt @cockpit-fix-tmux-defaults on)"

# cockpit_restyle OPTION NEW TMUX_DEFAULT... — the theme repairs below, skipped
# entirely under `@cockpit-fix-tmux-defaults off`.
cockpit_restyle() {
  [ "$fix_defaults" = off ] && return 0
  cockpit_own "$@"
}

# The status bar cockpit draws ON. tmux ships it green-with-black-ink, so a fresh
# install reverses cockpit's blue [S] chip against green — the accents can only
# read as the terminal's theme if the bar underneath them IS the terminal. The
# window list has to be centred too, or the main row's three groups (sessions ·
# windows · hint) collapse onto the left instead of spreading space-between.
cockpit_restyle status-style   bg=default,fg=default bg=green,fg=black
cockpit_restyle status-justify centre                left
# the current window is the one thing in the centred list that needs to stand out
cockpit_restyle window-status-current-style "fg=$c_sessions,reverse,bold" default

# The right group the centred layout leaves room for: a PREFIX indicator plus the
# one hint that makes the whole plugin discoverable. tmux ships the pane title and
# a clock there instead, so a fresh install centred its window list against nothing
# and never advertised the menu. `fg=red,reverse` and NOT `bg=red,fg=white` —
# `white` is ansi slot 7, which GitHub Light resolves to a GRAY (#6e7781), so
# white-on-red renders as grey-on-red mud. Reverse takes the ink from the terminal.
# The chip sits inside a #{?client_prefix,…,…} conditional, so its own commas have
# to be escaped as `#,` or tmux reads them as the conditional's argument separator.
# #{prefix} is the live prefix option, so a rebound prefix relabels the hint itself.
prefix_chip="#[fg=red#,reverse#,bold] PREFIX #[default]"
cockpit_restyle status-right \
  "#{?client_prefix,$prefix_chip ,}#[bold]#{prefix} Space = menu#[default] " \
  '#{?window_bigger,[#{window_offset_x}#,#{window_offset_y}] ,}"#{=21:pane_title}" %H:%M %d-%b-%y'
# the hint plus the chip does not fit tmux's 40-column default
cockpit_restyle status-right-length 80 40

# the prompt bar: rename window, rename session, `branch:`, `reminder:` …
cockpit_restyle message-style         bg=default,fg=default,reverse      bg=yellow,fg=black
# vi/emacs command mode inside the prompt — bold rather than a second pinned hue
cockpit_restyle message-command-style bg=default,fg=default,reverse,bold bg=black,fg=yellow
# copy-mode: the hue is what carries the meaning, so keep it and drop the ink only
cockpit_restyle mode-style                    fg=yellow,reverse  noattr,bg=yellow,fg=black bg=yellow,fg=black
cockpit_restyle copy-mode-match-style         fg=cyan,reverse    bg=cyan,fg=black
cockpit_restyle copy-mode-current-match-style fg=magenta,reverse bg=magenta,fg=black
cockpit_restyle copy-mode-mark-style          fg=red,reverse     bg=red,fg=black
# prefix+Space menu — cockpit's own surface, so its selection follows the [S] accent
cockpit_restyle menu-selected-style "fg=$c_sessions,reverse,bold" bg=yellow,fg=black
