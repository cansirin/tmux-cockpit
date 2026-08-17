#!/usr/bin/env bash
# tmux-cockpit link — symlink the command-line-facing cockpit scripts into a bin
# dir so they're on $PATH as bare commands (tmsg).
#   link [bin-dir]
#
# Bin dir precedence: $1, then @cockpit-bin-dir, then ~/.local/bin. Idempotent: a
# correct link is skipped, a stale link is repointed, a real (non-symlink) file
# in the way is left untouched with a warning, and a link to a script the plugin
# no longer ships is pruned. Run it via `make install`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

bin_dir="${1:-}"
[ -z "$bin_dir" ] && bin_dir="$(cockpit_opt @cockpit-bin-dir "")"
[ -z "$bin_dir" ] && bin_dir="$HOME/.local/bin"
bin_dir="${bin_dir/#\~/$HOME}"

mkdir -p "$bin_dir" || { echo "link: cannot create bin dir $bin_dir" >&2; exit 1; }

# The link set. Kept as a loop (rather than a single `ln`) so adding the next CLI
# is a one-word edit, and so each candidate is existence-checked before linking.
for src in "$SCRIPT_DIR"/tmsg.sh; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .sh)"
  dest="$bin_dir/$name"

  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$src" ]; then
      echo "ok      $dest -> $src"
      continue
    fi
    ln -sf "$src" "$dest"            # stale symlink → repoint it atomically
    echo "linked  $dest -> $src"
    continue
  elif [ -e "$dest" ]; then
    echo "skip    $dest exists and is not a symlink — leaving it alone" >&2
    continue
  fi

  ln -s "$src" "$dest"
  echo "linked  $dest -> $src"
done

# Prune our OWN dangling links: a symlink pointing into this plugin's scripts dir
# whose target no longer exists — what a previously-linked script that has since
# been removed from the plugin leaves behind (it would otherwise stay on $PATH
# forever, resolving to a confusing "No such file or directory"). Scoped to links
# we could have created, so a symlink to anything else is never touched.
for dest in "$bin_dir"/*; do
  [ -L "$dest" ] || continue
  target="$(readlink "$dest")"
  case "$target" in "$SCRIPT_DIR"/*) ;; *) continue ;; esac
  [ -e "$target" ] && continue
  rm -f "$dest"
  echo "pruned  $dest -> $target (gone)"
done
