#!/usr/bin/env bash
# tmux-cockpit link — symlink the command-line-facing cockpit scripts into a bin
# dir so they're on $PATH as bare commands (tmsg, wt-status, duo-heartbeat, ...).
#   link [bin-dir]
#
# Bin dir precedence: $1, then @cockpit-bin-dir, then ~/.local/bin. The link set
# is a fixed glob CONVENTION — scripts/{tmsg,duo-*,wt-*}.sh — so any future
# duo-*/wt-* script auto-links here with no edit to this file. Idempotent: a
# correct link is skipped, a stale link is repointed, a real (non-symlink) file
# in the way is left untouched with a warning. Run it via `make install`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

bin_dir="${1:-}"
[ -z "$bin_dir" ] && bin_dir="$(cockpit_opt @cockpit-bin-dir "")"
[ -z "$bin_dir" ] && bin_dir="$HOME/.local/bin"
bin_dir="${bin_dir/#\~/$HOME}"

mkdir -p "$bin_dir" || { echo "link: cannot create bin dir $bin_dir" >&2; exit 1; }

# The convention: tmsg plus every duo-* / wt-* script. Globs that match nothing
# expand to the literal pattern, so each candidate is existence-checked below.
for src in "$SCRIPT_DIR"/tmsg.sh "$SCRIPT_DIR"/duo-*.sh "$SCRIPT_DIR"/wt-*.sh; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .sh)"
  dest="$bin_dir/$name"

  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$src" ]; then
      echo "ok      $dest -> $src"
      continue
    fi
    rm -f "$dest"                    # stale symlink → repoint it
  elif [ -e "$dest" ]; then
    echo "skip    $dest exists and is not a symlink — leaving it alone" >&2
    continue
  fi

  ln -s "$src" "$dest"
  echo "linked  $dest -> $src"
done
