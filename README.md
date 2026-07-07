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
| `prefix + Space` → `D` | **launch a Claude duo** — 2–3 coordinated AI panes (1.1 leads) in the current repo |
| `prefix + Space` → `H` | **handoff brief** — a re-orientation snapshot (HEAD, recent commits, open PRs, worktrees) |
| `prefix + Space` → `w` | **worktree status** — which worktrees are merged (safe to prune) vs still unmerged |
| `prefix + Space` → `e` | **edit reminders** — pop open the reminders file in `$EDITOR` |
| `prefix + Space` → `a` | **add reminder** — type a line, it's appended to the reminders file (quick capture) |
| status bar | a **labelled legend** — `[S]` sessions · `[G]` git context · centred window list · `[R]` reminders (its own row), each a colored section tag |
| `[G]` git context | active pane's **branch + dirty/ahead/behind** — vanishes outside a repo |
| reminders | a **`[R]` row** of inline notes and/or a file you keep updated — appears automatically when configured |
| open a project | auto **cockpit layout** (main pane + dev/git/logs) for anything with a `package.json` |
| every pane | a **titled border bar** — session name · pane title, live-updated by whatever's running (Claude, vim, …) |

Session names stay readable but never collide: each session records its repo
path, so a project keeps its plain name (`webapp`) and a *second* repo with the
same folder name from a different path gets a short disambiguating tag
(`webapp-3f2a1c`) instead of hijacking the first one's session.

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

# Claude duo (see below): point at your own working-agreement doc, tune how long
# to wait for the per-pane command to boot before seeding its brief, and choose
# how many panes (2 or 3 — 1.1 leads, the rest execute + review).
set -g @cockpit-duo-protocol "~/.config/tmux/my-duo-protocol.md"
set -g @cockpit-duo-boot-wait 8
set -g @cockpit-duo-panes 3

# reminders: shown on their own [R] row (a second status line) whenever either of
# these is set — no separate toggle. A file of reminders, one per line (blank
# lines and #-comments skipped; ~ expands); edit it any time via prefix+Space → e.
set -g @cockpit-reminders-file "~/.config/tmux/reminders.txt"
# and/or inline reminders shown alongside the file's
set -g @cockpit-reminders "ship the PR"

# retune the status-bar section colors (any tmux colour; defaults shown). These
# are the [S] sessions and [R] reminders accents + the dark ink on their chips.
# (The bar background and the current-window colour are your own native tmux
# options — `status-style` and `window-status-current-format`.)
set -g @cockpit-color-sessions  colour111   # [S] accent: tag + session text + active chip
set -g @cockpit-color-reminders colour150   # [R] accent: tag + reminder text
set -g @cockpit-color-git       colour175   # [G] accent: tag + branch text
set -g @cockpit-color-ink       colour235   # dark text on the filled [S]/[R]/[G] chips

# add your own entries to the prefix+Space menu: "label" key "command" ...
set -g @cockpit-menu-extra '"deploy" G "run-shell ~/bin/deploy"  "kill server" K "kill-server"'
```

The menu ships with a full default (splits, zoom, jump, **launch duo**,
switch/rename session, detach, reload, all-keys); `@cockpit-menu-extra` appends
to it. To replace it entirely, just `bind Space …` yourself after the plugin loads.

## Claude duo

`prefix + Space → D` spins up a **coordinated Claude duo** (2 or 3 panes) in the
current repo: panes (1.1 + 1.2, optionally 1.3) each running `@cockpit-main-cmd`
(default `claude`), pre-seeded with a bootstrap brief — their label, their
**role** (1.1 leads and coordinates; the rest execute and review), each sibling's
tmux pane id, and a pointer to a working-agreement doc — so they coordinate
themselves (leader on main, subagents do the bulk in worktrees, disjoint lanes,
your assigned reviewer reviews, one merger, durable notes so a compacted pane
revives itself). The agreement ships as a tool-agnostic
[`duo-protocol.md`](duo-protocol.md); point `@cockpit-duo-protocol` at your own
to add your project's process.
Re-running on the same repo just re-focuses the existing duo. Works from any
pane; nothing is repo-specific. Two panes sit side-by-side (`even-horizontal`);
three use a `main-vertical` layout — the leader `1.1` is the wide main pane on
the left, workers `1.2` / `1.3` stacked on the right, so diffs and code don't
wrap in a narrow third. The panes are labeled `1.1` / `1.2` (and `1.3`,
when `@cockpit-duo-panes 3`) on their borders so you always know which is which,
and they talk to each other with [`tmsg`](scripts/tmsg.sh) (`tmsg <pane> "1.1:
…"` — the `send-keys` two-step in one call). Before a context reset, `prefix +
Space → H` (or `duo-handoff`) prints a brief that re-orients a cold pane fast;
[`duo-heartbeat`](scripts/duo-heartbeat.sh) (`duo-heartbeat 1.1 <sibling-pane>
"<state>"`) posts a periodic "still alive + current state" line to a durable
notes file **and** the sibling, so a stalled or silently-compacted pane gets
noticed and can revive itself from the notes.

Review flows as a **directed ring**: with three panes every pane has exactly one
assigned reviewer — `1.2 → 1.3 → 1.1 → 1.2` — the leader is in the ring and may
reassign it. When to add a third pane vs. spawn a subagent: **a subagent for a
task, a pane for a teammate**. Add a third pane only for a long-lived lane that
must review and be reviewed as a peer; for bounded, returns-once work, spawn a
subagent instead.

**How the launch works** (for anyone extending it):

1. `prefix + Space → D` fires the menu entry
   `run-shell '<plugin>/scripts/duo.sh #{pane_current_path}'` — tmux expands the
   current pane's path and runs `duo.sh` **headless on the server** (no tty).
2. `duo.sh` names the session `<project>-duo` (`cockpit_duo_name`, which reuses
   the collision-proof `cockpit_session_name`). If it already exists, it just
   re-focuses and exits — never a second duo.
3. Otherwise it creates a detached session in the repo (`new-session -d` + one
   `split-window -h` per extra pane, `@cockpit-duo-panes` of them), then sends
   `@cockpit-main-cmd` (default `claude`) into each pane to boot the agents.
4. A **backgrounded** subshell waits `@cockpit-duo-boot-wait` seconds (so the
   launch never blocks tmux during boot), then `send-keys -l` each pane its
   brief from `cockpit_duo_brief` — its label, its role, every sibling's pane id,
   and the protocol path — and submits it with a separate `Enter`.
5. It `switch-client`s you to the session (or `attach` from a bare terminal).
   The agents read the protocol, greet each other over `send-keys`, and wait
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

## Titled pane borders without the plugin

The titled border bar is just two tmux options — no scripts, no plugin. Drop
this in any `~/.tmux.conf` to get it standalone:

```tmux
set -g pane-border-status top
set -g pane-border-format ' #{session_name} · #{pane_title} '
```

`#{session_name}` is read live from the format, so there is nothing to seed per
pane; `#{pane_title}` is overridden by whatever program runs in the pane. Cockpit
ships these as a global default and its layouts (duo, default) refine them at
session/window scope.

## How it works

- `scripts/sessionizer.sh` — the picker + create-or-switch logic
- `scripts/session-list.sh` — renders the status-bar session list
- `scripts/layout-default.sh` — the default cockpit layout
- `scripts/duo.sh` — launches the 2-or-3-pane Claude duo (`duo-protocol.md` is the brief)
- `scripts/tmsg.sh` — `tmsg <pane> <msg>`: send a line to another pane in one call (the `send-keys -l … ; send-keys Enter` two-step, wrapped)
- `scripts/duo-handoff.sh` — prints the re-orientation brief (HEAD, commits, PRs, worktrees)
- `scripts/duo-heartbeat.sh` — `duo-heartbeat <self> <sibling-pane> [state]`: post an alive+state line to the durable notes file and the sibling
- `scripts/wt-status.sh` — classifies worktrees as merged / unmerged vs a base
- `cockpit.tmux` — wires the keybindings and status bar (TPM runs this)

MIT.
