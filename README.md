# tmux-cockpit ✈️

[![test](https://github.com/cansirin/tmux-cockpit/actions/workflows/test.yml/badge.svg)](https://github.com/cansirin/tmux-cockpit/actions/workflows/test.yml)

Turn tmux into a project command center. One keystroke jumps between projects,
every session is visible in the status bar, each project opens a ready-to-fly
"cockpit" layout, and a menu means you never memorize a binding.

Built by [@cansirin](https://github.com/cansirin), stolen with love by
[@usirin](https://github.com/usirin). 🌟

## What you get

| Press | Does |
|---|---|
| `Ctrl-f` (no prefix) | floating fuzzy **project picker** — create-or-jump to any project's session, works even inside vim/claude |
| `prefix + f` | same picker |
| `prefix + Space` | **menu of everything** (split, zoom, jump, detach, all-keys) — recall, not memorize |
| status bar | **every session at a glance** — `●` where you are, `○` running in the background |
| open a project | auto **cockpit layout** (main pane + dev/git/logs) for anything with a `package.json` |

Session names are made collision-proof automatically (two folders both named
`monorepo`? → `parentA-monorepo`, `parentB-monorepo`).

## Install (TPM)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'cansirin/tmux-cockpit'
run '~/.tmux/plugins/tpm/tpm'   # keep this last
```

Then press `prefix + I` to fetch it. Requires `tmux >= 3.2`, `fzf`.

## Configure (optional)

```tmux
# where to look for projects (space-separated; ~ and globs expand)
set -g @cockpit-paths "$HOME/code $HOME/work/*"

# launch a command in each cockpit's main pane (great with an AI agent)
set -g @cockpit-main-cmd 'claude'

# include these exact dirs in the picker (for a repo nested deeper than its
# siblings, e.g. a monorepo root). @cockpit-paths scans children; this adds dirs verbatim.
set -g @cockpit-extra "$HOME/work/big-monorepo"

# a folder of per-project layout overrides: <session-name>.sh
set -g @cockpit-layouts "~/.config/tmux/layouts"

# add your own entries to the prefix+Space menu: "label" key "command" ...
set -g @cockpit-menu-extra '"deploy" D "run-shell ~/bin/deploy"  "kill server" K "kill-server"'
```

The menu ships with a full default (splits, zoom, new/rename window, jump,
switch/rename session, detach, reload, all-keys); `@cockpit-menu-extra` appends
to it. To replace it entirely, just `bind Space …` yourself after the plugin loads.

## Tests

```bash
bats tests/        # needs: bats, tmux, fzf, jq
```
Unit tests cover session-name collision handling; integration tests run on an
isolated tmux socket (your real sessions are never touched). CI runs them on every push.

## How it works

- `scripts/sessionizer.sh` — the picker + create-or-switch logic
- `scripts/session-list.sh` — renders the status-bar session list
- `scripts/layout-default.sh` — the default cockpit layout
- `cockpit.tmux` — wires the keybindings and status bar (TPM runs this)

MIT.
