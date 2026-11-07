# tasks/gate3-qualified-challenge.md

phase: 1
goal: The gate-3 Challenge states the obligations of `Mitos.Core`, the model the gate was given and the plugin's extractor, whatever else the imported model modules declare.
statement: none (gate fix)
touches: gate/MitosGate/Accept.lean (the generated Challenge text only), eval/cheats/shadow_obligation/, examples/acme/accepted/ToyRequire.json
must_not_touch: statements.lock, models.lock, core/, gate/MitosGate/Lint.lean, eval/cheats/run.sh, models
checks: build, imports, lock, core check, core comparator --paranoid, example build, scorer, accept-toy --paranoid, cheats
budget: 15 iterations · 2h wall · 500k tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Found by a red-team review. It has no row in `plan/phase-1.md`, which the owner keeps.
- Lean elaborates `theorem P.sound : T` with namespace `P` open, so `Mitos.SoundWrt` in `T`
  resolves to `P.Mitos.SoundWrt` if one exists, and `Models.X.model` to `P.Models.X.model`.
- The Challenge imports `Mitos.Core` and the model module, not the plugin. A shadow that only the
  plugin declares changes only the plugin's statements, and gate 3 already rejects that
  (`shadow_obligation`). A shadow in a model module reaches both sides, so they match.
- Fix: every name in the statements starts from `_root_`.
- The model-side case needs a pinned model. `eval/cheats/run.sh` gets `model_approved=yes`
  support in #21 (P1-009); the red team's `shadow_model` case joins the corpus with it.
- Not in this task: `core/Challenge/Resolver.lean` uses the same dotted form, but its only import
  is the locked `Mitos.Core`.

## Done when
- [x] on `main`, a pinned model that declares `ToyRequire.Models.ToyRequire.model`,
  `ToyRequire.Mitos.CompleteWrt` or `ToyRequire.ToyRequire.extractor` lets an extractor that
  fails an obligation for `Models.ToyRequire.model` pass gates 0–5. With the fix, gate 3 rejects
  all three.
- [x] `shadow_obligation` is rejected at gate 3 in both modes
- [x] the honest toy is accepted with `--paranoid`, and the record is regenerated
- [x] every existing cheat case behaves as its `expect` says
- [x] run-log record written (ops/runs/)
