# tasks/P2-005b-chain-mutants.md

phase: 2
goal: Each kind of fault that chains add to the resolver and to impact analysis has one mutant case in
  `eval/mutants/cases/` that the comparator refutes on a chain input, also with `--paranoid`, so the
  nightly mutant run ends with every case as expected and no known gap, and every Challenge theorem a
  chain can reach has a chain breaker in the breakers table.
statement: none locked (tooling task); no theorem, statement or `statements.lock` line changes
touches: the 28 new directories under `eval/mutants/cases/` named in `modules` (each holds a `mutant`
  file and a `Refute.lean`, 56 files), this file, ops/runs/
must_not_touch: every file of the 44 case directories on `main`, `eval/mutants/Main.lean`,
  `eval/mutants/Mutants/` (the lint included), the other files of `eval/mutants/`, `core/` (spec,
  `Impl/` and `Proofs/`), `statements.lock`, `models.lock`, `examples/`, `eval/score/`,
  `eval/fixtures/`, `gate/`, `eval/cheats/`, `.github/`, `docs/`, `plan/`, `.claude/` (Context, D6
  names the one line there that landing this file moves)
checks: eval/mutants build; `mitos-mutants --prepare` on the 28 cases (the lint and the anchors);
  each new case alone, default and --paranoid; control-fails; the nightly dispatched at the head (every
  case in one --paranoid invocation); the runner's peak memory; run-log check; plan-tasks.test.sh;
  gate green in CI
budget: 10 iterations · 3h wall · 800k tokens (every case text below was built and run, see Context 3)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
1. **The row.** Plan row P2-005b in `plan/phase-2.md` (wave W5), issue #206. Its design was tested
   against P2-001b's branch at `3d939da`. P2-001b (#204) merged in #545 at `1770a97`, and
   P2-005b merged in #547 at `5914856`.
2. **Inputs that settle things.**
   - The owner ruled O1 on #204 ("go 'rule out'", recorded in
     [this comment](https://github.com/kitimark/mitos/issues/204#issuecomment-6898646864)): `boundB`
     rules out a binding from an identity to itself (`&& p.fact.ident != r.fact.ident`).
     `self_binding_allowed` pins that ruling, and the three other cases that inline `boundB` keep
     the conjunct.
   - The merged cases open `Mitos.Spec.Chains` for twelve refutation inputs (`needDb`, `bindDb`,
     `provDb`, `chain`, `wfChain`, `chainEdge`, `chainAI`, `bindStaging`, `twoBindings`,
     `wfTwoBindings`, `selfBound`, `wfSelfBound`). They use Phase 1's `req`, `prov`, `goodEdge` and
     `twoProvisions` from `Mitos.Spec.Adequacy`. Locked `decide` theorems pin the fixtures'
     `derivations`.
   - The exceptions are the five cases whose refutation the replay kernels reject over string
     literals (T9). Four `StatusHonest` cases and `impact_through_head_only` build their input with
     `String.ofList`, as Phase 1's four status cases do.
3. **How this design was checked.** It was run, not read. Everything below was measured at `3d939da`
   on Lean v4.35.0, in a scratch checkout, with the real runner (`lake --dir eval/mutants exe
   mitos-mutants`). The host is shared: 4 cores, and one 14.3 GB memory cgroup for every agent's
   shell in the session.
   - `--prepare` over the 28 cases printed 28 paths and no `lint:` line, exit 0.
   - Each of the 28 cases run alone printed `control ... ACCEPTED`, then the case `REFUTED` with
     exactly the theorems of its `breaks=`, then `mutants: all 1 cases as expected, 1 refuted`. This
     held both default and with `--paranoid`. Case TIME was 22 to 31 s default and 31 to 62 s with
     `--paranoid`, one run each.
   - Each `Refute.lean` fails against the unmutated core (28 of 28, `lake env lean`, exit 1).
   - Runner B's earlier runs at the same head agree for the 23 texts that are unchanged here.
   - Earlier texts that failed a kernel or injected two faults were rewritten. T9 and T11 list them.
   - A ten-case `--paranoid` invocation refuted its first three cases, then was killed (exit 137).
     That was the shared cgroup's OOM killer while another agent's runner ran beside it (`dmesg`:
     `Memory cgroup out of memory`). It says nothing about a case. The same cause explains runner
     B's exit 137s.
   - Not run here: every case in one invocation. That is the nightly's shape, and fixture
     `nightly-dispatch` runs it on GitHub's runner.
4. **What a wrong builder, a cheating resolver or a cheating input could get past this row.** The
   row's criterion, "each mutant breaks at least one theorem", is cheap to meet. These are the ways
   to meet it without pinning anything about chains, and what stops each:

   | # | Attack | What gets through | What stops it |
   |---|---|---|---|
   | T1 | A mutant that breaks everything (an edit that empties `edges`) | It breaks a theorem, so it counts, but it says nothing about chains | The scope pin in 26 of the 28 cases. The mutated `resolve` still returns `Spec.Adequacy.goodEdge` on Phase 1's own fixture, and `impact` still answers on `goodEdge`. The two cases without the pin are not chain-only on purpose (their `why=` and the table say so) |
   | T2 | An anchor the cached resolver never runs: `ends`, or the default `same` arguments of `statusOf`, `mkEdge` and `mkBoundEdge` | An equivalent mutant. No refutation can be proved, so the case ends `REJECTED, NOT REFUTED`. It cannot be relabelled `survives=`, which needs an accepted gate run | Every anchor lies in text that `resolveOne`, `mkEdge`, `mkBoundEdge`, `boundProviders`, `summarizeEnds` or `fires` runs. P2-001b's candidate (c), `providers fs r ++ fs.flatMap (boundProviders fs r)` → `providers fs r`, is the `ends` line and is dead. All ten resolver statements hold on nine inputs under it (measured). It is replaced by `unresolved_ignores_bound_ends` and `status_ignores_bound_ends` (fixture `anchors-live`) |
   | T3 | A refutation input with no binding in it | A Phase 1 case in disguise | Inputs are locked `Spec.Chains` fixtures whose `derivations` a locked theorem pins, or local inputs with an `example` that pins `derivations` |
   | T4 | Anchor or edit text the runner's lint refuses | A case `REFUSED BY LINT`. The plan-time `inductive EndSummary` did this to every `Impl/Resolve.lean` case, and the branch made it an `abbrev`. A later edit that brings back a `structure` or `inductive` repeats it, and the 15 `rejects=lint` cheat cases would still read as rejected, for the wrong reason | `--prepare` over the cases before any run (fixture `prepare-lint-clean`), and P2-005a's `cheat-evidence-unchanged` |
   | T5 | A refutation that is true of the unmutated resolver | Impossible for a checked proof, but a stale input can make a proof elaborate for another reason, or the case pin nothing | Fixture `control-fails`: every Refute file fails to build against the unmutated core. Each fails on the proposition it names, except that two fail their consequence pin first and five report `decide failed to reduce` |
   | T6 | Relabelling a stubborn case `survives=` | A spec gap hidden | A case that cannot be refuted is re-anchored or cut and reported, never relabelled. A real survivor (the gate accepts it and the values check accepts it) goes to the owner (exit criterion 3). None is predicted |
   | T7 | A resolver wrong in a way no theorem sees | A hole in the spec | The matrix under Rationale: every clause a chain extends has a chain breaker. The one theorem without one, `resolve_unresolved_nodup`, has no chain source of duplicates (`unresolved` holds one entry per requirement), and Phase 1's `unresolved_duplicated` keeps it |
   | T8 | A plugin that emits facts a resolver mishandles: a binding with no provision, a binding of someone else's identity, a binding to a requirement, a binding held in the requirer's repo, a binding to itself, two bindings that reach one provider, an AI-proposed binding, a test-scoped requirement under a runtime binding | Each is a valid input, and the resolver must answer it by the spec | The cases named in the table under `statements` |
   | T9 | A refutation that elaborates in Lean but that a replay kernel rejects | The case ends `REJECTED, NOT REFUTED`. Measured: runner B's first `StatusHonest` texts over `chain`, `chainAI` and `fork` were rejected by the Lean default kernel, and `decide +kernel` did not help. Runner B's `impact_through_head_only`, over `{ chainEdge with through := ... }`, is `REFUTED` by default but rejected by lean4lean under `--paranoid` (`unknown constant 'Char.ofNat'` at `Mitos.Spec.Adequacy.needDb`). A local edge with string literals failed the same way at `Mitos.Refute.edge`. The nightly runs only `--paranoid`, so that text would have turned it red | The five cases named in Context 2 use `String.ofList` inputs. Every case is judged by the real runner, default and `--paranoid`, never by `lake env lean` alone (fixture `new-cases-refuted`) |
   | T10 | A case set the nightly host cannot hold | The nightly dies mid-run and every case reads as failed | Fixtures `runner-peak` and `nightly-dispatch` measure the current runner with all 72 cases |
   | T11 | An edit that injects two faults while its `why=` names one | A case that seems to pin one clause and pins two | Each inlined `boundB` keeps every conjunct except the one it names. Runner B's three texts also dropped O1's conjunct and broke `Sound` on `selfBound`. The texts below do not (measured, Design) |

5. **Where this design and its inputs disagree.** None blocks the row.
   - **D1. Fixture namespace.** The judged branch put the chain fixtures in `Spec.Adequacy`.
     The merged implementation uses the plan-time `Spec.Chains` namespace.
   - **D2. P2-001b's candidate list.** It hands this row seven candidates.
     - Six are cases here: `through_dropped`, `binding_origin_forgotten`, `bound_edges_dropped`,
       `impact_through_ignored`, `bound_key_legs_swapped` and `edges_one_per_repo_key`.
     - Candidate (c) is dead (T2).
     - P2-001a's one-edge-per-repo-key mutant is `edges_one_per_repo_key`.
     - #276 V1 is `chain_also_direct`: a record whose key no derivation has, which `AssumptionsExact`
       and `StatusHonest` do not see.
   - **D3. Case counts.** `main` has 44 cases: 24 refuted, 20 cheat cases rejected, 15 generated
     Challenges. After this row it has 72 cases: 52 refuted, 20 cheat cases rejected, no known gap and
     19 generated Challenges. The branch migrates #311's two cases already, so Design A's drift
     finding (two #311 `find=` texts that would not apply) is fixed at `3d939da`.
   - **D4. Shared anchor lines.**
     - Four cases anchor on the `| .binds _ => fs.filter (boundB r b)` line.
     - Three anchor on `e.through.any ...`.
     - Two each anchor on the assumptions, status, unresolved and `groups` lines.
     - Two anchor on the `through := [b.repo]` text (`through_dropped`, `bound_scope_from_binding`).

     Each case applies to the unedited file, so the cases never meet. But a rewrite of one of those
     lines in P2-001b moves every case on it.
   - **D5. Plan cell.** The Owns cell, "new directories in `eval/mutants/cases/`", covers all 28
     directories. No file outside them is written, except this file and the run log.
   - **D6. Landing this file.** `.claude/scripts/plan-tasks.pending` lists `P2-005b`, and
     `plan-tasks.test.sh` fails a listed row that has a valid file. So the PR that adds this file
     removes that line. `.claude/` is the owner's, so the owner merges that design PR. The build PR
     stays agent-merged.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. P2-001b merged on 2026-11-21. All 28 anchors occur exactly once on merged
`main` at `1770a97`, and the self-binding guard remains. The 12 chain fixtures moved to
`Spec.Chains`; the four Phase 1 fixtures remain in `Spec.Adequacy`. The Appendix opens both.

revisit_when: re-check after P2-001b merges (#204). At branch time, from the repository root:
1. `git fetch origin main`, then `git diff --stat 3d939da origin/main -- core eval/mutants`. It
   lists what moved since the head these cases were built on. Read each listed file against this
   design first.
2. Write the 56 files from the Appendix. Then run `lake --dir eval/mutants build`, then
   `lake --dir eval/mutants exe mitos-mutants --prepare <scratch> <the 28 cases>`. It prints 28 paths
   and no `lint:` or error line, exit 0. A `find=` that no longer occurs exactly once is named there.
   Re-anchor that case to the smallest text that occurs once and makes the same edit, and keep its
   `why=`, `breaks=` and Refute. A re-anchor that needs a new refutation goes to a stronger model
   (`opus`), the third step of `escalation`.
3. `grep -c 'p.fact.ident != r.fact.ident' core/Mitos/Core/Spec/Derivations.lean` prints `1`, which
   is O1's conjunct in `boundB`. If it prints `0`, drop `self_binding_allowed`, and delete the
   trailing `&& p.fact.ident != r.fact.ident` from the three other inlined texts, so each still drops
   exactly one conjunct.
4. The 16 fixture names are in two files:
   - `grep -cE '^(def|theorem) (needDb|bindDb|provDb|chain|wfChain|chainEdge|chainAI|bindStaging|twoBindings|wfTwoBindings|selfBound|wfSelfBound) ' core/Mitos/Core/Spec/Chains.lean`
     prints `12`, the chain names in namespace `Mitos.Spec.Chains`.
   - `grep -cE '^(def|theorem) (req|prov|goodEdge|twoProvisions) ' core/Mitos/Core/Spec/Adequacy.lean`
     prints `4`, Phase 1's names in `Mitos.Spec.Adequacy`.

   Each Refute opens both namespaces (Appendix A1). If a name moves again, open its new namespace
   in each Refute that uses it.
5. The merged `Impl/Resolve.lean` still has `resolveOne` with `direct`, `groups`, `allEnds` and
   `summary`, and `mkBoundEdge` over `mkEdge`. `Impl/Impact.lean` still has `fires` over
   `e.through`. A different shape moves the anchors named in D4, and step 2 finds each one.
6. Cases added to `main` since `3d939da` (the #231 or #311 style) join the counts in
   `nightly-dispatch` and `breakers-table`.

modules: one directory per case, two files each. Nothing else is written.
- `eval/mutants/cases/<case>/mutant` holds one `why=` line (the injected fault, in the existing
  cases' one-sentence style), one `breaks=` line and one `file=`/`find=`/`replace=` triple. 5 lines.
  It copies `eval/mutants/cases/first_fact_skipped/mutant`.
- `eval/mutants/cases/<case>/Refute.lean` holds, in order:
  - the shared header (Appendix A1);
  - the scope pin the case's heading names;
  - the case's body: its local inputs, then one `theorem <t> : ¬ Spec.<S> Impl.<R>` per name in
    `breaks=`;
  - `end Mitos.Refute`.

  The merged files are 15 to 44 lines each. They follow
  `eval/mutants/cases/requirer_origin_forgotten/Refute.lean`, which has several theorems in one file.
  The five `String.ofList` cases follow `status_any_not_all/Refute.lean`.
- The 28 directories, 23 on `Impl/Resolve.lean` and 5 on `Impl/Impact.lean`: `assumes_pool_all_bindings`,
  `binding_ident_unchecked`, `binding_origin_duplicated`, `binding_origin_forgotten`,
  `binding_same_repo_skipped`, `binding_target_unchecked`, `bound_always_inferred`,
  `bound_edge_from_binding`, `bound_edges_dropped`, `bound_edges_duplicated`,
  `bound_key_legs_swapped`, `bound_scope_from_binding`, `bound_status_ignores_binding`,
  `chain_also_direct`, `dangling_binding_hides_unresolved`, `direct_edge_through_set`,
  `edges_one_per_repo_key`, `impact_binding_repo_affected`, `impact_through_bypasses_seen`,
  `impact_through_head_only`, `impact_through_ignored`, `impact_through_not_transitive`,
  `provision_kind_unchecked`, `self_binding_allowed`, `status_counts_derivations`,
  `status_ignores_bound_ends`, `through_dropped`, `unresolved_ignores_bound_ends`.

### Usage (caller's view)

A case is a fault written as a one-line edit, plus a proof that a Challenge theorem is false for the
edited code. The smallest one:

```text
why=Leaves the binding's repo out of a chain edge, so the edge reads as a direct one and impact analysis loses the binding.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=through := [b.repo]
replace=through := []
```

```lean
import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide

end Mitos.Refute
```

The `example` is the scope pin. The mutant still resolves Phase 1's own fixture, so the fault is a
chain fault. `chain` and `wfChain` are locked fixtures, so the refutation input is a chain by
construction. The runner then judges the case:
- the mutant builds (the holes run);
- the gate rejects it (the approved run);
- the comparator accepts the refutation with the holes as values.

types: none of the row's own. A Refute may declare local inputs under `Mitos.Refute`. Each has an
`example` that pins its `derivations`, or it is a locked fixture that already has one.

| Input | Built from | Its derivations | Used by |
|---|---|---|---|
| `fs` of `binding_ident_unchecked` | `[needDb, bindDb, provDb, needOther]`, where `needOther` is a requirement of `env/OTHER` in `api` | `[bound 0 1 2]` | that case |
| `fs` of `binding_target_unchecked` | `[needDb, bindDb, provDb, provOther]`, where `provOther` provides `svc/billing` | `[bound 0 1 2]` | that case |
| `fs` of `provision_kind_unchecked` | `[needDb, bindDb, needSvc]`, where `needSvc` is a requirement of `svc/orders-db` | `[]` | that case |
| `fs` of `bound_scope_from_binding` | `[needTest, bindDb, provDb]`, where `needTest` is `needDb` in scope `test` | `[bound 0 1 2]` | that case |
| `fs` of `binding_same_repo_skipped` | `[needDb, bindHome, provDb]`, where `bindHome` is `bindDb` in repo `web` | `[bound 0 1 2]` | that case |
| `fs` of `binding_origin_duplicated` | `[needDb, bindSameOrigin, provDb]`, one origin for the requirement and the binding | `[bound 0 1 2]` | that case |
| `fs` of `dangling_binding_hides_unresolved` | `[needDb, bindDb]` | `[]` | that case |
| `nReq`, `nBind`, `nProv`, `nBindAI`, `nBindOther`, `fReq`, `fProv`, `fBind`, `fSvc` | the `chain`, AI-binding, two-bindings and fork inputs, rebuilt with `String.ofList` (with `s`, `idEnv`, `idSvc`, `idNpm` and `loc` to build them) | pinned by an `example` on `derivations` | the four `resolve_status_honest` cases |
| `longEdge` | an edge from `w` to `o` through `[d, m]`, every string built with `String.ofList` | n/a (an edge) | `impact_through_head_only` |
| `edge src dst`, `es` | Phase 1's `edge` helper, with `chainEdge` | n/a | `impact_through_not_transitive`, `impact_through_bypasses_seen` |

statements: none locked. Each case claims that the theorems in its `breaks=` line are false for its
mutant, and the runner checks every claim with a proof. Here are the 28 cases by the fault each one
injects. The exact `find=` and `replace=` lines are in the Appendix. R is `Mitos/Impl/Resolve.lean`
and I is `Mitos/Impl/Impact.lean`.

| Case | Edit (file, text → text) | Input | Breaks | Pin | Fault |
|---|---|---|---|---|---|
| `through_dropped` | R: `through := [b.repo]` → `through := []` | `chain` | `resolve_sound` | resolver | the binding's repo left off the record |
| `direct_edge_through_set` | R: `key := .direct r.id p.id,` → `... through := [r.repo],` | `[req, prov]` | `resolve_sound` | none | a direct edge given a `through`, so the empty default of the new field is a statement (not chain-only) |
| `bound_edge_from_binding` | R: `mkEdge fs r p same with` → `mkEdge fs b p same with` | `chain` | `resolve_sound` | resolver | the repo-level fields taken from the binding |
| `bound_key_legs_swapped` | R: `.bound r.id b.id p.id` → `.bound r.id p.id b.id` | `chain` | `resolve_sound`, `resolve_complete` | resolver | a key that no chain has |
| `bound_scope_from_binding` | R: `through := [b.repo],` → `... scope := b.fact.scope,` | `needTest` chain | `resolve_sound` | resolver | a test-only requirement read as runtime |
| `binding_ident_unchecked` | R: `boundB` inlined without `b.fact.ident == r.fact.ident` | a requirement of another identity | `resolve_sound` | resolver | one binding applies to every requirement |
| `binding_target_unchecked` | R: `boundB` inlined without `binds p.fact.ident` | a provision of another identity | `resolve_sound` | resolver | a binding reaches every provision |
| `provision_kind_unchecked` | R: `boundB` inlined without `p.fact.kind == .provides` | a requirement of the bound identity | `resolve_sound` | resolver | a chain ends at a non-provider |
| `self_binding_allowed` | R: `boundB` inlined without `p.fact.ident != r.fact.ident` | `selfBound` | `resolve_sound` | resolver | the owner's O1 ruling undone |
| `chain_also_direct` | R: the direct records are written for `allEnds`, not `direct` | `chain` | `resolve_sound`, `resolve_retract_exact` | resolver | #276 V1: a record under a direct key that no derivation has. `AssumptionsExact` and `StatusHonest` hold on `chain` (measured) |
| `bound_edges_dropped` | R: the bound `groups.flatMap (...)` → `[]` | `chain` | `resolve_complete`, `resolve_total` | resolver | chains never resolved |
| `binding_same_repo_skipped` | R: `groups` skips a binding in the requirer's repo | a binding in `web` | `resolve_complete`, `resolve_unresolved_exact` | resolver | the O5 case: a binding held at home |
| `edges_one_per_repo_key` | R: `edges :=` keeps one edge per `repoKey` | `twoBindings` | `resolve_complete`, `resolve_retract_exact` | none (consequence pin) | option C lost: the staging and prod example |
| `unresolved_ignores_bound_ends` | R: `allEnds.isEmpty` → `direct.isEmpty` in `unresolved` | `chain` | `resolve_unresolved_exact` | resolver | a requirement met by a chain listed as unresolved |
| `dangling_binding_hides_unresolved` | R: `unresolved` also asks that the identity has no binding | `[needDb, bindDb]` | `resolve_unresolved_exact`, `resolve_total` | resolver | a binding with no provision hides its requirement |
| `binding_origin_forgotten` | R: `.insert b.origin` dropped | `chain` | `resolve_assumptions_exact`, `resolve_retract_exact` | resolver | an AI-proposed binding not listed (the consequence pin shows it launders a `confirmed`) |
| `assumes_pool_all_bindings` | R: `assumes :=` adds every binding's origin | `twoBindings` | `resolve_assumptions_exact`, `resolve_retract_exact` | resolver | retracting staging kills the prod chain |
| `binding_origin_duplicated` | R: `.insert b.origin` → `++ [b.origin]` | one origin for the requirement and the binding | `resolve_assumptions_nodup` | resolver | an extractor named twice |
| `bound_status_ignores_binding` | R: status asks `assumptionsOf r p` | `chainAI`, literal-free | `resolve_status_honest` | resolver | an AI-proposed binding leaves the edge confirmed |
| `bound_always_inferred` | R: bound status `.inferred` | `chain`, literal-free | `resolve_status_honest` | resolver | a chain of confirmed facts never confirmed |
| `status_counts_derivations` | R: `rest.all (·.id == p.id)` → `rest.isEmpty` | `twoBindings`, literal-free | `resolve_status_honest` | resolver | owner decision 3 as first worded ("exactly one derivation"), against the plan's refined rule |
| `status_ignores_bound_ends` | R: `summarizeEnds allEnds` → `summarizeEnds direct` | `fork`, literal-free | `resolve_status_honest` | resolver | the direct provider confirmed despite a chain to another |
| `bound_edges_duplicated` | R: `groups` over `fs ++ fs` | `chain` | `resolve_edges_nodup` | resolver | every chain edge twice |
| `impact_through_ignored` | I: the `through` test → `false` | `[chainEdge]`, `"deploy"` | `impact_correct` | impact | a change in a binding's repo does not reach its requirer |
| `impact_through_not_transitive` | I: the `through` test without `seen` | a direct edge, then `chainEdge` | `impact_correct` | impact | a chain edge that cannot continue a path |
| `impact_binding_repo_affected` | I: the binding repos added to the affected list | `[chainEdge]`, `"orders"` | `impact_correct` | impact | the provider's change reported at the binding's repo |
| `impact_through_head_only` | I: `e.through.take 1` | an edge through two repos, literal-free | `impact_correct` | impact | `ImpactCorrect` holds for longer chains, which the resolver does not emit yet |
| `impact_through_bypasses_seen` | I: the requirer guard skipped on a `through` hit | a direct edge and `chainEdge` | `impact_nodup` | impact | a repo reached by a provider and by a binding, listed twice |

Every case also holds a `why=` line that names its one injected fault.

The signatures a Refute declares, one per name in a `breaks=` line. The cases reach 11 of the 12
Challenge theorems. `resolve_unresolved_nodup` is the one they do not reach (see T7).

```lean
theorem Mitos.Refute.resolve_sound : ¬ Spec.Sound Impl.resolve
theorem Mitos.Refute.resolve_complete : ¬ Spec.Complete Impl.resolve
theorem Mitos.Refute.resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve
theorem Mitos.Refute.resolve_total : ¬ Spec.Total Impl.resolve
theorem Mitos.Refute.resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve
theorem Mitos.Refute.resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve
theorem Mitos.Refute.resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve
theorem Mitos.Refute.resolve_edges_nodup : ¬ Spec.EdgesNodup Impl.resolve
theorem Mitos.Refute.resolve_assumptions_nodup : ¬ Spec.AssumptionsNodup Impl.resolve
theorem Mitos.Refute.impact_correct : ¬ Spec.ImpactCorrect Impl.impact
theorem Mitos.Refute.impact_nodup : ¬ Spec.ImpactNodup Impl.impact
```

A `breaks=` line that names a theorem the Refute does not prove does not come out `REFUTED`, so a
claim cannot be inflated. A Refute that proves a theorem false which `breaks=` omits loses only a
cell in the breakers table.

**`breaks=` sets and memory.** Each distinct `breaks=` set is one generated Challenge, 19 for the 72
cases. The runner's peak resident memory does not grow with that number or with the number of
cases. It stays between 4.63 and 4.83 GiB (4,855,436 to 5,055,668 KiB). A new case or a new
`breaks=` set adds time and no memory.

The design-time runner kept every import and reached 10.8 GB at 72 cases. Since the #521 fix
(`a046630`, #536), the runner frees each Lean import after its check. It holds the approved
Challenge, the parse check's set and one generated Challenge at a time. The first step checks the
generated Challenges before any case is judged, and `--prepare` runs that step, writes the
workspaces and runs the lint, and judges nothing. Its peak is within 4 % of a full run's.

Measured peaks of the `mitos-mutants` process:

| Cases (generated Challenges) | Command | Peak in KiB | Runs | Read as | Source |
|---|---|---|---|---|---|
| 1 (2) | full run, default mode | 5,055,428 and 4,959,228 | 2 | `VmHWM` | #537, `main` at `00fae4d` |
| 72 (19) | full run, default mode | 5,055,668 | 1 | `VmHWM` | #537, `main` at `00fae4d` |
| 1 (2) | `--prepare` | 4,958,044 | 1 | `VmHWM` | #537, `main` at `00fae4d` |
| 72 (19) | `--prepare` | 4,956,016 and 4,855,436 | 2 | `VmHWM` | #537, `main` at `00fae4d` |
| 72 | not recorded | 5,029,100 | 1 | `VmHWM` | #550 item 3, from #547's verifier |
| 1 (2) | `--prepare` | 4,992,568 | 1 | `/usr/bin/time -v` max RSS | #536 |
| 44 (15) | `--prepare` | 5,001,472 | 1 | `/usr/bin/time -v` max RSS | #536 |
| 44 (15) | full run, `--paranoid` | 4,989,044 to 5,001,284 | 3 | `/usr/bin/time -v` max RSS | #536 |

- Each figure is one process and never a sum. `VmHWM` and the max RSS of `/usr/bin/time -v` both
  give the largest single process, and the runner is the largest. In the #537 runs, the max RSS that
  `wait4` returns equals the runner's `VmHWM`.
- The #537 rows ran on a host with 4 cores and 15.7 GiB, inside one 13.4 GiB memory cgroup that
  every agent's shell shares. The #536 rows ran on a host with 4 cores and 16 GB.
- The #537 runs of one command lie within 102,608 KiB (2 %) of each other, with 1 case or with 72.
  So the measurements show no slope. The lower 72-case `--prepare` run ran while another agent's
  process filled the cgroup.
- While a case is judged, the comparator's children run beside the runner. The largest were one
  `leanexport` at 1,678,412 KiB and one `lean` at 1,648,800 KiB (`VmHWM`, the 72-case run). The
  anonymous memory of the whole process tree peaked at 4,156,900 KiB in a 1-case run (one run).
  #536 measured 4,061 to 4,092 MiB for 44 cases with `--paranoid` (three runs).
- The 72-case run ended `mutants: all 72 cases as expected, 52 refuted, 0 known gap(s), 20 cheat
  case(s) rejected`, exit 0, after 3,948 s wall, 3,830 s by the runner's own count. That is one
  run, and other agents' Lean builds shared its four cores for part of it.

These four new sets each name two refuted theorems:
- `resolve_sound resolve_complete` (`bound_key_legs_swapped`);
- `resolve_sound resolve_retract_exact` (`chain_also_direct`);
- `resolve_complete resolve_total` (`bound_edges_dropped`);
- `resolve_complete resolve_retract_exact` (`edges_one_per_repo_key`).

reuse:
- The chain and Phase 1 fixtures listed in Context 2.
- The runner, unchanged: `--prepare`, the logs in `.lake/mutants/`, the breakers table.
- Phase 1's refutation pattern (`intro h; have := h fs wf; revert this; decide`). For impact, it uses
  `decide +kernel`, as `impact_direct_only` does. For `StatusHonest`, it uses Phase 1's
  `String.ofList` inputs (`status_any_not_all`).
- P2-005a's fallbacks for a replay kernel that rejects a `decide`, in order:
  1. strings built with `String.ofList`;
  2. `decide +kernel`;
  3. a proof that names the edge and the chain and closes with `simp`.

fixtures: two kinds. In-file pins are checked on every run, because the case does not build without
them. The builder reports the run-level fixtures.

In-file pins, in the Refute of the cases they fit:
- **Scope pin.** The 21 chain-only resolver cases carry
  `(Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge]` and
  `(Impl.resolve [Spec.Adequacy.req]).unresolved = [0]`. The five impact cases carry
  `Impl.impact [Spec.Adequacy.goodEdge] "sdk" = ["web"]`. It stops a mutant that also breaks Phase 1
  from counting as a chain mutant (T1). `edges_one_per_repo_key` and `direct_edge_through_set` do not
  carry it.
- **Derivations pin.** An `example` on the local input's `derivations` (T3).
- **Impact helper.** In `impact_binding_repo_affected`, `affects_chainEdge` proves that the only
  affected destination from this edge is `web`. The refutation uses it to rule out the mutant's
  report that a change in `orders` affects `deploy`.
- **Consequence pin.**
  - `binding_origin_forgotten` carries `(Impl.resolve chainAI).edges.map Edge.status = [.confirmed]`.
    It shows what the missing origin does: an AI-proposed binding turns into a confirmed edge.
  - `edges_one_per_repo_key` carries
    `(Impl.resolve Spec.Adequacy.twoProvisions).edges.map Edge.key = [.direct 0 1]`. That is
    P2-001a's two-provisions-in-one-repo form of the same fault.

Run-level fixtures:
- `prepare-lint-clean`: `lake --dir eval/mutants exe mitos-mutants --prepare <scratch> <the 28 cases>`
  prints one `<case>: <dir>` line per case and no `lint:` line, exit 0. Measured at `3d939da`: 28 of
  28.
- `new-cases-refuted`: each new case runs alone, as `lake --dir eval/mutants exe mitos-mutants <case>`
  and again with `--paranoid`. Each run ends with `control ... ACCEPTED`, the case line `REFUTED`
  with exactly the theorems of its `breaks=`, and `mutants: all 1 cases as expected, 1 refuted`.
  Measured at `3d939da`: 28 of 28 in both modes. Case TIME was 22 to 31 s default and 31 to 62 s with
  `--paranoid`, one run each, on the shared host.
- `control-fails`: from `core/` of the P2-001b head, `lake env lean <Refute.lean>` fails for every
  new Refute. Each fails on the proposition it names, except that `binding_origin_forgotten` and
  `edges_one_per_repo_key` first fail their consequence pins, and the five impact cases report
  `decide failed to reduce`. Build `Mitos.Impl.Resolve` and `Mitos.Impl.Impact` first. Without
  them, every file fails on its import, which shows nothing. Measured at `3d939da` and again on
  `main` at `00fae4d`: 28 of 28 exit 1.
- `anchors-live`: `grep -lE '^find=.*(def ends|\(ends fs r\)|providers fs r \+\+ fs\.flatMap)'` over
  the 28 `mutant` files prints nothing (T2), and no case ends `REJECTED, NOT REFUTED`. A case that does
  is re-anchored on live text, never relabelled. Measured: nothing printed.
- `runner-peak`: run `--prepare` over every case directory while reading the `mitos-mutants`
  process's `VmHWM` from `/proc/<pid>/status`. The run prints `generated Challenges (as Lean built
  them): 19`. Report the peak beside the lines under "`breaks=` sets and memory". Measured at
  `00fae4d`: 4,956,016 KiB and 4,855,436 KiB, two runs. The exit is 0. The run prints one
  `<case>: <dir>` line for each of the 57 other cases, and `refused by the lint, as its manifest
  says` for each of the 15 `rejects=lint` cheat cases.
- `nightly-dispatch`: at the head the PR owner reports, run
  `gh workflow run nightly.yml --ref <branch>`. Job `full`, step "Mutation testing (paranoid)", ends
  `mutants: all 72 cases as expected, 52 refuted, 0 known gap(s), 20 cheat case(s) rejected`, with
  the counts moved by any case `main` gained since. This is the only run of every case in one
  invocation on the nightly's host (GitHub's `ubuntu-24.04`). It has precedent: the P1-006 branch
  dispatched the nightly the same way. A nightly run at `beed5eb` took 654 s for that step, with 42
  cases. If the run is still going after the owner's two bounded waits, the owner reports
  "pushed, waiting on the nightly dispatch" with the run's number. The root's monitor does not report
  that run, so the root spawns a watcher for it.
- `breakers-table`: the dispatch run's "BROKEN BY" table, per theorem, is Phase 1 and #311 plus the
  new breakers:

  | Theorem | Total | New |
  |---|---|---|
  | `resolve_sound` | 14 | 10 |
  | `resolve_complete` | 7 | 4 |
  | `resolve_unresolved_exact` | 7 | 3 |
  | `resolve_total` | 5 | 2 |
  | `resolve_assumptions_exact` | 4 | 2 |
  | `resolve_status_honest` | 8 | 4 |
  | `resolve_retract_exact` | 7 | 4 |
  | `impact_correct` | 8 | 4 |
  | `resolve_edges_nodup` | 2 | 1 |
  | `resolve_unresolved_nodup` | 1 | 0 |
  | `resolve_assumptions_nodup` | 2 | 1 |
  | `impact_nodup` | 2 | 1 |

  That is 36 new claims over 28 cases.
- `cheat-evidence-unchanged`: P2-005a's fixture over the 15 `rejects=lint` cases. Each evidence line
  in the dispatch run names that case's own cheat, not this row's text.
- `new-files-only`: `git diff --name-status --no-renames origin/main...HEAD -- eval/mutants` shows
  only `A` lines, 56 of them, all under the 28 new directories.
  `git diff --stat origin/main...HEAD -- core eval/mutants/Main.lean eval/mutants/Mutants` prints
  nothing. `git diff --name-only origin/main...HEAD` lists only those 56 files, this file and files
  under `ops/runs/`.
- `run-log`: `lake exe mitos-gate runlog --head ops/runs` passes, and the `ops/runs` diff shows only
  `A` lines.

Measurements from #547's verifier: one run refuted all 28 new cases in 2324 s. The full run
reported "all 72 cases as expected, 52 refuted, 0 known gaps, 20 cheat cases rejected". The
measured runner peak for 72 cases was about 4.8 GiB (VmHWM 5,029,100 KiB). The nightly dispatch at `13ec624`
passed with `--paranoid` in 3861 s. [Verification findings](https://github.com/kitimark/mitos/issues/550)
[Nightly dispatch](https://github.com/kitimark/mitos/actions/runs/44892073901)

cut_line: ships the 28 cases, this file's measured lines and the run log. It ships no change to the
runner, the lint or an existing case, no `survives=` case and no `rejects=` case. P2-001b adds no
cheat surface that the lint's allow-list does not already close: no syntax, attribute, instance or
import, and the cases name only `Mitos` namespaces. The PR says `Closes #206`.
- Keep all 28 cases and their declared theorems. Memory is no reason to cut a case or to narrow a
  `breaks=` set, because the runner's peak does not grow with either (measured, "`breaks=` sets and
  memory"). A memory failure is a fault of the runner, the host or the case's own build. It blocks
  completion until the runner's peak and the reason for the failure are established, and it drops
  nothing. This keeps the expected counts in `runner-peak`, `nightly-dispatch`, `breakers-table`
  and `new-files-only` tied to one corpus and preserves the sole chain `impact_nodup` breaker.

deferrals:
- **From P2-001b (#204), its contract.**
  - Taken: six of the seven candidate mutants (D2), the chain fixtures as inputs, and the
    status rule's two halves (`status_counts_derivations`, `status_ignores_bound_ends`).
  - Not taken as written: candidate (c) (T2).
- **From P2-001a (#203):** a mutant that keeps one edge per repo-level key (`edges_one_per_repo_key`).
- **From #276 V1:** a record that no derivation has (`chain_also_direct`).
- **To P2-001b's PR, before it merges.** Keep the anchors this design names (D4), or say in its PR
  body which moved. `revisit_when` step 2 finds each one either way.
- **To P2-012 (#213).**
  - P2-012 decides the shards, if any, for the nightly and for #107 item 2 using measurements
    from the current runner after the #521 fix.
  - The 28 cases add about 7 min to the nightly's mutation step, at the 15 s per case it averaged at
    `beed5eb`.
- **To #538 item 2 (the runner's import scoping, no row).** Only a result type (`Detach`) enforces
  the rule that an environment must not escape a `withImport` scope. A rank-2, `ST`-style scoped
  token for the environment would stop the environment itself from escaping. #536 left it out to
  stay small, and #537 recorded it.
- **To a later chain row (longer chains, or a second binding constructor).** `impact_through_head_only`
  becomes load-bearing then. Each new premise conjunct of `boundB` adds one case of the
  `binding_*_unchecked` kind. No row exists yet.
- **To this PR's follow-up issue (no row, all minor).**
  - A mutant that drops the changed repo from its own impact
    (`impactGo x es []` → `(impactGo x es []).filter (· != x)`) has no case. It is the inverse of
    Phase 1's `impact_includes_self`. A same-repo direct edge refutes it as well as a binding held at
    home, so it is a Phase 1 gap and not a chain mutant. Runner B refuted it at `3d939da` on an edge
    through its own requirer's repo.
  - The runner reports a case's refutations only for the theorems `breaks=` names. Measured, with
    `lake env lean` on the locked inputs, these cases break more than their `breaks=` names:
    - `bound_key_legs_swapped` also breaks `StatusHonest` on `chain`;
    - `chain_also_direct` also breaks `EdgesNodup` on `twoBindings`;
    - `binding_ident_unchecked` and `provision_kind_unchecked` also break `UnresolvedExact` on their
      inputs;
    - `binding_target_unchecked` also breaks `StatusHonest` on its input.
  - lean4lean rejects some exports that carry string literals but no `Char.ofNat`, while it accepts
    Phase 1's literal `edge` helper elsewhere (T9). Which forms pass is measured per form, not
    understood. A later case author runs `--paranoid` before trusting a form.
  - Runner B's `phantom_record_per_requirement` (`mkEdge fs r r true` per requirement) was not taken.
    Its `why=` says `StatusHonest` does not look at the record. But on `chain` that record is
    `confirmed` while its providing id is the requirement's own, so `StatusHonest` is false too
    (measured). It also breaks Phase 1's `[req, prov]`.
  - `survives=` cannot record an equivalent mutant, which ends `REJECTED, NOT REFUTED`. That is
    correct, but the runner's output does not make it obvious.
  - Two cases are not chain-only on purpose, and only their `why=` and the missing scope pin record
    it.

owner_decisions: none new. The row is class A.
- Settled and followed: O1 on #204, "rule out", which `self_binding_allowed` pins.
- The root's defaults, which the owner can overrule, and none blocks:
  - the base, the grafts and the cuts in the Synthesis decision;
  - running the nightly by dispatch before merge, because only that run has the nightly's shape and
    host;
  - a survivor, should one appear, goes to the owner (exit criterion 3), and none is predicted;
  - the nightly cost of 28 more cases, which P2-012 owns.

## Done when
- [ ] `revisit_when` steps 1 to 5 hold at the head, or the PR body names each re-anchored case with
      its new `find=`
- [ ] all `checks` pass at the head: locally one Lean build at a time and one case per invocation,
      both modes; and the nightly dispatch run
- [ ] every run-level fixture under Design holds, and its measured line is in the PR body
- [ ] the PR body compares the breakers table with `breakers-table` and accounts for each design
      case and its exact `breaks=` set against the merged corpus. It names any omitted cases or
      changed `breaks=` sets, says `Closes #206`, and confirms that the corpus diff adds 56 files
      and that no existing corpus case files changed
- [ ] no `sorry`, no new axioms, no `survives=` case
- [ ] run-log record written (`ops/runs/<UTC date>/P2-005b-builder-<attempt>.json`)

## Appendix: checked text

Each case is two files. The `Refute.lean` is the shared header (A1), then the pin its heading names,
then the body shown, then `end Mitos.Refute`. These are the texts the measured runs used.

### A1. Shared pieces

```lean
import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains
```

The resolver pin goes on every resolver case except `edges_one_per_repo_key` and
`direct_edge_through_set`:

```lean
example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide
```

The impact pin goes on all five impact cases:

```lean
example : Impl.impact [Spec.Adequacy.goodEdge] "sdk" = ["web"] := by decide +kernel
```

A blank line separates the header, the pin and the body. The local theorem for a local input is
called `wfIn`, not `wf`, because `open Mitos.Spec.Adequacy` brings Phase 1's `wf` into scope.

### A2. The 28 cases

#### A2.1 `through_dropped` (resolver pin)

```text
why=Leaves the binding's repo out of a chain edge, so the edge reads as a direct one and impact analysis loses the binding.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=through := [b.repo]
replace=through := []
```

```lean
theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide
```

#### A2.2 `direct_edge_through_set` (no pin)

```text
why=Gives every direct edge the requirer's repo as a chain repo, so an edge with no binding reads as passing through one.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=key := .direct r.id p.id,
replace=key := .direct r.id p.id, through := [r.repo],
```

```lean
theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h [Spec.Adequacy.req, Spec.Adequacy.prov] (by unfold WellFormed; decide)
  revert this
  decide
```

#### A2.3 `bound_edge_from_binding` (resolver pin)

```text
why=Builds the chain edge from the binding fact in place of the requirement, so the edge points from the binding's repo to the provider's.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find={ mkEdge fs r p same with
replace={ mkEdge fs b p same with
```

```lean
theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide
```

#### A2.4 `bound_key_legs_swapped` (resolver pin)

```text
why=Writes the provision's id where the binding's belongs in a chain edge's key, so no edge carries the key of the chain it stands for.
breaks=resolve_sound resolve_complete
file=Mitos/Impl/Resolve.lean
find=.bound r.id b.id p.id
replace=.bound r.id p.id b.id
```

```lean
theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide

theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide
```

#### A2.5 `bound_scope_from_binding` (resolver pin)

```text
why=Takes a chain edge's scope from the binding instead of the requirement, so a test-only requirement bound by a runtime binding reads as a runtime dependency.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=through := [b.repo],
replace=through := [b.repo], scope := b.fact.scope,
```

```lean
def needTest : Located := { needDb with fact := { needDb.fact with scope := .test } }

def fs : List Located := [needTest, bindDb, provDb]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.6 `binding_ident_unchecked` (resolver pin)

```text
why=Applies a binding to every requirement, not only to a requirement of the identity it binds, so an unrelated requirement is reached through someone else's binding.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=| .binds _ => fs.filter (boundB r b)
replace=| .binds i => fs.filter (fun p => r.fact.kind == .requires && p.fact.kind == .provides && p.fact.ident == i && p.fact.ident != r.fact.ident)
```

```lean
def needOther : Located :=
  { needDb with id := 3, repo := "api", fact := { needDb.fact with ident := ⟨"env", "OTHER"⟩ } }

def fs : List Located := [needDb, bindDb, provDb, needOther]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.7 `binding_target_unchecked` (resolver pin)

```text
why=Ignores the identity a binding binds to, so a requirement is reached through its binding at every provision, not only the one it names.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=| .binds _ => fs.filter (boundB r b)
replace=| .binds _ => fs.filter (fun p => r.fact.kind == .requires && b.fact.ident == r.fact.ident && p.fact.kind == .provides && p.fact.ident != r.fact.ident)
```

```lean
def provOther : Located :=
  { provDb with id := 3, fact := { provDb.fact with ident := ⟨"svc", "billing"⟩ } }

def fs : List Located := [needDb, bindDb, provDb, provOther]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.8 `provision_kind_unchecked` (resolver pin)

```text
why=Accepts any fact of the bound identity as the end of a chain, so a requirement of that identity, or another binding, is reached as a provider.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=| .binds _ => fs.filter (boundB r b)
replace=| .binds i => fs.filter (fun p => r.fact.kind == .requires && b.fact.ident == r.fact.ident && p.fact.ident == i && p.fact.ident != r.fact.ident)
```

```lean
def needSvc : Located :=
  { id := 3, repo := "billing", rev := "e", path := "app.env", origin := .extractor "env"
    fact := { kind := .requires, ident := ⟨"svc", "orders-db"⟩, span := ⟨0, 9⟩ } }

def fs : List Located := [needDb, bindDb, needSvc]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : derivations fs = [] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.9 `self_binding_allowed` (resolver pin)

```text
why=Lets a binding from an identity to itself give a requirement a second chain to the provider it already reaches directly, against the owner's ruling on #204.
breaks=resolve_sound
file=Mitos/Impl/Resolve.lean
find=| .binds _ => fs.filter (boundB r b)
replace=| .binds i => fs.filter (fun p => r.fact.kind == .requires && b.fact.ident == r.fact.ident && p.fact.kind == .provides && p.fact.ident == i)
```

```lean
example : derivations selfBound = [Chain.direct Spec.Adequacy.req Spec.Adequacy.prov] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h selfBound wfSelfBound
  revert this
  decide
```

#### A2.10 `chain_also_direct` (resolver pin)

```text
why=Writes a direct record for every end of a requirement, so a provision reached only through a binding also gets a record under a direct key that no derivation has, which AssumptionsExact and StatusHonest do not look at.
breaks=resolve_sound resolve_retract_exact
file=Mitos/Impl/Resolve.lean
find=direct.map (fun p => mkEdge fs r p (summary.accepts p.id))
replace=allEnds.map (fun p => mkEdge fs r p (summary.accepts p.id))
```

```lean
theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h chain bindDb.origin wfChain (.direct 0 2)
  revert this
  decide
```

#### A2.11 `bound_edges_dropped` (resolver pin)

```text
why=Resolves a requirement's direct providers only, so a requirement met through a binding has no edge and is not listed as unresolved.
breaks=resolve_complete resolve_total
file=Mitos/Impl/Resolve.lean
find=groups.flatMap (fun (b, ps) => ps.map fun p => mkBoundEdge fs r b p (summary.accepts p.id))
replace=[]
```

```lean
theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide

theorem resolve_total : ¬ Spec.Total Impl.resolve := by
  intro h
  have := h chain wfChain needDb (by simp [chain]) rfl
  revert this
  decide
```

#### A2.12 `binding_same_repo_skipped` (resolver pin)

```text
why=Skips a binding that lives in the requirement's own repo, so a chain through it has no edge and its requirement is listed as unresolved.
breaks=resolve_complete resolve_unresolved_exact
file=Mitos/Impl/Resolve.lean
find=let groups := fs.map fun b => (b, boundProviders fs r b);
replace=let groups := fs.map fun b => (b, if b.repo == r.repo then [] else boundProviders fs r b);
```

```lean
def bindHome : Located := { bindDb with repo := "web" }

def fs : List Located := [needDb, bindHome, provDb]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide

theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h fs wfIn 0
  revert this
  decide
```

#### A2.13 `edges_one_per_repo_key` (no pin)

```text
why=Keeps one edge for each pair of repos, identity and scope, so two bindings that reach one provider in different repos leave a single edge.
breaks=resolve_complete resolve_retract_exact
file=Mitos/Impl/Resolve.lean
find=edges := rows.flatMap Prod.fst
replace=edges := (rows.flatMap Prod.fst).foldl (fun acc e => if acc.any (fun a => a.repoKey == e.repoKey) then acc else acc ++ [e]) []
```

```lean
example : (Impl.resolve Spec.Adequacy.twoProvisions).edges.map Edge.key = [.direct 0 1] := by decide

theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h twoBindings wfTwoBindings
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h twoBindings bindDb.origin wfTwoBindings (.bound 0 3 2)
  revert this
  decide
```

#### A2.14 `unresolved_ignores_bound_ends` (resolver pin)

```text
why=Lists a requirement as unresolved when it has no direct provider, even if a chain reaches one.
breaks=resolve_unresolved_exact
file=Mitos/Impl/Resolve.lean
find=if isRequirement r && allEnds.isEmpty then [r.id] else []
replace=if isRequirement r && direct.isEmpty then [r.id] else []
```

```lean
theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h chain wfChain 0
  revert this
  decide
```

#### A2.15 `dangling_binding_hides_unresolved` (resolver pin)

```text
why=Treats a binding of a requirement's identity as handling it, so a requirement whose binding reaches no provision is not listed as unresolved.
breaks=resolve_unresolved_exact resolve_total
file=Mitos/Impl/Resolve.lean
find=if isRequirement r && allEnds.isEmpty then [r.id] else []
replace=if isRequirement r && allEnds.isEmpty && !(fs.any fun b => b.fact.ident == r.fact.ident && b.fact.kind != .requires && b.fact.kind != .provides) then [r.id] else []
```

```lean
def fs : List Located := [needDb, bindDb]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : derivations fs = [] := by decide

theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h fs wfIn 0
  revert this
  decide

theorem resolve_total : ¬ Spec.Total Impl.resolve := by
  intro h
  have := h fs wfIn needDb (by simp [fs]) rfl
  revert this
  decide
```

#### A2.16 `binding_origin_forgotten` (resolver pin)

```text
why=Leaves the binding's origin out of a chain edge's assumptions, so an AI-proposed binding is not listed, and retracting a binding leaves its edge in place.
breaks=resolve_assumptions_exact resolve_retract_exact
file=Mitos/Impl/Resolve.lean
find=(assumptionsOf r p).insert b.origin
replace=assumptionsOf r p
```

```lean
example : (Impl.resolve chainAI).edges.map Edge.status = [.confirmed] := by decide

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h chain bindDb.origin wfChain (.bound 0 1 2)
  revert this
  decide
```

#### A2.17 `assumes_pool_all_bindings` (resolver pin)

```text
why=Lists the origins of every binding of the requirement's identity under each chain edge, so retracting one binding removes the chain that goes through another.
breaks=resolve_assumptions_exact resolve_retract_exact
file=Mitos/Impl/Resolve.lean
find=assumes := assumptionsVia r b p,
replace=assumes := (assumptionsVia r b p ++ (fs.filter (fun c => c.fact.ident == r.fact.ident && c.fact.kind != .requires && c.fact.kind != .provides)).map (·.origin)).eraseDups,
```

```lean
theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h twoBindings wfTwoBindings
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h twoBindings bindStaging.origin wfTwoBindings (.bound 0 1 2)
  revert this
  decide
```

#### A2.18 `binding_origin_duplicated` (resolver pin)

```text
why=Appends the binding's origin without checking that it is already listed, so a requirement and a binding from one extractor name that extractor twice.
breaks=resolve_assumptions_nodup
file=Mitos/Impl/Resolve.lean
find=(assumptionsOf r p).insert b.origin
replace=assumptionsOf r p ++ [b.origin]
```

```lean
def bindSameOrigin : Located := { bindDb with origin := needDb.origin }

def fs : List Located := [needDb, bindSameOrigin, provDb]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_assumptions_nodup : ¬ Spec.AssumptionsNodup Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.19 `bound_status_ignores_binding` (resolver pin)

```text
why=Judges a chain edge's status by the requirement's and the provision's origins only, so an AI-proposed binding leaves it confirmed.
breaks=resolve_status_honest
file=Mitos/Impl/Resolve.lean
find=status := statusOf fs r p (assumptionsVia r b p) same }
replace=status := statusOf fs r p (assumptionsOf r p) same }
```

```lean
def s (cs : List Char) : String := String.ofList cs

def idSvc : Identity := ⟨s ['s'], s ['o']⟩

def loc (id : Nat) (repo : String) (kind : FactKind) (ident : Identity) (origin : Assumption) :
    Located :=
  { id, repo, rev := s [], path := s [], origin, fact := { kind, ident, span := ⟨0, 0⟩ } }

def idEnv : Identity := ⟨s ['e'], s ['d']⟩

def nReq : Located := loc 0 (s ['w']) .requires idEnv (.extractor (s ['x']))

def nBind : Located :=
  loc 1 (s ['d']) (.binds idSvc) idEnv (.humanDeclaredOutsideSource (s ['h']))

def nProv : Located := loc 2 (s ['o']) .provides idSvc (.extractor (s ['y']))

def nBindAI : Located := { nBind with origin := .ai (s ['g']) }

def fs : List Located := [nReq, nBindAI, nProv]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.20 `bound_always_inferred` (resolver pin)

```text
why=Marks every chain edge inferred, so a chain of confirmed facts that reaches one provider is never confirmed.
breaks=resolve_status_honest
file=Mitos/Impl/Resolve.lean
find=status := statusOf fs r p (assumptionsVia r b p) same }
replace=status := .inferred }
```

```lean
def s (cs : List Char) : String := String.ofList cs

def idSvc : Identity := ⟨s ['s'], s ['o']⟩

def loc (id : Nat) (repo : String) (kind : FactKind) (ident : Identity) (origin : Assumption) :
    Located :=
  { id, repo, rev := s [], path := s [], origin, fact := { kind, ident, span := ⟨0, 0⟩ } }

def idEnv : Identity := ⟨s ['e'], s ['d']⟩

def nReq : Located := loc 0 (s ['w']) .requires idEnv (.extractor (s ['x']))

def nBind : Located :=
  loc 1 (s ['d']) (.binds idSvc) idEnv (.humanDeclaredOutsideSource (s ['h']))

def nProv : Located := loc 2 (s ['o']) .provides idSvc (.extractor (s ['y']))

def fs : List Located := [nReq, nBind, nProv]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.21 `status_counts_derivations` (resolver pin)

```text
why=Confirms an edge only when its requirement has exactly one derivation, so two bindings that reach the same provider leave both edges inferred.
breaks=resolve_status_honest
file=Mitos/Impl/Resolve.lean
find=rest.all (·.id == p.id)
replace=rest.isEmpty
```

```lean
def s (cs : List Char) : String := String.ofList cs

def idSvc : Identity := ⟨s ['s'], s ['o']⟩

def loc (id : Nat) (repo : String) (kind : FactKind) (ident : Identity) (origin : Assumption) :
    Located :=
  { id, repo, rev := s [], path := s [], origin, fact := { kind, ident, span := ⟨0, 0⟩ } }

def idEnv : Identity := ⟨s ['e'], s ['d']⟩

def nReq : Located := loc 0 (s ['w']) .requires idEnv (.extractor (s ['x']))

def nBind : Located :=
  loc 1 (s ['d']) (.binds idSvc) idEnv (.humanDeclaredOutsideSource (s ['h']))

def nProv : Located := loc 2 (s ['o']) .provides idSvc (.extractor (s ['y']))

def nBindOther : Located :=
  { nBind with id := 3, repo := s ['t'], origin := .humanDeclaredOutsideSource (s ['i']) }

def fs : List Located := [nReq, nBind, nProv, nBindOther]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2, .bound 0 3 2] := by decide

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.22 `status_ignores_bound_ends` (resolver pin)

```text
why=Asks only the direct providers whether a requirement reaches one provider, so a requirement with a direct provider and a chain to another is confirmed.
breaks=resolve_status_honest
file=Mitos/Impl/Resolve.lean
find=let summary := summarizeEnds allEnds;
replace=let summary := summarizeEnds direct;
```

```lean
def s (cs : List Char) : String := String.ofList cs

def idSvc : Identity := ⟨s ['s'], s ['o']⟩

def loc (id : Nat) (repo : String) (kind : FactKind) (ident : Identity) (origin : Assumption) :
    Located :=
  { id, repo, rev := s [], path := s [], origin, fact := { kind, ident, span := ⟨0, 0⟩ } }

def idNpm : Identity := ⟨s ['n'], s ['k']⟩

def fReq : Located := loc 0 (s ['w']) .requires idNpm (.extractor (s ['x']))

def fProv : Located := loc 1 (s ['k']) .provides idNpm (.extractor (s ['x']))

def fBind : Located := loc 2 (s ['d']) (.binds idSvc) idNpm (.humanDeclaredOutsideSource (s ['h']))

def fSvc : Located := loc 3 (s ['o']) .provides idSvc (.extractor (s ['y']))

def fs : List Located := [fReq, fProv, fBind, fSvc]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.direct 0 1, .bound 0 2 3] := by decide

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide
```

#### A2.23 `bound_edges_duplicated` (resolver pin)

```text
why=Scans the facts twice for bindings, so every chain edge is emitted twice.
breaks=resolve_edges_nodup
file=Mitos/Impl/Resolve.lean
find=let groups := fs.map fun b => (b, boundProviders fs r b);
replace=let groups := (fs ++ fs).map fun b => (b, boundProviders fs r b);
```

```lean
theorem resolve_edges_nodup : ¬ Spec.EdgesNodup Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide
```

#### A2.24 `impact_through_ignored` (impact pin)

```text
why=Fires an edge only on its provider's repo, so a change in the repo that holds a binding does not reach the requirement that uses it.
breaks=impact_correct
file=Mitos/Impl/Impact.lean
find=e.through.any fun b => b == x || seen.contains b
replace=false
```

```lean
theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h [chainEdge] "deploy" "web").mpr
    (.through (e := chainEdge) (by decide) (by decide))
  exact absurd hc (by decide +kernel)
```

#### A2.25 `impact_through_not_transitive` (impact pin)

```text
why=Lets a binding's repo start a chain edge but not continue one, so a requirement behind a binding is missed when the change reaches the binding's repo through other edges.
breaks=impact_correct
file=Mitos/Impl/Impact.lean
find=e.through.any fun b => b == x || seen.contains b
replace=e.through.any fun b => b == x
```

```lean
def edge (src dst : String) : Edge :=
  { requiringRepo := src, providingRepo := dst, ident := ⟨"npm", "lib"⟩, scope := .runtime,
    key := .direct 0 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "deploy" "a", chainEdge]

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h es "a" "web").mpr
    (.trans (y := "deploy") (.step (e := edge "deploy" "a") (by decide))
      (.through (e := chainEdge) (by decide) (by decide)))
  exact absurd hc (by decide +kernel)
```

#### A2.26 `impact_binding_repo_affected` (impact pin)

```text
why=Adds the repos of a binding to the affected list whenever its edge fires, so a change in a provider reports the repo that holds the binding too.
breaks=impact_correct
file=Mitos/Impl/Impact.lean
find=impactGo x (rest.erase e) (e.requiringRepo :: seen)
replace=impactGo x (rest.erase e) (e.requiringRepo :: e.through ++ seen)
```

```lean
theorem affects_chainEdge {x y : String} (h : Affects [chainEdge] x y) :
    y = "web" ∧ (x = "orders" ∨ x = "deploy") := by
  induction h with
  | step he =>
    obtain rfl := List.mem_singleton.mp he
    simp [chainEdge]
  | through he hb =>
    obtain rfl := List.mem_singleton.mp he
    simp [chainEdge] at hb ⊢
    exact Or.inr hb
  | trans _ _ ih1 ih2 =>
    rcases ih2.2 with h | h <;> simp [ih1.1] at h

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hy := (h [chainEdge] "orders" "deploy").mp (by decide +kernel)
  have := (affects_chainEdge hy).1
  revert this
  decide
```

#### A2.27 `impact_through_head_only` (impact pin)

```text
why=Reads only the first repo a chain passes through, so a change in a later repo of a longer chain does not reach the requirement.
breaks=impact_correct
file=Mitos/Impl/Impact.lean
find=e.through.any fun b => b == x || seen.contains b
replace=(e.through.take 1).any fun b => b == x || seen.contains b
```

```lean
def s (cs : List Char) : String := String.ofList cs

def longEdge : Edge :=
  { requiringRepo := s ['w'], providingRepo := s ['o'], ident := ⟨s ['n'], s ['k']⟩,
    scope := .runtime, key := .direct 0 0, assumes := [], status := .confirmed,
    through := [s ['d'], s ['m']] }

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h [longEdge] (s ['m']) (s ['w'])).mpr
    (.through (e := longEdge) (by decide) (by decide))
  exact absurd hc (by decide +kernel)
```

#### A2.28 `impact_through_bypasses_seen` (impact pin)

```text
why=Lets an edge fire on its binding's repo even when its requirer is already listed, so a repo reached by a provider and by a binding appears twice.
breaks=impact_nodup
file=Mitos/Impl/Impact.lean
find=!seen.contains e.requiringRepo
replace=(!seen.contains e.requiringRepo || e.through.any fun b => b == x)
```

```lean
def edge (src dst : String) : Edge :=
  { requiringRepo := src, providingRepo := dst, ident := ⟨"npm", "lib"⟩, scope := .runtime,
    key := .direct 0 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "web" "deploy", chainEdge]

theorem impact_nodup : ¬ Spec.ImpactNodup Impl.impact := by
  intro h
  have hn := h es "deploy"
  revert hn
  decide +kernel
```

### A3. The phase1-agree probe (design-time evidence)

This is a scratch file. Run it with `lake env lean` from `core/` of a workspace that holds the mutated
`Impl/` files, and compare its output with the same run on the unmutated head:

```lean
import Mitos.Impl.Resolve
import Mitos.Impl.Impact
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains
def show' (fs : List Located) : String :=
  s!"{repr (Impl.resolve fs).edges}|{(Impl.resolve fs).unresolved}"
#eval show' [req, prov]
#eval show' twoProvisions
#eval show' [req]
#eval show' [prov]
#eval show' [req, provAI]
#eval Impl.impact [goodEdge, { goodEdge with requiringRepo := "api", providingRepo := "web" }] "sdk"
```

Measured at `3d939da`, with one mutant applied at a time to a copy of `core/`, 26 of the 28 cases
print byte for byte what the unmutated head prints:
- 22 as runner B measured them;
- the three edited `boundB` texts, which change only the `.binds` arm, which no probe input reaches
  (runner B measured their first texts);
- `chain_also_direct`, measured by the judge.

The other two differ:
- `edges_one_per_repo_key` differs on `twoProvisions`, as intended.
- `direct_edge_through_set` differs by construction, because its input is the probe's first.

## Rationale

### Problem
P2-001b changes what the twelve theorems mean for inputs with a `binds` fact. The 44 existing cases
are all Phase 1 faults, and none of their inputs has a binding. So the row must show that the
theorems still see a wrong chain resolver. The risk is not a failing proof. It is a row that counts
cases that pin nothing:
- a mutant that breaks every input;
- an anchor on code the resolver never runs;
- a refutation on an input without a chain;
- an edit that injects two faults;
- a text that passes by default and fails the nightly's `--paranoid`.

Every chain clause needs one case whose fault is that clause alone, and each case must pass the run
the nightly makes.

### Shape
The unit is a fault class, not a theorem. Each case injects one fault, has one `why=`, and is named
for its fault. The theorems a case refutes are a consequence that the runner checks, so the breakers
table is a result, not a target. The faults come from three places:
- each premise and field of the chain: what `boundB`, `Chain.bound`, `Chain.through` and the four
  `Edge` fields say;
- each statement's two directions: `Sound` and `Complete`, and `UnresolvedExact`, `AssumptionsExact`
  and `StatusHonest` both ways;
- the adversarial inputs a plugin can emit (T8).

The locked fixtures are the inputs on purpose. P2-001b already proved their `derivations`, so an
input's chain is a locked fact and not a claim in a comment. The five literal-free cases are the
exception (T9), and they pin their local inputs with an `example`.

The matrix by theorem lists the Phase 1 and #311 breakers, the chain breakers added, and the clause
each chain case exercises:

| Theorem | Phase 1 + #311 | Chain breakers added | Clauses the chain cases pin |
|---|---|---|---|
| `resolve_sound` | 4 | 10 | key, repo-level fields, `through` and its empty default, scope, each premise of `boundB` (identity, target, provision kind, self-binding), no record under a key that no chain has |
| `resolve_complete` | 3 | 4 | every chain has a record: with the right key, at all, in both repos of option C, in the requirer's own repo |
| `resolve_unresolved_exact` | 4 | 3 | a chain resolves its requirement; a binding with no provision does not |
| `resolve_total` | 3 | 2 | a chain's requirement has an edge or is listed |
| `resolve_assumptions_exact` | 2 | 2 | the binding's origin is listed; no other binding's origin is |
| `resolve_status_honest` | 4 | 4 | an AI binding; a chain can be confirmed; two derivations to one provider confirm; a direct and a bound provider differ |
| `resolve_retract_exact` | 3 | 4 | retracting a binding removes its own chain only, and with it a record that no chain has |
| `impact_correct` | 4 | 4 | `through` reaches the requirer, transitively, in one direction, and for longer chains |
| `resolve_edges_nodup` | 1 | 1 | a chain edge once |
| `resolve_unresolved_nodup` | 1 | 0 | no chain source of duplicates |
| `resolve_assumptions_nodup` | 1 | 1 | one origin for the requirement and the binding |
| `impact_nodup` | 1 | 1 | a repo reached by two kinds of leg |

### Decisions that depart from a plain reading of the row
A plain reading, "add mutants until each breaks a theorem", falls short in six places:
1. P2-001b's candidate (c) is a dead anchor. A builder who copied it would get `REJECTED, NOT
   REFUTED`.
2. "Breaks at least one theorem" is not the aim. The scope pin and the derivations pin make the chain
   part a check the runner makes.
3. Two clauses of the status rule have no locked fixture: a chain that comes out `confirmed`, and two
   bindings that reach one provider and both come out `confirmed`. The statement pins both for every
   input, so the spec is not weaker. But `bound_always_inferred` and `status_counts_derivations` are
   the only checks that an implementation does the same. The plan's refined rule ("a direct and a
   bound derivation to the same provider is still confirmed") cannot be reached after the O1 ruling.
   The direct and the bound chain of one requirement now always end at different provisions, because
   a bound provision's identity differs from the requirement's.
4. A case counts only when the real runner says `REFUTED` in the nightly's mode. `lake env lean`
   accepted every first text. The Lean default kernel rejected three status texts, and lean4lean
   rejected one impact text under `--paranoid` only (T9).
5. Memory is measured on the full corpus using the current runner (Design).
6. The two traps P2-001b's build found the hard way are made fixtures, so the next edit to
   `EndSummary` or `fires` cannot repeat them unseen: the lint refuses `inductive` in `Impl/`, and
   #311 moved two anchors.

### Design red flags, screened
- **Hand-synced list.**
  - The scope pin is one of two short `example`s, copied into 26 files. The import rule allows a case only
    `Mitos.Core` and `Mitos.Impl`, and the row may not write `eval/mutants/Mutants/`, so a shared
    module cannot hold it. It names locked fixtures, not literals, so only a change in the resolver's
    Phase 1 behaviour moves it, and then every case fails loudly.
  - The `String.ofList` input blocks repeat in five files, as in Phase 1's four. Each has a
    derivations pin.
  - The breakers table here is checked against the runner's own table (`breakers-table`).
- **Two ways to do one task.** One refutation route per statement kind: `h fs wf; revert this;
  decide`, then `decide +kernel` for impact and `String.ofList` inputs where a replay kernel needs
  them. Design A's route through the fixture theorems (`sound_records_the_binding h`) is dropped, so
  a builder copying a case finds one form.
- **Meaning only in prose.** "Chain-only" was a claim in `why=` lines. The scope pin makes it a
  check. The two cases without the pin are marked in the table's Pin column.
- **Information leakage.** The anchors depend on P2-001b's text. Mutants are edits of that text, so
  this cannot be avoided. `revisit_when` step 2 finds every moved anchor in one `--prepare` run.
- Shallow module, temporal decomposition, split ownership and importable internals do not apply.
  The row adds data files only, and the lint keeps case imports inside `Mitos.Core` and `Mitos.Impl`.

### Tradeoffs accepted
- The cases depend on P2-001b's fixture names and on its resolver text. A rename is loud (the lint or
  the build fails) and cheap (one `open` line, or a re-anchor).
- Four cases inline `boundB` into the `.binds` arm to drop one conjunct each. They test the resolver
  against the spec's premise. They would not notice a conjunct missing from the spec itself. The
  `Spec.Adequacy` fixtures and the owner's review of `boundB` cover that.
- Five cases do not use the locked fixtures (T9). Their inputs are local copies that can drift from
  the fixtures, and their derivations pins and the review of `Spec.Adequacy` keep them honest.
- Two cases are not chain-only (`edges_one_per_repo_key`, `direct_edge_through_set`). P2-001a's
  deferral and Sound's new `through` conjunct hand them to this row.
- The 28 cases were estimated to add about 7 min to the nightly.

### Alternatives considered
- **Design A's eight cases (smallest surface).** Fewer files, two new `breaks=` sets, and a
  `Spec.Chains` namespace the branch does not have. It leaves `boundB`'s premises, the
  `through` field's transitivity and direction, the `assumes` pooling, two status clauses and the
  nodup statements without a chain breaker. Exit criterion 3 asks that each chain mutant breaks a
  theorem, and the matrix shows which clauses those eight would leave unchecked. Rejected as the
  base. Its V1 case is grafted.
- **One case per theorem and clause cell.** Rejected: several cells share one fault, and a fault with
  one `why=` is easier to review.
- **Inline copies of every input, as Phase 1 does.** Rejected where the input is a locked fixture,
  because a copy can drift from the fixture the owner approved. Local inputs stay where the fault
  needs an input no fixture has, or a kernel needs a literal-free one.
- **Allow `inductive` in the lint.** Rejected: `eval/mutants/Mutants/` is outside the row's cell, and
  a wider allow-list widens what the 15 `rejects=lint` cases pin.
- **Record an equivalent mutant as `survives=`.** Not possible: it needs an accepted gate run, and the
  proofs name the code the mutant changed.
- **Run every case in one local invocation, in shards (runner B).** Dropped for the dispatch run. The
  shared cgroup here cannot tell a case's cost from a neighbour's, and only GitHub's runner has the
  nightly's shape and memory.

### Open questions and risks
- Changes to the shared lines in D4 can move several anchors. `revisit_when` step 2 finds them in
  one `--prepare` run.
- lean4lean's treatment of string literals is measured per form, not understood. Every new text
  runs `--paranoid` before it counts.

### Implementation
#547 merged all 28 cases with the exact `breaks=` sets from Appendix A2, retaining all 36 declared
refutation claims. Its review recorded that each of the 28 refutation files passed against its
mutant and failed against the unmutated control.
[Review catch-up](https://github.com/kitimark/mitos/pull/547#issuecomment-7061038947)

### Synthesis decision
The root's default, recorded here with its reasons. The base is Design B (adversarial).
- B was built against the branch head `3d939da` and the real runner. It used the branch's
  `Spec.Adequacy` namespace (P2-001b's D2 fallback).
- B pins every clause a chain extends, with data files only and no runner change. Design A was built
  on the plan-time text with `Spec.Chains` names and a hand-laid comparator workspace, and covers
  eight clauses.

Grafted from A:
- `chain_also_direct` replaces B's `phantom_record_per_requirement` for #276 V1. A's case is
  chain-only, and its scope pin holds. On `chain` it leaves `AssumptionsExact` and `StatusHonest`
  true while `Sound` and `RetractExact` fail, which is V1 itself. B's phantom also breaks
  `StatusHonest`, against its own `why=`, and it breaks Phase 1's `[req, prov]` (both measured).
- A's name check, as `revisit_when` step 4.
- A's survey method, deciding each statement on the locked inputs. It found the extra breaks and
  the double faults listed above.

The judge's changes, each measured at `3d939da`:
- The three inlined `boundB` texts keep O1's conjunct, so each drops one premise, not two (T11).
- `impact_through_head_only` is rewritten literal-free. B's text fails lean4lean under
  `--paranoid`, which would have turned the nightly red (T9).
- `impact_self_through_dropped` moves to the follow-up issue as a Phase 1 gap.
- The `runner-peak` and `nightly-dispatch` fixtures check the current runner on the full corpus.

All 28 final texts were refuted one case per invocation, default and `--paranoid`, and each fails
against the unmutated core. The red-flag screen leaves one forced copy, the scope pin, which the
import rule makes unavoidable and which fails loudly if it goes stale.
