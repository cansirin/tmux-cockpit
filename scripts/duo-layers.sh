#!/usr/bin/env bash
# tmux-cockpit duo-layers — pick which startup "layers" a duo should seed.
#   duo-layers.sh
#
# A layer is one file `<name>.layer` (see layers/) whose lines seed an extra
# startup instruction into every duo pane, composed onto the base brief. Lists
# every available layer name across the search dirs (user dir shadows the shipped
# repo `layers/`), fzf-multi-selects with a tty, and prints the chosen names
# space-separated on stdout for duo.sh to consume. Zero layers -> print nothing,
# exit 0 (the caller launches a plain duo).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Available layer names, deduped with the FIRST dir winning (user shadows repo),
# preserving that precedence — bash 3.2-safe, no assoc arrays.
dirs="$(cockpit_duo_layer_dirs)"
names=""
while IFS= read -r dir; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.layer; do
    [ -f "$f" ] || continue          # the glob is literal when nothing matches
    n="$(basename "$f" .layer)"
    case " $names " in *" $n "*) continue ;; esac
    names="$names $n"
  done
done <<EOF
$dirs
EOF
names="${names# }"

[ -z "$names" ] && exit 0

# A fixed selection for tests (and any non-interactive caller) — bypasses fzf so
# no tty is needed. Honored verbatim; the caller is trusted to name real layers.
if [ -n "${COCKPIT_DUO_LAYERS_PICK:-}" ]; then
  printf '%s\n' "$COCKPIT_DUO_LAYERS_PICK"
  exit 0
fi

# No tty (e.g. run headless): can't prompt, so launch plain rather than block.
[ -t 0 ] && [ -t 1 ] || exit 0

# Preview the layer's first comment line (its one-line description) if present.
sel="$(printf '%s\n' $names | fzf --multi --prompt='layers ❯ ' --height=40% --reverse \
  --preview "grep -m1 '^#' '$SCRIPT_DIR/../layers/{}.layer' 2>/dev/null | sed 's/^# *//'" \
  --preview-window=up:1)"

# fzf prints one selection per line; flatten to a space-separated list.
printf '%s' "$sel" | tr '\n' ' ' | sed 's/ *$//'
