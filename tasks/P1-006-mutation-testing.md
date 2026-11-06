# tasks/P1-006-mutation-testing.md

phase: 1
goal: Each plausible bug in the resolver or impact analysis is refuted by at least one Challenge theorem, in CI.
statement: none (tooling task)
touches: eval/mutants/, .github/workflows/ci.yml, docs/process.md, plan/phase-1.md, ops/runs/
must_not_touch: statements.lock, core/Mitos/Core/, core/Challenge/, core/comparator.json, gate/, eval/cheats/
checks: build, imports, lock, core lake check, mutants
budget: 40 iterations · 3h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Phase 1 exit criterion 3 (`plan/phase-1.md`).
- A mutant is caught when `lake comparator` accepts a proof that the named theorem is false for
  it. A failing proof build would also flag a correct refactor, so it is not used.
- Twelve mutants cover all eight theorems. `RetractExact` follows from `Sound`, `Complete` and
  `AssumptionsExact` for the one-rule resolver, and `Total` from `Complete` and
  `UnresolvedExact`, so no mutant breaks either of them alone.
- `decide` over `String` equality builds in Lean but can be rejected when the comparator replays
  the export. The two status refutations use `simp` for that reason.

## Done when
- [x] `eval/mutants/run.sh` refutes every mutant, and fails on an equivalent, `sorry`, unbuildable
      or mislabelled mutant
- [x] CI runs it after the core comparator step
- [x] all `checks` pass locally
- [x] run-log record written (ops/runs/)
