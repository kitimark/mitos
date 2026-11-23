# tasks/P2-029-watch-delete-bash.md

phase: 2 (Watch track, #502; milestone 6)
goal: The bash watcher is gone: `watch-github.sh`, its test suite, `watch-own.sh` and the replay files `watch-diff.test.sh` and `watch-diff.intended` (P2-024's, whose only subject is `watch-github.sh`) are removed, and no file outside `tasks/`, `ops/runs/`, `plan/` (its rows are history) and one `ci.yml` step name names a removed script.
statement: none (tooling task)
touches: remove .claude/scripts/watch-github.sh, .claude/scripts/watch-github.test.sh, .claude/scripts/watch-own.sh, .claude/scripts/watch-diff.test.sh and .claude/scripts/watch-diff.intended (the replay files retire with the bash watcher, under Q9); .claude/scripts/gh-api-rest.test.sh (their `NAMED` and `EXPECTED` lines); .claude/scripts/sourced-bash.test.sh (`watch-github.sh` leaves its `shellcheck -x` list); the fallback paragraph P2-027 kept, in both `kitimark-mode` copies, with the roster stamps; docs/process.md (the gh-only row's text); tasks/P2-029-watch-delete-bash.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, .github/, and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: the gates in `tasks/502-watch/PR-SEQUENCE.md` (Gates before PR 15) and the owner's sign-off first; then `bash .claude/scripts/gh-api-rest.test.sh`, `bash .claude/scripts/sourced-bash.test.sh`, `python3 .agents/scripts/agents-skills.py check`, and a grep that shows no file outside `tasks/`, `ops/runs/`, `plan/` (its rows are history, and only PR 0 edits `plan/`) and that `ci.yml` step name naming a removed script, and that `watch-diff.test.sh` and `watch-diff.intended` are gone; the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-029 in `plan/phase-2.md` (Watch track), issue [#578](https://github.com/kitimark/mitos/issues/578). It is PR 15 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: the Gates before PR 15 (P2-024 green, P2-025 merged and proven by a real run where the root runs, P2-026's canary and A/B reported and passing, P2-027 merged and used for a week with each fallback recorded on the Owner dashboard) and a yes to owner question 9.
- Role: PR owner, hard (`opus`, `xhigh`). It removes a test suite, which is the owner's call, and it touches `.claude/` and `docs/process.md`, so the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 15's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. Row 15 and the Gates before PR 15 of `tasks/502-watch/PR-SEQUENCE.md` fix what is removed and what must hold first.
revisit_when: re-check after P2-027 (#576) merges and its week of use is recorded.
modules: none added; the removals in `touches`
types: none
statements: none (tooling task)
reuse: none
fixtures: none; the grep in `checks`
cut_line: row 15 of `tasks/502-watch/PR-SEQUENCE.md`; the `ci.yml` step name that names `watch-github.sh` is under `.github/`, so it stays stale here, and the root files a follow-up for a one-line rename the owner merges
deferrals: the `ci.yml` step rename moves from this row to a follow-up issue the root files
owner_decisions: question 9 (no keeps the bash watcher as the fallback and drops this row)

## Done when
- [ ] row 15's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
