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
- Design written at plan time with P2-006's, by the same arena. The contract sketch type-checks on Lean v4.35.0.
- The design was completed to build depth after P2-006 merged (#272).

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists. This amendment, written after P2-006 merged (#272), changes neither.

depth: build. The sketch under `types` is all of `examples/acme/Plugins/GoMod.lean`. Every
definition and statement is final text, and each `sorry` is a proof whose route under `statements`
closes as written. The sketch type-checks on Lean v4.35.0 against `main` at 9bc5b8b. `main` is at
a222e99 as this is written, and `examples/acme`, `core/`, `gate/` and `lean-toolchain` are the
same at 7b556a3 (where P2-006 merged), 9bc5b8b and a222e99. With the routes written in, the file
is 59 lines, and gates 0 to 6 ACCEPTED it with `--paranoid` in a scratch copy (fixtures, F1). The
named fixtures are F1 to F4.

revisit_when: none. P2-006 has merged, and the names under `types` are its names on `main`. The
builder still runs stop condition S1 first. Two events move this row, and neither is a redesign:
- A PR that changes `core/Mitos/` merges before this one. #277 (P2-001a) is open as this is
  written. The plugin builds unchanged against the core of its head 83361a9, because #277 leaves
  `Fact.lean`, `Lines.lean`, `Obligations.lean` and `ModelExamples.lean` alone. P2-001b (#204)
  adds a `FactKind` constructor, and the plugin never matches on `FactKind`. Only the record's
  `core_sha256` moves: re-record at the head after that rebase (check 6, R1).
- The owner answers O1 on #208 with "drop the fold". Then `types` becomes the probe of
  `tasks/P2-006-gomod-model.md` under the name `GoMod`.

modules: one topic per file. A build that outgrows this map reports it as a deviation.
- `examples/acme/Plugins/GoMod.lean`: the go.mod extractor, a fold over `Mitos.lines`, with its
  equation to the model and the three obligations. 60 lines (59 in the checked build). It copies
  the layout of `examples/acme/Plugins/ToyRequire.lean`: imports, `open`, one namespace, the
  definitions, one helper lemma, then `sound`, `anchored` and `complete`. Unlike the toy's, its
  helpers are `private`.
- `examples/acme/accepted/GoMod.json`: the record of the accept run. 11 lines, written by
  `accept --record`, last, in the shape of `accepted/ToyRequire.json`.

### Usage (caller's view)

The gate, from the repository root:

```
lake exe mitos-gate accept --workspace examples/acme --plugin GoMod --model Models.GoMod.model --paranoid --record
```

```
GATE 0 provenance: PASS
GATE 1 lint: PASS — 0 violation(s)
GATE 2 sandbox build: PASS
GATE 3 statements: PASS
GATE 4 axioms: PASS — propext, Quot.sound, Classical.choice
GATE 5 kernels: PASS — lean4lean, nanoda, con-leche, con-ron, paranoid
GATE 6 model adequacy: PASS — Models.GoMod.model.adequate : Mitos.Model.Adequate Models.GoMod.model Models.GoMod.model.examples, examples from Models.GoMod.Examples
recorded examples/acme/accepted/GoMod.json
VERDICT: ACCEPTED
```

What the extractor gives on the golden file `wholeFile`, in file order. Each line is a fact's
kind, identity kind, key, span start, span length in bytes, and scope:

```
GoMod.extractor.run Models.GoMod.wholeFile.file
  = [ provides  go-module  "example.com/app"   7   15  runtime,
      requires  go-module  "example.com/lib"   44  15  runtime,
      requires  go-module  "example.com/util"  69  16  runtime ]
```

Call sites:
- P2-009b's scorer: `import Plugins.GoMod`, then
  `(GoMod.extractor.run f.text).map (·, .extractor "GoMod")` on a file named `go.mod`. It is the
  toy's line in `factsOf` (`eval/score/Score.lean`) with the name changed.
- P2-008's differential runner: `GoMod.extractor.run text`. It compares the `provides` key with
  Go's `Module.Path` and the `requires` keys, in list order, with `Require[].Path`. For the lines
  outside the subset it reads `Models.GoMod.readings text`. List order is file order because of
  `GoMod.run_eq`, not because of the gate (deferrals).
- The interface is `GoMod.extractor` and four theorems: `GoMod.run_eq`, which a caller may cite,
  and the three obligations, which the gate judges. `Scan`, `scanLine` and `foldl_scanLine` are
  `private`. A file that imports `Plugins.GoMod` cannot name them (`Unknown identifier`), so a
  later reshape of a helper breaks no caller.
- Code that produces facts calls `GoMod.extractor.run`. `Models.GoMod.facts` is the spec and
  appears in statements only.

### How a builder goes wrong here

- A name in namespace `GoMod` that `Models.GoMod` also has, such as `facts`, `fact`, `model`,
  `entries` or `readings`. Inside the namespace the short name then means the plugin's. Gate 3
  catches a changed obligation. Nothing in the gate catches a changed `run_eq`; F3 prints it.
- A fold with no final `reverse`, or one that adds a fact twice. It builds, and `sound`,
  `anchored` and `complete` still prove, because they are about membership. A scratch plugin with
  both faults was ACCEPTED by gates 0 to 6 (fixtures, wrong folds). Only `run_eq` and F3 fail.
  Keep `run_eq` as stated and prove the three obligations through it.
- `private` dropped from a helper because the toy's helpers have none. The gate accepts both.
  `private` is what keeps P2-008 and P2-009b off the helpers.
- A banned name component (gate 1, `Lint.banned`): `init`, `prefix`, `meta`, `debug`, `export`,
  `syntax`, `native`, `macro`, `opaque`, `instance`, `Lean`, also as a named argument.
  `foldl scanLine (init := …)` is rejected with `[banned:init]`. The sketch passes the start
  state by position.
- `#eval`, or a `decide` on `List Fact`, in the plugin. Gate 1 rejects `#eval`, and such a
  `decide` compares `String`s in five kernels. The runs on files are scratch files.
- A case split with no name. With plain `cases reading.entry?` the `filterMap` side still holds
  `fun r => r.2.entry?`, and `simp only` ends with unsolved goals. The route names the equation:
  `cases h : reading.entry?`.
- `lake build` taken for the check. It passes with a `sorry`, which is only a warning: five for
  the sketch. No CI step lints or accepts `GoMod` until P2-012, so checks 2 and 4 run locally.
- A lemma added to a model file. `examples/acme/Models/` is locked and needs `spec-approved`. A
  helper lives in the plugin.
- The record written before the last rebase, written without `--paranoid`, or edited by hand.
- A comment that says the list is reversed. The field name `reversedFacts` says it.

types:
- Inputs, as they are on `main`. From `Models.GoMod` (`examples/acme/Models/GoMod.lean`):
  - `Mode.step (mode : Mode) (line : Nat × List Char) : Mode × Reading`
  - `Reading.entry? (reading : Reading) : Option Entry`, with
    `Entry := Mitos.FactKind × Nat × List Char`
  - `fact : Entry → Mitos.Fact`
  - `readingsFrom : Mode → List (Nat × List Char) → List (Nat × Reading)`
  - `readings s := readingsFrom .top (Mitos.lines s.toList)`
  - `entries s := (readings s).filterMap fun r => r.2.entry?`
  - `facts s := (entries s).map fact`
  - `model : Mitos.Model`, with `Holds s f := f ∈ facts s`
  - `facts_anchored {s : String} {f : Mitos.Fact} (h : f ∈ facts s) :
    f.span.text s.toList = some f.ident.key.toList`

  From the core: `Mitos.lines`, `Mitos.Extractor`, `Mitos.Anchored`, `Mitos.SoundWrt`,
  `Mitos.CompleteWrt`.
- Outputs: `GoMod.extractor : Mitos.Extractor`, whose `run` gives `Models.GoMod.facts`, in the
  same order, and the record.
- The sketch, the file in full. Each `sorry` is a proof; the routes are under `statements`.

```lean
import Mitos.Core
import Models.GoMod

open Mitos Models.GoMod

namespace GoMod

private structure Scan where
  mode : Mode
  reversedFacts : List Fact

private def scanLine (scan : Scan) (line : Nat × List Char) : Scan :=
  match scan.mode.step line with
  | (next, reading) =>
    { mode := next, reversedFacts := (reading.entry?.map fact).toList ++ scan.reversedFacts }

def extractor : Extractor where
  run s :=
    ((lines s.toList).foldl scanLine { mode := .top, reversedFacts := [] }).reversedFacts.reverse

private theorem foldl_scanLine (ls : List (Nat × List Char)) (scan : Scan) :
    (ls.foldl scanLine scan).reversedFacts =
      (((readingsFrom scan.mode ls).filterMap fun r => r.2.entry?).map fact).reverse ++
        scan.reversedFacts := by
  sorry

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

- `Scan` names the fold's state: the mode for the next line, and the facts so far, newest first.
  The contract had the pair `Mode × List Fact`, whose second part was reversed, and only the
  proof knew it. The core calls the same thing `reversedLine`, and the model `reversedWord`.
- `scanLine` holds no rule of go.mod. It calls `Mode.step`, turns the reading into at most one
  fact, and puts it in front. `run` reverses once, so it is linear in the file.
- A line is `Nat × List Char`, as in the model. `Mitos.lines` gives `Utf8ByteCount × List Char`,
  and `Utf8ByteCount` is an `abbrev` for `Nat`.
- The plugin imports `Mitos.Core` and `Models.GoMod` only. Its names (`Scan`, `scanLine`,
  `extractor`, `foldl_scanLine`, `run_eq`, `sound`, `anchored`, `complete`) share none with
  `Models.GoMod`.
- Gate 1 has no rule on `private` in a plugin; it leaves it out of models only. Gates 2 to 5
  passed with the three `private` helpers, with five kernels.

statements:
- What the gate generates. `accept` writes `Challenge/GoMod.lean` into its judging directory
  (`Accept.challenge` in `gate/MitosGate/Accept.lean`), with `import Mitos.Core` and
  `import Models.GoMod`. The builder does not write it. Its declarations:

```lean
def _root_.GoMod.extractor : _root_.Mitos.Extractor := sorry
theorem _root_.GoMod.anchored : _root_.Mitos.Anchored _root_.GoMod.extractor := sorry
theorem _root_.GoMod.sound : _root_.Mitos.SoundWrt _root_.Models.GoMod.model _root_.GoMod.extractor := sorry
theorem _root_.GoMod.complete : _root_.Mitos.CompleteWrt _root_.Models.GoMod.model _root_.GoMod.extractor := sorry
```

  Its `comparator.json` names `GoMod.anchored`, `GoMod.sound` and `GoMod.complete` as the
  theorems, `GoMod.extractor` as the definition, and `propext`, `Quot.sound`, `Classical.choice`
  as the axioms. Gate 3 compares each with the plugin's declaration of that name. Unfolded, they
  say:
  - `GoMod.anchored`: `∀ s, ∀ f ∈ GoMod.extractor.run s, f.span.text s.toList = some f.ident.key.toList`
  - `GoMod.sound`: `∀ s, ∀ f ∈ GoMod.extractor.run s, f ∈ Models.GoMod.facts s`
  - `GoMod.complete`: `∀ s f, f ∈ Models.GoMod.facts s → ∃ g ∈ GoMod.extractor.run s, g.kind = f.kind ∧ g.ident = f.ident`

  Gate 6 judges `Models.GoMod.model.adequate` against its own generated Challenge, as it did for
  P2-006's probe.
- The plugin's own: `GoMod.run_eq : ∀ (s : String), GoMod.extractor.run s = Models.GoMod.facts s`.
  The gate does not judge it. It is the only statement about order and count, which P2-008
  compares with Go's, so the verifier checks its text (F3).
- A helper the builder may reshape: `GoMod.foldl_scanLine`, which says what the fold holds after
  any lines from any state. `run_eq` is that lemma at the start state.
- Routes. Each closes as written on v4.35.0, and the file then builds with no warning:

```lean
-- foldl_scanLine
  induction ls generalizing scan with
  | nil => rfl
  | cons line rest ih =>
    rw [List.foldl_cons, ih]
    unfold scanLine
    rw [readingsFrom]
    rcases scan.mode.step line with ⟨next, reading⟩
    cases h : reading.entry? with
    | none =>
      simp only [h, Option.map_none, Option.toList_none, List.nil_append,
        List.filterMap_cons_none]
    | some entry =>
      simp only [h, Option.map_some, Option.toList_some, List.cons_append, List.nil_append,
        Option.some.injEq, List.filterMap_cons_some, List.map_cons, List.reverse_cons,
        List.append_assoc]

-- run_eq
  simp only [extractor, foldl_scanLine, List.append_nil, List.reverse_reverse, facts, entries,
    readings]

-- sound
  intro s f hf
  rw [run_eq] at hf
  exact hf

-- anchored
  intro s f hf
  rw [run_eq] at hf
  exact facts_anchored hf

-- complete
  intro s f hf
  exact ⟨f, by rw [run_eq]; exact hf, rfl, rfl⟩
```

  The `-- name` lines label the routes in this file only. The plugin has no comments.
- All three obligations go through `run_eq`, so gate 4's axiom check covers it too.
  `#print axioms GoMod.run_eq` gives `[propext, Classical.choice, Quot.sound]`.

reuse: `Models.GoMod.facts_anchored`, `Mode.step`, `Reading.entry?`, `fact`, `readingsFrom`;
`Mitos.lines`; the layout of `examples/acme/Plugins/ToyRequire.lean`; `List.foldl_cons`,
`List.filterMap_cons_none`, `List.filterMap_cons_some`, `List.map_cons`, `List.reverse_cons`,
`List.reverse_reverse`, `List.append_assoc`, `List.append_nil`, `List.nil_append`,
`List.cons_append`, `Option.map_none`, `Option.map_some`, `Option.toList_none`,
`Option.toList_some`, `Option.some.injEq`.

fixtures:
- F1, the accept run (Usage), ACCEPTED with five kernels named on gate 5. Measured with
  `--paranoid --record` on 4 vCPU and 15 GiB: five runs, 2 min 12 s to 3 min 1 s. The final text
  ran twice, at 2 min 51 s and 3 min 1 s, while other agents loaded the machine (load average 9),
  and both runs wrote the same record bytes. P2-006's probe took 2 min 10 s, one run.
- F2, P2-006's twelve golden files, with no new one, because a golden file is a locked model
  file: `wholeFile`, `commentedOutLine`, `excludeBlockIsNotRequired`, `moduleBlock`,
  `quotedPathIsNotRead`, `wrongArgumentCount`, `commentTouchingPath`, `carriageReturnIsNotInPath`,
  `parenTouchingVerb`, `charOffsetNotByteOffset`, `lonePunctuationIsNotAPath`, `quoteInsidePath`.
  With `GoMod.sound` and `GoMod.complete`, the core's `Mitos.Model.Adequate.sound_on_golden` and
  `complete_on_golden` tie the plugin to each of them as a set of facts.
- F3, the golden run, and F4, the Go run: one scratch file, `Run.lean`, never committed. F3 ties
  the compiled plugin to each golden file as a list: order, count, spans and scope. F4 runs it on
  the 19 go.mod files of the Go 1.24.7 distribution and compares its keys, in order, with
  `go mod edit -json`.

```lean
import Plugins.GoMod
import Models.GoMod.Examples

open Mitos

#check @GoMod.run_eq
#print axioms GoMod.run_eq

def keys (fs : List Fact) : List String :=
  fs.map fun f =>
    (match f.kind with | .provides => "provides " | .requires => "requires ") ++ f.ident.key

def main (paths : List String) : IO UInt32 := do
  let golden := Models.GoMod.model.examples.golden
  let differ := (golden.filter fun g => GoMod.extractor.run g.file != g.facts).length
  IO.println s!"golden: {golden.length} files, {differ} differ from their golden facts"
  for path in paths do
    let facts := GoMod.extractor.run (← IO.FS.readFile path)
    IO.println s!"{path}\t{String.intercalate "," (keys facts)}"
  return if differ == 0 then 0 else 1
```

```
cd examples/acme && lake env lean --run <scratch>/Run.lean $(find "$(go env GOROOT)" -name go.mod | sort) > <scratch>/lean.out
for f in $(find "$(go env GOROOT)" -name go.mod | sort); do printf '%s\t%s\n' "$f" "$(go mod edit -json "$f" | jq -r '[("provides " + .Module.Path)] + [.Require[]? | "requires " + .Path] | join(",")')"; done > <scratch>/go.out
grep -vP '\t' <scratch>/lean.out
grep -P '\t' <scratch>/lean.out | diff - <scratch>/go.out
```

  Expected, and measured at design time. The third command prints these three lines, and the
  fourth prints nothing, for 19 files and 84 facts. P2-006's Build notes have the same 84 for the
  model.

```
GoMod.run_eq : ∀ (s : String), GoMod.extractor.run s = Models.GoMod.facts s
'GoMod.run_eq' depends on axioms: [propext, Classical.choice, Quot.sound]
golden: 12 files, 0 differ from their golden facts
```

- Wrong folds, measured against the golden files. They show what each check can see. A scratch
  file defines its own wrong fold, because it cannot name the plugin's `private` helpers.

| Wrong fold | Golden files where the list differs | Where the set differs | What stops it |
|---|---|---|---|
| no final `reverse` | `wholeFile`, `carriageReturnIsNotInPath` | none | `run_eq` and F3 only |
| each fact added twice | the eight files that have a fact | none | `run_eq` and F3 only |
| the mode is not carried (always `.top`) | `wholeFile`, `excludeBlockIsNotRequired`, `moduleBlock`, `parenTouchingVerb` | the same four | `complete` has no proof, because `complete_on_golden` is false on those four; F3 too |

  One scratch plugin with the first two faults together, its obligations proved through a
  membership lemma, was ACCEPTED by gates 0 to 6 without `--paranoid` (54 s, one run).
- No kernel-checked example in the plugin file: a `decide` on `List Fact` compares `String`s.

### Checks, in order

From the repository root, at the head after the last rebase.

1. `cd examples/acme && lake build` prints `Build completed successfully`, with no `warning:`
   line for `Plugins/GoMod.lean`.
2. `lake build && lake exe mitos-gate lint examples/acme/Plugins/GoMod.lean` prints
   `0 violation(s)`.
3. `lake exe mitos-gate lock-models --workspace examples/acme --check` prints
   `examples/acme/models.lock up to date (7 models)`.
4. The accept run of Usage prints its nine lines. Run it last, after the last rebase, and commit
   `examples/acme/accepted/GoMod.json` as it wrote it. The record holds no time and no commit, so
   a second run at the committed head leaves `git status --porcelain examples/acme/accepted/`
   empty. The verifier makes that second run in its own worktree.
5. `git diff --name-only origin/main...HEAD` prints only `examples/acme/Plugins/GoMod.lean`,
   `examples/acme/accepted/GoMod.json`, `tasks/P2-007-gomod-plugin.md` and files under `ops/runs/`.
6. The record names the inputs of the head `h` itself. This needs no build and no checkout, only
   a clone that has the commit, and it prints nothing:

```
h=<head>
p=GoMod
sha() { sha256sum | cut -d' ' -f1; }
core() {
  git ls-tree -r --name-only "$h" core/Mitos | grep '\.lean$' | LC_ALL=C sort |
    while IFS= read -r f; do printf '%s\n' "${f#core/}"; git show "$h:$f"; done
}
diff <(git show "$h:examples/acme/accepted/$p.json" |
         jq -r '.toolchain, .plugin_sha256, .models_lock_sha256, .core_sha256') \
     <(git show "$h:lean-toolchain"
       git show "$h:examples/acme/Plugins/$p.lean" | sha
       git show "$h:examples/acme/models.lock" | sha
       core | sha)
```

   A printed line means the record is stale at `h`: run check 4 at that head and push the record.
   The command hashes the same bytes as `Accept.writeRecord`. If a `gate/` PR changes that
   function, this command changes with it, and check 4 stays the authority. The builder runs it
   at the head it reports, the verifier at the head it judges, and whoever makes the merge call
   at the head the merge pins (R1).
7. F3 and F4 print their expected lines. The numbers go in the PR body.
8. `lake exe mitos-gate runlog --head ops/runs`, and
   `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
   shows only `A` lines.
9. `.claude/scripts/plan-tasks.test.sh`, because this file changes.
10. In CI, `gate` is green. It builds the plugin (`cd examples/acme && lake build`) and accepts
    only the toy. The cheat runner copies `Plugins/GoMod.lean` into each case workspace
    (`CheatsRun.prepare`) and judges only `ToyRequire`, whose judging directory holds no other
    plugin file (`Accept.judge`). So no case's result can change.

### What `accepted/GoMod.json` records

The gate writes nine fields (`Accept.writeRecord`). At `main` a222e99:

| Field | Value | Moves when |
|---|---|---|
| `plugin` | `GoMod` | never |
| `model` | `Models.GoMod.model` | never |
| `toolchain` | `leanprover/lean4:v4.35.0` | P2-011 bumps it |
| `plugin_sha256` | `sha256sum examples/acme/Plugins/GoMod.lean` | any byte of the plugin changes |
| `models_lock_sha256` | `799b341d…536360e`, as in `ToyRequire.json` | a model file changes (`spec-approved`) |
| `core_sha256` | `8ae154a0…edfb184`, as in `ToyRequire.json` | any `.lean` file under `core/Mitos/` changes; #277 moves it to `f7d74757…5e6cb9e` |
| `challenge_sha256` | `f8358eed694771f11fcb8d9458b3c2b851e7e06b9181d492dbc01edd6e0d1eca` | `Accept.challenge` changes (`gate/`) |
| `adequacy_challenge_sha256` | `092eb667328ff8b84068aa5987151963e1be324bf6e5c6e0b3a62d4360203b79` | `Accept.adequacyChallenge` changes (`gate/`) |
| `paranoid` | `true` | a run without `--paranoid` writes `false`, which fails Done when |

### Risks and stop conditions

Risks:
- R1. A stale record can merge. If a core PR merges first, the updater rebases this PR, the
  content id stays the same, the verdict carries and `gate` stays green, because no CI step reads
  the record. Measured: against the core of #277's head, a record written on `main` fails check 6
  on its `core_sha256` line. So check 6 runs at the head the merge pins. A printed line means the
  PR owner re-records at that head, and the new head, a small-fix head, gets a verifier.
- R2. If this PR merges first, #277's branch holds a stale `GoMod.json` from its next rebase on
  (deferrals).
- R3. `run_eq`'s proof unfolds `facts`, `entries` and `readings`. A model PR that reshapes them
  breaks the plugin's build. Such a PR needs `spec-approved`, moves `models.lock` and re-accepts
  the plugin anyway.
- R4. F1's times come from a shared machine. The plugin has no `decide`, so its share of gate 5
  is small.
- R5. The routes name 15 core lemmas. A toolchain that renames one breaks the build, not trust.
  The nightly canary judges only the toy plugin and does not build `examples/acme`, so the break
  shows at P2-011's bump.

Stop conditions for the builder:
- S1. Before writing, after `git fetch origin main`, this prints nothing:

```
git diff --stat a222e99 origin/main -- examples/acme/Models examples/acme/models.lock core/Mitos/Core/Fact.lean core/Mitos/Core/Lines.lean core/Mitos/Core/Obligations.lean core/Mitos/Core/ModelExamples.lean lean-toolchain
```

  If it prints a file, stop; this design is amended first. #277's merge keeps it empty.
- S2. A gate fails and the fix is outside `examples/acme/Plugins/GoMod.lean`: stop and report.
  Never edit `gate/`, `examples/acme/Models/`, `models.lock` or `core/`.
- S3. Gate 3 fails: the plugin states something else than the Challenge. Look for a shadowed
  name in namespace `GoMod`. The fix is in the plugin.
- S4. A kernel rejects, or the accept runs past 10 minutes: stop and report which kernel and the
  comparator tail. The smaller plugin of O1 is the owner's call, not a fallback.
- S5. A route does not close: the builder may reshape `foldl_scanLine`, its statement included.
  It does not change the statement of `run_eq` or of the three obligations, does not weaken
  `run_eq` to a membership statement and does not drop it. If `run_eq` has no proof for the fold
  as sketched, stop and report.
- S6. The builder stops when the PR is open on `main`, `gate` is green, checks 1 to 9 pass at the
  head and every thread is answered. It reports that head as merge-ready. No path here is the
  owner's, so an agent merges it, after check 6 at the head the merge pins.

cut_line: ships the plugin, its proofs and the record. It leaves the CI accept step to P2-012
(#213), the differential runner to P2-008 (#209) and the fixture to P2-009b (#211).

deferrals:
- To P2-012 (#213) and #275 item 1: a CI step that runs the GoMod accept with `--record` and then
  `git diff --exit-code examples/acme/accepted/`. Until it lands, CI checks the plugin only
  through `lake build` with Lean's kernel, where a `sorry` is a warning. Checks 2, 4 and 6 are
  the builder's, the verifier's and the merging agent's. The canary runs only the toy accept, so
  P2-012 adds GoMod's there too.
- To every row that re-records `accepted/*.json` (the core rows and P2-011; `plan/phase-2.md`,
  Shared files 1): re-record `GoMod.json` too, once it exists. #277 (P2-001a) was built before it
  existed. If this PR merges first, the root tells #277's owner, and check 6 with `h` at #277's
  rebased head prints the `core_sha256` line. A later round of #277 re-records `GoMod.json`. #277
  gets no round only for this: if it merges without one, `GoMod.json` on `main` is stale until
  P2-001b (#204) re-records it, as `ToyRequire.json` was before #272, and the root notes that on
  #275. Nothing reads a record, and gate 0 reads the live core.
- To P2-011 (#147): a toolchain bump that breaks a tactic in the plugin re-proves it and
  re-records. The plugin is not locked, so that is not a spec change.
- To P2-008 (#209): F4 is its runner in small. File order comes from `GoMod.run_eq`. Where its
  Lean code states anything about order, it cites `GoMod.run_eq`, so a plugin change that drops
  or weakens it breaks P2-008's build. #275 item 3 (Go's lax parser) is recorded there.
- To P2-009b (#211): the call site under Usage. Identity kind `go-module`, scope `runtime`
  (P2-006's deferrals).
- To this PR's follow-up issue, no row (`core/Mitos/Core/Obligations.lean` is spec, and `gate/`
  is the owner's): the three obligations are about membership, so the gate accepts a plugin that
  reorders or repeats the model's facts (fixtures, wrong folds). The toy plugin has the same
  freedom. Here `run_eq` pins order and count, and only a reader checks that it is there and
  says what it should. Whether acceptance itself should pin them is the owner's call.
- From P2-006: its probe plugin, `run := Models.GoMod.facts`, is the smaller plugin of O1.
- From #275: item 1 is check 6 and R1 here, and P2-012's step. Item 2 is wording in P2-006's
  task file, which this row does not touch. Item 3 is P2-008's.

owner_decisions:
- Settled by the plan: the plugin is a fold over `Mitos.lines`; it proves anchored, sound and
  complete; `accepted/GoMod.json` is written last; an agent merges it. P2-006 has merged (#272),
  so there is no stack and the PR opens on `main`.
- **O1, open. Keep the fold?** The model is itself a walk, so `run := Models.GoMod.facts` passes
  the same gates with one-line proofs. Measured: the fold is 59 lines, and the probe is 18 as
  `tasks/P2-006-gomod-model.md` has it. The fold's accept took 2 min 12 s to 3 min 1 s over five
  runs, and the probe's 2 min 10 s, one run (F1), so these runs show no difference in time. The
  fold proves the same list. Default: keep the fold, as the plan says, until the owner says
  otherwise on #208.
- This design's defaults, not owner rulings:
  - The fold's state is the structure `Scan`, not the contract's pair. Reason: the reversed list
    gets a name, at a cost of three lines.
  - The helpers are `private`. Reason: `run_eq` and the obligations stay the only facts about
    the plugin a caller can use, at a cost of three keywords.
  - P2-007 does not wait for #277. It merges once verified and green, and the record is handled
    as R1 and the deferrals say. Reason: holding it blocks P2-008 and P2-009b, and a stale record
    harms nothing until P2-012's check lands.

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
