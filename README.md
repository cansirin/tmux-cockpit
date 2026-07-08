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
| `prefix + Space` → `c` | **launch the pipeline-crew** — a 3-window Claude crew (triage · em · ea) in the current repo, each seeded with its role prompt |
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
command-line tools (`tmsg`, `wt-new`, `wt-prune`, `wt-status`, …) are handy to
type — and crew windows call `tmsg` by name to message each other. From the
plugin dir:

```bash
make install          # symlinks scripts/{tmsg,wt-*}.sh into ~/.local/bin
make install BIN=~/bin # or a dir of your choice
```

It's idempotent and won't clobber a real file; new `wt-*` scripts are picked up
automatically on the next run.

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

# pipeline-crew (see below): tune how long to wait for the per-window command to
# boot before seeding its role prompt, and map each config model tier to a real
# --model (the crew.config.jsonc names tiers; this says which model each tier is).
set -g @cockpit-crew-boot-wait 8
set -g @cockpit-crew-model-planning-tier 'opus'
set -g @cockpit-crew-model-build-tier    'opus'

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

The menu ships with a full default (splits, zoom, jump, **launch crew**,
switch/rename session, detach, reload, all-keys); `@cockpit-menu-extra` appends
to it. To replace it entirely, just `bind Space …` yourself after the plugin loads.

## Pipeline crew

`prefix + Space → c` stands up the [kamp.us **pipeline-crew**](https://github.com/kamp-us/phoenix/tree/main/claude-plugins/pipeline-crew)
as a tmux session in the current repo — three Claude windows, one per seam of the
issue→merge conveyor:

```
    intake                execution                 human
  ┌──────────┐        ┌──────────────┐        ┌──────────────┐
  │  triage  │  ───▶  │      em      │  ───▶  │      ea      │
  │ triage-  │        │ engineering- │        │    exec-     │
  │   guy    │        │   manager    │        │  assistant   │
  └──────────┘        └──────────────┘        └──────────────┘
```

Each window runs `@cockpit-main-cmd` (default `claude`) on its model tier,
pre-seeded with a spawn prompt that tells it which pipeline-crew agent def to
follow (`triage-guy` / `engineering-manager` / `exec-assistant`), its seam
behaviour, and to resolve the personalization seam. You land on the **ea** window
— your single point of contact into the crew. Re-running on the same repo just
re-focuses; nothing is repo-specific. Windows message each other with
[`tmsg`](scripts/tmsg.sh) by name — `tmsg crew:em "ea: ship #123"`.

This is a **starter, not the crew itself.** The three agent defs live in the
installed [`pipeline-crew`](https://github.com/kamp-us/phoenix/tree/main/claude-plugins/pipeline-crew)
plugin (which conducts the [`kampus-pipeline`](https://github.com/kamp-us/phoenix/tree/main/claude-plugins/kampus-pipeline)
skills) — install both, then this button brings them up as a session. tmux-cockpit
only owns the topology; the crew owns its own behaviour.

### The config seam — zero duplication

Window names and per-role model tiers come from the pipeline-crew
**personalization file** (`$CREW_CONFIG`, else `<repo>/.claude/crew.config.jsonc`)
— the plugin's *own* seam, so tmux-cockpit stores none of it and nothing drifts
out of sync with the defs:

```jsonc
{
  "tmux":       { "windows": { "ea": "ea", "engineeringManager": "em", "triage": "triage" } },
  "modelTiers": { "ea": "planning-tier", "engineeringManager": "build-tier", "triage": "planning-tier" }
}
```

The launcher reads only those two objects (window names + tier names). Everything
else in the file — operator, notification handle, §CP approver, WIP caps — the
crew defs read themselves at spawn. **No config?** It still launches with the
default window names (`triage`/`em`/`ea`), and the defs prompt you to run
stand-up. Tier→model is the one thing the plugin doesn't own: map each tier name
to a real `--model` once via `@cockpit-crew-model-<tier>` (e.g.
`@cockpit-crew-model-build-tier 'opus'`); unset → plain `@cockpit-main-cmd`, so a
role never silently downgrades on a made-up model.

**How the launch works** (for anyone extending it):

1. `prefix + Space → c` fires the menu entry
   `display-popup -E -d '#{pane_current_path}' '<plugin>/scripts/crew.sh'` — the
   popup gives `crew.sh`'s final `switch-client` a live client to target.
2. `crew.sh` names the session `<project>-crew` (`cockpit_crew_name`, which reuses
   the collision-proof `cockpit_session_name`). If it already exists, it just
   re-focuses and exits — never a second crew.
3. Otherwise it creates a detached session with one window per seam
   (`new-session -d -n <triage>` + a `new-window` for em and ea), reading the
   names from the config, and boots `@cockpit-main-cmd` (with `--model` per tier)
   in each.
4. It computes each window's spawn prompt now (`cockpit_crew_brief`) into a temp
   file, then hands the deferred send to the tmux **server** with
   `run-shell -b '…/crew-seed.sh …'`. `crew-seed.sh` waits `@cockpit-crew-boot-wait`
   seconds, `send-keys -l`s each window its prompt, and deletes the file.
   Server-side is load-bearing: the launcher runs inside a display-popup, and a
   plain backgrounded shell job would be killed when the popup closes — before the
   boot-wait — so nothing would reach the windows.
5. It `select-window`s to **ea** and `switch-client`s you there (or `attach` from
   a bare terminal).

The pure logic (`cockpit_crew_name`, `cockpit_crew_config_get`,
`cockpit_crew_brief`) lives in `scripts/lib.sh` and is unit-tested in
`tests/crew.bats`; the launch + re-focus behavior is covered in
`tests/integration.bats` (on an isolated socket).

## Tests

```bash
bats tests/        # needs: bats, tmux, fzf
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
ships these as a global default and the default cockpit layout refines them at
window scope.

## How it works

- `scripts/sessionizer.sh` — the picker + create-or-switch logic
- `scripts/session-list.sh` — renders the status-bar session list
- `scripts/layout-default.sh` — the default cockpit layout
- `scripts/crew.sh` — the `prefix+Space → c` entry: stands up the `<project>-crew` session with one window per seam (names + model tiers from `.claude/crew.config.jsonc`), boots `@cockpit-main-cmd` per tier, and seeds each its role prompt
- `scripts/crew-seed.sh` — server-side (`run-shell -b`) deferred prompt send, so it survives the launch popup closing
- `scripts/tmsg.sh` — `tmsg <target> <msg>`: send a line to another window/pane in one call (e.g. `crew:em`; the `send-keys -l … ; send-keys Enter` two-step, wrapped)
- `scripts/wt-status.sh` / `wt-new.sh` / `wt-prune.sh` — worktree lifecycle: classify / create / prune-merged (dry-run by default)
- `scripts/link.sh` — `make install`: symlink the `tmsg`/`wt-*` CLIs onto `PATH`
- `cockpit.tmux` — wires the keybindings and status bar (TPM runs this)

MIT.
