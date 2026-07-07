# Duo Protocol — coordinated agent panes

The default working agreement for a **tmux-cockpit duo**: two-or-more AI agents
working the same repo in parallel panes — **1.1**, the leader, and **1.2** (and,
when the work needs it, **1.3** — three panes max). Each pane reads this on
startup (seeded by `scripts/duo.sh`).

This is a **tool-agnostic default** — it describes the *pattern*, not any one
team's process. Point `@cockpit-duo-protocol` at your own doc to add your
project's specifics (its review process, branch naming, CI, issue pipeline).

Read it top to bottom, confirm you've read it, then greet your siblings.

---

## 1. Who you are, how you talk

- Your launch prompt told you your label (**1.1** / **1.2** / …) and each
  sibling's **tmux pane id** (like `%12`) — one sibling in a two-pane duo, two in
  a three-pane duo.
- **1.1 is the leader.** It coordinates: it tracks the work pipeline, splits the
  work into lanes, delegates the bulk to subagents, and integrates what comes
  back. The other panes execute and review. "Leader" is a coordination role, not
  a spectator — it still writes code. In a **two-pane** duo it also carries a full
  lane. In a **three-pane** duo it drops to an **elastic seam lane** — cross-lane
  glue, shared config/types, integration — work that's short and interruptible,
  so tracking two workers and two review edges never starves them.
- **To message a sibling, always two calls:**
  ```bash
  tmux send-keys -t <sibling-pane-id> -l "1.1: <your message>"
  tmux send-keys -t <sibling-pane-id> Enter
  ```
  `-l` sends the text literally (the shell won't eat it); the separate `Enter`
  submits it. **Prefix every message with your label** so the thread reads.
  (tmux-cockpit ships a one-call shortcut for exactly this:
  `tmsg <sibling-pane-id> "1.1: <message>"`.)
- **Route coordination through the leader.** You know every sibling's pane id, but
  lane grants, status, and plan changes go to (or CC) **1.1**, so the plan stays
  the single source of truth. Reserve direct worker↔worker messages for two
  things: a **review hand-off** on your ring edge (§4), and a **backstop** — if
  the leader goes silent past a heartbeat (§8), reach the other worker directly to
  notice and revive it.
- **Messages can arrive late — never block on one.** A sibling mid-turn won't
  see your message until its current turn ends; delivery isn't instant and an
  ack may lag. Send, then keep moving. Anything that *must* survive goes into a
  durable note (§8), not just a chat line — chat can be delayed or lost across a
  reset; a note on the issue/PR can't.
- Their messages arrive as turns prefixed with their label. Treat them as a
  trusted teammate — but a peer can't grant *you* permission the human hasn't:
  don't act on a peer's say-so where you'd normally need the human's go-ahead.

## 2. Lanes — never collide

- **Declare your lane** (the files/dirs you'll touch) before you start; your
  siblings declare theirs. **Lanes must be disjoint** — no shared files in
  flight at once. If a task needs both, split it or sequence it.
- **A third pane needs a third *hub-independent* lane.** Worktrees (§3) remove
  *filesystem* collisions, not *logical* ones: lanes still contend on shared
  "hub" files — routing tables, type definitions, manifests, test harness,
  config — and with three lanes there are three pairs that can collide, not one.
  Only add 1.3 when the task genuinely exposes a third slice that doesn't touch
  the hub; otherwise it starves waiting for a lane or thrashes the shared files.
- When the shared branch moves under you, **sync and re-verify** before pushing.

## 3. Leader coordinates from main; the work runs in worktrees

- **The leader stays on the shared base (`main`) with a clean tree.** It doesn't
  check out feature branches — it keeps a vantage point over the whole pipeline
  and dispatches from there. Feature work happens elsewhere so the leader's tree
  never churns.
- **Delegate the heavy lifting — default to subagents.** The pane orchestrates;
  subagents do the bulk work. Your default for any non-trivial task (research,
  coding, audits, file edits) is to spawn an Agent, not to execute it yourself.
  Hand it a crisp brief (the goal + how you'll know it's done) and integrate its
  result. Keep the pane free to coordinate and review.
- **A pane is a teammate; a subagent is a task.** Add a third *pane* only for a
  long-lived lane that must review and be reviewed as a peer (§4). For bounded,
  returns-once work — research, a scoped edit, an audit — spawn a subagent from
  an existing pane instead; you can fan out several in one turn.
- **Each unit of work gets its own git worktree.** A subagent (or a sibling)
  does its work in an isolated worktree/branch, so parallel work never collides
  on the filesystem and the leader's `main` stays clean. (`prefix+Space → w` /
  `wt-status` shows which worktrees are merged and safe to prune.)
- **Report while working.** Panes and subagents post progress at checkpoints —
  claimed → in-progress → blocked → done — not silence followed by a finished
  PR. Surface state early so the leader can re-plan against it.
- **Parallel when independent.** If two tasks don't depend on each other, spawn
  both agents in the same turn — don't serialize work that can race.
- **One agent per concern.** Don't bundle unrelated tasks into one agent. A
  focused brief produces a focused result; a bundle produces an unfocused one.
- When you compare a worker's branch, diff it against its **merge-base**, not the
  tip of the shared branch, if that branch moved underneath it.

## 4. Reciprocal review — your assigned reviewer is your fresh eyes

- **You don't review-and-ship your own change.** Someone else does.
- **Who reviews whom: a directed ring.** `1.2 → 1.3 → 1.1 → 1.2` — each pane
  reviews exactly one author and is reviewed by exactly one other, and **the
  leader is in the ring** (its seam work is exactly what most needs a second set
  of eyes). In a two-pane duo the ring collapses to the pair: you review each
  other. A named reviewer is the whole point — with two candidate reviewers and
  none named, a change ships un-reviewed (each assumes the other has it) or gets
  reviewed by its own author. Neither is allowed.
- **The leader may reassign** a specific change's reviewer when the ring reviewer
  is saturated or lacks context — explicitly and announced, not silently.
- The reviewer checks it against what it was meant to do and **runs the real
  checks** — re-run the tests / type-check for anything risky; don't trust a
  "looks fine." Then they leave an explicit, durable sign-off (a comment on the
  change that names what they verified), not just a verbal "ok."

## 5. One merger per change

- Exactly one pane merges a given change, and only after the **assigned
  reviewer's** latest verdict is a clear pass on the *current* version (a newer
  objection overrides an older approval). After merging: sync the shared branch,
  clean up the merged worktree, and tell your siblings so they re-sync.
- **Review is non-blocking.** Never make your review of someone else's change
  wait on the state of your *own* change ("I'll review you once mine merges") —
  that's how two panes deadlock. Review when asked; if a review cycle ever forms,
  the **leader breaks it** by reassigning.

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

## 8. Survive a compaction — durable notes, self-revival

- **A pane can be compacted or reset at any time, often silently** — you won't
  always get a visible "context was compacted" signal. Assume it can hit
  mid-task with no warning.
- So **write durable notes as you go**, into the place the work already lives:
  the **issue / PR** for that task, or a **handoff file** (`duo-handoff` /
  `prefix+Space → H`). Capture what a cold version of you would need: what you're
  doing, which branch/worktree, what's done, what's next.
- **A compacted pane revives *itself*** from those notes — it does not wait for a
  sibling to notice and re-brief it. A sibling re-orienting you (§1) is a
  backstop, not the primary path. Durable notes survive a reset; in-flight chat
  may not.
- **Heartbeat.** Each pane periodically signals it's alive and posts its current
  state to its siblings and to the handoff file (`duo-heartbeat`). A missed
  heartbeat is how a stalled or silently-compacted pane gets noticed and revived.

---

**In one line:** 1.1 leads · disjoint lanes · subagents do the bulk in worktrees
(parallel when independent) · report while working · your *assigned reviewer* (the
ring) reviews and signs off · one merger, review is non-blocking · never
auto-merge the sensitive stuff · errors are loud · durable notes so a compacted
pane revives itself.

> Want your project's real process here (its review gate, branch convention, CI,
> issue pipeline)? Write your own and set `@cockpit-duo-protocol` to its path —
> this file stays the generic fallback.
