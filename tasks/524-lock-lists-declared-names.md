# tasks/524-lock-lists-declared-names.md

phase: n/a (follow-up to #524, closes #415)
goal: statements.lock lists every declaration its source declares and every spec axiom, and no declaration Lean derives, so a Lean release adds no line and no name hides a declaration.
statement: none (gate tooling); gate statements MitosGate.Lock.nameListed_of_axiom, nameListed_of_declared, not_declaredBySource_of_no_range, not_nameListed_of_no_range
touches: gate/MitosGate/Lock.lean, gate/MitosGate/LockFixture.lean, gate/MitosGate/LockFixtureMeta.lean (new), gate/MitosGate/LockFixtureModule.lean (new), gate/MitosGate/LockCases.lean, gate/lock-meaning-test.sh, statements.lock, docs/process.md, tasks/524-lock-lists-declared-names.md, ops/runs/2026-11-20/524-lock-lists-declared-names-builder-1.json
must_not_touch: core/ sources, models.lock, eval/cheats/, plan/, .github/
checks: build, imports, lock, lint-test, lock-meaning-test, lock-package-test, lock-reach-test, lock-header-test, runlog, v4.37.0-rc1 canary build and lock check
budget: 20 iterations · 2h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

Approved design from [#524](https://github.com/kitimark/mitos/issues/524) (base candidate A plus the synthesis grafts from candidate B and the judge), also closing [#415](https://github.com/kitimark/mitos/issues/415).

Today `Lock.nameListed` uses a deny-list of name shapes (`isGenerated`, `generatedSuffixes`, `isAuxRecursor`, `isNoConfusion`), which both churns on new Lean auxiliaries (Lean v4.37.0-rc1 adds 6 matcher `congr_eq_N` lines) and hides hand-written declarations or axioms whose names match a denied suffix. Replacing the deny-list with positive evidence from Lean's `declRangeExt` (with a same-module shared-span check for `deriving` helpers and an unconditional axiom override) closes both gaps.

## Design

depth: build (statements proved on v4.35.0 and v4.37.0-rc1; fixtures, LockCases, and full-core lock verified on both toolchains)
revisit_when: none
modules:
  - `gate/MitosGate/Lock.lean`: what `statements.lock` pins; deletes `generatedSuffixes` and `isGenerated`, adds `private declaredBySource` (checking `declRangeExt` and same-module shared span with `n.getPrefix`), updates `nameListed` (declared and non-internal, or axiom), adds `(level := .private)` in `importRoot`, drops `textEntries`' duplicate listing rule, and proves the listing statements.
  - `gate/MitosGate/LockFixture.lean`: `Init`-only spec-style fixture declarations (existing regression cases, `#524` `congr_eq`, 23 `Plain.*` lookalikes, hidden/private/internal axioms, `deriving` shared-span, enum, inductive predicate `Rel`, structure, `mutual`, well-founded, `where`, and `partial` / `private partial` opaques).
  - `gate/MitosGate/LockFixtureMeta.lean`: `Lean`-importing fixture for metaprogramming-added declarations with no range (`Foo.inj` axiom listed, `claim` theorem residual unlisted) and cross-module same-span (`Nat.crossModSameSpan` copying `Nat`'s range, listed because its module differs from `Nat`).
  - `gate/MitosGate/LockFixtureModule.lean`: `module`-header fixture pinning public/private declarations, `deriving` helpers, and public/private axioms under `(level := .private)`.
  - `gate/MitosGate/LockCases.lean`: compile-time listing guards over `LockFixture`, `LockFixtureMeta`, and `LockFixtureModule`, including shared-span, cross-module same-span, derived `partial` opaque refusal, and toolchain-conditional `unlistedWhenPresent` checks.
  - `gate/lock-meaning-test.sh`: end-to-end cases for hidden axiom + hand-written `congr_eq`, private/internal axioms + lookalikes, and reached unlisted `partial` opaque refusal.
types: `private declaredBySource : Environment → Name → Bool`; `nameListed : Environment → Name → Bool` (signature unchanged); `importRoot : Name → IO ImportedRoot` (passes `level := .private`)
statements: `MitosGate.Lock.nameListed_of_axiom`, `MitosGate.Lock.nameListed_of_declared`, `MitosGate.Lock.not_declaredBySource_of_no_range`, `MitosGate.Lock.not_nameListed_of_no_range`
reuse: `Lock.importRoot`, `Lock.entries`, `Lock.Canon`, `Lock.refOf`, `Lock.blockedMeaning`, and `lock-meaning-test.sh` helpers
fixtures: `LockFixture` (listed, unlisted, unlisted-when-present, shared-span, partial opaque refusal), `LockFixtureMeta` (`Foo.inj`, `claim`, `Nat.crossModSameSpan`), `LockFixtureModule` (module-system public/private/deriving/axioms), and the `lock-meaning-test.sh` end-to-end cases
cut_line: ships the declaration-range listing rule with the same-module shared-span check, `(level := .private)` in `importRoot`, the proved statements, the fixtures and guards, the end-to-end meaning tests, the 4-line `statements.lock` update (`Mitos.Affects.below`/`.brecOn`), and the `docs/process.md` lock row update
deferrals: spec-source command allowlist (the metaprogramming theorem residual) to a follow-up issue; deduplicating `ensure`/`lineOf`'s `specOf`/`pkgOf` and `textEntries`' `inCore` to a follow-up issue
owner_decisions: owner approved the design and grafts in #524; owner retains merge (`gate/`, `docs/process.md`) and `spec-approved` for the 4-line `statements.lock` change

## Done when
- [x] all local checks pass (`lake build`, `imports`, `lock --check`, `LockCases`, `lock-header-test`, `lock-reach-test`, `lock-package-test`, `lock-meaning-test`, `runlog`; `mitos-lint-test` passes all 263 non-`unshare` cases locally, full 269 in CI)
- [x] `statements.lock` changes by exactly the 4 `Mitos.Affects.below`/`brecOn` lines on v4.35.0 and is byte-identical on v4.37.0-rc1
- [x] no `sorry`, no new axioms in `core/`
- [x] run-log record written (`ops/runs/2026-11-20/524-lock-lists-declared-names-builder-1.json`)
