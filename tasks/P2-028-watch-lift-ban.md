# tasks/P2-028-watch-lift-ban.md

phase: 2 (Watch track, #502; milestone 6)
goal: Optional: the background-shell ban is lifted only if P2-026's numbers show the remaining re-arm cost is worth it and the owner says yes.
statement: none (rules change)
touches: the Watchers text and .agents/scripts/agents-roster.tsv (the `kitimark-mode` stamp) (row 14's Files column), tasks/P2-028-watch-lift-ban.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, .github/, and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: only if P2-026 shows the remaining re-arm cost is worth it and the owner says yes; then the checks of a rules change (`agents-skills.py stamp` then `check`, because the Watchers text of `kitimark-mode` changes) and the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-028 in `plan/phase-2.md` (Watch track), issue [#577](https://github.com/kitimark/mitos/issues/577). It is PR 14 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: the condition of owner question 2a, P2-026's numbers ([#575](https://github.com/kitimark/mitos/issues/575)) and a second yes from the owner.
- Role: PR owner, hard (`opus`, `xhigh`). It touches `.claude/`, so the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 14's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. Row 14 of `tasks/502-watch/PR-SEQUENCE.md`; whether it runs at all waits for P2-026's numbers.
revisit_when: re-check after P2-026 (#575) merges with its numbers.
modules: the Watchers text
types: none
statements: none (rules change)
reuse: the token arithmetic in `tasks/502-watch/DESIGN.md` (Alternatives)
fixtures: none
cut_line: row 14 of `tasks/502-watch/PR-SEQUENCE.md`; the row ships only on the owner's yes
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: question 2a's condition (default 2a keeps the ban) and the owner's second yes

## Done when
- [ ] row 14's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
