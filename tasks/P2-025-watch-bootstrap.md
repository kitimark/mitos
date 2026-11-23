# tasks/P2-025-watch-bootstrap.md

phase: 2 (Watch track, #502; milestone 6)
goal: Main's `mitos-gate` runs where the root runs, built or fetched without `lake` there, and a fetched tool is installed only when it is provably main's own build at the commit the shim resolved.
statement: none (tooling task)
touches: the owner's choice (question 3a). Recommended: a `main`-push job in .github/workflows/ that builds `mitos-gate`, attests it and uploads it as a release asset; `watch.sh build --fetch`, which verifies the attestation and installs it into the private `bin/`; .claude/scripts/gh-api-rest.test.sh (`EXPECTED` gains `watch.sh`'s `gh attestation` and `gh release` lines); the docs/process.md row that says `gh` runs only as `gh api`; tasks/P2-025-watch-bootstrap.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, `.github/` beyond the route question 3a picks, and every other path outside `touches`
checks: row 11's admission rule, shown by a real run in the root's environment, where GraphQL is blocked: `watch.sh build --fetch`, then `watch.sh wait --max 0` prints a line; a tampered asset and an asset of an older commit are refused; `bash .claude/scripts/gh-api-rest.test.sh`; the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-025 in `plan/phase-2.md` (Watch track), issue [#574](https://github.com/kitimark/mitos/issues/574). It is PR 11 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: owner question 3a and P2-023 ([#572](https://github.com/kitimark/mitos/issues/572)).
- Role: PR owner, hard (`opus`, `xhigh`). On the recommended route it touches `.github/`, so it is trust-critical: an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 11's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. The admission rule is fixed in row 11 of `tasks/502-watch/PR-SEQUENCE.md`; the route and its files wait for question 3a.
revisit_when: re-check after P2-023 (#572) merges and the owner answers question 3a.
modules: the route question 3a picks; on the recommended one, a release workflow and `watch.sh build --fetch`
types: none
statements: none (tooling task)
reuse: `.claude/scripts/lib/main-tool.sh` (`tasks/502-watch.md`, reuse)
fixtures: a tampered asset and an asset of an older commit, both refused
cut_line: row 11 of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: question 3a; defaults 3b and 3c

## Done when
- [ ] row 11's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
