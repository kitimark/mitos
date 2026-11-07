# tasks/P1-003-assumptions-status-retract.md

phase: 1
goal: The reference resolver tracks assumptions exactly, reports status honestly, and retracts exactly.
statement: Mitos.Proofs.resolve_assumptions_exact, resolve_status_honest, resolve_retract_exact
  (stated in core/Challenge/Resolver.lean; the Prop definitions are in Mitos.Core.Spec.Resolve)
touches: core/Mitos/Impl/Resolve.lean, core/Mitos/Proofs/Resolve/*.lean
must_not_touch: statements.lock, core/Mitos/Core/, core/Challenge/, core/comparator.json, gate/, eval/cheats/
checks: build, imports, lock, core lake check, core lake comparator
budget: 60 iterations · 4h wall · 3M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Follows P1-002 (same implementation file).
- `AssumptionsExact` and `StatusHonest` quantify over any fact with the edge's ids, so they need
  `WellFormed` (ids unique) to identify that fact with the one the edge was built from.
- `RetractExact` compares edges by key, so it holds even though statuses change after retraction
  (fewer providers can turn an `inferred` edge `confirmed`).

## Done when
- [x] the three theorems are proven, statements exactly as in the Challenge
- [x] `cd core && lake check` passes
- [x] run-log record written (ops/runs/)
