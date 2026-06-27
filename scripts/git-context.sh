#!/usr/bin/env bash
# tmux-cockpit — render the active pane's git context for the [G] status section:
# branch + dirty-file count + ahead/behind vs upstream. Prints nothing (so the
# [G] chip vanishes) when the pane isn't inside a git work tree.
#
# The [G] tag is emitted HERE, not in cockpit.tmux like [S]/[R], because the
# condition (is this pane in a repo?) is only known at render time from the live
# pane path — which the caller passes as $1 (#{pane_current_path}).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

path="${1:-$PWD}"
git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch="$(git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null \
          || git -C "$path" rev-parse --short HEAD 2>/dev/null)"
[ -z "$branch" ] && exit 0

dirty="$(git -C "$path" status --porcelain 2>/dev/null | grep -c .)"
ahead=0; behind=0
if up="$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
  read -r ahead behind <<<"$(git -C "$path" rev-list --left-right --count "HEAD...$up" 2>/dev/null)"
fi

gcol="$(cockpit_opt @cockpit-color-git colour175)"   # [G] accent
ink="$(cockpit_opt @cockpit-color-ink colour235)"    # dark text on the chip

ind=""
[ "${dirty:-0}" -gt 0 ]  && ind="$ind *$dirty"
[ "${ahead:-0}" -gt 0 ]  && ind="$ind ↑$ahead"
[ "${behind:-0}" -gt 0 ] && ind="$ind ↓$behind"

printf '#[fg=%s,bg=%s,bold] G #[default] #[fg=%s]%s#[default]#[dim]%s#[default]  ' \
  "$ink" "$gcol" "$gcol" "$branch" "$ind"
