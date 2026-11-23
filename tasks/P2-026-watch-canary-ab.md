# tasks/P2-026-watch-canary-ab.md

phase: 2 (Watch track, #502; milestone 6)
goal: Measured numbers decide the switch: tokens per idle 2 hours and wake latency for the bash watcher (arm A) and `watch.sh wait` (arm B), and a one-day canary that runs both watchers in one real session.
statement: none (measurement only)
touches: ops/runs/ records and a public summary in the PR, tasks/P2-026-watch-canary-ab.md
must_not_touch: everything outside `ops/runs/` and this task file
checks: at least 3 runs per arm in an idle session; the counters of row 12; every bash line of the canary matched or in `watch-diff.intended`; the report states run counts, spread, and whether the A/B pass condition holds (arm B's tokens per idle 2 hours not above arm A's, its largest wake latency at most 3 minutes); the run-log check
budget: its own A/B budget (owner question 2c): at most about 11M tokens for the arms and about 8M for the canary day (`tasks/502-watch/DESIGN.md`, Alternatives)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-026 in `plan/phase-2.md` (Watch track), issue [#575](https://github.com/kitimark/mitos/issues/575). It is PR 12 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: owner questions 2b and 2c, and P2-025 ([#574](https://github.com/kitimark/mitos/issues/574)).
- Role: each arm is a session of its own, which the owner starts (or the root, through a session-launch tool where its harness has one); a routine PR owner opens the scratch draft PR and makes each toggle; the root runs the canary beside its own monitor; a routine PR owner opens the records PR.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 12's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. The method is fixed in row 12 of `tasks/502-watch/PR-SEQUENCE.md`; there is no sketch.
revisit_when: re-check after P2-025 (#574) merges and the owner answers questions 2b and 2c.
modules: none (records only)
types: none
statements: none (measurement only)
reuse: `.claude/scripts/usage-sum.sh` for the token sums (#223)
fixtures: a label toggle on a scratch draft PR at minutes 90 to 110 of each arm
cut_line: row 12 of `tasks/502-watch/PR-SEQUENCE.md`; on a failed A/B the bash watcher stays and the design goes back to the architect with the numbers
deferrals: from `tasks/502-watch.md` (deferrals): conditional requests (ETag) follow this row's REST count, and a larger overlap follows only if its count of late facts calls for it
owner_decisions: questions 2b and 2c; default 2a

## Done when
- [ ] row 12's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
