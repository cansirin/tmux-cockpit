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
| `prefix + Space` → `D` | **launch a Claude duo** — two coordinated AI panes (1.1 + 1.2) in the current repo |
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

# Claude duo (see below): point at your own working-agreement doc, and tune how
# long to wait for the per-pane command to boot before seeding its brief.
set -g @cockpit-duo-protocol "~/.config/tmux/my-duo-protocol.md"
set -g @cockpit-duo-boot-wait 8

# add your own entries to the prefix+Space menu: "label" key "command" ...
set -g @cockpit-menu-extra '"deploy" G "run-shell ~/bin/deploy"  "kill server" K "kill-server"'
```

The menu ships with a full default (splits, zoom, jump, **launch duo**,
switch/rename session, detach, reload, all-keys); `@cockpit-menu-extra` appends
to it. To replace it entirely, just `bind Space …` yourself after the plugin loads.

## Claude duo

`prefix + Space → D` spins up a **two-pane coordinated Claude pair** in the
current repo: two panes (1.1 + 1.2) each running `@cockpit-main-cmd` (default
`claude`), pre-seeded with a bootstrap brief — their label, their sibling's tmux
pane id, and a pointer to a working-agreement doc — so they coordinate
themselves (disjoint lanes, the other pane reviews, one merger). The agreement
ships as a tool-agnostic [`duo-protocol.md`](duo-protocol.md); point
`@cockpit-duo-protocol` at your own to add your project's process.
Re-running on the same repo just re-focuses the existing duo. Works from any
pane; nothing is repo-specific.

**How the launch works** (for anyone extending it):

1. `prefix + Space → D` fires the menu entry
   `run-shell '<plugin>/scripts/duo.sh #{pane_current_path}'` — tmux expands the
   current pane's path and runs `duo.sh` **headless on the server** (no tty).
2. `duo.sh` names the session `<project>-duo` (`cockpit_duo_name`, which reuses
   the collision-proof `cockpit_session_name`). If it already exists, it just
   re-focuses and exits — never a second duo.
3. Otherwise it creates a detached **two-pane** session in the repo
   (`new-session -d` + `split-window -h`), then sends `@cockpit-main-cmd`
   (default `claude`) into each pane to boot the agents.
4. A **backgrounded** subshell waits `@cockpit-duo-boot-wait` seconds (so the
   launch never blocks tmux during boot), then `send-keys -l` each pane its
   brief from `cockpit_duo_brief` — its label, its sibling's pane id, and the
   protocol path — and submits it with a separate `Enter`.
5. It `switch-client`s you to the session (or `attach` from a bare terminal).
   The two agents read the protocol, greet each other over `send-keys`, and wait
   for your task.

The pure logic (`cockpit_duo_name`, `cockpit_duo_brief`) lives in
`scripts/lib.sh` and is unit-tested in `tests/duo.bats`; the launch + re-focus
behavior is covered in `tests/integration.bats` (on an isolated socket).

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
- `scripts/duo.sh` — launches the two-pane Claude duo (`duo-protocol.md` is the brief)
- `cockpit.tmux` — wires the keybindings and status bar (TPM runs this)

MIT.
