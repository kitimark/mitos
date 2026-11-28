# tasks/P2-024-watch-diff-replay.md

phase: 2 (Watch track, #502; milestone 6)
goal: Before anything is deleted, every bash-watcher fixture, re-authored with the app key as the live API gives it, replays through both watchers, and each difference is listed with its reason.
statement: none (tooling task)
touches: .claude/scripts/watch-diff.test.sh, .claude/scripts/watch-diff.intended, tasks/P2-024-watch-diff-replay.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, .github/, and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: `bash .claude/scripts/watch-diff.test.sh`: every difference between the two watchers is in `watch-diff.intended` with its reason, the Claude-app issue comment that the root's catch-all hears as `peers` among them, and the Lean side replays as the root's catch-all; `shellcheck -x` on the new script; the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-024 in `plan/phase-2.md` (Watch track), issue [#573](https://github.com/kitimark/mitos/issues/573). It is PR 10 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-023 ([#572](https://github.com/kitimark/mitos/issues/572)).
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: two more listed differences (a Claude-app issue comment is `peers`, which the root's catch-all does not hear, and outside lines ride when no `--ride` is given), and the Lean side replays as `--as claude/root` with no topic flags.
- Role: PR owner, routine (`sonnet`, `high`). It touches `.claude/`, so the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 10's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. The design is row 10 of `tasks/502-watch/PR-SEQUENCE.md`, which lists the expected classes of difference; there is no sketch.
revisit_when: re-check after P2-023 (#572) merges.
modules: `.claude/scripts/watch-diff.test.sh` (the replay through both watchers) and `.claude/scripts/watch-diff.intended` (the listed differences)
types: none
statements: none (tooling task)
reuse: the fixtures and fake `gh` of `.claude/scripts/watch-github.test.sh`
fixtures: every `watch-github.test.sh` fixture, re-authored with the app key
cut_line: row 10 of `tasks/502-watch/PR-SEQUENCE.md`
retirement: P2-029 (PR 15) removes `watch-diff.test.sh` and `watch-diff.intended` together with the bash watcher, because they replay through `watch-github.sh` and have no other subject; the owner's Q9 sign-off covers it
deferrals: from `tasks/502-watch.md` (deferrals): the bash watcher's first-poll scan is not carried over, and `watch-diff.intended` lists that difference
owner_decisions: default 6 (outside-account lines ride along, a listed difference) and question 11 (`peers` off by default, a listed difference)

## Done when
- [ ] row 10's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
