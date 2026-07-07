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
| `prefix + Space` → `D` | **launch a Claude duo** — coordinated AI panes (1.1 leads) in the current repo; asks how many panes (2/3) and which startup layers to run |
| `prefix + Space` → `H` | **handoff brief** — a re-orientation snapshot (HEAD, recent commits, open PRs, worktrees) |
| `prefix + Space` → `w` | **worktree status** — which worktrees are merged (safe to prune) vs still unmerged |
| `prefix + Space` → `W` | **new worktree** — type a branch, get a worktree in a sibling dir |
| `prefix + Space` → `p` | **prune worktrees** — preview the merged ones (dry-run; `wt-prune --force` to act) |
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

**Optional — put the CLIs on your `PATH`.** The menu works without this, but the
command-line tools (`tmsg`, `duo-handoff`, `duo-heartbeat`, `duo-whoami`,
`duo-revive`, `duo-check`, `wt-new`, `wt-prune`, …) are handy to type — and duo
agents call them by name. From the plugin dir:

```bash
make install          # symlinks scripts/{tmsg,duo-*,wt-*}.sh into ~/.local/bin
make install BIN=~/bin # or a dir of your choice
```

It's idempotent and won't clobber a real file; new `duo-*`/`wt-*` scripts are
picked up automatically on the next run.

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
# to wait for the per-pane command to boot before seeding its brief, and set the
# default pane count (2 or 3 — 1.1 leads, the rest execute + review; the launch
# picker pre-selects this and can override it per launch).
set -g @cockpit-duo-protocol "~/.config/tmux/my-duo-protocol.md"
set -g @cockpit-duo-boot-wait 8
set -g @cockpit-duo-panes 3
# extra dir of your own `<name>.layer` startup add-ons (shadow the shipped ones)
set -g @cockpit-duo-layers "~/.config/tmux/duo-layers"

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
and they talk to each other with [`tmsg`](scripts/tmsg.sh) — address a sibling by
**label**, `tmsg 1.2 "1.1: …"` (a raw `%pane`/`sess:win.pane` target still works),
resolved through a small **identity registry** the launcher stamps into tmux
options (`@cockpit-duo-npanes`, a `@cockpit-duo-pane-1-2 → %id` map, and each
pane's own `@cockpit-duo-label`) so labels survive even a compaction. A pane can
re-locate itself with [`duo-whoami`](scripts/duo-whoami.sh) (its label, siblings,
assigned reviewer, notes path) and [`duo-reviewer`](scripts/duo-reviewer.sh) (just
the ring slice). Before a context reset, `prefix + Space → H` (or `duo-handoff`)
prints a brief that re-orients a cold pane fast;
[`duo-heartbeat`](scripts/duo-heartbeat.sh) (`duo-heartbeat 1.1 <sibling>
"<state>"`) posts a "still alive + current state" line to a durable notes file
**and** the sibling. After a silent compaction, [`duo-revive`](scripts/duo-revive.sh)
rebuilds a pane's world (whoami + notes tail + handoff + its worktree), and
[`duo-check`](scripts/duo-check.sh) reads siblings' tmux activity to flag a
stalled or dead pane — no background daemon, just tmux's own liveness signal.

Review flows as a **directed ring**: with three panes every pane has exactly one
assigned reviewer — `1.2 → 1.3 → 1.1 → 1.2` — the leader is in the ring and may
reassign it. When to add a third pane vs. spawn a subagent: **a subagent for a
task, a pane for a teammate**. Add a third pane only for a long-lived lane that
must review and be reviewed as a peer; for bounded, returns-once work, spawn a
subagent instead.

### Duo layers

The brief above is the **base**, always on. A **layer** is an opt-in, composable
add-on that seeds one extra startup instruction into every pane — a different axis
than coordination. A layer is one file, `<name>.layer`, whose lines (minus `#`
comments and blanks) are the seed; layers **stack** onto the base and onto each
other, so you can multi-select. Two ship in [`layers/`](layers):

- **`caveman`** — each pane runs `/caveman full` (a talk-terse style).
- **`kampus`** — each pane is told to drive the kampus-pipeline workflow.

Add your own by dropping a `<name>.layer` file — no code change. Point
`@cockpit-duo-layers` (or `$COCKPIT_DUO_LAYERS`) at a directory of them; a
same-named file there **shadows** the shipped one.

```tmux
set -g @cockpit-duo-layers "~/.config/tmux/duo-layers"
```

`prefix + Space → D` opens a popup that first **asks how many panes** (2 or 3 —
single-select, pre-set to `@cockpit-duo-panes`) and then **which layers to run**
(fzf multi-select) before launching. Either prompt is skipped when there's
nothing to choose (no layers, or no terminal), so a plain duo launches unchanged.
Layers are per-duo (every pane gets the same set), not per-pane.

**How the launch works** (for anyone extending it):

1. `prefix + Space → D` fires the menu entry
   `display-popup -E -d '#{pane_current_path}' '<plugin>/scripts/duo-launch.sh'`
   — a popup (so the pickers get a real tty) whose `duo-launch.sh` runs the pane
   picker (`duo-panes.sh`, passed on as `--panes N`) and the layer picker
   (`duo-layers.sh`, exported as `$COCKPIT_DUO_SELECTED`), then `exec`s `duo.sh`
   in the popup's own process so its `switch-client` has a live client.
2. `duo.sh` names the session `<project>-duo` (`cockpit_duo_name`, which reuses
   the collision-proof `cockpit_session_name`). If it already exists, it just
   re-focuses and exits — never a second duo.
3. Otherwise it creates a detached session in the repo (`new-session -d` + one
   `split-window -h` per extra pane — `--panes` if picked, else `@cockpit-duo-panes`),
   labels/records the identity registry, then sends `@cockpit-main-cmd` (default
   `claude`) into each pane to boot the agents.
4. It computes each pane's brief now (`cockpit_duo_brief` — label, role, every
   sibling's pane id, protocol path, with any selected layers composed on via
   `cockpit_duo_compose_brief`) into a temp file, then hands the deferred send to
   the tmux **server** with `run-shell -b '…/duo-seed.sh …'`. `duo-seed.sh` waits
   `@cockpit-duo-boot-wait` seconds, `send-keys -l`s each pane its brief, and
   deletes the file. Server-side is load-bearing: the launcher runs inside a
   display-popup, and a plain backgrounded shell job would be killed when the
   popup closes — before the boot-wait — so nothing would reach the panes.
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
- `scripts/duo.sh` — launches the 2-or-3-pane Claude duo (`duo-protocol.md` is the brief; `--panes` overrides `@cockpit-duo-panes`; composes any selected layers onto the brief)
- `scripts/duo-launch.sh` — the popup entry for `prefix+Space → D`: pick pane count + layers, then `exec` `duo.sh`
- `scripts/duo-panes.sh` — single-select fzf for how many panes (2 or 3), pre-set to `@cockpit-duo-panes`
- `scripts/duo-layers.sh` — lists/fzf-multi-selects available `layers/*.layer` (user dir shadows the shipped ones)
- `scripts/duo-seed.sh` — server-side (`run-shell -b`) deferred brief send, so it survives the launch popup closing
- `scripts/tmsg.sh` — `tmsg <pane|label> <msg>`: send a line to another pane in one call (label resolves via the duo registry; the `send-keys -l … ; send-keys Enter` two-step, wrapped)
- `scripts/duo-handoff.sh` — prints the re-orientation brief (HEAD, commits, PRs, worktrees)
- `scripts/duo-heartbeat.sh` — `duo-heartbeat <self> <sibling> [state]`: post an alive+state line to the durable notes file and the sibling
- `scripts/duo-whoami.sh` / `duo-reviewer.sh` — a pane's label, siblings, and ring-assigned reviewer, read from the duo registry
- `scripts/duo-revive.sh` — reconstruct a compacted pane: whoami + notes tail + handoff + its worktree
- `scripts/duo-check.sh` — flag a stalled/dead sibling from tmux's pane activity (read-only, no daemon)
- `scripts/wt-status.sh` / `wt-new.sh` / `wt-prune.sh` — worktree lifecycle: classify / create / prune-merged (dry-run by default)
- `scripts/link.sh` — `make install`: symlink the `tmsg`/`duo-*`/`wt-*` CLIs onto `PATH`
- `cockpit.tmux` — wires the keybindings and status bar (TPM runs this)

MIT.
