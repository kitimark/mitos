# tasks/P2-007-gomod-plugin.md

phase: 2
goal: `GoMod.extractor` emits exactly the facts `Models.GoMod.model` holds, in file order, gates 0 to 6 accept it with `--paranoid`, and `examples/acme/accepted/GoMod.json` records that.
statement: `GoMod.anchored`, `GoMod.sound` and `GoMod.complete`, as the gate's generated Challenge states them; the plugin's own `GoMod.run_eq`
touches: examples/acme/Plugins/GoMod.lean, examples/acme/accepted/GoMod.json (written by the gate, last), this file, ops/runs/
must_not_touch: examples/acme/Models/, examples/acme/models.lock, examples/acme/accepted/ToyRequire.json, core/, statements.lock, gate/, eval/, .github/, plan/
checks: acme build, plugin lint, accept GoMod with --paranoid --record at the head after the last rebase
budget: 15 iterations · 2h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-007 in `plan/phase-2.md` (go.mod track, wave W2), issue #208. It stacks on
  P2-006's PR (#207, `tasks/P2-006-gomod-model.md`), and an agent merges it once P2-006 has
  merged. P2-008 (#209) and P2-009b (#211) wait for it.
- The sketch this row starts from is "go.mod plugin over the line layer" in
  [#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795051235). The owner's
  decisions are in
  [#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085).
- #160 (plan review follow-ups) has no item for this row.
- Design written at plan time with P2-006's, by the same arena. No Lean was run for it.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: contract only. The sketch under `types` shows the shape. It becomes a build-depth design
when P2-006's names are on `main`.

revisit_when: re-check after P2-006's PR merges. The inputs below are P2-006's names as designed.
If its PR changes one, amend this file first.

modules:
- `examples/acme/Plugins/GoMod.lean`: the extractor and its three obligations; 60 lines; copies
  `examples/acme/Plugins/ToyRequire.lean`.
- `examples/acme/accepted/GoMod.json`: written by `accept --record`, last.

types:
- Inputs, from `Models.GoMod` as P2-006 merges it: `Mode`, `Mode.step`, `Reading.entry?`, `fact`,
  `facts`, `entries`, `readingsFrom`, `model`, `facts_anchored`.
- Outputs: `GoMod.extractor : Mitos.Extractor`, whose `run` gives the facts in file order, and the
  record. P2-009b's scorer calls `(GoMod.extractor.run f.text).map (·, .extractor "GoMod")`.
- The sketch, with each `sorry` a proof the builder writes:

```lean
import Mitos.Core
import Models.GoMod

open Mitos Models.GoMod

namespace GoMod

def scanLine (state : Mode × List Fact) (line : Nat × List Char) : Mode × List Fact :=
  match state.1.step line with
  | (next, reading) => (next, (reading.entry?.map fact).toList ++ state.2)

def extractor : Extractor where
  run s := ((lines s.toList).foldl scanLine (.top, [])).2.reverse

theorem run_eq (s : String) : extractor.run s = facts s := by
  sorry

theorem sound : SoundWrt model extractor := by
  sorry

theorem anchored : Anchored extractor := by
  sorry

theorem complete : CompleteWrt model extractor := by
  sorry

end GoMod
```

statements:
- `GoMod.run_eq (s : String) : extractor.run s = facts s`. Route: for every `ls`, `mode` and
  `acc`,
  `(ls.foldl scanLine (mode, acc)).2 = (((readingsFrom mode ls).filterMap fun r => r.2.entry?).map fact).reverse ++ acc`,
  by induction on `ls`.
- `GoMod.sound` and `GoMod.complete`: rewrite with `run_eq`. `model.Holds s f` is `f ∈ facts s`.
- `GoMod.anchored`: `run_eq`, then `Models.GoMod.facts_anchored`.
- The gate generates the Challenge that states the three obligations against
  `Models.GoMod.model`. The builder does not write it.

reuse: `Models.GoMod.facts_anchored`; `List.foldl_cons`, `List.filterMap_cons`,
`List.reverse_cons`, `List.mem_map`.

fixtures:
- The accept run, ACCEPTED with five kernels named on gate 5:

```
lake exe mitos-gate accept --workspace examples/acme --plugin GoMod --model Models.GoMod.model --paranoid --record
```

- No kernel-checked example in the plugin file: a `decide` on `List Fact` compares `String`s. The
  core's `sound_on_golden` and `complete_on_golden` tie an accepted plugin to P2-006's twelve
  golden files.
- A scratch run, not committed: the extractor on the go.mod files of a Go distribution gives Go's
  `Module.Path` and `Require[].Path` (`go mod edit -json`).

cut_line: ships the plugin, its proofs and the record. It leaves the CI accept step to P2-012
(#213), the differential runner to P2-008 (#209) and the fixture to P2-009b (#211).

deferrals:
- To P2-012 (#213): the CI accept step. Until it lands, no CI step notices a stale
  `accepted/GoMod.json`.
- To every row that re-records `accepted/*.json` (the core rows and P2-011; `plan/phase-2.md`,
  Shared files 1): re-record `GoMod.json` too, once it exists.
- From P2-006: its probe plugin, `run := Models.GoMod.facts`, is the smaller plugin of O1 below.

owner_decisions:
- Settled by the plan: the plugin is a fold over `Mitos.lines`; it proves anchored, sound and
  complete; `accepted/GoMod.json` is written last; an agent merges it once P2-006 has merged.
- **O1, open. Keep the fold?** The model is itself a walk, so `run := Models.GoMod.facts` passes
  the same gates with one-line proofs. The fold costs about 30 lines and proves the same list.
  Default: keep the fold, as the plan says, until the owner says otherwise on #208.

## Rationale

### Problem

The plugin must emit what the reviewed model holds and prove it, without a second statement of
any rule of the model.

### Shape

`scanLine` calls the model's `Mode.step`, so the plugin holds the iteration and no rule. `foldl`
builds the list in reverse, and `run` reverses it once. One lemma, `run_eq`, gives the three
obligations.

### Tradeoffs accepted

- We accept a second walk over the lines, in exchange for the plugin the plan names and a gate 3
  that judges a proof with content.

### Alternatives considered

- `run := Models.GoMod.facts`. It is the smallest plugin, and gates 3 to 5 then judge three
  one-line proofs. It is owner decision O1.
- A plugin with its own tokenizer. It states every rule twice, and the plan puts the tokenizer
  and the block state in the model.

### Open questions and risks

- If P2-006's PR changes `Mode.step` or `facts`, this contract changes with it (`revisit_when`).
- Each later core PR moves `core_sha256`, so the record is stale until that PR re-records it
  (deferrals).

### Next implementation step

After P2-006 merges, re-check the inputs against `main`. Then write `scanLine`, `extractor` and
`run_eq`.

## Done when
- [ ] `VERDICT: ACCEPTED` for `--plugin GoMod --model Models.GoMod.model --paranoid --record` at
      the head after the last rebase, with five kernels named on gate 5
- [ ] `examples/acme/accepted/GoMod.json` committed as that run wrote it
- [ ] the scratch run against `go mod edit -json` reported in the PR body
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
