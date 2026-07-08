#!/usr/bin/env bash
# tmux-cockpit crew-init — one-shot stand-up for the pipeline-crew in this repo.
#   crew-init [repo-dir]
#
# Does the parts of stand-up a machine can own, idempotently:
#   1. ensures the kampus marketplace + kampus-pipeline/pipeline-crew plugins
#   2. scaffolds .claude/crew.config.jsonc from the plugin's template, PREFILLED
#      from your git/gh identity + sane defaults (windows, tiers, WIP caps)
#   3. gitignores that config (it holds operator data)
# What it can't own stays yours: your model/permission taste (~/.tmux.conf), the
# one genuinely-personal field (where to notify), and merging code. Auto-run by
# `crew.sh` the first time a repo has no config; also runnable standalone or via
# the prefix+Space → C menu entry. Re-running is safe — a present plugin / filled
# config / existing gitignore line is left alone.
set -uo pipefail
# Resolve through symlinks so lib.sh is found even via a ~/.local/bin symlink.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$dir/$SOURCE" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

target="${1:-$PWD}"
if ! target="$(cd "$target" 2>/dev/null && pwd)"; then
  echo "crew-init: not a directory: ${1:-$PWD}" >&2
  exit 1
fi

MARKET="kampus"
MARKET_SRC="kamp-us/phoenix"

# --- 1. plugins ---------------------------------------------------------------
# Skipped under an isolated test socket (tests must never touch the real plugin
# registry) — the same COCKPIT_SOCKET signal the pickers used as a test bypass.
if [ -z "${COCKPIT_SOCKET:-}" ]; then
  if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace list 2>/dev/null | grep -q "$MARKET" \
      || { echo "crew-init: adding marketplace $MARKET_SRC"; claude plugin marketplace add "$MARKET_SRC" || true; }
    for p in kampus-pipeline pipeline-crew; do
      claude plugin list 2>/dev/null | grep -q "$p" \
        || { echo "crew-init: installing $p@$MARKET"; claude plugin install "$p@$MARKET" || true; }
    done
  else
    echo "crew-init: 'claude' not on PATH — install the plugins yourself:" >&2
    echo "  claude plugin install kampus-pipeline@$MARKET && claude plugin install pipeline-crew@$MARKET" >&2
  fi
fi

# --- 2. config scaffold + prefill ---------------------------------------------
config="${CREW_CONFIG:-$target/.claude/crew.config.jsonc}"
if [ -f "$config" ]; then
  echo "crew-init: config exists — leaving $config"
else
  tmpl="${COCKPIT_CREW_TEMPLATE:-$(find "$HOME/.claude/plugins" -name crew.config.template.jsonc 2>/dev/null | head -1)}"
  if [ -z "$tmpl" ]; then
    echo "crew-init: template not found — install pipeline-crew, then re-run" >&2
  else
    name="$(git -C "$target" config user.name 2>/dev/null)"; [ -z "$name" ] && name="operator"
    login="$(gh api user -q .login 2>/dev/null)"
    [ -z "$login" ] && login="$(git -C "$target" config user.email 2>/dev/null | sed 's/@.*//')"
    [ -z "$login" ] && login="operator"
    handle="@$login"
    sess="$(cockpit_crew_name "$target")"

    # Escape sed replacement metachars (& | \) in the interpolated identity values
    # so a name like "R&D Bot" or "A|B" can't corrupt the substitution or abort it.
    esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
    e_name="$(esc "$name")"; e_handle="$(esc "$handle")"
    e_login="$(esc "$login")"; e_sess="$(esc "$sess")"

    mkdir -p "$(dirname "$config")"
    # Prefill every field we can derive; leave the one genuinely-unknowable field
    # (where to deliver notifications) as a <fill-me> so the def surfaces it. The
    # §CP approver defaults to you (a solo operator reviews their own §CP PRs);
    # change it if a second human owns that gate. The numeric caps drop their
    # template quotes so they land as JSON numbers. Write to a temp then mv, so a
    # sed failure never leaves a half-written (and now gitignored) empty config.
    tmp="$(mktemp "${TMPDIR:-/tmp}/cockpit-crew-cfg.XXXXXX")"
    if sed \
      -e "s|<operator-name>|$e_name|g" \
      -e "s|<operator-handle>|$e_handle|g" \
      -e "s|<control-plane-approver-name>|$e_name|g" \
      -e "s|<control-plane-approver-login>|$e_login|g" \
      -e "s|<notification-channel>|<fill-me: notification target>|g" \
      -e "s|<notification-handle>|$e_handle|g" \
      -e "s|<tmux-session-name>|$e_sess|g" \
      -e "s|<ea-window-name>|ea|g" \
      -e "s|<em-window-name>|em|g" \
      -e "s|<triage-window-name>|triage|g" \
      -e "s|<ea-model-tier>|planning-tier|g" \
      -e "s|<em-model-tier>|build-tier|g" \
      -e "s|<triage-model-tier>|planning-tier|g" \
      -e "s|\"<wip-cap-product-lanes>\"|2|g" \
      -e "s|\"<wip-cap-platform-lanes>\"|2|g" \
      "$tmpl" > "$tmp"; then
      mv "$tmp" "$config"
      echo "crew-init: wrote $config (prefilled from $name / $login)"
    else
      rm -f "$tmp"
      echo "crew-init: failed to render config from template — left it unwritten" >&2
    fi
  fi
fi

# --- 3. gitignore -------------------------------------------------------------
gi="$target/.gitignore"
ignore=".claude/crew.config.jsonc"
if [ -f "$gi" ] && grep -qxF "$ignore" "$gi"; then
  :
else
  # Ensure the file ends in a newline first, else the entry fuses onto the last
  # line (`node_modules` + our line → one broken pattern that ignores neither).
  if [ -f "$gi" ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ]; then
    printf '\n' >> "$gi"
  fi
  printf '%s\n' "$ignore" >> "$gi"
  echo "crew-init: gitignored $ignore"
fi

# --- summary ------------------------------------------------------------------
echo
echo "crew-init done. Left to you:"
echo "  • fill any <fill-me> in $config (where to send notifications)"
echo "  • optional: model/permission taste in ~/.tmux.conf (defaults: opus + no --permission-mode)"
echo "  • prefix+Space → c  to launch the crew"

# Hold the popup open so the output is readable (the menu sets COCKPIT_POPUP).
if [ -n "${COCKPIT_POPUP:-}" ]; then
  printf '\n[press any key to close] '
  read -n1 -r _ </dev/tty 2>/dev/null || true
fi
