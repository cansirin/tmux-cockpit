#!/usr/bin/env bash
# tmux-cockpit — open the reminders file in $EDITOR (run inside a popup by the
# prefix+Space menu). Resolves the path from @cockpit-reminders-file (leading ~
# expanded) and creates it if missing, so the bar's [R] row is editable in two
# keystrokes. The status bar picks up edits on its next status-interval refresh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

file="$(_tm show-option -gqv @cockpit-reminders-file 2>/dev/null)"
case "$file" in "~"|"~/"*) file="$HOME${file#\~}" ;; esac
if [ -z "$file" ]; then
  _tm display-message "set @cockpit-reminders-file to use the reminders editor"
  exit 0
fi

mkdir -p "$(dirname "$file")" 2>/dev/null
[ -e "$file" ] || : > "$file"
exec "${EDITOR:-vi}" "$file"
