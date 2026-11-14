# tasks/P2-005a-migrate-mutants.md

phase: 2
goal: Every Phase 1 mutant case keeps its verdict on keyed edges, with no `find=`, `breaks=`, `survives=`, `rejects=` or `why=` line changed.
statement: none locked (tooling task); Mutants.total_of_complete_unresolved and Mutants.retract_of_sound_complete_assumptions keep their statements
touches: eval/mutants/Mutants/Implied.lean; Refute.lean in 15 case directories and the replace= text of 5 mutant files (the table under Design); this file, ops/runs/
must_not_touch: every find=, breaks=, survives=, rejects= and why= line; the 26 other case directories; eval/mutants/Main.lean and the rest of eval/mutants/Mutants/; new case directories (P2-005b); gate/, eval/cheats/, .github/
checks: eval/mutants build, the full mutant run (default and --paranoid)
budget: inside P2-001a's (about 15 iterations · 4h wall · 1.5M tokens of it)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-005a in `plan/phase-2.md`, issue #205. It lands in P2-001a's PR (#203,
  `tasks/P2-001a-keyed-edges.md`), so no mutant is dropped and the nightly run stays green.
- The edge key becomes a `Derivation` there
  ([#156 sketch](https://github.com/kitimark/mitos/issues/156#issuecomment-6795051235),
  [owner decisions](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085)), which
  breaks every `Edge` literal and every key in `eval/mutants/`.
- How the runner judges a case is in `tasks/P1-006-mutation-testing.md`. On `main` the run ends
  with all 42 cases as expected: 22 refuted, no known gap, 20 cheat cases rejected.
- Mutants run nightly only, so this row's evidence is a local run.
- Design written at plan time with P2-001a's (its Rationale, Synthesis decision). The table below
  was checked against every `mutant` and `Refute.lean` file on `main` at e5bd16c, by reading. No
  case was run.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. Types and statements are P2-001a's. This block states only the migration.

revisit_when: re-check the table after #231 merges, because its cases would carry `Edge` literals
and the counts would move. Otherwise it follows P2-001a's.

modules:
- `eval/mutants/Mutants/Implied.lean`: which statements follow from which. 55 → about 45 lines. In
  place. `wellFormed_retract` leaves for the core.
- `eval/mutants/cases/<case>/Refute.lean` and `mutant`: one case each, edited by the rules below.

types: none of its own. A `Refute.lean` file names `Derivation.direct`, `Chain.direct` and
`derivations` from the core.

statements: `Implied.lean` keeps both statements, and `contains_false_iff` stays. The new proofs
use only P2-001a's laws, so P2-001b's `bound` rule does not change them.
- `total_of_complete_unresolved`: split on whether some derivation starts at `r`. If one does,
  `Complete` gives an edge with its key and `derivations_key_ends` turns that into
  `e.requiringFactId = r.id`. If none does, `UnresolvedExact` lists `r`. A draft, not built:

```lean
theorem total_of_complete_unresolved {R : Resolver} (hc : Spec.Complete R)
    (hu : Spec.UnresolvedExact R) : Spec.Total R := by
  intro fs wf r hr hk
  by_cases h : ∃ c ∈ derivations fs, c.requirement.id = r.id
  · obtain ⟨c, hcm, hcr⟩ := h
    obtain ⟨e, he, hkey⟩ := hc fs wf c hcm
    exact .inl ⟨e, he, by rw [Edge.requiringFactId, hkey, (derivations_key_ends hcm).1, hcr]⟩
  · exact .inr ((hu fs wf r.id).mpr ⟨r, hr, rfl, hk, fun c hcm hcr => h ⟨c, hcm, hcr⟩⟩)
```

- `retract_of_sound_complete_assumptions`: `Sound` names the edge's chain,
  `mem_derivations_retract` moves the chain between `fs` and `retract a fs`, `AssumptionsExact`
  turns `a ∉ c.origins` into `a ∉ e.assumes` and back, and `Complete` gives the edge on the other
  side. No injectivity is needed.
- The library builds with `warningAsError`, so an unused name or `simp` argument fails it.

### The migration

No anchor moves. The 21 distinct `find=` texts were checked against the new
`core/Mitos/Impl/Resolve.lean`: its only changed line is line 17
(`requiringFactId := r.id, providingFactId := p.id,`), which no `find=` text holds, and each text
still occurs exactly once. `Impl/Impact.lean` and the first line of `Proofs/Resolve/Basic.lean`
do not change.

Rewrite rules:
- R1, an `Edge` literal: `requiringFactId := M, providingFactId := N` becomes
  `key := .direct M N`.
- R2, a key passed to `RetractExact`: `(M, N)` becomes `(.direct M N)`.
- R3, `AssumptionsExact` of the mutant's own resolver: the `have` keeps only its first two
  arguments, `have := h fs (by unfold WellFormed; decide)`. `revert this` and `decide` stay.
- R4, `AssumptionsExact` of a bogus resolver: after the edge and its membership proof, the
  arguments `r hr p hp rfl rfl a` become `(Chain.direct r p) (by decide) rfl`, and the closing
  `simp [...] at this` becomes `revert this` and `decide`.
- R5, `Sound` at the empty list: the closing `simp at this` becomes `simp [derivations] at this`.
- R6, the copy of the implementation: `mkEdge` in the `replace=` text takes the same one-line
  change as `core/Mitos/Impl/Resolve.lean`.

R4 on `cheat_hide_gap`, as an example:

```lean
theorem Mitos.Refute.resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h [Mitos.Refute.loc 0 "a" .requires, Mitos.Refute.loc 1 "b" .provides]
    (by unfold WellFormed; decide) Mitos.Refute.bogus (List.mem_singleton_self _)
    (Chain.direct (Mitos.Refute.loc 0 "a" .requires) (Mitos.Refute.loc 1 "b" .provides))
    (by decide) rfl
  revert this
  decide
```

| Case | `Refute.lean` | `replace=` text |
|---|---|---|
| `assumptions_branches_swapped`, `requirer_origin_forgotten` | R2, R3 | |
| `first_fact_skipped` | R2 (`(1, 2)`) | |
| `impact_direct_only`, `impact_reversed`, `impact_skips_first_edge` | R1 in `edge` | |
| `cheat_hide_gap`, `cheat_impl_imports_case`, `cheat_namespace_shadow`, `cheat_own_hole` | R1, R4 | |
| `cheat_impl_run_cmd`, `cheat_impl_shadow_resolve`, `cheat_include_str`, `cheat_include_str_first` | R1, R4 | R1 |
| `cheat_private_hole` | R1, R5 | |
| `cheat_proofs_own_hole` | no such file | R6 |

The other 26 cases keep every byte:
- sixteen bug cases: `ai_ignored`, `all_confirmed`, `assumptions_dedupe_dropped`,
  `edges_duplicated`, `first_provider_only`, `ident_kind_ignored`, `impact_includes_self`,
  `kind_unchecked`, `provider_scope`, `same_repo_skipped`, `src_dst_swapped`,
  `status_any_not_all`, `status_requirer_only`, `unresolved_dropped`, `unresolved_inverted`,
  `unresolved_lists_provisions`. Each refutation was read against the restated statement it
  names, at its own input, and still holds;
- ten cheat cases: `cheat_impl_macro`, `cheat_impl_macro_gap`, `cheat_impl_shadow_gap`,
  `cheat_impl_shadow_nobug`, `cheat_impl_shadow_theorem`, `cheat_namespace_scoped`,
  `cheat_native_decide`, `cheat_open_scoped`, `cheat_refute_macro`, `cheat_with_decl_name`.

The cheat cases built on `assumptions_dedupe_dropped` still say the truth: listing an origin twice
meets `AssumptionsExact`, which compares what the lists hold.

If a replay kernel rejects a `decide` that Lean accepts, the fallbacks in order are: strings
written with `String.ofList`, as the four status cases do; `decide +kernel`, as the impact cases
do; then a proof that names the edge and the chain and closes with `simp`.

reuse:
- P2-001a's laws `derivations_key_ends` and `mem_derivations_retract`, and
  `Mitos.wellFormed_retract`.
- The runner as it is: `mitos-mutants`, `--prepare`, the logs in `.lake/mutants/`.

fixtures:
- `implied-builds`: `lake --dir eval/mutants build`.
- `all-cases-as-expected`: `lake --dir eval/mutants exe mitos-mutants` ends with all 42 cases as
  expected, 22 refuted, no known gap, 20 cheat cases rejected. The same with `--paranoid`.
- `breakers-table-unchanged`: the runner's "CHALLENGE THEOREM / BROKEN BY" table equals `main`'s.
- `cheat-evidence-unchanged`: the evidence line under each cheat case equals `main`'s, from one
  default run on `main` or the latest nightly output. A line that names `RefuteCase.lean` means
  the refutation no longer elaborates. A case rejected at the refutation run would then pass for
  the wrong reason, and pin nothing.
- `cheat-refutations-elaborate`: each of the nine migrated cheat `Refute.lean` files elaborates
  over its mutated core. No run shows this for seven of them, so it is checked once by hand, one
  build at a time, outside the repository:
  - `cheat_namespace_shadow` and `cheat_own_hole` (`rejects=refutation`) show it in their own run;
  - `cheat_hide_gap` and `cheat_private_hole` (`rejects=holes`): build `Mitos.Proofs.RefuteCase`
    in the workspace that `mitos-mutants --prepare` writes;
  - the five the lint refuses (`cheat_impl_imports_case`, `cheat_impl_run_cmd`,
    `cheat_impl_shadow_resolve`, `cheat_include_str`, `cheat_include_str_first`): apply the case's
    edits to a scratch copy of `core/` and build the same module there.
- `no-anchor-moved`: this prints nothing:
  `git diff origin/main -- eval/mutants/cases | grep -E '^[-+](find|breaks|survives|rejects|why)='`
- `no-old-fields`: this prints nothing:
  `grep -rn 'requiringFactId := \|providingFactId := ' core eval`

cut_line: ships the 16 migrated cases and `Implied.lean`. No case is added, dropped or relabelled.

deferrals:
- To P2-005b (#206): new mutants, the chain mutants and the one-edge-per-repo-key mutant that
  P2-001a's task file names.
- From #231: its two cases (`unresolved_duplicated`, `impact_repeats_repo`) join the table only if
  #231 merges first. An `Edge` literal in them takes R1, and the counts become 44 cases.
- To P2-012 (#213): mutants on PRs that touch `core/` (#107 items 2 and 3).

owner_decisions: none. No `breaks=`, `survives=` or `rejects=` line changes, so no ruling under
exit criterion 3 is needed.

## Done when
- [ ] all `checks` pass locally, one Lean build at a time
- [ ] every fixture above holds, and the run's last line and breakers table are in the PR body
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
