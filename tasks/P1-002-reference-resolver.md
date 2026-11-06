# tasks/P1-002-reference-resolver.md

phase: 1
goal: A reference resolver that is proven sound, complete, unresolved-exact and total.
statement: Mitos.Proofs.resolve_sound, resolve_complete, resolve_unresolved_exact, resolve_total
  (stated in core/Challenge/Resolver.lean; the Prop definitions are in Mitos.Core.Spec.Resolve)
touches: core/Mitos/Impl/Resolve.lean, core/Mitos/Proofs/Resolve/*.lean
must_not_touch: statements.lock, core/Mitos/Core/, core/Challenge/, core/comparator.json, gate/, eval/cheats/
checks: build, imports, lock, core lake check, accept-toy, cheats
budget: 60 iterations · 4h wall · 3M tokens
escalation: hint → automation (grind, simp lemmas for List.filter / flatMap) → stronger model → pair → split → revisit statement

## Context
- Spec PR: P1-001.
- Shape that satisfies the spec (prototype checked on the adequacy examples): for each
  requirement `r`, its providers are `fs.filter (matchesB r)`; emit one edge per provider; list
  `r.id` as unresolved when there are none.
- Keep it list-based and structurally recursive. Performance work (HashMap indexes, proven
  equivalent) comes later.
- Put the theorems in `core/Mitos/Proofs/Resolve/*.lean`, not in `Mitos/Proofs/Resolver.lean`.
  That file is the comparator's solution module and must provide every name in
  `core/comparator.json` at once, so it is added by whichever of P1-002, P1-003 and P1-004
  merges last. CI judges the Challenge as soon as it exists.

## Done when
- [x] the four theorems are proven, statements exactly as in the Challenge
- [x] `cd core && lake check` passes (no `sorry`, standard axioms only)
- [x] run-log record written (ops/runs/)
