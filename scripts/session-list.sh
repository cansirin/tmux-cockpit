#!/usr/bin/env bash
# tmux-cockpit — render all sessions for the status bar.
#   ● = attached / current (reverse-video chip)   ○ = background session
#
# THEME-AWARE + a11y, with NO hardcoded colors. The active session uses the
# `reverse` attribute, which swaps the status bar's own fg/bg — so the chip is
# built from whatever colors the current theme already uses for the bar. Its
# contrast therefore equals the bar's normal text contrast (good by definition),
# and it follows light/dark theme switches automatically. Hardcoded colourNNN
# values would not. WCAG 1.4.1 (use of color) is satisfied structurally: the
# active session is marked by the inverted chip + bold + ● glyph, never hue
# alone. Inactive sessions render in the bar's normal foreground — fully legible,
# they just lack the chip.
#
# NB: do NOT use named ANSI colors (black/cyan/white) here. Those are palette
# slots 0/6/7 which themes remap — that is what made an earlier `fg=black` chip
# render as slate-on-teal (near-invisible).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

_tm list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null | \
while read -r attached name; do
  if [ "${attached:-0}" -gt 0 ]; then
    printf '#[reverse,bold] ●%s #[default] ' "$name"
  else
    printf '#[none]○%s #[default] ' "$name"
  fi
done
