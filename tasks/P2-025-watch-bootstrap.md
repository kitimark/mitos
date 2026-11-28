# tasks/P2-025-watch-bootstrap.md

phase: 2 (Watch track, #502; milestone 6)
goal: Main's `mitos-gate` runs in a provider's cloud container, where the root and every other agent run, fetched and verified offline at session start without `lake`; a fetched tool is installed only when it is provably main's own build at the commit the shim resolved, and `build --fetch` names each host assumption that fails.
statement: none (tooling task)
touches: the attested release asset (question 3a): a `main`-push job in .github/workflows/ that builds `mitos-gate`, attests it and uploads it as a release asset; the pinned trusted root .github/attest/trusted_root.jsonl; `watch.sh build --fetch` in .claude/scripts/watch.sh, which verifies the asset offline, installs it into the private `bin/` and runs the host checks, with its cases in .claude/scripts/watch.test.sh; .claude/scripts/gh-api-rest.test.sh (`EXPECTED` gains `watch.sh`'s `gh attestation` and `gh release` lines); the docs/process.md row that says `gh` runs only as `gh api`; tasks/P2-025-watch-bootstrap.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, `.github/` beyond the release workflow and the pinned trusted root, and every other path outside `touches`
checks: row 11's admission rule, verified offline against the pinned trusted root, and its host checks (one `watch: host:` line per failed row, each row made to fail once in `watch.test.sh`), shown by a real run on Claude Code cloud, where GraphQL is blocked: `watch.sh build --fetch` at session start, then `watch.sh wait --max 0` prints a line; a tampered asset, an asset of an older commit, a bundle from another ref or another workflow, and a trusted-root file that does not hold the asset's signer are refused; `bash .claude/scripts/gh-api-rest.test.sh`; `bash .claude/scripts/watch.test.sh`; the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-025 in `plan/phase-2.md` (Watch track), issue [#574](https://github.com/kitimark/mitos/issues/574). It is PR 11 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: PR 0b, which carries question 13 (how the asset is verified), and P2-023 ([#572](https://github.com/kitimark/mitos/issues/572)). Question 3a is answered: the attested release asset.
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: a provider's cloud container is the baseline host, the tool is fetched and verified offline at session start, `build --fetch` runs the host checks, and the row is not done before one real run on Claude cloud.
- Role: PR owner, hard (`opus`, `xhigh`). On the recommended route it touches `.github/`, so it is trust-critical: an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 11's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. Row 11 of `tasks/502-watch/PR-SEQUENCE.md` fixes the admission rule and the host checks, and `tasks/502-watch/DESIGN.md` (Cloud host profile) fixes each row and its check; there is no sketch of the workflow.
revisit_when: re-check after P2-023 (#572) merges and after the owner answers question 13 on PR 0b; re-check the pinned trusted root at each GitHub key rotation.
modules: a release workflow under `.github/workflows/`, the pinned trusted root, and `watch.sh build --fetch` with the host checks (`tasks/502-watch.md`, modules: the `.claude/scripts/watch.sh` row)
types: none
statements: none (tooling task)
reuse: `.claude/scripts/lib/main-tool.sh` (`tasks/502-watch.md`, reuse)
fixtures: a tampered asset, an asset of an older commit, a bundle from another ref, a bundle from another workflow and a trusted-root file that does not hold the asset's signer, all refused; each host row made to fail once, and the time, slug and wake rows printed `unchecked`
cut_line: row 11 of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: question 3a (answered: the attested release asset) and question 13 (offline against the pinned file, open on PR 0b); defaults 3b and 3c (with its Codex clause)

## Done when
- [ ] row 11's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
