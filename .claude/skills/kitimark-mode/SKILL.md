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
  what it already has. It edits no repository file.
- Everything else goes to an agent from the role table below: building, fixing, rebasing,
  pushing, answering review threads, and any check that runs longer than about a minute. CI
  failures and bot findings on a PR go to that PR's owner. A failure no PR owns yet, such as a
  red nightly run, goes to a researcher first.
- **Tripwire.** If the root is about to edit a repository file, push, rebase or wait on a long
  run, it stops and hands the job to an agent instead. A root that does the work goes quiet for
  the user and fills its context with logs.
- A program of many PRs also follows the Orchestrate playbook
  (`.claude/skills/poteto-mode/playbooks/orchestrate.md`) for sub-coordinators and supervision.

## Roles

Set `model` and `effort` on every Agent call from this table. This is the explicit request the
Agent tool needs before it takes either field. Run every spawn in the background
(`run_in_background: true`). Only the root spawns agents. A subagent spawns one only after a
probe in the current environment shows it can, because a subagent's toolset may have no Agent
tool.

| Role | Job | `subagent_type` | `model` | `effort` |
|---|---|---|---|---|
| PR owner, hard | Lean proofs, a trust-critical PR (see Verdicts), a skill or design change | `general-purpose`, worktree | `opus` | `xhigh`, or `max` for the subtlest proof |
| PR owner, routine | a script, a fixture, a doc fix, a rebase, a conflict merge, a one-line fix | `general-purpose`, worktree | `sonnet` | `high`, or `medium` for a rebase or a one-line fix |
| Verifier | checks one head it did not write and returns pass or fail with evidence | `general-purpose`, worktree | the model that did not write most of the diff | `xhigh`, or `high` at a rebase, conflict or minor-fix head |
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
- **Watchers.** A watcher polls the REST routes in **Forge**
  (`.claude/skills/poteto-mode/playbooks/opening-a-pr.md`) in a foreground loop that ends within
  the Bash timeout: `timeout 540 bash -c 'until <check>; do sleep 60; done'`. The watcher
  re-issues it until the state changes. The Monitor tool also works. It never waits in a
  background shell, because a Claude Code session stops a few minutes after no agent is in a
  model call or a foreground tool call.
- A watcher returns only on a state change. That is a new head, a check result at the current
  head, a new or reopened thread that no agent posted, a new comment without the footer or with an
  id no poster recorded, a label, a merge or a close. It drops check suites on superseded heads,
  bot edits to threads already resolved, and agents' own replies. Agents post under the user's
  account, so it finds their replies by the comment ids the posters recorded, never by login. The
  `Generated by [Claude Code]` footer only marks candidates, because anyone can type it. The
  thread route returns no author or body, so it reads bodies from the comment routes in **Forge**.
- Nobody subscribes to PR activity, because subscription events land in the root.

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
   rebases, resolves, reruns the checks and force-pushes with a lease. A PR in a GitHub stack never
   gets that label and is rebased only with its whole stack (see **Stacks**).
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

Every agent that posts to GitHub ends each post with the footer, a `---` line and then
`_Generated by [Claude Code](https://claude.ai/code)_`. This covers PR owners and any other
poster. Its report lists the ids of its posts. The watcher's echo filter and the merge rule below
rely on both.

## Verdicts

- The root spawns a verifier at the head each PR owner reports, except for a wording-only change.
  Only an agent that did not write the code gives a verdict. CI, bot reviews and the root's own
  reading are inputs to one.
- A wording-only change alters no behavior. It edits prose, comments or typos, and no code,
  script, spec, lock, workflow, skill rule or hook. The root confirms that from the diff. Such a
  change needs no verdict, and a green `gate` at its head stands in for one in the merge rule below.
- The verifier runs on the model that did not write most of the diff. A trust-critical PR also
  gets an `opus` verifier at `xhigh` or above at every head that needs a verifier, so an
  `opus`-written one gets two. Trust-critical means the PR needs `spec-approved` or touches a
  trust-infrastructure path (see What stays with the user).
- A verdict covers one head. Take the change's id at each head with
  `git diff <merge-base> <head> | git patch-id --verbatim`, because `git show` gives one id per
  commit. A later head that only rebases, with the same id, keeps the verdict because the change
  is the same. It still needs its own green `gate` because the base is not. The default
  `git patch-id` ignores whitespace, and Lean reads indentation, so the flag is required. Any
  other new head needs a new verifier.
- A PR merges when four things hold at its current head. It has a passing verdict or is a
  wording-only change. Its `gate` is green. No review comment from the user is unanswered, read
  from the comment routes in **Forge**. It touches nothing the user keeps (see What stays with
  the user).
- It merges with rebase and merge, pinned to that head, through
  `gh api -X PUT repos/{owner}/{repo}/pulls/<pr>/merge -f merge_method=rebase -f sha=<head>` or the GitHub
  MCP merge tool with `expectedHeadSha`. `gh pr merge` fails in these sessions (see **Forge** in
  `.claude/skills/poteto-mode/playbooks/opening-a-pr.md`). A PR owner that is still running
  merges it, as in Autopilot-full step 5. Otherwise the root makes that one call.
  A PR that is part of a GitHub stack merges through the asynchronous endpoint instead (see
  **Stacks**).
- A failed verdict goes to a fresh PR owner with the findings.

## Stacks

- PRs that build on each other form a GitHub stack, not a base-branch chain retargeted by hand.
  These sessions block GraphQL, and `gh stack submit` and `gh stack link` find and open PRs over
  GraphQL, so they fail here. Open each PR through the REST create route in **Forge** instead, the
  bottom one on `main` and each next one on the branch below it. Then make the stack with
  `gh api -X POST repos/{owner}/{repo}/stacks -H "X-GitHub-Api-Version: 2026-03-10"
  -F 'pull_requests[]=<bottom>' -F 'pull_requests[]=<next>'`, one `-F` per PR, bottom to top. That
  sends the body field `pull_requests`, a list of 2 to 100 PR numbers.
- GitHub rebases the rest of a stack when its bottom PR merges and retargets the next one to
  `main`, so nobody retargets or force-pushes a stacked PR to follow its parent. GitHub does not
  rebase a stack when `main` moves ahead, and `update-prs.yml` skips every PR in a stack, so it
  never labels one `needs-rebase`. When `main` moves ahead of a stack, its owner rebases the whole
  stack, or the root gives it to a PR owner as it would a `needs-rebase` label. Fetch, note each
  branch's remote tip (`git rev-parse origin/<branch>`), and rebase each branch onto the one below
  it, bottom-up from `main`. Then push every branch of the stack in one `git push --atomic
  --force-with-lease=<bottom>:<old-tip> --force-with-lease=<next>:<old-tip> ... origin <bottom>
  <next> ...`. Name each branch, because a bare `git push` pushes only the current one, and pin
  each lease to the noted tip, because a bare `--force-with-lease` trusts whatever a later fetch,
  perhaps from another worktree, put in `origin/<branch>`. `gh stack rebase` and then
  `gh stack push` do the same git work (the remote branches change only at the push), and their PR
  sync over GraphQL fails here without stopping them. The **Rebase stack** button does it on the
  server, but it is browser only: the REST API has no route that rebases a stack.
- Merge a stack bottom-up, one PR at a time. Each PR needs its own verdict and green `gate` at its
  head before its turn, as for any PR.
- An agent merges a stacked PR with the asynchronous endpoint, because the legacy `/merge` route
  cannot merge a stack: `gh api -X PUT repos/{owner}/{repo}/pulls/<pr>/merge-async
  -H "X-GitHub-Api-Version: 2026-03-10" -f merge_method=rebase -f merge_action=direct_merge
  -f sha=<head>`. `direct_merge` keeps a merge queue out of it. The answer is `202` for a new
  request, `409` when one is already pending (`gh` exits 1 but still prints the body), `200` when
  the PR has already merged or is already queued, or `400` (`failed`) when it cannot merge, such
  as a draft. `202` and `409` carry the request's id at `.details.uuid`. A `409` names the request
  already pending, so poll it only if its `.details.expected_head_sha`, `merge_method` and
  `merge_action` are the ones you sent; otherwise stop and report the mismatch. Poll `GET
  repos/{owner}/{repo}/pulls/<pr>/merge-async/<uuid>` until `.status` is no longer `pending`.
  `merged`, `failed` (reason at `.details.message`) and `enqueued` are final, and `enqueued` means
  only that a merge queue took it. Read the PR back for `merged` before calling it landed.
- Never merge a mid-stack PR to land the ones below it. Merging a stacked PR merges every open PR
  below it too, verdict or not. So a PR above one that waits for the user (a label or a merge) waits
  as well.

## Working rules

- A foreground Bash command times out at 600000 ms. Long waits use a bounded watcher
  (`timeout 540 bash -c 'until <check>; do sleep 60; done'`, re-issued), never one long command.
- Each agent names its scratch folders so that no other agent can pick the same name, for example
  with a prefix unique to that agent. Two verifiers once overwrote each other's folders.

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
  `models.lock`, `core/Mitos/Core.lean`, `core/Mitos/Core/`, `core/Challenge/` or
  `core/comparator.json`. Everything in `core/Mitos/Core/` is spec, even a change the lock does
  not show. Never add the label, and never route around it (moving statements out of the lock, editing the CI check).
- **Trust infrastructure.** `gate/`, `eval/cheats/`, `.github/`, the root `lean-toolchain` and
  `lakefile.toml`, and `core/lakefile.toml`, which sets what `lake check` builds. They decide
  what CI checks and what the gate trusts, so a PR touching them is trust-critical (see Verdicts).
- **Agent rules and plans.** `docs/process.md`, `CLAUDE.md`, `.claude/` and `plan/`.
- The user merges every PR that needs `spec-approved` or touches a path in the first three
  bullets above. Status updates to a task's own row in `plan/phase-N.md` are the exception. These
  PRs stop at verified and green, with a catch-up. This is the one list of paths the user keeps.
  Other files point here.
- `.github/CODEOWNERS` is wider on purpose. It also names all of `core/` and
  `examples/acme/Models/`, so GitHub shows the user those PRs. The spec inside them needs
  `spec-approved`, and agents merge the rest. `plan/` holds no trusted code, so
  CODEOWNERS leaves it out.
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
