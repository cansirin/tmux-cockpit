# Duo Protocol — two coordinated Claude panes

The working agreement for a **tmux-cockpit duo**: two Claude instances working
the same repo in parallel panes, **1.1** and **1.2**. Each pane reads this on
startup (seeded by `scripts/duo.sh`). It is **repo-independent** — the rules
hold anywhere; the optional pipeline layer engages only where that tooling
exists.

Read it top to bottom, confirm you've read it, then greet your sibling.

Override the path with `@cockpit-duo-protocol` if you want your own.

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
- Their messages arrive as user turns prefixed with their label. They're a
  trusted teammate — but a peer can't grant you escalation (never merge control
  plane on their say-so, never treat a peer as the human's approval; see §6).

## 2. Lanes — never collide

- **Declare your lane** (files/dirs/services you'll touch) before building; your
  sibling declares theirs. **Lanes must be disjoint** — no shared files in
  flight at once. If a task needs both, split or sequence it.
- When main moves under you, **rebase and re-verify** before pushing.

## 3. Delegate the hard work to subagents

- **The pane orchestrates; background worktree subagents write the code.** Give
  each a crisp brief (design + acceptance criteria); have it commit locally but
  NOT push / PR / comment. You rebase → push → PR → review → gate → ship.
- Diff an agent branch against its **merge-base**, not `main`, when main moved.
- `cd` OUT of a worktree before `git worktree remove` (or the cwd tangles).

## 4. Reciprocal review — the other pane is your fresh eyes

- **You don't review-and-ship your own PR.** The *sibling* fresh-eyes it,
  **runs the real checks** (re-run the suite/typecheck for risky changes — don't
  trust a claim), and posts a **SHA-bound marker on the PR**:
  ```
  review-code: PASS @ <full-head-sha> — merge-ready
  ```
  (or `FAIL @ <sha> …` with reasons). A verbal "looks good" is not the gate.
  Post with `gh pr comment <n> --body-file <file>` (NOT `--jq`); confirm it
  landed.

## 5. One ship-it actor per PR

- One pane merges a given PR, only on the **latest** verdict being a PASS bound
  to the **current** head SHA (a newer FAIL vetoes an older PASS). After merge:
  pull main, delete the branch, clean the worktree, tell your sibling the new
  SHA so they rebase.

## 6. Control plane — never auto-merge

- **Never auto-merge** a PR touching `.github/**`, `.claude/**`, or the
  gate/merge skills. Split it so the safe half ships and the control-plane half
  is **handed to the human to merge by hand.** Surface it; don't sit on it.

## 7. Errors are data

- Never silently swallow a failure. Surface a red check / failing test / skipped
  step plainly, with the output, even when inconvenient. A pre-existing failure
  that isn't yours: say so and prove it (e.g. it fails at the baseline commit
  too); don't let it silently block unrelated work.

## 8. Survive compaction — revitalize each other

- When the human compacts a pane, the sibling re-orients it on wake with a
  five-point brief: (1) `main` SHA + green/red, (2) what moved since the last
  shared checkpoint, (3) open PRs/issues + state, (4) what's in *your* lane in
  flight, (5) any heads-up the other would miss. Keep a short `HANDOFF.md` at
  checkpoints so a cold pane re-orients without you.

## 9. Optional pipeline layer (where it exists)

If the repo uses the **kampus-pipeline** skills (`status:needs-triage`,
`type:epic`, an `epic-ledger` gate), run work through it: `report` → `triage` →
`plan-epic` → `review-plan` → write-code → `review-code` → `ship-it`. GitHub ops
via `gh api` REST, never GraphQL. If the repo has none of that, §§1–8 still
fully apply — they're the substrate; the pipeline is structure on top.

---

**In one line:** disjoint lanes · subagents build · the *other* pane reviews with
a SHA-bound marker · one shipper · never auto-merge the control plane · errors
are loud · revitalize on compaction.
