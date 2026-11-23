# tasks/P2-014-watch-pr-state.md

phase: 2 (Watch track, #502; milestone 6)
goal: `pr-state.sh` takes its unanswered column from main's `mitos-gate watch unanswered` and shows `?` whenever it cannot decide, so the hook and the waiter share one classifier.
statement: none (tooling task)
touches: .claude/hooks/pr-state.sh, .claude/hooks/pr-state.test.sh, tasks/P2-014-watch-pr-state.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, .github/, and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: `bash .claude/hooks/pr-state.test.sh` with row 3's cases (the old fixtures re-authored with `performed_via_github_app` give the same lines; an item without the key, a missing tool and a page that is not UTF-8 each give `?`; the footer-text class has a case), `bash .claude/scripts/gh-api-rest.test.sh`, `bash .claude/scripts/sourced-bash.test.sh`, `shellcheck -x .claude/hooks/pr-state.sh`, the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-014 in `plan/phase-2.md` (Watch track), issue [#563](https://github.com/kitimark/mitos/issues/563). It is PR 3 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-013 ([#562](https://github.com/kitimark/mitos/issues/562)), P2-025 ([#574](https://github.com/kitimark/mitos/issues/574)) and PR 3a, the #501 stopgap in pr-state ([#501](https://github.com/kitimark/mitos/issues/501)).
- Role: PR owner, routine (`sonnet`, `high`). It touches `.claude/`, so the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 3's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. The design is row 3 of `tasks/502-watch/PR-SEQUENCE.md`; `tasks/502-watch/sketch/.claude/hooks/pr-state-unanswered.sh` is an unchecked fragment of the two replaced classifiers.
revisit_when: re-check after P2-013 (#562) and P2-025 (#574) merge.
modules: `.claude/hooks/pr-state.sh`: its two jq classifiers (`full_thread_unanswered` and `owner_unanswered_by_thread`) give way to `mitos-gate watch unanswered` (`tasks/502-watch.md`, modules, last paragraph)
types: the `unanswered` signature in `tasks/502-watch.md` (types): `{"<pr>":[<id>...]}` on stdout, exit 1 on any refusal
statements: none here; it relies on the Voice statements that P2-013 proves
reuse: the hook's own main-tool lookup (`main_tool ready`, `tool_bin`), as the sketch fragment shows
fixtures: row 3's `pr-state.test.sh` cases
cut_line: row 3 of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: one owner default shared by `watch.sh`, `watch-github.sh` and `pr-state.sh` stays a follow-up (`tasks/502-watch.md`, deferrals)
owner_decisions: question 8a, default 3b (pr-state uses main's tool once P2-025 lands)

## Done when
- [ ] row 3's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
