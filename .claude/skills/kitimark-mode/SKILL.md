---
name: kitimark-mode
description: >-
  How the Mitos owner (kitimark) wants agents to work. The session the user talks to plans and
  delegates, agents do the work on a model and effort chosen for their role, and the user keeps
  only spec approval and trust-infrastructure changes. Use for /kitimark-mode, "work in
  kitimark's style", or any autonomous work on Mitos tasks.
---

# kitimark mode

The process itself (loops, two-PR protocol, locks, gates, tripwires) is in `docs/process.md`.
This file says who does the work and how much to decide alone while following it.

## The root orchestrates

The root is the session the user talks to. It plans, delegates, judges and catches the user up.
Agents do the rest, so the root is always free to answer the user. A spawned agent is not the
root. It does its brief's work itself and follows the parts of this file for its role.

- The root picks the next task, writes each brief, spawns agents, reads each report together with
  the diff or artifact behind it, and decides what happens next. It answers a quick question from
  what it already has, and it makes a one-line edit itself.
- Everything else goes to an agent from the role table below: building, fixing, rebasing,
  pushing, answering review threads, and any check that runs longer than about a minute. CI
  failures and bot findings on a PR go to that PR's owner. A failure no PR owns yet, such as a
  red nightly run, goes to a researcher first.
- **Tripwire.** If the root is about to push, rebase, edit more than one line or wait on a long
  run, it stops and hands the job to an agent instead. A root that does the work goes quiet for
  the user and fills its context with logs. One session that worked this way compacted three
  times, and the user had to ask "what's next?" twice.
- A program of many PRs also follows the Orchestrate playbook
  (`.claude/skills/poteto-mode/playbooks/orchestrate.md`) for sub-coordinators and supervision.

## Roles

Set `model` and `effort` on every Agent call from this table. This is the explicit request the
Agent tool needs before it takes `effort`. Run every spawn in the background
(`run_in_background: true`).

| Role | Job | `subagent_type` | `model` | `effort` |
|---|---|---|---|---|
| PR owner, hard | Lean proofs, a trust-critical PR (see Verdicts), a skill or design change | `general-purpose`, worktree | `opus` | `xhigh`, or `max` for the subtlest proof |
| PR owner, routine | a script, a fixture, a doc fix, a rebase, a conflict merge, a one-line fix | `general-purpose`, worktree | `sonnet` | `high`, or `medium` for a rebase or a one-line fix |
| Verifier | checks one head it did not write and returns pass or fail with evidence | `general-purpose`, worktree | the model the PR owner did not use | `xhigh`, or `high` at a rebase or minor-fix head |
| Watcher | waits on one PR or one condition and returns when its state changes | `general-purpose` | `sonnet` | `low` |
| Researcher | reads docs or prior art, or diagnoses a failure, and edits nothing | `general-purpose` | `sonnet`, or `opus` for a judgment call | `medium`, or `high` on `opus` |

- **Briefs.** Each brief states the user's goal, the task, the paths the agent may write, the
  evidence that proves the job done, and where the agent stops. A worktree spawn sets
  `isolation: "worktree"` and names the commit to start from, because an isolated worktree starts
  from the default branch.
- **Other spawns.** A spawn whose model a routed skill (`how`, `swarm`, `reflect` and the like)
  or an agent file names keeps that model and takes the closest row's `effort`. Under the
  **poteto-mode** skill, `poteto-agent` replaces `general-purpose` for PR owners. If the Agent
  tool rejects a value, omit that field and say so.
- **Forks.** A `fork` ignores `model` and `effort` and runs on the root's settings and context.
  Fork only when the job needs the root's built state, never for a PR round, a review or a
  verdict.
- **Watchers.** A watcher polls `gh api` from a background shell loop, so waiting costs no turns.
  It returns only on a state change: a new head, a check result at the current head, a new or
  reopened thread from someone else, a label, a merge or a close. It drops check suites on
  superseded heads, the session's own replies echoed back, and bot edits to threads already
  resolved. Nobody subscribes to PR activity, because subscription events land in the root.

`.claude/hooks/check-agent-spawn.sh` warns when an Agent call leaves out `model` or `effort`, or
when a fork sets either.

## Decide, don't ask

- When there is a recommended next step, take it and report what you did. Do not end a turn with
  "Should I…?". The user has answered every such question with "yes" or "what's next?".
- Pick the next task yourself: the first `not started` row in the current `plan/phase-N.md`
  whose dependencies are met. Prefer work that strengthens the checks (mutants, fixtures,
  scorer) before new features. When a phase's exit criteria are met, draft the next phase's
  plan together with its spec PR; plans are the user's, so both wait for the user.
- Choose between implementation options on your own; record the choice and the reason in the
  task file or PR body, not as a question.

## PR owners carry their PR

A PR owner carries one PR from its branch to a green `gate` with every review thread answered,
then reports the head and returns. A brief never stops it at "code-ready" for the root to open
the PR. The root never takes over a round. A later round, such as a red check after a rebase or
a new bot finding, goes to a fresh PR owner with consolidated scope: the first brief, every later
directive, the last report and the branch.

1. Branch from the latest `main`. One task, or a few tightly coupled ones, per PR. Keep the
   branch current by rebasing onto `main`, not by merging `main` in. A `needs-rebase` label (set
   by `.github/workflows/update-prs.yml` when an automatic rebase conflicts) gets a PR owner, who
   rebases, resolves, reruns the checks and force-pushes with a lease.
2. Before pushing, run locally every check in the `docs/process.md` check matrix that the change
   can affect. For Lean work that includes `cd core && lake check` and
   `lake comparator --paranoid`.
3. Open the PR without asking. Watch it the way a watcher does until CI and the bots finish.
   Batch known fixes into one push, because each push starts CI and a paid bot review.
4. CI red: reproduce locally, fix, push. Never weaken a theorem, gate or cheat expectation to
   get green; that is a spec change and goes to the user.
5. Check each bot finding against the code. Fix the real ones, and reply on every thread with
   the fixing commit or the reason the code stays. Leave a security finding's thread open for the
   user.
6. Update the task file, `plan/phase-N.md` and the run log (`ops/runs/`) in the same PR.
7. Push every known fix, then report the head as merge-ready or as waiting on the user.

## Verdicts

- The root spawns a verifier at the head each PR owner reports, except for a wording-only change.
  Only an agent that did not write the code gives a verdict. CI, bot reviews and the root's own
  reading are inputs to one.
- A wording-only change alters no behavior. It edits prose, comments or typos, and no code,
  script, spec, lock, workflow, skill rule or hook. The root confirms that from the diff. Such a
  change needs no verdict, and a green `gate` at its head stands in for one in the merge rule below.
- The verifier runs on the model the PR owner did not use. A trust-critical PR also gets an
  `opus` verifier at `xhigh` or above, so an `opus`-owned one gets two. Trust-critical means the
  PR needs `spec-approved` or touches `gate/`, `eval/cheats/` or `.github/workflows/`.
- A verdict covers one head. A later head that only rebases, with the same `git patch-id --verbatim`,
  keeps it because the change is the same, but still needs its own green `gate` because the base
  is not. The default `git patch-id` ignores whitespace, and Lean reads indentation, so the flag
  is required. Any other new head needs a new verifier.
- When the current head holds a passing verdict, or is a wording-only change, and holds a green
  `gate`, no review comment from the
  user is unanswered, and the PR touches nothing the user owns (below), the PR merges with rebase
  and merge, pinned to that head (`gh pr merge <pr> --rebase --match-head-commit <sha>`). A PR owner
  that is still running merges it, as in Autopilot-full step 5. Otherwise the root runs that one
  command. A failed verdict goes to a fresh PR owner with the findings.

## Done means verified

- The checks pass locally and in CI, and a small concrete run shows the behaviour. Report
  numbers and results, not "should work".
- A script that calls GitHub or another external API proves itself with a real run against that
  API, such as a `workflow_dispatch` run, or with a verifier told to break its API calls. A local
  stand-in such as a scratch git remote proves only the git steps.

## Lean first

- New logic goes in Lean with proved statements. Use fixtures or tests only for what cannot be
  stated as a theorem.
- Stuck on a proof: follow the task file's escalation order. If the statement looks false, write
  the counterexample and open a spec PR; do not bend the implementation.

## What stays with the user

- **Spec approval.** The `spec-approved` label on PRs that change `statements.lock`,
  `models.lock`, `core/Mitos/Core/`, `core/Challenge/` or `core/comparator.json`. Everything in
  `core/Mitos/Core/` is spec, even a change the lock does not show. Never add the label, and
  never route around it (moving statements out of the lock, editing the CI check).
- **Trust infrastructure and plans.** PRs touching `gate/`, `eval/cheats/`, `.github/`,
  `plan/`, `CLAUDE.md` or `.claude/` are merged by the user. Status updates to a task's own row
  in `plan/phase-N.md` are the exception. These PRs stop at verified and green, with a catch-up.
- **Outside the repo.** GitHub settings, branch protection, environment network access,
  anything that sends messages or costs money. Automation that multiplies pushes, such as a bot
  that rebases every open PR on each merge, costs money too. Each push starts CI and a paid bot
  review, so its proposal lists what one push triggers.

## Catching the user up

This is the root's main job between spawns.

- Message the user when something changes for them: a PR becomes merge-ready, merges or starts
  waiting on them, a verdict fails, or a call needs them. Send one rollup per change. A round of
  the same event is one line ("the updater rebased 6 PRs, all green", or which are red).
- A notification that changes nothing for the user gets no message. That covers an agent's
  interim status, a watcher re-arming, and every event a watcher drops. Never send "nothing to
  do".
- Short and plain. The user writes brief messages in non-native English. Lead with what
  happened, then what you are doing next.
- For "why" questions: the idea first, then one concrete example from this repo.
- While a PR waits on the user (a label, a merge, a setting only they can change), post one
  catch-up comment on the PR, then carry on with an independent task. The comment has:
  - **Status:** each check and verdict at the current head, with its evidence. A verdict names
    the head it covers, says whether later heads only rebase (same `git patch-id --verbatim`) or change
    content, and names who gave it: a verifier agent and its model, a bot, or the root itself.
    Never call a bot's verdict or your own independent.
  - **Next steps:** numbered, with a `gh` command (one per code block) wherever one exists; say
    "browser only" where none does.
  - **Expected result** of each step, and what to do if it differs.
  A known fix that is not pushed yet, such as one held back to save bot reviews, goes in a new
  catch-up as "hold the merge until N fixes land". Nothing confidential: no IDs, keys, tokens,
  codes, emails or private URLs. When the state changes, post a new catch-up rather than editing
  an old one, so the user is notified.
- After a catch-up that waits on a user action, spawn a watcher on that exact condition. When it
  returns, check the condition yourself and carry on without waiting to be told.

## Research

- Run researchers in parallel for research and broad investigation; the user asked for this.
  Keep the conclusions, not the dumps.
- Subagents share the session's network policy, so a host blocked for the root is blocked for
  them too. For a blocked vendor docs host, read the vendor's official repositories on GitHub,
  which clone. Otherwise ask the user once to allow the host.
