# tasks/P1-006-mutation-testing.md

phase: 1
goal: Every mutant of the resolver and impact analysis in `eval/mutants/` that names theorems
  (`breaks=`) breaks each of them, shown by the sandboxed `lake comparator`; a realistic mutant the
  theorems miss is kept as a known gap (`survives=`) for the owner; the nightly job checks both
  (Phase 1 exit criterion 3, which stays open while a known gap does).
statement: none (tooling task); proves the runner's own logic in `eval/mutants/Mutants/`
touches: eval/mutants/, .github/workflows/nightly.yml, tasks/P1-006-mutation-testing.md,
  ops/runs/
must_not_touch: statements.lock, models.lock, core/, gate/, eval/cheats/, examples/,
  docs/process.md, .github/workflows/ci.yml, plan/ (the plan holds no status; it lives in #30)
checks: build, imports, lock, core lake check, comparator --paranoid, mitos-lint-test,
  eval/mutants build, the full mutant run (default and --paranoid), actionlint
budget: 30 iterations · 4h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Issue #30. Prior attempt: #9, closed without a merge. It had twelve mutants as full copies of
  the implementation files, a `Refute.lean` per mutant and a bash runner. This task keeps its
  idea (a mutant counts as caught only when the comparator accepts a proof that a Challenge
  theorem is false for it) and its refutations, and changes the rest (below).
- `docs/process.md` lists mutation testing as a nightly check (L3), and its tripwire "a mutation
  of our code still passes a theorem" means the theorem is too weak: a spec question for the
  owner.

## Design

**Why refutations.** A mutant whose proofs no longer build is not evidence that a theorem sees the
bug: a correct refactor also breaks proofs, usually in a helper lemma. So each mutant is judged
twice, both times by the sandboxed `lake comparator`:

1. **approved run:** the approved `core/comparator.json`, Challenge and solution module on the
   mutated core. It must reject. This is what the PR gate would do with the bug.
2. **refutation run:** a Challenge generated from `core/Challenge/Resolver.lean` with each theorem
   the case names negated (`theorem Mitos.Refute.<t> : ¬ (<approved statement>)`), with the
   approved definition holes and permitted axioms, on the mutated core. It must accept: each named
   theorem is proved false, as a kernel term, with standard axioms only.

**Binding the refutation to the mutant.** The comparator compares definition holes by type only.
So a `Refute.lean` used as the solution module directly could declare its own `Mitos.Impl.impact`
and refute that instead of the mutant (review finding on #86). The runner therefore writes the
case's file as `Mitos.Proofs.RefuteCase` and generates the solution module `Mitos.Proofs.Refute`
(`Mutants.refutationSolution`). That module imports every module under `Mitos/Impl/` of the
mutated core, then the case's file. A case file that declares a hole itself clashes with the
imported declaration ("environment already contains 'Mitos.Impl.impact'"), and the run is
rejected. Two scratch cases were REFUTED before this binding and are rejected with it:
- a resolver mutant whose `Refute.lean` declares its own `impact` and names `impact_correct`;
- the same, plus an unused helper that builds only on the mutant.

A first fix judged the refutation on the unmutated core as well and required a rejection. The
second case defeats that, because its helper fails to build there.

A control run judges the unmutated core first and must accept, so a rejection comes from the
mutant. Every run gets a fresh copy of `core/` sources (no build outputs), removed afterwards.

**Cases.** `eval/mutants/cases/<name>/` holds a manifest `mutant` (`why=`, `breaks=` or
`survives=`, and `file=`/`find=`/`replace=` edits) and, for `breaks=`, `Refute.lean`. Edits
instead of copies of the implementation files (#9 copied them): the manifest shows the bug as a
one-line diff, and when `core/Mitos/Impl/` changes, a mutant whose text no longer occurs exactly
once fails as INVALID instead of silently testing an old copy. A `breaks=` case may edit only
`Mitos/Impl/`. A `survives=` case records a known gap: its approved run must accept, with proof
repairs under `Mitos/Proofs/` where a proof needs one, which shows the mutant meets every
Challenge theorem.

**Lean first.** The runner is a small Lake package, `eval/mutants/` (`lean_exe mitos-mutants`),
outside the root package so `gate/` and the root `lakefile.toml` are unchanged and the parallel
`mitos-gate cheats` work does not conflict. Its pure logic is proved, and the package builds with
`warningAsError`, so a `sorry` fails it:
- `Mutants.Edit`: an edit applies only where its text occurs exactly once, and replaces that
  occurrence and nothing else (`splitOnce_eq_some_iff`, `applyEdit_eq_some_iff`); files no edit
  names are unchanged (`applyEdits_lookup`).
- `Mutants.Manifest`: `parse` returns only valid manifests (`parse_valid`): a `breaks=` case edits
  only `Mitos/Impl/` (`valid_breaks_impl`), no case edits outside `Mitos/Impl/` and
  `Mitos/Proofs/` (`valid_area`, `inArea_head`).
- `Mutants.Challenge`: the refutation Challenge holds only kept Challenge lines and negations of
  named Challenge statements, each named theorem stated exactly once (`mem_refutation`,
  `refutation_once`); the reader refuses any Challenge line that could change a statement's
  meaning if dropped (`open`, `namespace`, a multi-line statement).
- `Mutants.Verdict`: the run passes exactly when the control is accepted, every case is judged
  exactly once and meets its expectation (`passes_iff`); then every `breaks=` case was rejected
  by the approved run and its refutation accepted (`passes_refuted`).
- `Mutants.Challenge` also generates the refutation's solution module, which imports every
  implementation module of the core and the case's file, and nothing else (`mem_solutionImports`).
- `Mutants.Implied`: `Total` follows from `Complete` and `UnresolvedExact`, and `RetractExact`
  from `Sound`, `Complete` and `AssumptionsExact`. So no mutant can break either alone.

The file I/O, the process calls and the printing in `Main.lean` are not proved.

**String literals and the replay kernels.** The status refutations build in Lean with string
literals, but the comparator rejected them: with `decide`, Lean's kernel could not reduce the
replayed `decide` term to `true`, and with `simp` (as #9 did), lean4lean failed on `loc` with
`unknown constant 'Char.ofNat'`: the export declared `loc`, with its literals, before
`Char.ofNat`. Those four refutations therefore write their strings with `String.ofList`
(`str ['a']`), which makes the export declare it first; with `decide` they then pass all five
kernels under `--paranoid`. The other refutations pass all five with literals (`decide`, and
`decide +kernel` for impact). If a toolchain changes that, the nightly canary shows it.

**CI.** Nightly only (`nightly.yml`, job `full`, with `--paranoid`, and the canary without it), as
the check matrix in `docs/process.md` already says. A local run of the 21 cases takes 250 s, and
343 s with `--paranoid` (about 12 s and 16 s a case, two comparator runs each); on the nightly
runner, a `workflow_dispatch` run of this branch took 191 s with `--paranoid`. That is too slow to
add to every PR's `gate` for a check whose result changes only when `core/Mitos/Impl/`, the
Challenge or the cases change.

**Not in this task.** A scheduler: the cases run one after another. The `mitos-gate cheats`
runner being built in parallel has a job scheduler this runner could reuse later.

## Done when
- [x] every `breaks=` case is refuted, every `survives=` case survives, locally, default and
      `--paranoid`
- [x] each of the eight Challenge theorems is broken by some mutant; `Total` and `RetractExact`
      only together with another theorem, as `Mutants.Implied` proves they must be
- [x] the runner fails on an INVALID case, a mutant that survives unexpectedly, a refutation that
      is not accepted, and a refutation that declares a definition hole of its own
- [x] all `checks` pass locally
- [x] run-log record written (ops/runs/)
- [ ] the owner decides the known gap `assumptions_dedupe_dropped` (strengthen
      `Spec.AssumptionsExact`, or rule list multiplicity out of scope)
