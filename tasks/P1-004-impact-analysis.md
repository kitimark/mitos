# tasks/P1-004-impact-analysis.md

phase: 1
goal: Impact analysis returns exactly the repos that depend on a changed repo.
statement: Mitos.Proofs.impact_correct  (Mitos.Spec.ImpactCorrect Mitos.Impl.impact)
touches: core/Mitos/Impl/Impact.lean, core/Mitos/Proofs/Impact.lean
must_not_touch: statements.lock, core/Mitos/Core/, core/Challenge/, core/comparator.json, gate/, eval/cheats/
checks: build, imports, lock, core lake check
budget: 60 iterations · 4h wall · 3M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- `Affects es x y` (Mitos.Core.Graph): `y` requires, directly or transitively, something `x`
  provides. Note `x` itself is in the result only if there is a cycle back to it.
- Suggested algorithm: worklist reverse reachability with a visited list. Termination: the
  number of distinct repo names in `es` not yet visited. Invariant: everything visited is
  reachable; at the end the visited set is closed under reverse edges.

- If this is the last of P1-002, P1-003 and P1-004 to merge, also add
  `core/Mitos/Proofs/Resolver.lean`, which re-exports all eight theorems under the Challenge's
  names, and confirm `cd core && lake comparator` accepts.

## Done when
- [x] `impact_correct` proven, statement exactly as in the Challenge
- [x] `cd core && lake check` passes
- [x] run-log record written (ops/runs/)
