#!/usr/bin/env bash
# tmux-cockpit — append a reminder to the reminders file (quick capture from the
# prefix+Space menu: a → type → Enter). Resolves @cockpit-reminders-file (leading
# ~ expanded) and creates it if missing; no-op on empty/whitespace input. The [R]
# row reflects the new line on the next status refresh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

text="$*"
[ -z "${text// /}" ] && exit 0   # nothing but spaces → nothing to capture

file="$(cockpit_opt @cockpit-reminders-file "")"
case "$file" in "~"|"~/"*) file="$HOME${file#\~}" ;; esac
if [ -z "$file" ]; then
  _tm display-message "set @cockpit-reminders-file to capture reminders"
  exit 0
fi

mkdir -p "$(dirname "$file")" 2>/dev/null
printf '%s\n' "$text" >> "$file"
_tm display-message "✓ reminder added"
