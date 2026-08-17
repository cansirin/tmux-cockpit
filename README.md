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
| `prefix + Space` → `e` | **edit reminders** — pop open the reminders file in `$EDITOR` |
| `prefix + Space` → `a` | **add reminder** — type a line, it's appended to the reminders file (quick capture) |
| status bar | a **labelled legend** — `[S]` sessions · `[G]` git context · centred window list · `[R]` reminders (its own row), each a colored section tag |
| hold the prefix | a **`PREFIX` chip** lights up on the right, next to the standing `prefix + Space = menu` hint |
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

**Optional — put the `tmsg` CLI on your `PATH`.** The menu works without this,
but `tmsg` is handy to type. From the plugin dir:

```bash
make install          # symlinks scripts/tmsg.sh into ~/.local/bin
make install BIN=~/bin # or a dir of your choice
```

It's idempotent, won't clobber a real file, and prunes links to scripts the
plugin no longer ships.

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

# the picker also reads zoxide's frecency list when zoxide is installed, so a
# project you've visited is findable with no config. Opt out / retune:
# set -g @cockpit-zoxide off
# set -g @cockpit-zoxide-limit 200

# reminders: shown on their own [R] row (a second status line) whenever either of
# these is set — no separate toggle. A file of reminders, one per line (blank
# lines and #-comments skipped; ~ expands); edit it any time via prefix+Space → e.
set -g @cockpit-reminders-file "~/.config/tmux/reminders.txt"
# and/or inline reminders shown alongside the file's
set -g @cockpit-reminders "ship the PR"

# retune the status-bar section colors (any tmux colour; defaults shown). The
# defaults are NAMED ansi slots, which the terminal resolves from its ACTIVE
# theme — so the accents follow a light/dark theme flip for free. Pin a fixed
# 256-palette value here instead if you'd rather they never move.
# The filled [S]/[R]/[G] chips are drawn with `reverse`, so their letter is
# painted in the terminal's own background colour — there is no ink option.
set -g @cockpit-color-sessions  blue      # [S] accent: tag + session text + active chip
set -g @cockpit-color-reminders green     # [R] accent: tag + reminder text
set -g @cockpit-color-git       magenta   # [G] accent: tag + branch text

# Same reasoning applies to tmux's OWN theme-blind styles: the status bar
# (`bg=green,fg=black`), the right-hand PREFIX chip + menu hint (tmux puts a clock
# there), the prompt bar (rename window, `branch:`, `reminder:`),
# copy-mode (selection, search hits, mark) and the prefix+Space menu selection all
# ship as `<ansi hue> on fg=black`, unreadable on a theme whose palette is dark
# (GitHub Dark's yellow is #9e6a03). cockpit repaints them with `reverse` so the ink
# is the terminal's own background, and centres the window list so the main row's
# three groups spread space-between.
# It only ever replaces a value tmux itself shipped — set `status-style`,
# `mode-style` & co. yourself and yours is kept. This opts out of the lot:
set -g @cockpit-fix-tmux-defaults off     # default: on

# add your own entries to the prefix+Space menu: "label" key "command" ...
set -g @cockpit-menu-extra '"deploy" G "run-shell ~/bin/deploy"  "kill server" K "kill-server"'
```

The menu ships with a full default (splits, zoom, jump,
switch/rename session, detach, reload, all-keys); `@cockpit-menu-extra` appends
to it. To replace it entirely, just `bind Space …` yourself after the plugin loads.

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

## What the picker lists

Three sources, unioned:

1. **every child of `@cockpit-paths`** — a depth-1 scan, so roots are *containers
   of projects*, not projects themselves
2. **`@cockpit-extra`** — literal dirs, verbatim
3. **zoxide's frecency list**, when `zoxide` is installed — anything you've `cd`'d
   into is pickable with **zero config**. Visit a folder once and it's there.

Sources 1 and 2 are what you *configured*, so they are offered as-is (minus
dot-dirs — a root scan otherwise turns up `.claude` and `.github` as projects).
Source 3 is what you *visited*, which is a noisier set, so it gets filtered:

- **stale entries** are dropped (zoxide's db outlives the directories in it)
- **hidden dirs and `$HOME` upward** are dropped — `~/.config/foo`, `~/`, `/Users`
  are places you passed through, not projects
- **a configured root**, and anything *above* one, is never offered as a project.
  You named it as the place projects live *in*, so it and its parents are
  containers by your own declaration. Roots are matched by filesystem identity,
  so a case-insensitive `~/desktop` and a symlinked alias are caught too
- **a nest collapses to one row.** Having visited eleven folders under
  `~/Desktop/sofia` should offer *sofia*, not eleven near-identical rows that push
  the real one off the top

How the collapse decides:

A path suppresses only its own **descendants**, never an ancestor. `~/Desktop`
stays on the list ranked where zoxide ranks it — dropping ancestors collapsed
nests from the wrong end, letting a `~/work` you visit daily eat every project
inside it.

A **configured** path is never dropped, and it does suppress. Naming a dir (or
its parent root) says it is a project, so the folders you have opened inside it
are the same project rather than more of them.

**Known cost:** a namespace layout — `~/code/github.com/owner/repo` under a
`~/code` root — has `github.com` as a root child by mechanical listing, not
because it is a project, so suppressing hides the repos. The answer is a glob
root, which `@cockpit-paths` already expands:

```tmux
set -g @cockpit-paths "$HOME/code/github.com/*"
```

Each owner becomes a root, so the repos arrive configured themselves.

**Known limit:** if you visit a *container* more than the projects inside it, and
it is not configured, the container wins and its projects collapse into it. From
the outside that is indistinguishable from sofia outranking its own subfolders.
The fix is to name it in `@cockpit-paths` — its children then arrive configured,
and nothing can suppress those.

Note it deliberately does **not** filter on `.git`: a folder of coursework or
scratch work is still a project.

Tune with `@cockpit-zoxide off` (drop source 3 entirely) and
`@cockpit-zoxide-limit` (how many surviving entries to take, default 200).

## How it works

- `scripts/sessionizer.sh` — the picker + create-or-switch logic
- `scripts/session-list.sh` — renders the status-bar session list
- `scripts/layout-default.sh` — the default cockpit layout
- `scripts/tmsg.sh` — `tmsg <target> <msg>`: send a line to another window/pane in one call (e.g. `myrepo:build`; the `send-keys -l … ; send-keys Enter` two-step, wrapped)
- `scripts/link.sh` — `make install`: symlink the `tmsg` CLI onto `PATH`
- `cockpit.tmux` — wires the keybindings and status bar (TPM runs this)

MIT.
