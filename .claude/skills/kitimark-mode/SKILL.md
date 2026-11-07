---
name: kitimark-mode
description: >-
  How the Mitos owner (kitimark) wants agents to work: decide and keep going instead of asking,
  with the owner kept only on spec approval and trust-infrastructure changes. Use for
  /kitimark-mode, "work in kitimark's style", or any autonomous work on Mitos tasks.
---

# kitimark mode

The process itself (loops, two-PR protocol, locks, gates, tripwires) is in `docs/process.md`.
This file says how much to decide alone while following it.

## Decide, don't ask

- When there is a recommended next step, take it and report what you did. Do not end a turn with
  "Should I…?": the user has answered every such question with "yes" or "what's next?".
- Pick the next task yourself: the first `not started` row in the current `plan/phase-N.md`
  whose dependencies are met. Prefer work that strengthens the checks (mutants, fixtures,
  scorer) before new features. When a phase's exit criteria are met, draft the next phase's
  plan together with its spec PR; plans are the owner's, so both wait for the user.
- Choose between implementation options on your own; record the choice and the reason in the
  task file or PR body, not as a question.

## What stays with the user

- **Spec approval.** The `spec-approved` label on PRs that change `statements.lock`,
  `models.lock`, `core/Mitos/Core/`, `core/Challenge/` or `core/comparator.json`. Everything in
  `core/Mitos/Core/` is spec, even a change the lock does not show. Never add the label, and
  never route around it (moving statements out of the lock, editing the CI check).
- **Trust infrastructure and plans.** PRs touching `gate/`, `eval/cheats/`, `.github/`,
  `plan/`, `CLAUDE.md` or `.claude/` are merged by the user. Status updates to a task's own row
  in `plan/phase-N.md` are the exception. Open them, get CI green, say so.
- **Outside the repo.** GitHub settings, branch protection, environment network access,
  anything that sends messages or costs money.
- While a PR waits on the user: one line with the link, then carry on with an independent task.

## PR loop

1. Branch from the latest `main`. One task, or a few tightly coupled ones, per PR. Keep the
   branch current by rebasing onto `main`, not by merging `main` in. A `needs-rebase` label
   (set by `.github/workflows/update-prs.yml` when an automatic rebase conflicts) is yours to
   resolve: rebase, resolve, rerun the checks, force-push with a lease.
2. Before pushing, run locally every check in the `docs/process.md` check matrix that the change
   can affect. For Lean work that includes `cd core && lake check` and
   `lake comparator --paranoid`.
3. Open the PR without asking, then subscribe to its activity.
4. CI red: reproduce locally, fix, push. Never weaken a theorem, gate or cheat expectation to
   get green; that is a spec change and goes to the user.
5. When `gate` is green, there are no unanswered review comments from the user, and the PR
   touches nothing the user owns (above): merge it with rebase and merge. Then restart the branch
   from `main` and start the next task.
6. Update the task file, `plan/phase-N.md` and the run log (`ops/runs/`) in the same PR.

## Lean first

- New logic goes in Lean with proved statements. Use fixtures or tests only for what cannot be
  stated as a theorem.
- Stuck on a proof: follow the task file's escalation order. If the statement looks false, write
  the counterexample and open a spec PR; do not bend the implementation.

## Done means verified

- The checks pass locally and in CI, and a small concrete run shows the behaviour. Report
  numbers and results, not "should work".

## Research

- Use subagents or a workflow in parallel for research and broad investigation; the user asked
  for this. Keep the conclusions, not the dumps.

## Replies

- Short and plain. The user writes brief messages in non-native English. Lead with what
  happened, then what you are doing next.
- For "why" questions: the idea first, then one concrete example from this repo.
