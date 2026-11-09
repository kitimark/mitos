# tasks/ci-concurrency.md

phase: 1
goal: A PR's `ci` runs on superseded heads are cancelled, and no run can cancel a run at the PR's current head.
statement: none (tooling task)
touches: .github/workflows/ci.yml, .claude/skills/kitimark-mode/SKILL.md (PR owner step 4), tasks/ci-concurrency.md, ops/runs/2026-11-09.ndjson (appended lines only)
must_not_touch: statements.lock, models.lock, core/, gate/, eval/cheats/, models
checks: actionlint (with shellcheck), the canceller step against a stub `gh`, a dry run of the step against the real API, a probe PR with a sleep-only copy of the workflow, `gate` on the PR
budget: 10 iterations · 3h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Attempt 1 (#90) put the runs of a PR's heads in one concurrency group, `ci-<PR>`, with
  `cancel-in-progress`. GitHub orders a group by arrival, not by head. So a re-run or a
  late-created run of an old head cancelled the current head's run: reproduced on #96, and a
  near case on #84 at 09:45 UTC (CodeRabbit thread 4511569391 on #90).
- Attempt 2 is #97 items 1, 2, 6 and 7.
- Attempt 3 is round 2 of #105. Its opus verifier found that the canceller listed the runs of the
  branch but read the head of the event's PR. A closed or merged PR keeps its old head, so a late
  run or a re-run of a closed PR cancelled the current-head runs of an open PR that reuses its
  branch. Branches were reused in 3 of 59 PRs (#1 and #2, #88 and #89, #92 and #94).

## Decisions
- **Cancel by head, not by arrival.** The `cancel-superseded` job lists the unfinished
  `pull_request` runs of the PR's branch, reads the PR's state and head over REST
  (`GET pulls/<n>`), and for an open PR cancels each run whose head differs, its own run last. A
  run at that head is never cancelled, so two runs at the current head (a label run and a sync
  run) both finish. The workflow has no concurrency group, so a push to `main` is never cancelled
  either.
- **A closed or merged PR's run judges only itself.** Its PR keeps the head it had at close, and
  its branch may carry a new PR, whose runs the listing also returns. So the job reads the state
  with the head in one read, and when the agreed state is not `open` it cancels only its own run.
  It does not even do that when an open PR from the branch
  (`GET pulls?state=open&head=<owner>:<branch>`) is at its head: its cancelled `gate` would sit on
  that PR's head beside the PR's own. That happened here: #94 opened from #92's branch at #92's
  head dfb326b. This also stops a run created after its PR closed from running to the end (#104).
- **The runs API cannot tell which PR a run belongs to.** A run's `pull_requests` field holds the
  open PRs from the run's branch as they are when the run is read, with their current heads. On
  #105 the run at the old head 9d83f04 lists #105 at b83cf72; every run of the closed #88, #89 and
  #102 lists none. So it cannot keep the cancel set to this PR's runs. For an
  open PR that is not needed: another open PR from the branch has the same head, and a closed
  PR's run on the branch is useless.
- **Read the head from REST, not from the event.** A re-run keeps its old event, so only a REST
  read tells a re-run of an old head that it is stale. That run then cancels itself.
- **List first, read twice.** Every listed run already existed when the head was read. The job
  acts only when two reads 10 s apart agree, so a read that lags behind a push for less than 10 s
  cancels nothing. A head that keeps moving for three reads cancels nothing.
- **Beside `gate`, not before it.** `gate` does not `need` the job. With `needs` and no `if`, a
  canceller failure would skip `gate`, and a skipped required check counts as passed. With
  `if: ${{ !cancelled() }}` it would run, but it would also wait for the canceller's runner. A
  failure (an API error, a refused cancel) fails only the `cancel-superseded` check, which is not
  required.
- **Forks skip the job.** A fork's token cannot cancel runs, so the job would always fail. A
  fork's old runs finish, which costs runner time only.
- **Label runs.** A label run at the current head is never cancelled, so a late `labeled` run
  cannot cancel the `unlabeled` run that checks a `spec-approved` removal. A label run at a
  superseded head is cancelled like any other run there (item 6): only the latest head can merge.
- **Inline step, no checkout.** The job that holds `actions: write` reads no file of the PR.
- **Permissions (item 7).** `permissions: {}` for the workflow. `cancel-superseded` gets
  `actions: write` and `pull-requests: read`, `gate` gets `contents: read`, and
  `scorecard-comment` keeps `pull-requests: write`.
- **A PR can edit the canceller.** A `pull_request` run uses the PR's own `ci.yml`, so a PR could
  change which runs its canceller cancels. That is no worse than editing `gate`, which the PR
  can make pass. A fork's token is read-only, so a fork can cancel nothing.
- **Cancelled `gate` at the current head (item 2).** The job removes the race, but a person,
  GitHub, or a REST read that stays stale for 10 s can still cancel it. So the PR owner's step 4 in
  the kitimark-mode skill gives the rule: unless the log shows a timeout, re-run the head's latest
  run and only that one. A re-run keeps its event's labels, so when `spec-approved` changed after
  that run started, the owner pushes or the user re-labels instead.

## Rejected
- **Keep the group and add only the re-run rule.** The race stays, and a late-created run of an
  old head is not a re-run anyone chose.
- **A group per head (`ci-<PR>-<sha>`).** It never cancels an old head.
- **A `workflow_run` or `pull_request_target` canceller.** Either runs the default branch's file,
  so a PR could not edit it, and forks would get a write token. But a `workflow_run` workflow
  fires only from the file on `main`, so no PR can test it before it lands, and it doubles the
  number of runs. A `pull_request_target` run does not see a re-run or a late-created `ci` run,
  the cases this task is about. zizmor flags both triggers as dangerous.
- **The cancel as a step in `gate`.** Then the job that runs the PR's code would hold
  `actions: write`.

## Done when
- [x] actionlint passes
- [x] the step passes 11 cases against a stub `gh`, and a dry run against PR #84 over REST
- [x] probe PR #102 (sleep-only `gate`): a push cancels the old head's run; a re-run of an old
      head cancels only itself; a label change at the current head cancels nothing; a canceller
      whose token cannot cancel fails with 403 and leaves `gate` running to success
- [ ] `gate` is green on the PR
- [x] run-log record written (ops/runs/)
- [x] attempt 3: the step passes 17 stub cases, the 11 above and 6 for closed and merged PRs; the
      step of attempt 2 fails 5 of the 6
- [x] attempt 3: probe PRs #110 and #111 from one branch (sleep-only `gate`): a re-run of the
      closed #110's run 42620356965 cancelled only itself, and #111's run 42620508277 at its
      current head ran on to success; a dry run of the step over REST, with cancels printed and not
      sent, took both closed-PR paths (cancel itself; go on when an open PR is at its head)
