# tasks/gate3-qualified-challenge.md

phase: 1
goal: The gate-3 Challenge states the obligations of `Mitos.Core`, the model the gate was given and the plugin's extractor, whatever names the imported model modules declare. This covers name shadows only: a model that changes syntax (a `notation` for `_root_.Mitos.CompleteWrt`, say) is a lint concern, handled by the model allowlist in #24, not by qualifying names.
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
- `_root_.` in `T` is not enough on its own (round 2, found by the verifier): with `P` open,
  Lean looks `_root_.Mitos.CompleteWrt` up as `P._root_.Mitos.CompleteWrt` before it strips
  `_root_`, and a model can declare that name, directly or with an `export` inside
  `namespace P._root_.Mitos`. `theorem _root_.P.sound` declares the same name without opening
  `P`, so nothing under `P` is in scope. #21's `adequacyChallenge` uses the same form.
- The Challenge imports `Mitos.Core` and the model module, not the plugin. A shadow that only the
  plugin declares changes only the plugin's statements, and gate 3 already rejects that
  (`shadow_obligation`). A shadow in a model module reaches both sides, so they match.
- Fix: every name in the Challenge starts from `_root_`, the declared ones (`_root_.P.sound`) as
  well as the ones its statements use.
- Not in this task: `core/Challenge/Resolver.lean` uses the same dotted form, but its only import
  is the locked `Mitos.Core`.

## Model-side cheat cases: pending `model_approved=yes`
A model-side case brings its own `Models/ToyRequire.lean`, so `eval/cheats/run.sh` must re-pin
`models.lock` for it. On `main` it cannot (the case would stop at gate 0); #21 (P1-009) adds
`model_approved=yes`. When that is on `main`, these cases join the corpus, each with
`full=3`, `comparator_only=reject@3` and `model_approved=yes`. Each model is the honest
`examples/acme/Models/ToyRequire.lean` plus the declaration below; each plugin is the toy with an
extractor that emits nothing (or, for the extractor shadow, one false fact), spelling the
shadowed name as the Challenge spells it.

| Case | Added to the model | ACCEPTED (--paranoid) on |
|---|---|---|
| `shadow_model` | `namespace ToyRequire.Models.ToyRequire` / `def model` where nothing holds | `main` |
| `shadow_obligation_model` | `def ToyRequire.Mitos.CompleteWrt … := True` | `main` |
| `shadow_extractor_model` | `namespace ToyRequire.ToyRequire` / a reference `ofLine` and `extractor` | `main` |
| `shadow_root_component` | `def ToyRequire._root_.Mitos.CompleteWrt … := True` | round-1 head (25fce96) |
| `shadow_root_export` | `namespace ToyRequire._root_.Mitos` / `export Weak (CompleteWrt)`, with `Weak.CompleteWrt … := True` | round-1 head (25fce96) |

The `_root_`-component forms of the model and extractor shadows
(`ToyRequire._root_.Models.ToyRequire.model`, `ToyRequire._root_.ToyRequire.extractor`) were also
accepted at the round-1 head; all are rejected at gate 3 with this fix, in both modes.

## Done when
- [x] on `main`, a pinned model that declares `ToyRequire.Models.ToyRequire.model`,
  `ToyRequire.Mitos.CompleteWrt` or `ToyRequire.ToyRequire.extractor` lets an extractor that
  fails an obligation for `Models.ToyRequire.model` pass gates 0–5. With the fix, gate 3 rejects
  all three.
- [x] the same with a literal `_root_` component (`ToyRequire._root_.Mitos.CompleteWrt`, `…model`,
  `…extractor`, or an `export` into `ToyRequire._root_.Mitos`): accepted at the round-1 head,
  rejected at gate 3 with the fix
- [x] `shadow_obligation` is rejected at gate 3 in both modes
- [x] the honest toy is accepted with `--paranoid`, and the record is regenerated
- [x] every existing cheat case behaves as its `expect` says
- [ ] the model-side cases above join `eval/cheats/` once `model_approved=yes` is on `main`
- [x] run-log record written (ops/runs/)
