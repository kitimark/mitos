# tasks/P2-026-watch-canary-ab.md

phase: 2 (Watch track, #502; milestone 6)
goal: Measured numbers decide the switch: tokens per idle 2 hours and wake latency for the bash watcher (arm A) and `watch.sh wait` (arm B), a one-day canary that runs both watchers in one real session, and the idle cost of a standing topic agent.
statement: none (measurement only)
touches: ops/runs/ records and a public summary in the PR, tasks/P2-026-watch-canary-ab.md
must_not_touch: everything outside `ops/runs/` and this task file
checks: at least 3 runs per arm in an idle session in a cloud container, arm B with `watch.sh wait --max 27` under Monitor; the counters of row 12, the idle-cost counter among them; every bash line of the canary matched or in `watch-diff.intended`; the report states run counts, spread, and whether the A/B pass condition holds (arm B's tokens per idle 2 hours not above arm A's, its largest wake latency at most 3 minutes); the run-log check
budget: its own A/B budget (owner question 2c, answered yes): at most about 11M tokens for the arms and about 8M for the canary day (`tasks/502-watch/DESIGN.md`, Alternatives); the idle-cost subagent adds about 0.2M (four hours at the repository's one measured rate, about 70k tokens over 99 minutes)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-026 in `plan/phase-2.md` (Watch track), issue [#575](https://github.com/kitimark/mitos/issues/575). It is PR 12 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-025 ([#574](https://github.com/kitimark/mitos/issues/574)). The owner answered questions 2b (a provider's cloud container is the baseline host) and 2c (the spend, and they start the arm sessions) on 27 November.
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: arm B runs `--max 27`, and the row adds the idle-cost counter, requests per hour for one container, the longest run past a deadline, and whether a VM paused during a wait.
- Role: each arm is a session of its own, which the owner starts (or the root, through a session-launch tool where its harness has one); a routine PR owner opens the scratch draft PR and makes each toggle; the root runs the canary beside its own monitor and spawns the idle-cost subagent; a routine PR owner opens the records PR.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 12's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. The method is fixed in row 12 of `tasks/502-watch/PR-SEQUENCE.md`; there is no sketch.
revisit_when: re-check after P2-025 (#574) merges.
modules: none (records only)
types: none
statements: none (measurement only)
reuse: `.claude/scripts/usage-sum.sh` for the token sums (#223)
fixtures: a label toggle on a scratch draft PR at minutes 90 to 110 of each arm; four hours of one idle topic subagent in the canary session
cut_line: row 12 of `tasks/502-watch/PR-SEQUENCE.md`; on a failed A/B the bash watcher stays and the design goes back to the architect with the numbers
deferrals: from `tasks/502-watch.md` (deferrals): conditional requests (ETag) follow this row's count of requests per container and go ahead of any other REST work, since a 304 answer does not count against the limit; a larger overlap follows only if its count of late facts calls for it
owner_decisions: questions 2b and 2c (answered) and question 12 (standing topic agents wait for this row's idle-cost counter, open on PR 0b); defaults 2a and 14 (at most three containers wait at once until this row reports, fewer above five open owned heads; raising it waits for this row's request counter and conditional requests)

## Done when
- [ ] row 12's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
