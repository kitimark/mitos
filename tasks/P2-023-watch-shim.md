# tasks/P2-023-watch-shim.md

phase: 2 (Watch track, #502; milestone 6)
goal: `.claude/scripts/watch.sh` finds the clone, the repository, the owner and main's tool, and runs a private copy of the tool for every caller, so all the logic stays in `mitos-gate`.
statement: none (tooling task)
touches: .claude/scripts/watch.sh, .claude/scripts/watch.test.sh, .claude/scripts/gh-api-rest.test.sh (`NAMED` and `EXPECTED`), .claude/scripts/sourced-bash.test.sh (`watch.sh` joins its `shellcheck -x` list), .claude/scripts/main-tool.test.sh, tasks/P2-023-watch-shim.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, .github/, and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: `bash .claude/scripts/watch.test.sh` and `bash .claude/scripts/main-tool.test.sh` with row 9's cases (the topic flags reach the tool unchanged, `status` runs with no `--as`, and `wait --ride words` prints one stdout `watch: usage:` line and exits 2), `shellcheck -x .claude/scripts/watch.sh`, `bash .claude/scripts/sourced-bash.test.sh`, `bash .claude/scripts/gh-api-rest.test.sh`; `watch-github.test.sh` and `pr-state.test.sh` unchanged; the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-023 in `plan/phase-2.md` (Watch track), issue [#572](https://github.com/kitimark/mitos/issues/572). It is PR 9 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-022 ([#571](https://github.com/kitimark/mitos/issues/571)).
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: the shim's usage names `--topics`, `--on` (in place of `--pr`) and `--ride`, and `status` takes `--as` as an option.
- Role: PR owner, routine (`sonnet`, `high`). It touches `.claude/`, so the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 9's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. The design is row 9 of `tasks/502-watch/PR-SEQUENCE.md`; `tasks/502-watch/sketch/.claude/scripts/watch.sh` is an unchecked sketch of the shim.
revisit_when: re-check after P2-022 (#571) merges.
modules: the `.claude/scripts/watch.sh` row of `tasks/502-watch.md` (modules)
types: the commands in `tasks/502-watch/DESIGN.md` (Usage)
statements: none (tooling task)
reuse: `.claude/scripts/lib/main-tool.sh` and `lib/origin-repo.sh` (`tasks/502-watch.md`, reuse)
fixtures: row 9's `watch.test.sh` and `main-tool.test.sh` cases
cut_line: row 9 of `tasks/502-watch/PR-SEQUENCE.md`; `build --fetch` and the host checks wait for P2-025
deferrals: from `tasks/502-watch.md` (deferrals): one owner default shared by `watch.sh`, `watch-github.sh` and `pr-state.sh` is a follow-up issue, not part of this row
owner_decisions: default 3c (an outside agent gets the tool through `watch.sh build --fetch`, and one that can read GitHub but cannot get the tool keeps a bounded `gh` loop; under Codex's defaults the agent phase reads nothing on GitHub, so a Codex task does not wait until it has agent-phase GET and a read-only token)

### reshape
Inputs for this row, from the `/no-comments` pass over the sketch at 588dc1a (`tasks/502-watch/REVIEW-LOG.md`, Amendment 1). The row's PR owner settles each one. None is fixed in the sketch.
- reshape (no-comments): `owner_login=${MITOS_OWNER:-kitimark}` (`watch.sh`): the pass flagged the shared owner default that `deferrals` above already leaves to a follow-up issue (`.claude/hooks/pr-state.sh` and `.claude/scripts/watch-github.sh` hold the same default). Nothing is added here.
- reshape (no-comments): the private-copy block of `watch.sh` (`private=$state/bin/mitos-gate` to `exec {MAIN_TOOL_FD}>&-`): it copies main's tool under `main-tool.sh`'s shared lock and closes that lock before the exec. Extract it into a named function in `lib/main-tool.sh`, which `touches` does not list yet.

## Done when
- [ ] row 9's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
