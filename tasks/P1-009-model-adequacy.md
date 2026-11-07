# tasks/P1-009-model-adequacy.md

phase: 1
goal: A plugin is accepted only if its model ships reviewed examples and proves it agrees with
  them, so neither the extractor that emits nothing nor the one that emits everything can pass
  against it.
statement: Mitos.ModelExamples, Mitos.Model.Adequate, Mitos.Extractor.empty,
  Mitos.ModelExamples.everything, Mitos.Model.Adequate.{empty_not_complete, everything_not_sound},
  Mitos.Model.{nothing_holds_not_adequate, everything_holds_not_adequate} (new)
touches: spec PR: core/Mitos/Core/ModelExamples.lean, core/Mitos/Core.lean, statements.lock,
  examples/acme/{Models/ToyRequire.lean, models.lock, accepted/ToyRequire.json};
  gate PR: gate/MitosGate/Accept.lean, eval/cheats/run.sh, eval/cheats/{empty_extractor,
  emit_everything, weakened_adequacy}/, docs/process.md, .github/workflows/ci.yml (step name),
  examples/acme/accepted/ToyRequire.json, plan/phase-1.md (P1-009 row), ops/runs/
must_not_touch: core/Challenge/, core/comparator.json, existing eval/cheats/*/ cases and expect files
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
- `Models.X.model.examples : Mitos.ModelExamples`: two lists of `(file, fact)` pairs.
  - `holds`: facts the model must say hold.
  - `nearMisses`: facts it must reject.
- `Models.X.model.adequate : Mitos.Model.Adequate Models.X.model Models.X.model.examples`.

`Model.Adequate` holds when:
- both lists are non-empty
- every example's fact holds and is anchored in its file
- no near miss's fact holds

Two locked theorems turn this into the vacuity checks:
- `Adequate.empty_not_complete`: `Extractor.empty` is not complete.
- `Adequate.everything_not_sound`: `ex.everything`, which emits every example fact on every file,
  is not sound.

Two corollaries are tripwires for the definition itself:
- `nothing_holds_not_adequate`: the model where nothing holds is adequate for no examples.
- `everything_holds_not_adequate`: the model where everything holds is adequate for no examples.

If a later edit dropped the non-emptiness conjuncts, both would stop proving.

**Choices and reasons.**

| Choice | Reason | Rejected alternative |
|---|---|---|
| The meaning of adequacy is a locked core definition (`Mitos.Model.Adequate`), and the vacuity facts are core theorems | "People review statements": gate 3 means `Mitos.Anchored`/`SoundWrt`/`CompleteWrt`, so gate 6 should mean a core definition too, not a string in gate code. The vacuity facts are proved once, for every model | Statements only in the gate's generated Challenge, with vacuity proved by tactics the gate generates. That avoids a core change, but the toy model needs a spec PR anyway (`models.lock`) |
| Examples live in the model file, pinned by `models.lock` | Examples the plugin author chose would prove nothing | Examples in the plugin, or in an unpinned file |
| A naming convention under the model constant (`<model>.examples`, `<model>.adequate`) | No new CLI flag; works for several models in one module | A new field on `Mitos.Model`. It would break the anonymous `⟨fun _ _ => True⟩` in `swapped_model`, which would then fail at gate 2 instead of 3 |
| Gate 6 judges the model module itself as the comparator solution. The model and its examples are definition holes; the adequacy theorem is the statement | The same machinery as gates 2–5: kernel-term statement match, axiom allow-list, sandbox, and `--paranoid` kernels. Gate 0 already pins the hole values | A gate-generated solution that re-exports the model's theorem. It adds a file and checks the same thing |
| A second, fresh judging directory, without the plugin, after gates 0–5 pass | Nothing the plugin's sandboxed build wrote to `.lake` can reach the model's check. Gate numbers stay in order, and existing cheats never reach gate 6 with a weak model, so no existing expectation changes | Reusing gate 3's directory saves about 15 s, but a plugin's elaboration (lint skipped) can write `.olean`s there |
| Every gate-6 failure is reported as gate 6, with a reason read from the comparator's output: missing declaration, illegal axiom, statement mismatch, kernel rejection | Fails closed: anything but a clean comparator run rejects | — |
| Gate 0 also rejects a `--model` that is not a dotted identifier | Gate 6 interpolates it into a generated `def`, not only into a term | — |
| The acceptance record gains `adequacy_challenge_sha256` | The record pins what acceptance meant | — |

**Toy model.**
- Examples: `require left-pad` at byte 0, and the second line of `"require é\nrequire left-pad\n"`
  at byte 11.
- Near misses:
  - a commented-out line
  - the character offset 10 (the P1-005 bug)
  - the whole line `require left-pad` as the package
- Near misses are proved by `decide` through `holds_iff`, a decidable restatement of `Holds`.

**Cheats** (all `model_approved=yes`, so the runner pins their model; each is accepted by today's
gates 0–5 and rejected at gate 6, full and comparator-only):

| Case | Model | Extractor | Gate 6 says |
|---|---|---|---|
| `empty_extractor` | nothing holds; no examples (a model written before gate 6) | emits nothing | declarations missing |
| `emit_everything` | every line is a requirement; the reviewer's examples; adequacy is `sorry` (unprovable: the whole-line near miss holds) | emits every line | illegal axiom `sorryAx` |
| `weakened_adequacy` | nothing holds; proves only "near misses fail" under the name `model.adequate` | emits nothing | statement mismatch |

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
  It still rejects; only the gate number is off. Left for a separate gate PR, with a cheat case.
- Cost: the honest `accept --paranoid` goes from about 36 s to about 63 s. Each run that reaches
  gate 6 without `--paranoid` adds about 15 s. In the corpus that is 11 runs, about 3 minutes:
  the five comparator-only accepts, and the three new cases twice each.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] every existing cheat case fails at its expected gate, comparator-only results unchanged
- [x] each new cheat is accepted by today's gates 0–5 and rejected at gate 6
- [ ] owner adds `spec-approved` to the spec PR and merges it
- [ ] owner merges the gate PR
- [x] run-log record written (ops/runs/)
