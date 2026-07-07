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
# Resolve through symlinks so `lib.sh` is found even when this is invoked via a
# symlink on PATH (the `duo-*` install glob links it into ~/.local/bin). `readlink
# -f` isn't portable to old macOS, so walk the link chain by hand.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$dir/$SOURCE" ;; esac  # relative → absolute
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Available layer names, deduped with the FIRST dir winning (user shadows repo),
# preserving that precedence — bash 3.2-safe, no assoc arrays. Names are filtered
# to the safe charset (matches cockpit_duo_layer_seed's guard) so an odd filename
# — a space, a slash — can't enter the space-separated selection transport.
dirs="$(cockpit_duo_layer_dirs)"
names=""
while IFS= read -r dir; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.layer; do
    [ -f "$f" ] || continue          # the glob is literal when nothing matches
    n="$(basename "$f" .layer)"
    case "$n" in ''|*[!a-zA-Z0-9._-]*) continue ;; esac
    case " $names " in *" $n "*) continue ;; esac
    names="$names $n"
  done
done <<EOF
$dirs
EOF
names="${names# }"

[ -z "$names" ] && exit 0

# TEST-ONLY bypass: a fixed selection so tests need no tty/fzf. Gated on
# COCKPIT_SOCKET (tests always run on an isolated socket, real launches never set
# it) so a value left in a real shell can't silently override the picker.
if [ -n "${COCKPIT_DUO_LAYERS_PICK:-}" ] && [ -n "${COCKPIT_SOCKET:-}" ]; then
  printf '%s\n' "$COCKPIT_DUO_LAYERS_PICK"
  exit 0
fi

# No tty (e.g. run headless) or no fzf: can't prompt, so launch plain, not block.
[ -t 0 ] && [ -t 1 ] || exit 0
command -v fzf >/dev/null 2>&1 || exit 0

# Preview the layer's first comment line (its one-line description) if present.
sel="$(printf '%s\n' $names | fzf --multi --prompt='layers ❯ ' --height=40% --reverse \
  --preview "grep -m1 '^#' '$SCRIPT_DIR/../layers/{}.layer' 2>/dev/null | sed 's/^# *//'" \
  --preview-window=up:1)"

# fzf prints one selection per line; flatten to a space-separated list.
printf '%s' "$sel" | tr '\n' ' ' | sed 's/ *$//'
