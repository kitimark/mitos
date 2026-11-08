# tasks/P1-009-model-adequacy.md

phase: 1
goal: A plugin is accepted only if its model ships reviewed examples and proves it agrees with
  them. Against such a model the extractor that emits nothing is not complete, and the one that
  emits every example fact is not sound. Whether a model that holds too much is caught depends on
  the reviewed examples: one whose examples agree with it is adequate.
statement: Mitos.ModelExamples, Mitos.Model.Adequate, Mitos.Extractor.empty,
  Mitos.ModelExamples.everything, Mitos.Model.Adequate.{empty_not_complete, everything_not_sound},
  Mitos.Model.{nothing_holds_not_adequate, everything_holds_not_adequate} (new); follow-up spec PR:
  Mitos.GoldenFile, Mitos.Model.Adequate.{sound_on_golden, complete_on_golden} (new),
  Mitos.ModelExamples and Mitos.Model.Adequate (changed: golden files)
touches: spec PR: core/Mitos/Core/ModelExamples.lean, core/Mitos/Core.lean, statements.lock,
  examples/acme/{Models/ToyRequire.lean, models.lock, accepted/ToyRequire.json};
  gate PR: gate/MitosGate/{Accept.lean, Util.lean, Lint.lean (`include_str` ban)}, gate/Main.lean,
  gate/LintTest.lean (`include_str` cases), eval/cheats/run.sh (`lock_append=`
  lines), eval/cheats/{empty_extractor, emit_everything, weakened_adequacy, judge_dir_model,
  missing_obligation, double_elaboration, lock_duplicate_path,
  model_include_str, model_include_str_src}/,
  eval/cheats/shadow_{model, obligation_model, extractor_model, root_component, root_export,
  export_model}/ (deferred by tasks/gate3-qualified-challenge.md),
  eval/cheats/{model_notation, model_implemented_by, model_dotdot_import}/Models/, docs/process.md,
  .github/workflows/ci.yml (step name), examples/acme/accepted/ToyRequire.json,
  tasks/gate3-qualified-challenge.md, plan/phase-1.md (P1-009 row), ops/runs/;
  follow-up spec PR: core/Mitos/Core/ModelExamples.lean, statements.lock,
  examples/acme/{Models/ToyRequire.lean, models.lock, accepted/ToyRequire.json},
  eval/cheats/{emit_everything, weakened_adequacy, judge_dir_model}/Models/ (new examples form),
  eval/cheats/nearmiss_scope/, docs/process.md, this file, plan/phase-1.md, ops/runs/
must_not_touch: core/Challenge/, core/comparator.json, existing eval/cheats/*/ expect files (round 3
  gives the models of #24's three model cases the toy's adequacy proof; see Findings).
  Exception, follow-up spec PR: the models of emit_everything, weakened_adequacy and
  judge_dir_model (new in the gate PR) move to the golden-file form, and two why= lines are
  reworded; no full= or comparator_only= line changes
checks: build, imports, lock, core lake check, core comparator --paranoid, acme build,
  accept-toy --paranoid, cheats (full and comparator-only)
budget: 40 iterations · 4h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Gates 0–5 take the reviewed model as given. A plugin passes them by emitting exactly what the
  model says holds, so a weak model admits a lazy plugin. Today's gate accepts, `--paranoid`
  included:
  - a model where nothing holds, with the extractor that emits nothing
  - a model where every line is a requirement, with the extractor that emits every line
- The architecture report ("The human-reviewed model is the real attack surface") asks for
  examples, near misses and two vacuity checks:
  - on a positive example, the empty extractor must fail completeness
  - on a negative example, an "emit everything" extractor must fail soundness

  Mutation adequacy and counterexample search are the rest of the report's gate 6. They are not
  part of this task.
- This is spec, then gate. The meaning of adequacy is a locked core definition and the toy model
  changes (`models.lock`), so the spec PR needs `spec-approved`. The gate PR is stacked on it.

## Design

**What gate 6 checks.** For `--model Models.X.model`, the model module must declare:
- `Models.X.model.examples : Mitos.ModelExamples`: golden files, each a `Mitos.GoldenFile`: a file
  and every fact the model must say holds in it, and no other.
- `Models.X.model.adequate : Mitos.Model.Adequate Models.X.model Models.X.model.examples`.

`Model.Adequate` holds when:
- on each golden file, a fact holds exactly when it is listed
- every listed fact is anchored in its file
- some golden file lists a fact that another golden file does not

Two locked theorems say what this buys a plugin that also passes gate 3:
- `Adequate.sound_on_golden`: a sound extractor emits on each golden file only listed facts.
- `Adequate.complete_on_golden`: a complete extractor emits on each golden file a fact with the kind
  and identity of each listed fact.

Two more turn this into the vacuity checks:
- `Adequate.empty_not_complete`: `Extractor.empty` is not complete.
- `Adequate.everything_not_sound`: `ex.everything`, which emits every listed fact on every file, is
  not sound.

Two corollaries are tripwires for the definition itself:
- `nothing_holds_not_adequate`: the model where nothing holds is adequate for no examples.
- `everything_holds_not_adequate`: the model where everything holds is adequate for no examples.

If a later edit dropped the last conjunct, both would stop proving.

The first spec (#20) had examples and near misses: `(file, fact)` pairs the model must accept and
reject. The red team showed that is weaker than it reads. A near miss excludes one exact `Fact`, so
a model that reads `# require x` as a dev requirement passed the reviewed near miss "a
commented-out line" (`nearmiss_scope`). The follow-up spec replaces both lists with golden files.

**Choices and reasons.**

| Choice | Reason | Rejected alternative |
|---|---|---|
| The meaning of adequacy is a locked core definition (`Mitos.Model.Adequate`), and the vacuity facts are core theorems | "People review statements": gate 3 means `Mitos.Anchored`/`SoundWrt`/`CompleteWrt`, so gate 6 should mean a core definition too, not a string in gate code. The vacuity facts are proved once, for every model | Statements only in the gate's generated Challenge, with vacuity proved by tactics the gate generates. That avoids a core change, but the toy model needs a spec PR anyway (`models.lock`) |
| Examples live in the model file, pinned by `models.lock` | Examples the plugin author chose would prove nothing | Examples in the plugin, or in an unpinned file |
| A naming convention under the model constant (`<model>.examples`, `<model>.adequate`) | No new CLI flag; works for several models in one module | A new field on `Mitos.Model`. It would break the anonymous `⟨fun _ _ => True⟩` in `swapped_model`, which would then fail at gate 2 instead of 3 |
| Gate 6 judges the model module itself as the comparator solution. The model and its examples are definition holes; the adequacy theorem is the statement | The same machinery as gates 2–5: kernel-term statement match, axiom allow-list, sandbox, and `--paranoid` kernels. The hole values are gate 0's checked copy of the models | A gate-generated solution that re-exports the model's theorem. It adds a file and checks the same thing |
| One judging directory for gates 2–6. The comparator judges gate 6 there first, with `--config=adequacy.json`, then the plugin with `comparator.json`. After each run the gate hashes every file under `.lake/build/lib/lean/` from its own process, and the plugin's run must leave every output of gate 6's run unchanged; a changed or missing output, or an entry there that is not a regular file, fails gate 6. The verdict still reports gates 2–5 before 6 | Gates 3 and 6 judge one elaboration of the model: the plugin's run reuses the model's `.olean` from gate 6's run, and the directory's files are the same in both runs (`judge_dir_model`). The hash check makes that hold without lint: a model that runs code can make Lake rebuild it in the plugin's run (`double_elaboration`, verifier F21-1). The sandbox runs with `--die-with-parent` in its own PID namespace, so nothing of a run is left to change the outputs once it ends. The whole tree is hashed, not only `Models/`, since a forged core output changes what both runs import. A symlink or device is refused, because hashing it could follow it out of the directory or never end. An accepted gate 6 run that left no `.olean` for the model module fails too, so a Lake layout change cannot turn the comparison into a no-op (CodeRabbit, round 3; a scratch gate that hashed the wrong directory accepted the toy without this guard and rejects it at gate 6 with it). The plugin is not built until gate 6 is judged, so nothing it writes reaches gate 6. The core is built once, so the honest `accept` is faster. A run that fails gates 2–5 still pays for gate 6, about 10 s | Round 1's second, fresh directory without the plugin. A model that reads its directory meant two models there. Stating `<model>.adequate` in gate 3's Challenge as well: the Challenge imports the model module, so the statement would clash with it, or the model would become a hole and gate 3 would stop comparing its value |
| Gate 0 reads the models and `models.lock` once and checks the hashes itself, as strictly as `sha256sum --check --strict`: a malformed line, a path listed twice, a listed path that is not a model, and an unlisted model all fail. It returns a `LockedModels` value, which only `provenance` can build, and the judging directory, the Challenge and the record use only that value | A model edited between gate 0 and a judgment cannot be judged in place of the locked one, and the record names the lock that was checked (CodeRabbit, `Accept.lean:142-157`). `adequacyChallenge` takes the value as evidence that gate 0 ran | `sha256sum --check` in the workspace, then copying `Models/` once per judging directory |
| Gate 1 lints every model with main's model allowlist (#24, `Lint.checkModel`: the plugin token rules, the command allowlist, the component-wise import rule and the parser-stop check), on gate 0's snapshot of the model bytes. Round 2's own model denylist (`modelBanned`) is gone | One set of model rules. The allowlist rejects code that runs while a model elaborates (`#eval`, `initialize`, attributes) and `noncomputable`, so a computable `examples` is data a reviewer can evaluate. `sorry` and `axiom` are now rejected at gate 1 as in plugins, so an unproved model fails there in a full run and at gate 6 only without lint (`emit_everything`). `include_str` and `Classical.choose` pass the allowlist: `include_str` reads the judging directory, whose files are the same in both runs and which the hash check pins to one elaboration, and its use is in the reviewed bytes; `choose` in data needs `noncomputable` | Keeping `modelBanned` beside the allowlist: two lists for one rule |
| The `--model` module's first component must be `Models` | `models.lock` covers only `Models/`, and only `Models/` is copied into the judging directory | — |
| Gate 6's Challenge writes every name from `_root_`, declared and referenced, the form main's gate-3 Challenge uses since #25 | A declaration name such as `Models.X.model.examples` opens its own namespace while the Challenge elaborates | — |
| Gate 6's Challenge is `Challenge/Mitos/ModelAdequacy.lean` (module `Challenge.Mitos.ModelAdequacy`), and the gate refuses to write two judging-directory files to one path | A plugin name is a plain identifier, so `Challenge/{p}.lean` cannot be that path. Round 2's `Challenge/ModelAdequacy.lean` was the plugin `ModelAdequacy`'s own Challenge, which the adequacy one overwrote (verifier F21-2; it failed closed, at gate 3) | — |
| Text from the workspace, Lean or the comparator is printed through `oneLine`, an allowlist: printable ASCII but `\`, and blocks of letters, digits, punctuation and symbols (Latin, Greek, Cyrillic, math, arrows, CJK and others). Every other code point prints as `\u{XXXX}`. Proved: the output holds only allowlisted code points and the `\` of an escape (`oneLine_printable`), and C0/C1 controls, DEL, U+2028/U+2029, bidi controls and other format characters are not allowlisted (`unsafeSamples_escaped`). The standalone `mitos-gate lint` and `imports` print through it too | A file name or message must not start a line of its own (a forged `VERDICT:`), move the cursor or reorder the text (CWE-117). Round 2 escaped only code points below 32 and 127; C1 controls such as U+0085 and U+009B, U+2028 and U+202E passed (verifier finding). Escaping `\` keeps one output per input | A denylist of control and format characters, which misses whatever it does not name |
| An I/O error in a gate prints `VERDICT: REJECTED (gate N: <name>: I/O error)` and exits 1. The judging directory is removed in `finally`, or kept with `--keep`. A failed record write prints `VERDICT: REJECTED (record: …)` | Every failure path ends in a verdict line, and a failed run leaves no copy of the core and models in `/tmp` (CodeRabbit, `Accept.lean:157`) | An uncaught exception, which fails closed but prints no verdict |
| A plugin missing an obligation is reported as gate 3 | The comparator panics exporting the missing constant (`not found in environment`); `failedGate` reads that before the build-failure default | Reporting it as gate 2, a build failure |
| A comparator run with no judgment marker is gate 2, whatever its output: a build error, or `lake` that did not run at all | Without `lake` on `PATH` the output is only `could not execute external process 'lake'`, which round 2 reported as gate 3 (verifier finding). The gate also flushes its standard output before it runs a command, so a child that fails to start does not repeat the gate's lines | — |
| Every gate-6 failure is reported as gate 6, with a reason read from the comparator's output: missing declaration, illegal axiom, statement mismatch, kernel rejection | Fails closed: anything but a clean comparator run rejects | — |
| Gate 0 also rejects a `--model` that is not a dotted identifier | Gate 6 interpolates it into a generated `def`, not only into a term | — |
| The acceptance record gains `adequacy_challenge_sha256` | The record pins what acceptance meant | — |
| Golden files: each reviewed file lists every fact that holds in it, and `Adequate` requires `Holds file f ↔ f ∈ facts` (follow-up spec) | Each reviewed file is an exact test. "This file requires nothing" can be stated, and the old near misses follow from it. Both vacuity theorems still follow, from one witness conjunct | Near misses at kind-and-identity level: still one fact per entry, and a reviewer cannot state "nothing else holds" |
| The witness conjunct is "some golden file lists a fact that another does not" | The weakest condition from which emitting every listed fact is unsound. It also implies a listed fact exists, so emitting nothing is incomplete | Requiring one golden file with no facts. That is simpler to read but rules out conventions where every file has a fact |

**Toy model.** Each golden file is named for the mistake it catches:
- `wholeLineAsPackage`: `require left-pad` requires only `left-pad`, not the whole line.
- `charOffsetNotByteOffset`: `"require é\nrequire left-pad\n"` requires `é` and `left-pad`. The
  second line starts at `utf8Len "require é\n"` bytes, not at its character offset (the P1-005 bug).
- `commentedOutLine`: `# require left-pad` requires nothing.

`golden_of_requirements` reduces exactness and anchoring on a golden file to `decide` on its
requirement lines, as `(offset, characters)` pairs. So no proof compares `String`s, which overflowed
nanoda's stack on non-ASCII input.

**Cheats** (all `model_approved=yes`, so the runner pins their model). Round 1's three cases are
accepted by gates 0–5 and rejected at gate 6 without lint. In full runs `empty_extractor` and
`weakened_adequacy` reach gate 6 too, while `emit_everything` is rejected at gate 1 since the
rebase onto #24, whose model lint bans its `sorry`. `judge_dir_model` and `double_elaboration` are
rejected at gate 1 in full runs and at gate 6 without lint:

| Case | Model | Extractor | Gate 6 says |
|---|---|---|---|
| `empty_extractor` | nothing holds; no examples (a model written before gate 6) | emits nothing | declarations missing |
| `emit_everything` | every line is a requirement; the reviewer's examples; adequacy is `sorry` (unprovable: the whole line holds on `wholeLineAsPackage`) | emits every line | illegal axiom `sorryAx` |
| `weakened_adequacy` | nothing holds; proves only "nothing outside the golden lists holds" under the name `model.adequate` | emits nothing | statement mismatch |
| `nearmiss_scope` (follow-up spec) | the toy's golden files; reads `# require x` as a dev requirement; adequacy is `sorry` (`commentedOutLine_not_exact`) | reports commented-out lines as dev requirements | full: gate 1, `sorry`. Comparator-only: illegal axiom `sorryAx`. Accepted under #20's near misses |
| `judge_dir_model` | reads `../comparator.json` with `include_str`; the toy model only where that is gate 6's configuration, otherwise nothing holds; adequacy falls back to `sorry` | emits nothing | full: gate 1, `sorry`. Comparator-only: illegal axiom `sorryAx`, since gates 3 and 6 now judge one elaboration |
| `double_elaboration` (verifier F21-1) | an `#eval` leaves a marker and forges the core's cached `Core.olean.hash`, so the plugin's run rebuilds the model; the first elaboration is the toy model and proves adequacy, the second holds nothing | emits nothing | full: gate 1, `#eval` and `sorry`. Comparator-only: the plugin's run changed gate 6's build outputs. Without that check: ACCEPTED, gates 0–6 |

`missing_obligation` is the honest model with a plugin that declares no `complete`; it is rejected at
gate 3 in both modes.

`lock_duplicate_path` (round 3, for round 2's CodeRabbit finding) lists `Models/ToyRequire.lean`
twice in `models.lock`, first with the model's hash and then with a wrong one; `sha256sum --check`
fails it. The case has only an `expect` file: its `lock_append=` line is appended to the example
workspace's lock by the runner. A committed `models.lock` under `eval/cheats/` would have made CI's
`spec-approved` step read the case as a spec change, which its first push did. With gate 0's
duplicate check removed, gates 0–6 accept it with the honest plugin in both modes; with the check,
it is rejected at gate 0 in both modes.

The six model-side shadow cases that #25 deferred until `model_approved=yes` existed
(`tasks/gate3-qualified-challenge.md`) join the corpus here. Each model is the honest toy model plus
one declaration; each plugin emits nothing, or one false fact for the extractor shadow. Each was
run on a scratch gate that differs from this head only in the check that stops it, and on main
before #25 (`beb6f01`, gates 0–5):

| Case | Head: full / no lint | Check removed: full / no lint | Main before #25: full / no lint |
|---|---|---|---|
| `shadow_model` | gate 3 / gate 3 | Challenge without `_root_`: ACCEPTED / ACCEPTED | ACCEPTED / ACCEPTED |
| `shadow_obligation_model` | gate 3 / gate 3 | Challenge without `_root_`: ACCEPTED / ACCEPTED | ACCEPTED / ACCEPTED |
| `shadow_extractor_model` | gate 3 / gate 3 | Challenge without `_root_`: ACCEPTED / ACCEPTED | ACCEPTED / ACCEPTED |
| `shadow_export_model` | gate 1 / gate 3 | Challenge without `_root_`: gate 1 / ACCEPTED | gate 1 / ACCEPTED |
| `shadow_root_component` | gate 3 / gate 3 | #25 round 1 (`_root_` in statements only): ACCEPTED / ACCEPTED | gate 3 / gate 3 |
| `shadow_root_export` | gate 1 / gate 3 | #25 round 1: gate 1 / ACCEPTED | gate 1 / gate 3 |

The two `export` cases stop at gate 1 in full runs because #24's model allowlist bans `export` (a
banned token, and not an allowed command). Without lint, gate 3 rejects them. The `_root_`-component
cases are rejected by main before #25 too, because its Challenge did not write `_root_`; they need
#25's round-1 form to be accepted.

The runner's new `expect` key `model_approved=yes` regenerates `models.lock` in the case's temporary
workspace. Without it, a case's own model is rejected at gate 0 (`model_tamper`, unchanged).

## Findings
- **nanoda overflowed its stack on the toy model's first adequacy proof** (`--paranoid` only; the
  other four kernels accepted it). The near miss at character offset 10 of the `é` file made
  `decide` compare whole facts, building each line's `String`. `holds_iff` now also states the
  fact's start offset and compares it first, so a misplaced fact is rejected with `Nat`
  arithmetic. Model authors should keep `decide` away from `String` construction on non-ASCII
  input. The fix landed in the spec PR.
- **`lake comparator` panics on a missing solution constant.** It prints `PANIC at
  LeanExport.dumpConstant … Constant … not found in environment` and exits 134, instead of
  `Const not found in solution`. Gate 6 reads that message. In gates 2–5, `failedGate` sees only
  `error:` and reports a plugin that lacks an obligation as gate 2 (sandbox build), not gate 3.
  It still rejects; only the gate number is off. Fixed in round 2 (`missing_obligation`).
- **A model that runs code could make gates 3 and 6 judge two elaborations** (verifier F21-1).
  One judging directory shares `.lake` between the two runs, and a model that forged a dependency's
  cached output hash in gate 6's run was rebuilt in the plugin's run. Lint stopped it; without lint
  the gate accepted it (`double_elaboration`). Fixed in round 3 by hashing the build outputs after
  each run.
- **#24's model allowlist rejects `sorry` in models.** After the rebase `emit_everything` is
  rejected at gate 1 in full runs (it was gate 6); without lint gate 6 still rejects it. `include_str`
  and `Classical.choose`, which round 2's denylist banned in models, pass the allowlist; see the
  design table.
- **Gate 6 masked #24's three model cases.** `model_notation`, `model_implemented_by` and
  `model_dotdot_import` carry a pre-gate-6 toy model with no `model.examples` or `model.adequate`.
  After the rebase their comparator-only runs were rejected at gate 6, so the corpus no longer
  showed that the comparator alone accepts them. Round 3 gives each model the toy's reviewed
  examples and adequacy proof, unchanged otherwise; their `expect` files are unchanged and all three
  are accepted without lint again.
- **A lookup-table model is adequate** (red team, `lookup_model`): its `Holds s f` says that `f` is listed
  for the golden file `s`. Against it, a lookup-table extractor passes every gate, with golden files as with
  near misses. This is an inherent limit. Owner review of `Holds` carries it, and later the mutation
  and corpus checks do. It is documented in `docs/process.md` and is not a cheat case, since no
  gate is expected to reject it.
- Cost (round 1): the honest `accept --paranoid` goes from about 36 s to about 63 s. Each run that reaches
  gate 6 without `--paranoid` adds about 15 s. In the corpus that is 11 runs, about 3 minutes:
  the five comparator-only accepts, and the three new cases twice each.

### Round 4

- **An approved, lint-clean model could pick its meaning and examples per plugin with `include_str`**
  (verifier F21-B1, opus). A model reads a judging-directory file the plugin controls
  (`../comparator.json`, `../Plugins/<P>.lean`) and, for the plugin being judged, means the weak
  model where only `require zz` holds, with weak examples it proves adequate. Gate 6 reads the same
  file, so it judges the weak model and the empty-for-`left-pad` extractor passes gates 0–6,
  `--paranoid` included. Round 2 had banned `include_str` in models; round 3 dropped that when it
  adopted #24's allowlist. **Fix:** `include_str` is added to `Lint.banned`, so gate 1 rejects it in
  every model and plugin. The two probes are added as `model_include_str` (reads `../comparator.json`)
  and `model_include_str_src` (reads `../Plugins/ToyRequire.lean`), both `model_approved=yes`,
  `full=1`, `comparator_only=accept`, with small literals so `--paranoid` does not run out of memory.
  Each is rejected at gate 1 with the ban and ACCEPTED in a full run with `include_str` removed from
  `banned` (shown on a scratch gate built from this head). `gate/LintTest.lean` gains a model and a
  plugin `include_str` reject case (now 147 cases: model 22/94, plugin 3/22).
- **`include_str` is the only `Init`/`Std` way a model reads a file's contents into a term.**
  Checked on the v4.35.0 toolchain sources: of the builtin term/tactic/command elaborators that do
  any `IO.FS`/`getEnv`/`Process` work,
  - `include_str` (`Init/Notation.lean`, `Lean/Elab/BuiltinTerm.lean`) reads a file into a `String`
    term — the vector, now banned;
  - `idbg` (`Lean/Parser/Term.lean`, `Lean/Elab/Idbg.lean`) yields a monadic (IO) value, not pure
    data, so it cannot inhabit `Mitos.Model`/`Mitos.ModelExamples`; at elaboration it only resolves
    its own source path (`IO.FS.realPath (getFileName)`) and starts a server task solely in editor
    mode (`Elab.inServer`), which the batch gate is not — no plugin-chosen file is read;
  - `bv_check "file.lrat"` / `bv_decide` (`Init/Tactics.lean`, `Lean/Meta/Tactic/BVDecide/*`) read an
    LRAT file from the source dir, but only as proof input to close a bitvector goal; they cannot
    read file contents into a definition's value, and the model's `model`/`examples` are elaborated
    before any proof;
  - `getEnv "LEAN_MANUAL_ROOT"` (`Lean/DocString/Links.lean`) only affects Verso docstring link
    rendering behind the `doc.verso` option; it produces no term data.
  Every command that would run arbitrary code at a model's elaboration (`#eval`, `run_cmd`,
  `initialize`, attributes, `set_option`) is already rejected by the model command allowlist, so no
  such elaborator fires. Conclusion: banning `include_str` closes the file-read-into-data channel.
- **Not in this round (follow-up issue):** a structural gate-6 defence that works without lint (a
  judging directory with no plugin files, or rebuild-and-compare); comparing the judging directory's
  core outputs against the trusted build (the hash check is one-directional); escaping blank-rendering
  code points such as U+2800 in `oneLine`; the docs saying lower-case hex and the recursive
  `models.lock` regeneration row. These are not regressions and each is caught by lint on the real
  (`--skip-lint`-free) acceptance path. `docs/process.md` now states that "does not rest on lint"
  covers the double-elaboration check only and that the hash check compares in one direction only.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] every existing cheat case fails at its expected gate, comparator-only results unchanged
- [x] each new cheat was accepted, or rejected at the wrong gate, before its fix, and is rejected
  at its expected gate after it
- [x] round 3: rebased onto #24 and #25; `double_elaboration` and the six shadow cases added, each
  shown accepted without its check; `oneLine` is an allowlist with a proof
- [x] round 4: `include_str` banned at gate 1 (`Lint.banned`); `model_include_str` and
  `model_include_str_src` added (full@1, comparator-only accept), each ACCEPTED with the ban removed;
  confirmed `include_str` is the only `Init`/`Std` file-read-into-data vector; minor findings deferred
  to a follow-up issue
- [x] owner adds `spec-approved` to the spec PR and merges it (#20)
- [ ] owner merges the gate PR
- [x] run-log record written (ops/runs/)
