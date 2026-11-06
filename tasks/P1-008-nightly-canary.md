# tasks/P1-008-nightly-canary.md

phase: 1
goal: A scheduled workflow runs the full checks every night and tries the next Lean toolchain as an early warning.
statement: none (tooling task)
touches: .github/workflows/nightly.yml, .github/actions/setup/action.yml, docs/process.md, plan/phase-1.md
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, .github/workflows/ci.yml
checks: yaml parses, actionlint, release resolution against the GitHub API, one manual workflow_dispatch run
budget: 10 iterations · 1h wall · 300k tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Phase 1 exit criterion 5: the nightly job runs the full checks and a next-toolchain canary.
- `docs/process.md`: L3 nightly loop, check matrix, tripwire "The next-toolchain canary fails".
- `ci.yml` is edited by other open PRs, so setup is duplicated into a composite action
  (`.github/actions/setup`) used only by `nightly.yml`.
- Follow-up: switch `ci.yml` to the composite action once the other `ci.yml` PRs have merged.
- Not in this task: scorecard, theorem mutation, differential tests (P1-006, P1-007, Phase 2).

## Done when
- [ ] a manual `workflow_dispatch` run of `nightly` is green on `main` (`full` and `canary`)
- [ ] the canary job summary lists the versions tried and the outcome
- [ ] run-log record written (ops/runs/)
