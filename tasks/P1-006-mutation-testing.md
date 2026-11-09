# tasks/P1-006-mutation-testing.md

phase: 1
goal: Every mutant of the resolver and impact analysis in `eval/mutants/` that names theorems
  (`breaks=`) breaks each of them, shown by the sandboxed `lake comparator` about the mutant's own
  definitions; a realistic mutant the theorems miss is kept as a known gap (`survives=`) for the
  owner; cheat cases (`rejects=`) show that a refutation or a gap counts only for the mutant's own
  definitions; the nightly job checks all three (Phase 1 exit criterion 3, which stays open while a
  known gap does).
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
bug: a correct refactor also breaks proofs, usually in a helper lemma. So a mutant counts as
caught only when the sandboxed `lake comparator` accepts a proof that a named Challenge theorem is
false for it, as a kernel term, with standard axioms only.

**The runs.** Each case gets up to three comparator runs, each in a fresh copy of `core/` sources
(no build outputs), removed afterwards (`Mutants.Verdict`):

1. **holes:** the core with the case's edits under `Mitos/Impl/` and nothing else: no
   `Mitos/Proofs/`, no file of the case. The approved Challenge and definition holes, no theorem,
   and a generated solution module that imports every `Mitos/Impl/` module. It must accept: the
   mutant's implementation builds from the approved core alone, and declares every approved hole
   publicly with its approved type.
2. **gate:** the approved `core/comparator.json`, Challenge and solution module on the mutated
   core. This is what the PR gate would do with the bug.
3. After an acceptance, **values:** the approved Challenge with the holes as values (below). A
   `survives=` case is a known gap only if this accepts: the gate's acceptance is then about the
   mutant's own definitions.
   After a rejection, for a `breaks=` case, **refutation:** a Challenge generated from
   `core/Challenge/Resolver.lean` with each named theorem negated
   (`theorem Mitos.Refute.<t> : ¬ (<approved statement>)`), the holes as values and the approved
   permitted axioms. It must accept: each named theorem is proved false for the mutant's own
   definitions.

A control run first judges the unmutated core as run 2 does, and must accept, so a rejection comes
from the mutant and not from the workspace.

### Binding a refutation to the mutant

**The premise that failed.** Two fixes for "a refutation about code the case wrote itself" failed
review on #86, and both assumed one premise:

> The case's `Refute.lean` can share a Lean environment with the mutated core, and a check on that
> environment stops it from standing in for a definition hole.

- Fix 1 also judged the refutation on the unmutated core and required a rejection there. A
  `Refute.lean` whose own `impact` uses a helper that builds only on the mutant beat it.
- Fix 2 made the solution module import every `Mitos/Impl/` module before the case's file, so that
  a second declaration of a hole clashed. A mutant that makes `def resolve` `private` beat it: the
  case then declares a public `Mitos.Impl.resolve` of its own without a clash.

The comparator compares a definition hole by its name and type only, and the case controls both
the mutated core and the code in the solution's environment. So no check on that environment can
tell which declaration is the hole.

**Test of the premise.** Round 1's runner (a08b51b) reports the private-hole cheat and the known
gap with a private hole (`cheat_private_hole`, `cheat_hide_gap`) REFUTED, and also an
implementation that imports the case's module and one that reads it with `include_str`. It reports
a caught bug whose proof repair declares its own resolver (`cheat_proofs_own_hole`) as a known
gap. Directly with `lake comparator`, on the known gap's mutant with a `Refute.lean` that declares
its own `Mitos.Impl.resolve` (`cheat_own_hole`): with the holes as definition holes it is accepted
(`Your solution is okay!`); with the holes as values it is rejected (`Const does not match between
challenge and target 'Mitos.Impl.resolve'`).

**The premise this design makes true.**

> In every run that counts a mutant (refutation, values), each definition hole is compared by
> value with the public declaration of the mutated `Mitos/Impl/` modules; and those modules build,
> and declare every approved hole publicly with its approved type, in a workspace that holds only
> the approved core and the mutant's implementation edits.

- **Holes as values.** The generated Challenges drop the approved hole lines
  (`def Mitos.Impl.resolve : … := sorry`) and import every `Mitos/Impl/` module of the mutated core
  instead, and their configurations name no definition holes. A hole is then an ordinary constant
  of the Challenge, and the comparator requires the solution's to be identical: the same type, the
  same value, and every constant it uses identical too. Whatever the case declares or imports, a
  hole that is not the mutant's is rejected. The case's `Refute.lean` is written as
  `Mitos.Proofs.RefuteCase`. The generated solution module `Mitos.Proofs.Refute` imports it and
  nothing else, and proves `Mitos.Refute.holes`, which names every hole, so every hole is compared
  in every refutation run, also one the named theorems do not mention.
- **The hole run** shows that the values compared are the mutant's: the implementation builds with
  no file of the case present, so it neither imports one nor reads one (`include_str`), and it
  declares each hole publicly, so a `private` hole stops there. `Mutants.holeCore_spec` proves that
  the hole run's core holds only paths of the approved core outside `Mitos/Proofs/`, and that each
  file outside `Mitos/Impl/` is the approved one.
- **The values run** binds the gate's acceptance the same way, so a known gap whose proof repair
  declares a resolver of its own is not a known gap (review on #86, opus m2).

**Options considered.**
- Chosen: isolation in the form the comparator supports itself, the comparison by value, with the
  hole run for the workspace that holds no file of the case. It removes the case's ability to
  supply a hole, instead of blocking known tricks one by one.
- A generated module that imports only `Mitos/Impl/` and names each hole, imported by the solution:
  it still binds by name, inside an environment the case shares. An implementation that imports or
  reads the case's file defeats it unless more checks are added.
- Refusing edits that touch `import`, `private`, `namespace`, `end` or a hole's `def` line: a list
  of known tricks. `protected`, `export`, a macro or `include_str` is not on it.
- `--challenge-from-export` from a workspace without the case's file: `lake comparator` has no
  export-only mode, so the runner would need its own `bwrap` sandbox around `lake build` and
  `leanexport`, a second sandbox to trust. The hole run gets that workspace from the comparator's
  own sandbox.
- Round 1's import binding is gone. It rested on the failed premise, and a case that it rejects (by
  a clash) would not pin the comparison by value.

**What this does not cover.** Code that runs while Lean elaborates a case's files (`#eval`,
`run_cmd`, `initialize`, an elaborator or a macro) can read and write files in the comparator's
sandbox, build outputs included, and each run elaborates the implementation again, so such code
could make two runs elaborate it differently. The gate stops this class with lint (gate 1). Here
a lint of the manifests' edits and of `Refute.lean` is follow-up #107 (review on #86, opus m1).
No committed case contains such code.

### Cases

`eval/mutants/cases/<name>/` holds a manifest `mutant` (`why=`, `breaks=` or `survives=`, an
optional `rejects=`, and `file=`/`find=`/`replace=` edits) and, for `breaks=`, `Refute.lean`.
Edits instead of copies of the implementation files (#9 copied them): the manifest shows the bug
as a one-line diff, and when `core/Mitos/Impl/` changes, a mutant whose text no longer occurs
exactly once fails as INVALID instead of silently testing an old copy. A `breaks=` case may edit
only `Mitos/Impl/`. A `survives=` case records a known gap: its gate run and its values run must
accept, with proof repairs under `Mitos/Proofs/` where a proof needs one, which shows the mutant
meets every Challenge theorem.

A case with `rejects=<run>` is a **cheat case**: its claim must not be counted, and the named run
must reject it after every earlier run let it through. Each pins one check of the binding: without
that check the claim is counted, so the run fails. The column "without" is the result with that
check switched off in a scratch copy of the runner (one run each, default kernel):

| Case | The cheat | Rejected at, with | Without | Round 1 |
|---|---|---|---|---|
| `cheat_own_hole` | the known gap as `breaks=`; `Refute.lean` declares its own `Mitos.Impl.resolve` and does not import the real one | refutation: `Const does not match … 'Mitos.Impl.resolve'` | holes by type: REFUTED | rejected (name clash) |
| `cheat_private_hole` | `private def resolve`; `Refute.lean` declares a public one | holes: the exporter finds no `Mitos.Impl.resolve` | hole run: rejected at refutation instead | REFUTED |
| `cheat_hide_gap` | the known gap, plus `private def resolve` and an own resolver | holes: as above | hole run: rejected at refutation instead | REFUTED |
| `cheat_impl_imports_case` | `Mitos/Impl/Resolve.lean` imports the case's module and takes `resolve` from it | holes: `bad import 'Mitos.Proofs.RefuteCase'` | hole run: rejected at refutation instead | REFUTED |
| `cheat_include_str` | the known gap, plus a `resolve` that turns bogus when `include_str` finds the case's file | holes: `no such file or directory` | hole run: REFUTED | REFUTED |
| `cheat_proofs_own_hole` | `src_dst_swapped` as a known gap; the proof repair declares a correct resolver of its own | values: `Const does not match … 'Mitos.Impl.mkEdge'` | values run: SURVIVED | SURVIVED (a false gap) |
| `cheat_namespace_shadow` | refutes a shadow `Mitos.Refute.Impl.resolve` | refutation: statement mismatch | (the comparator's own check) | rejected |
| `cheat_native_decide` | proves `False` with `native_decide` on an `implemented_by` lie | refutation: `Illegal axiom` | (the comparator's own check) | rejected |

With all three checks switched off and round 1's import binding back, the run fails on five of
the eight. Round 1's runner itself (a08b51b, the `rejects=` lines removed, which it does not read)
reports four of them REFUTED and one as a known gap.

### The rest

**Lean first.** The runner is a small Lake package, `eval/mutants/` (`lean_exe mitos-mutants`),
outside the root package so `gate/` and the root `lakefile.toml` are unchanged and the parallel
`mitos-gate cheats` work does not conflict. Its pure logic is proved, and the package builds with
`warningAsError`, so a `sorry` fails it:
- `Mutants.Edit`: an edit applies only where its text occurs exactly once, and replaces that
  occurrence and nothing else (`splitOnce_eq_some_iff`, `applyEdit_eq_some_iff`); edits add and
  remove no file (`applyEdits_paths`), and files no edit names are unchanged (`applyEdits_lookup`).
- `Mutants.Manifest`: `parse` returns only valid manifests (`parse_valid`): a `breaks=` case edits
  only `Mitos/Impl/` (`valid_breaks_impl`), no case edits outside `Mitos/Impl/` and
  `Mitos/Proofs/` (`valid_area`, `inArea_head`), and a `rejects=` run fits the claim
  (`Stage.fits`: `refutation` needs `breaks=`, `values` needs `survives=`).
- `Mutants.Challenge`: the refutation Challenge holds only imports of the implementation modules,
  the approved Challenge's import and comment lines, negations of named Challenge statements and
  `Mitos.Refute.holes`, each named theorem stated exactly once (`mem_refutation`,
  `refutation_once`); the approved Challenge by value holds the approved theorem lines verbatim
  (`mem_approvedByValue`); neither holds a definition hole line. The hole run's core holds no file
  under `Mitos/Proofs/` and only the implementation edited (`holeCore_spec`). The reader refuses
  any Challenge line that could change a statement's meaning if dropped (`open`, `namespace`, a
  multi-line statement).
- `Mutants.Verdict`: the run passes exactly when the control is accepted, every case is judged
  exactly once and meets its expectation (`passes_iff`). Then every `breaks=` case had its hole run
  accepted, its gate run rejected and its refutation accepted (`passes_refuted`); every `survives=`
  case had its hole, gate and values runs accepted (`passes_survived`); and every cheat case was
  rejected at its run and counted neither as refuted nor as surviving (`passes_rejects`).
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
`decide +kernel` for impact). Which constants the export holds matters too: with only `resolve`'s
definition in it, Lean's replay kernel could not reduce the `decide` in `src_dst_swapped`'s
refutation, and with `impact`'s as well it could (bisected to `List.get!Internal`, which `impact`
uses). Round 1 had both holes in every export because they were definition holes; now
`Mitos.Refute.holes` keeps them there. If a toolchain changes any of this, the nightly canary shows
it.

**CI.** Nightly only (`nightly.yml`, job `full`, with `--paranoid`, and the canary without it), as
the check matrix in `docs/process.md` already says. A local run of the 30 cases took 736 s with
`--paranoid` (one run): about 25 s for a case that gets all three comparator runs, and 4 to 6 s
for a cheat case the hole run stops. On the nightly runner, round 1's 21 cases with two runs each
took 263 s with `--paranoid` (a `workflow_dispatch` run at 2ff0df3); the latest dispatch of this
branch is reported on #86. That is too slow to add to every PR's `gate` for a check whose result
changes only when `core/Mitos/Impl/`, the Challenge or the cases change.

**Not in this task.** A scheduler: the cases run one after another. The `mitos-gate cheats`
runner being built in parallel has a job scheduler this runner could reuse later.

## Done when
- [x] every `breaks=` case is refuted, every `survives=` case survives and every cheat case is
      rejected at its run, locally, default and `--paranoid`
- [x] each of the eight Challenge theorems is broken by some mutant; `Total` and `RetractExact`
      only together with another theorem, as `Mutants.Implied` proves they must be
- [x] the runner fails on an INVALID case, a mutant that survives unexpectedly, a refutation that
      is not accepted, and a cheat case that is counted or rejected at another run
- [x] each check of the binding is pinned: a cheat case turns the run red without it
- [x] all `checks` pass locally
- [x] run-log record written (ops/runs/)
- [ ] the owner decides the known gaps `assumptions_dedupe_dropped` and `edges_duplicated`
      (list multiplicity: strengthen the spec, or rule multiplicity out of scope; #101)
