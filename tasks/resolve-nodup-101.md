# tasks/resolve-nodup-101.md

phase: 1
goal: The reference resolver lists each assumption, unresolved id, edge key and edge once.
statement: Mitos.Proofs.assumptionsOf_nodup, resolve_assumes_nodup, resolve_unresolved_nodup, resolve_keys_nodup, resolve_edges_nodup
touches: core/Mitos/Proofs/Resolve/Nodup.lean, tasks/resolve-nodup-101.md, ops/runs/*.ndjson
must_not_touch: statements.lock, models.lock, core/Mitos/Proofs/Resolver.lean, core/Mitos/Proofs/Resolve/Basic.lean, core/Mitos/Proofs/Resolve/Edges.lean, core/Mitos/Proofs/Resolve/Assumptions.lean, core/Mitos/Impl/, core/Mitos/Core/, core/Challenge/, core/comparator.json, gate/, eval/, .github/, lean-toolchain, lakefiles, .claude/, docs/, plan/
checks: build, imports, lock, core lake build, core lake check, core lake comparator --paranoid, runlog
budget: 8 iterations · 2h wall · tokens not metered
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- #101: the approved spec checks that each item appears in a resolver output, not that it appears once.
- Pilot task A on #100 (`resolve-nodup-101`). Prove the five `Nodup` facts of the real `resolve` now, so a later spec PR can reuse them. `WellFormed` (distinct fact ids) is the hypothesis. `fs.Nodup` is not enough: two facts with the same id that differ only in `path` give equal edges and `unresolved = [1, 1]`.
- The brief sets no iteration budget. The line above is only a cap for this small proof.

## Decisions
- **New module, not a change to `Resolver.lean`.** `Mitos.Proofs.Resolver` is the comparator solution. The existing `Mitos.Proofs.+` glob already builds `Mitos.Proofs.Resolve.Nodup`, so the theorems are checked without an import-root edit.
- **`List.Nodup` from sublists and `List.pairwise_flatMap`.** `assumptionsOf` returns one origin, or two when they differ. `unresolved` is a sublist of the input ids. Edge keys are `(r.id, p.id)` over `fs.flatMap`, and distinct ids make those pairs distinct. Nodup keys imply nodup edges.

## Done when
- [x] the five theorems are proved with the statements in the brief, no `sorry`, no new axioms
- [x] `lake build`, `cd core && lake build && lake check`, `cd core && lake comparator --paranoid`, `lake exe mitos-gate imports`, `lake exe mitos-gate lock --check`, and the run-log append check pass
- [x] run-log record written (ops/runs/)
