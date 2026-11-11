# Phase 2: chains and the first real extractor

**Goal:** a reference resolver for chains, where a requirement reaches its provider through a
binding (config key → deployment → service → repo). Each edge carries one derivation, and the
resolver's properties are proven against owner-approved statements. Beside it, the first built-in
extractor for a real format (go.mod), checked against the real tool.

Names marked *(new)* do not exist on `main` yet. This phase adds them.

**Exit criteria**

1. `cd core && lake comparator` accepts `Mitos.Proofs.Resolver` against the Phase 2
   `core/Challenge/Resolver.lean`: every theorem, #101's no-duplicates included, standard axioms
   only, also with `--paranoid`.
2. `cd core && lake check` passes: no `sorry` anywhere in the core.
3. Mutation testing: each mutant of the chain resolver and impact analysis in `eval/mutants/`
   breaks at least one theorem, every Phase 1 mutant still refutes after the migration, and no
   known gap (`survives=`) is open without an owner ruling.
4. CI accepts the go.mod plugin with `mitos-gate accept … --paranoid` (gates 0 to 6), and the
   differential run against `go mod edit -json` on the pinned repos reports no mismatch that is
   not triaged into a model issue.
5. The nightly job posts a scorecard for every fixture against hand labels: precision and recall
   per edge type (the chain and go.mod edge types included), the diff against `main`'s, and the
   most derivations any repo-level edge has.

## Before Phase 2 starts

The core track (P2-001a onward) starts only after items 1 to 5; item 6 is recommended. Tasks
that touch `core/` run one at a time (`docs/process.md`, Parallelism), so the Phase 1 core work
lands first. The go.mod track (P2-006 to P2-008, P2-009b) touches no core file and needs none of
them.

1. **#133, the owner's call on its core half.** Its branch, part of the no-comments audit
   (#129), renames `Edge` and `Assumption` fields in `core/Mitos/Core/Graph.lean` and follows
   them through the spec, `core/Mitos/Impl/Impact.lean`, `statements.lock`, `eval/mutants` and
   `eval/score`. That collides with both #101 PRs and with P2-001a, which replaces `Edge.req` and
   `Edge.prov` with a derivation key. The owner decides before #101's first PR: fold the naming
   into P2-001a (recommended), or land it first as one spec PR. Its items outside `core/`,
   `eval/mutants` and `eval/score` can run alongside.
2. **#137, the Span flag of #135.** A spec PR that adds to `Span` in
   `core/Mitos/Core/Fact.lean` and edits `Spec/Adequacy.lean` and `statements.lock`, which the
   #101 spec PR and P2-001b rewrite too. It merges, or closes, before the #101 PRs. It needs
   `spec-approved`.
3. **#101 option (a), first PR: the `impact` fix.** `Mitos.Impl.impact`
   (`core/Mitos/Impl/Impact.lean`) adds a repo once per edge that fires, so it can list a repo
   twice. Under D1 option C (see Scope decisions) a repeated record would read as a second
   derivation. Agents merge it.
4. **#101, second PR: no-duplicates in the spec** for the edges, `assumes`, the unresolved list
   and impact. It adds the statements, the Challenge lines, the `core/comparator.json` names and
   the `statements.lock` entries, with the proofs from `core/Mitos/Proofs/Resolve/Nodup.lean`. It
   needs `spec-approved`.
5. **#30, Phase 1 exit criterion 3.** The #101 spec PR flips the known gaps `edges_duplicated`
   and `assumptions_dedupe_dropped` (`eval/mutants/cases/`) from `survives=` to `breaks=`. Phase 1
   then exits before P2-005a migrates the mutants.
6. **#147 (P2-011), recommended.** The next-toolchain canary fails until the CrossCheckDecoy probe
   and the `String.le_*` deprecations are fixed. Landing it before P2-001a lets the canary check
   the migrated mutants. It never goes between two core PRs.

No other open PR is a prerequisite: #124, #125, #126, #138, #149, #151, #153 and #155 touch no
core file and can merge during the phase.

## Scope decisions

The owner's decisions on the draft are in
[#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085).

- **One edge record per derivation (D1, option C).** An edge's key is its derivation
  (`Edge.key : Derivation`, the type *(new)*). Two derivations between the same requirement and
  provider are two edge records. `Spec.RetractExact` keeps its Phase 1 text, and its proof stays
  a filter argument. Option A (one chosen derivation per pair) makes exact retraction false.
  Option B (ATMS labels) is exact too, but needs minimal-label proofs nobody has done in Lean.
- **The repo-level view is a union, proved, not a Challenge line.** `RepoKey` and
  `Edge.repoKey` *(new)* give one repo-level edge per set of derivations. Its guarantee,
  `retract_repo` *(new)*, follows from `Spec.Sound` and `Spec.RetractExact`: a repo-level edge
  survives retracting an assumption exactly when one of its derivations avoids it.
- **Rules are constructors of `Derivation` *(new)*,** not user data: `direct` (Phase 1's match)
  and `bound` (a requirement, a binding, a provision). A longer chain later is one more
  constructor, and no statement changes. The rule DSL is Phase 3.
- **Statements quantify over a finite list,** `derivations fs` *(new)*, not an inductive
  relation. Each statement is then decidable at a fixed input, and the Phase 1 mutant
  refutations (`revert this; decide`) keep working. Sound, complete, unresolved-exact,
  assumptions-exact and status-honest are restated. Total, retract-exact, impact-correct and
  #101's no-duplicates keep their text. With no binding fact, `derivations fs` holds exactly
  Phase 1's matches.
- **Each spec PR carries its implementation and proofs,** so `lake comparator --paranoid` runs
  at every merge of the phase. In Phase 1 the spec landed before the implementation, and CI
  skipped the comparator until `core/Mitos/Proofs/Resolver.lean` existed.
- **Bindings in this phase.** `FactKind.binds` *(new)* comes in P2-001b, so chains exist in
  Phase 2. It changes `Fact` for every plugin, so P2-001b re-accepts
  `examples/acme/accepted/ToyRequire.json`.
- **Status rule:** an edge is `confirmed` only when nothing under its derivation is AI-proposed
  and its requirement has exactly one derivation; otherwise `inferred` (`Spec.StatusHonest`). On
  Phase 1 inputs this says the same as Phase 1's "exactly one provider".
- **Union view status:** in the scorecard, a repo-level edge is `confirmed` if any of its
  derivations is. Today `collapse` in `eval/score/Score.lean` marks it `inferred` if any is.
- **Impact through bindings:** a change in the repo that holds a binding counts as impact
  (`Edge.through` and `Affects.through` *(new)*).
- **Revisit D1 by measurement.** The nightly scorecard reports the most derivations any
  repo-level edge has. D1 reopens when that number exceeds **[threshold set by the owner]**:
  option A if the counts explode, option B if users need minimal environments. On the
  hand-written chain fixture the number shows only what its author wrote, so it means most once
  a real chain extractor exists.
- **Chain facts are synthetic here.** No deployment or service extractor exists yet (YAML is
  later), so chain theorems run on a hand-written fixture and on `declaration` assumptions.
- **One real format:** go.mod over the existing line layer (`Mitos.lines`). The tokenizer and the
  `require ( … )` block state live in the reviewed model, so the core does not change. The subset
  is `module` and `require` lines and blocks. Quoted paths, `replace`, `exclude`, `retract` and
  versions give no fact, and the differential run lists them. JSON (package.json) and
  requirements.txt are deferred.
- **Differential tests are evaluation, not a gate.** Each pinned go.mod is vendored with its
  `go mod edit -json` output, so a run needs no Go. Only the nightly refresh installs Go. Gate 7
  for agent-written plugins is Phase 3.
- **Deferred, not decided here:** a HashMap production resolver with an equivalence proof,
  incremental-equals-from-scratch, a derivation-DAG certificate checker, the SQLite store and the
  NDJSON worker, staged judging (#55).

## Tasks

| # | Task | Kind | Issue |
|---|---|---|---|
| P2-001a | Keyed edges, direct rule only: `Derivation`, `Chain` and `derivations` *(new)*; `Edge.key` becomes a `Derivation` in place of `req` and `prov`; `RepoKey` and `Edge.repoKey` *(new)*. Five statements restated, `retract_repo` proved in `core/Mitos/Core/Spec/Repo.lean` *(new)*, adequacy theorems re-proved. Resolver, impact, proofs and `eval/score` move in the same PR (owner-gated: `core/Mitos/Core/`, `statements.lock`) | spec, impl | none yet |
| P2-001b | Chains: `FactKind.binds` *(new)* and the `bound` rule; `Edge.through` and `Affects.through` *(new)*; chain adequacy theorems; resolver, impact and proofs in the same PR; `examples/acme/accepted/ToyRequire.json` re-accepted (owner-gated: `core/Mitos/Core/`, `statements.lock`) | spec, impl | none yet |
| P2-005a | Phase 1 mutants migrated to keyed edges: the `Edge` literals in the `Refute.lean` files and the `find=` anchors in `eval/mutants/cases/`. Lands in P2-001a's PR, so no mutant is dropped and the nightly run stays green | tooling | none yet |
| P2-005b | Chain mutants in `eval/mutants/`, each breaking at least one theorem | tooling | none yet |
| P2-006 | go.mod model `examples/acme/Models/GoMod.lean` *(new)*, its golden files and adequacy module, and `examples/acme/models.lock` (owner-gated: reviewed model, `spec-approved`) | spec | none yet |
| P2-007 | go.mod plugin `examples/acme/Plugins/GoMod.lean` *(new)*, a fold over `Mitos.lines`; proves anchored, sound and complete; accepted by gates 0 to 6 with `--paranoid`; `examples/acme/accepted/GoMod.json` *(new)* written last | impl | none yet |
| P2-008 | Differential runner: plugin facts against the vendored `go mod edit -json` outputs of the pinned repos; mismatches and lines outside the model's subset listed per repo | tooling | none yet |
| P2-009a | Chain fixture and hand labels, with a requirement that has two derivations; scorer edge types for chain edges; the union view's status rule | tooling | none yet |
| P2-009b | go.mod fixture and hand labels; the scorer's go.mod edge type | tooling | none yet |
| P2-010 | Nightly scorecard code in `eval/score/`: every fixture, the diff against `main`'s, the most derivations per repo-level edge. Eval code only; the wiring is in P2-012 | tooling | none yet |
| P2-011 | Toolchain-bump readiness: the CrossCheckDecoy probe (`eval/mutants/Mutants/CrossCheck.lean`) for v4.36 and the `String.le_*` deprecations (`gate/MitosGate/ContentId.lean`); bump `lean-toolchain` when the release ships (owner-gated: `gate/`, `lean-toolchain`) | gate | [#147](https://github.com/kitimark/mitos/issues/147) |
| P2-012 | One `.github` PR: the CI accept step for `GoMod`; #107 items 2 and 3 (`mitos-mutants --prepare` on PRs that touch `core/`, a failure for a theorem no mutant breaks); the nightly Go refresh of the vendored outputs; the nightly scorecard post. #158 and #33 can ride along (owner-gated: `.github/`) | ci | none yet |

Each open row gets an issue in the Phase 2 milestone once this plan merges, and its status lives
in that issue and its PRs.

The draft's P2-002 to P2-004 (implementation and proofs) are folded into P2-001a and P2-001b.
The core track runs in order: P2-001a (with P2-005a), then P2-001b, then P2-005b and P2-009a.
The go.mod track runs beside it: P2-006 first, then P2-007 stacked on it, then P2-008 and
P2-009b. P2-007 writes `accepted/GoMod.json` last, because each core PR moves its
`core_sha256`. P2-010 follows P2-009a and P2-009b. P2-011 goes before P2-001a (recommended) or
after P2-001b, never between two core PRs. P2-012 comes last.
