# tasks/P1-006-mutation-testing.md

phase: 1
goal: Every mutant of the resolver and impact analysis in `eval/mutants/` that names theorems
  (`breaks=`) breaks each of them, shown by the sandboxed `lake comparator` about the mutant's own
  definitions; a realistic mutant the theorems miss is kept as a known gap (`survives=`) for the
  owner; cheat cases (`rejects=`) show that a refutation or a gap counts only for the mutant's own
  definitions and the approved statements, and that a case's Lean text runs no code and declares no
  syntax while Lean elaborates it; the nightly job checks all three (Phase 1 exit criterion 3, which
  stays open while a known gap does).
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

**The runs.** Before anything is built, the lint (below, `Mutants.Lint`) reads every Lean text the
case wrote or changed, and a case it finds anything in is refused. Then each case gets up to three
comparator runs, each in a fresh copy of `core/` sources (no build outputs), removed afterwards
(`Mutants.Verdict`):

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
  no file of the case present, and it declares each hole publicly, so a `private` hole stops there.
  `Mutants.holeCore_spec` proves that the hole run's core holds only paths of the approved core
  outside `Mitos/Proofs/`, and that each file outside `Mitos/Impl/` is the approved one;
  `Mutants.holeCore_impl`, that its `Mitos/Impl/` files are the other runs'. The hole run alone does
  not show that the implementation reads no file of the case: an `include_str` inside
  `first | … | …` builds without the file, and that is the lint's job (round 3, below).
- **The values run** binds the gate's acceptance the same way, so a known gap whose proof repair
  declares a resolver of its own is not a known gap (review on #86, opus m2).

**Options considered.**
- Chosen: isolation in the form the comparator supports itself, the comparison by value, with the
  hole run for the workspace that holds no file of the case. It removes the case's ability to
  supply a different hole, instead of blocking known tricks one by one.
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

### The case's Lean text: the lint (round 3)

**What failed.** Round 2's design was sound for the holes but took a case's Lean text as inert.
Both reviews of f1f5dad found a REFUTED for code the case wrote, through code that runs or
rewrites syntax while Lean elaborates:
- an implementation edit adding ``macro_rules | `(Mitos.Spec.AssumptionsExact $x) => `(False)``:
  the refutation Challenge imports the implementation before the approved statement lines, so the
  macro rewrites the statement, and `fun h => h` refutes it, for a correct implementation as for
  the known gap, also with `--paranoid` (opus B1);
- `def resolve := by (first | exact (let _ := include_str "../Proofs/RefuteCase.lean"; bogus) | exact real)`:
  the hole and gate runs, without the case's file, build the real resolver, and the refutation
  run, with it, the bogus one (sonnet B1);
- `import Lean` and a `run_cmd` that declares a bogus `resolve` when the case's file exists (opus
  m1), and a `macro_rules` twisting `¬` (sonnet m1).

The root cause: the manifests' `replace=` texts and `Refute.lean` are untrusted Lean source, and
Lean runs code while it elaborates source.

**The premise this round makes true.**

> Every Lean text a case wrote or changed (each `replace=` text, each file its edits change, and
> its `Refute.lean`) imports only the approved core and the implementation, contains only
> declarations that Lean's built-in code elaborates, and runs no code of the case and declares no
> syntax while Lean elaborates it. So the mutated implementation elaborates the same in every run,
> whatever other files the run holds, and the generated Challenges that import it state exactly the
> approved statements.

**The lint** (`Mutants.Lint`), before any build, in every run of the runner (and in `--prepare`):
an allow-list read from Lean's own parse, with the syntax of `Init` alone, which is all the approved
core and the implementation see:
- imports only under `Mitos.Core` and `Mitos.Impl` (`Mitos.Proofs` too in a known gap's proof
  repair), plain `import`s, no `module` or `prelude`;
- commands only a module doc, `namespace`, `section`, `end`, `open`, and `def`, `theorem`, `abbrev`
  and `example` declarations; so no `macro`, `syntax`, `notation`, `elab`, `run_cmd`, `#eval` or
  any other `#` command, `initialize`, `instance`, `attribute`, `set_option`, `open … in`;
- no attribute anywhere (`@[…]`);
- no token with a component in gate 1's plugin list, imported from `gate/MitosGate/Lint.lean`
  (`banned`: `macro_rules`, `include_str`, `Lean`, `native_decide`, `sorry`, …), nor `by_elab` or
  `run_tac`, the forms that run code inside an allowed declaration, nor `set_option` or
  `attribute` inside a declaration either; and no `#` token. A term-level `open … in` stays
  allowed: it changes name resolution in one term, and no module a case may import declares scoped
  syntax for it to open.

A text Lean's parser cannot read to the end is refused. Each `replace=` text is also checked as
plain text, without Lean's parser: no `#`, no `@[`, no banned word standing alone. The lint allows
`private` and ordinary declarations: they run nothing, and the hole run and the comparison by value
judge what they declare, so the cheat cases that pin those checks (`cheat_private_hole`,
`cheat_own_hole`, `cheat_proofs_own_hole`) still reach them.

**Options considered.**
- Chosen: the lint, as an allow-list. It removes the class at its root, code the case wrote that
  runs while Lean elaborates, instead of the ways such code was seen to fake a result. The
  allow-list is short because the approved implementation, its proofs and every committed
  refutation need nothing else; gate 1's ban list is reused, not copied.
- An Impl-free anchor run (opus fix a): also judge each refutation against a Challenge that does not
  import the implementation. It fixes what the statement means, but not what the implementation
  elaborates to in each run (sonnet B1), and every refutation would need a fourth comparator run.
- A ban-list of the commands seen so far: the next one not on it (`by_elab`, an `@[macro]`
  attribute) would get through.
- Every run's workspace holding the same files (sonnet's structural point): the hole run's job is a
  workspace without the case's files, so it cannot hold them; and with the lint it is not needed.
  An implementation that passes the lint elaborates from its own text and the modules it imports,
  which the lint limits to the approved core and the implementation; those texts are the same in
  every run (`holeCore_impl` for the hole run; the other runs share one mutated core), and the lint
  leaves no way to read any other file. So the files a run adds cannot reach it.

**What this does not cover.** Lean's built-in elaborators for the allowed commands, tactics such as
`decide` and `simp`, and the parser are trusted, as they are for the gate. The lint parses with
`Init`'s syntax; that is the syntax Lean elaborates a case's text with, because the approved core
declares none and a text that passes adds none.

### Cases

`eval/mutants/cases/<name>/` holds a manifest `mutant` (`why=`, `breaks=` or `survives=`, an
optional `rejects=`, and `file=`/`find=`/`replace=` edits) and, for `breaks=`, `Refute.lean`.
Edits instead of copies of the implementation files (#9 copied them): the manifest shows the bug
as a one-line diff, and when `core/Mitos/Impl/` changes, a mutant whose text no longer occurs
exactly once fails as INVALID instead of silently testing an old copy. A `breaks=` case may edit
only `Mitos/Impl/`. A `survives=` case records a known gap: its gate run and its values run must
accept, with proof repairs under `Mitos/Proofs/` where a proof needs one, which shows the mutant
meets every Challenge theorem.

A case with `rejects=<stage>` is a **cheat case**: its claim must not be counted, and the named
stage must reject it after every earlier one let it through. Each pins one check: without that
check the claim is counted or the case is rejected elsewhere, so the run fails. The column
"without" is the result with that check switched off in a scratch copy of the runner (one run
each, default kernel):

| Case | The cheat | Rejected at, with | Without | Round 2 runner |
|---|---|---|---|---|
| `cheat_impl_macro` | no bug; the implementation's `macro_rules` turns `AssumptionsExact _` into `False` (opus B1) | lint: `macro_rules` | lint: REFUTED | REFUTED |
| `cheat_impl_macro_gap` | the known gap, plus that `macro_rules` (opus B1) | lint: `macro_rules` | lint: REFUTED | REFUTED |
| `cheat_include_str_first` | the known gap, plus `resolve := by first \| exact (… include_str …; bogus) \| exact real` (sonnet B1) | lint: `include_str` | lint: REFUTED | REFUTED |
| `cheat_impl_run_cmd` | the known gap, plus `import Lean` and a `run_cmd` that declares a bogus `resolve` when the case's file exists (opus m1) | lint: `import Lean`, `run_cmd` | lint: REFUTED | REFUTED |
| `cheat_refute_macro` | `Refute.lean` reads `¬ _` as `True` with a local `macro_rules` | lint: `macro_rules` in `Refute.lean` | lint: rejected at refutation (statement mismatch) | rejected |
| `cheat_include_str` | the known gap, plus a `resolve` that turns bogus when `include_str` finds the case's file | lint: `include_str` | lint: rejected at holes (`no such file or directory`) | rejected at holes |
| `cheat_impl_imports_case` | `Mitos/Impl/Resolve.lean` imports the case's module and takes `resolve` from it | lint: `import Mitos.Proofs.RefuteCase` | lint: rejected at holes (`bad import`) | rejected at holes |
| `cheat_native_decide` | proves `False` with `native_decide` on an `implemented_by` lie | lint: `@[implemented_by]`, `native_decide` in `Refute.lean` | lint: rejected at refutation (`Illegal axiom`) | rejected |
| `cheat_own_hole` | the known gap as `breaks=`; `Refute.lean` declares its own `Mitos.Impl.resolve` and does not import the real one | refutation: `Const does not match … 'Mitos.Impl.resolve'` | holes by type: REFUTED | rejected |
| `cheat_private_hole` | `private def resolve`; `Refute.lean` declares a public one | holes: the exporter finds no `Mitos.Impl.resolve` | hole run: rejected at refutation instead | rejected |
| `cheat_hide_gap` | the known gap, plus `private def resolve` and an own resolver | holes: as above | hole run: rejected at refutation instead | rejected |
| `cheat_proofs_own_hole` | `src_dst_swapped` as a known gap; the proof repair declares a correct resolver of its own | values: `Const does not match … 'Mitos.Impl.mkEdge'` | values run: SURVIVED | rejected |
| `cheat_namespace_shadow` | refutes a shadow `Mitos.Refute.Impl.resolve` | refutation: statement mismatch | (the comparator's own check) | rejected |

The first five are new in round 3; the next three were rejected at a later stage before the lint
ran first, and the lint now rejects them too. The rows below them are round 2's, unchanged; their
"without" results are round 2's (one run each), whose runner they still describe, since the lint
passes those cases. Round 1's runner (a08b51b) reported `cheat_private_hole`, `cheat_hide_gap`,
`cheat_impl_imports_case` and `cheat_include_str` REFUTED and `cheat_proofs_own_hole` as a known
gap.

### The rest

**Lean first.** The runner is a small Lake package, `eval/mutants/` (`lean_exe mitos-mutants`),
outside the root package so `gate/` and the root `lakefile.toml` are unchanged and the parallel
`mitos-gate cheats` work does not conflict. It requires the root package only to import gate 1's
lint (`MitosGate.Lint`). Its pure logic is proved, and the package builds with `warningAsError`, so
a `sorry` fails it:
- `Mutants.Edit`: an edit applies only where its text occurs exactly once, and replaces that
  occurrence and nothing else (`splitOnce_eq_some_iff`, `applyEdit_eq_some_iff`); edits add and
  remove no file (`applyEdits_paths`), and files no edit names are unchanged (`applyEdits_lookup`).
- `Mutants.Manifest`: `parse` returns only valid manifests (`parse_valid`): a `breaks=` case edits
  only `Mitos/Impl/` (`valid_breaks_impl`), no case edits outside `Mitos/Impl/` and
  `Mitos/Proofs/` (`valid_area`, `inArea_head`), and a `rejects=` run fits the claim
  (`Stage.fits`: `refutation` needs `breaks=`, `values` needs `survives=`).
- `Mutants.Lint`: a source with no finding parses to the end, imports only under the kind's
  prefixes, holds only allowed commands, no attribute and no token outside `tokenOk`
  (`problems_eq_nil_iff`); a `replace=` text the plain-text check passes holds no `#`, no `@[`, and
  no banned word standing alone (`replaceProblems_banned`, from `mem_words`); every file an edit
  changes is linted (`mem_targets`). Reading a source with Lean's parser is not proved.
- `Mutants.Challenge`: the refutation Challenge holds only imports of the implementation modules,
  the approved Challenge's import and comment lines, negations of named Challenge statements and
  `Mitos.Refute.holes`, each named theorem stated exactly once (`mem_refutation`,
  `refutation_once`); the approved Challenge by value holds the approved theorem lines verbatim
  (`mem_approvedByValue`); neither holds a definition hole line. The hole run's core holds no file
  under `Mitos/Proofs/` and only the implementation edited (`holeCore_spec`). The reader refuses
  any Challenge line that could change a statement's meaning if dropped (`open`, `namespace`, a
  multi-line statement). The hole run's `Mitos/Impl/` files are the other runs' (`holeCore_impl`).
- `Mutants.Verdict`: the run passes exactly when the control is accepted, every case is judged
  exactly once and meets its expectation (`passes_iff`). Then every `breaks=` case passed the lint,
  had its hole run accepted, its gate run rejected and its refutation accepted (`passes_refuted`);
  every `survives=` case passed the lint and had its hole, gate and values runs accepted
  (`passes_survived`); every cheat case was rejected at its stage and counted neither as refuted
  nor as surviving (`passes_rejects`); and the lint refused only cheat cases that expect it, with
  no comparator run (`passes_refused`).
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
the check matrix in `docs/process.md` already says. A local run of the 35 cases took 751 s with
`--paranoid` (one run, round 3): 27 to 31 s for a refuted case (three comparator runs), about 38 s
for a known gap, about 6 s for a cheat case the hole run stops, and under 0.1 s for one the lint
refuses (the lint of all 35 cases, Lean's syntax loaded once, takes about 0.5 s). On the nightly runner, round 1's 21 cases with two runs each
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
- [x] a case's Lean text is linted before any build; the four ways round 2's reviews faked a
      REFUTED are cheat cases rejected at the lint, and REFUTED without it
- [x] all `checks` pass locally
- [x] run-log record written (ops/runs/)
- [ ] the owner decides the known gaps `assumptions_dedupe_dropped` and `edges_duplicated`
      (list multiplicity: strengthen the spec, or rule multiplicity out of scope; #101)
