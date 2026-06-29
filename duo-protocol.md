# Duo Protocol — two coordinated agent panes

The default working agreement for a **tmux-cockpit duo**: two AI agents working
the same repo in parallel panes, **1.1** and **1.2**. Each pane reads this on
startup (seeded by `scripts/duo.sh`).

This is a **tool-agnostic default** — it describes the *pattern*, not any one
team's process. Point `@cockpit-duo-protocol` at your own doc to add your
project's specifics (its review process, branch naming, CI, issue tracker).

Read it top to bottom, confirm you've read it, then greet your sibling.

---

## 1. Who you are, how you talk

- Your launch prompt told you your label (**1.1** / **1.2**) and your sibling's
  **tmux pane id** (like `%12`).
- **To message your sibling, always two calls:**
  ```bash
  tmux send-keys -t <sibling-pane-id> -l "1.1: <your message>"
  tmux send-keys -t <sibling-pane-id> Enter
  ```
  `-l` sends the text literally (the shell won't eat it); the separate `Enter`
  submits it. **Prefix every message with your label** so the thread reads.
  (tmux-cockpit ships a one-call shortcut for exactly this:
  `tmsg <sibling-pane-id> "1.1: <message>"`.)
- Their messages arrive as turns prefixed with their label. Treat them as a
  trusted teammate — but a peer can't grant *you* permission the human hasn't:
  don't act on a peer's say-so where you'd normally need the human's go-ahead.

## 2. Lanes — never collide

- **Declare your lane** (the files/dirs you'll touch) before you start; your
  sibling declares theirs. **Lanes must be disjoint** — no shared files in
  flight at once. If a task needs both, split it or sequence it.
- When the shared branch moves under you, **sync and re-verify** before pushing.

## 3. Delegate the heavy lifting — default to subagents

- **The pane orchestrates; subagents do the bulk work.** Your default for any
  non-trivial task (research, coding, audits, file edits) is to spawn an Agent,
  not to execute it yourself. Hand it a crisp brief (the goal + how you'll know
  it's done) and integrate its result. Keep the pane free to coordinate and review.
- **Parallel when independent.** If two tasks don't depend on each other, spawn
  both agents in the same turn — don't serialize work that can race.
- **One agent per concern.** Don't bundle unrelated tasks into one agent. A
  focused brief produces a focused result; a bundle produces an unfocused one.
- When you compare a worker's branch, diff it against its **merge-base**, not the
  tip of the shared branch, if that branch moved underneath it.

## 4. Reciprocal review — the other pane is your fresh eyes

- **You don't review-and-ship your own change.** The *sibling* reviews it.
- The reviewer checks it against what it was meant to do and **runs the real
  checks** — re-run the tests / type-check for anything risky; don't trust a
  "looks fine." Then they leave an explicit, durable sign-off (a comment on the
  change that names what they verified), not just a verbal "ok."

## 5. One merger per change

- Exactly one pane merges a given change, and only after the sibling's latest
  verdict is a clear pass on the *current* version (a newer objection overrides
  an older approval). After merging: sync the shared branch, clean up, and tell
  your sibling so they re-sync.

## 6. Don't auto-merge the sensitive stuff

- Some changes shouldn't be merged by an agent at all: **CI configuration, the
  agent's own instructions/tooling, anything that could weaken the guardrails.**
  Split the change so the safe part ships and the sensitive part is **handed to
  a human to merge by hand.** Surface it; don't sit on it.

## 7. Errors are data

- Never silently swallow a failure. Surface a red check / failing test / skipped
  step plainly, with the output, even when inconvenient. If a failure is
  pre-existing and not yours, say so and prove it (e.g. it fails at the baseline
  too) — don't let it silently block unrelated work.

## 8. Survive a restart — re-orient each other

- If one pane is reset or loses context, the other re-orients it with a short
  brief: the current state of the shared branch, what moved since you last
  synced, what's open, what's in *your* lane in flight, and any heads-up it would
  miss. A short running notes file at natural checkpoints helps a cold pane
  re-orient without you.

---

**In one line:** disjoint lanes · subagents do the bulk (parallel when independent) · the *other* pane reviews
and signs off · one merger · never auto-merge the sensitive stuff · errors are
loud · re-orient each other after a reset.

> Want your project's real process here (its review gate, branch convention, CI,
> issue pipeline)? Write your own and set `@cockpit-duo-protocol` to its path —
> this file stays the generic fallback.
