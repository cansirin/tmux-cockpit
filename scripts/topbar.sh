#!/usr/bin/env bash
# tmux-cockpit — render the opt-in reminder top bar.
#   reminders come from @cockpit-reminders-file (one per line, skip #/blank) then
#   the inline @cockpit-reminders option; joined with a dim separator.
# Prints NOTHING (exit 0) when nothing is configured, so an unconfigured bar stays blank.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

items=()

file="$(_tm show-option -gqv @cockpit-reminders-file 2>/dev/null)"
case "$file" in "~"|"~/"*) file="$HOME${file#\~}" ;; esac   # expand a leading ~ (tmux stores it literally)
if [ -n "$file" ] && [ -r "$file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ""|\#*) continue ;; esac   # skip blanks and #-comments
    items+=("$line")
  done < "$file"
fi

inline="$(_tm show-option -gqv @cockpit-reminders 2>/dev/null)"
[ -n "$inline" ] && items+=("$inline")

[ "${#items[@]}" -eq 0 ] && exit 0   # nothing configured → blank bar

# Theme-neutral, like session-list.sh: items ride the bar's own fg; only the
# separators are dimmed. No hardcoded colors (they read as loud, break on a light
# theme — see session-list.sh's color note). No marker here; the caller's section
# tag (e.g. the [R] chip) labels the line.
accent=colour150   # the [R] legend colour — keep in sync with the R tag in cockpit.tmux
sep=''
for it in "${items[@]}"; do
  printf '%s#[fg=%s]%s#[default]' "$sep" "$accent" "$it"
  sep='#[dim] · #[default]'
done
