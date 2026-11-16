# tasks/P2-010-nightly-scorecard.md

phase: 2
goal: `lake --dir eval/score exe mitos-score --all eval/fixtures [<baseline>]` prints one nightly scorecard: for each fixture and edge type the precision, recall, confirmed precision, inferred precision and most derivations; the most derivations any repo-level edge has, checked against the D1 threshold of 8; what changed against `<baseline>`, which is what `mitos-score --numbers eval/fixtures` printed on an earlier run, such as `main`'s; then every fixture's card. `mitos-score <fixture-dir>` prints exactly what it prints on `main`.
statement: none (tooling task, nothing in `statements.lock`). Four scorer theorems, not locked: `Score.Nightly.derivations_keys`, `Score.Nightly.le_most`, `Score.Nightly.most_mem`, `Score.Nightly.changed_eq_nil`. Also 18 build-time `#guard` pins in the same file (G1 to G18 under `statements`)
touches: eval/score/Main.lean, eval/score/Score/Nightly.lean (new), tasks/P2-010-nightly-scorecard.md, ops/runs/
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, eval/fixtures/, eval/score/Score.lean, eval/score/Score/GoMod.lean, eval/score/Policy.lean (if #332 has merged), eval/score/lakefile.toml, eval/score/lake-manifest.json, eval/score/lean-toolchain, examples/acme/, core/, eval/diff/, eval/mutants/, .github/, docs/, plan/, .claude/
checks: start checks (S1, S2), the scorer builds with no warning (check 1), axioms (check 2), single-fixture cards unchanged (check 3), `--numbers` is N2 (check 4), `--all` is N3 (check 5), own baseline is N4 (check 6), moved baseline is N5 (check 7), errors and usage are N6 (check 8), scratch roots N7 to N12 (check 9), the real fixtures after P2-009a, N13 (check 10), wrong variants (check 11), changed paths (check 12), the run-log check (check 13), `plan-tasks.test.sh` (check 14), `gate` green in CI (check 15)
budget: 5 iterations · 1h wall · 300k tokens (the text under `types` is final; the work is S1 and S2, copying, building, running and reporting)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-010 in `plan/phase-2.md` (`:144`, wave W6 at `:194`), issue #212. It waits for P2-009a (#210) and P2-009b (#211). P2-009b merged as #324. P2-009a waits for P2-001b (#204), which is not merged; its branch `claude/p2-001b-chains` is at 3d939da. P2-012 (#213) waits for this row. An agent carries and merges it (class A, "Who decides"). Brief role: PR owner, routine, `sonnet` at `high`. No path here is a trust path and no statement is locked, so one verifier on the model that did not write most of the diff.
- The row's cells (`:220`). Owns: `eval/score/Main.lean` and a scorecard module in `eval/score/Score/`. Reads: every fixture. Also must not touch: `eval/fixtures/`. Shared-files rule 4 (`:239-242`) lets a row edit `Score.lean` only as its cell says. P2-009a owns `collapse` and one import there, and #332 edits `score`, so this row edits no line of `Score.lean`.
- Inputs from the rows before this one:
  - P2-001a (`tasks/P2-001a-keyed-edges.md:633`): "derivations per repo-level edge" is the number of edge records that share one `repoKey`. That this equals the number of derivations follows from `EdgesNodup`, `Sound`, `Complete` and `derivations_key_inj`.
  - P2-001b (`tasks/P2-001b-chains.md:810`): bound records count too, and `twoBindings` is a two-derivation example. A chain edge shows as `env/runtime` (`:806`).
  - P2-009b (`tasks/P2-009b-gomod-fixture.md:520`): `gomod` is one of every fixture, its most derivations is 2 (F6 there, `mono` → `lib` from two go.mod files), and F2 is `main`'s go.mod card.
  - `docs/process.md:190`: the numbers never fail a run, and a scorer error does. `:492-494`: the diff against `main`'s scorecard comes with the nightly scorecard.
- Issue #325 (scorer policy Q1 to Q3) is answered by Grok Bot in PR #332, open at 856832b. It keeps same-repo edges (Q1), makes `score` fail on a label kind that no fact has (Q2), and reads every `go.mod` (Q3). It edits `Score.lean` (`score` and two new definitions above it), `Score/GoMod.lean` and `eval/score/lakefile.toml`, and adds `eval/score/Policy.lean`. This row writes none of those files. The table under Usage says which output depends on which answer.
- Designed at `main` eac85d2 on Lean v4.35.0. The files under `types` were built and run in three scratch copies made with `git archive`: `main` (44 jobs); `main` with #332's four `eval/score` files at 856832b on top (46 jobs, with #332's `Policy` library); and P2-001b's branch at 3d939da, whose core gains `Derivation.bound` and `Edge.through` (44 jobs). Each build was clean, and N1 to N5 hash the same on all three.
- Exit criterion 5 (`plan/phase-2.md:25`) needs a scorecard for every fixture, precision and recall per edge type with the chain and go.mod types included, the diff against `main`'s, and the most derivations any repo-level edge has. This row writes the code. P2-012 runs it nightly and posts it.
- Landing this file. `.claude/scripts/plan-tasks.pending` lists `P2-010`, and `plan-tasks.test.sh` fails once a listed row has a task file with a Design block. So the PR that lands this design also deletes the line `P2-010` from that list. `.claude/` is the owner's path, so the owner merges that PR. The build PR stays agent-merged.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file lists.

depth: build, except the chain fixture's own numbers. Under `types` are the whole of `eval/score/Score/Nightly.lean` and the whole diff of `eval/score/Main.lean`, as final text with every proof and pin written in. In a scratch copy of `main` at eac85d2, `lake --dir eval/score build` ends with `Build completed successfully (44 jobs).` and prints no `warning:` line; that build kernel-checks the four theorems and runs the 18 `#guard`s. N1 to N12 are as stated. The chain fixture's rows are contract only (N13): the code needs no change for them, but they cannot be measured before P2-009a merges.

revisit_when: re-check after #210 (P2-009a) merges. That also covers #204 (P2-001b), which P2-009a waits for. The re-check is S1 to S3 and N13. #332 changes no output here, whichever order it merges in (measured at 856832b).

modules:
- `eval/score/Score/Nightly.lean` *(new)*, 276 lines. It owns one topic, the nightly scorecard on top of one card: the derivation count per repo-level edge, the per-type counts and their check against the card's own text, the numbers file (three line kinds, written and read back), the line-set diff, the D1 line and the report. It copies the layout of `eval/score/Score/GoMod.lean`: imports, one namespace, `open Mitos`, definitions, theorems, then pins. Its helpers are `private`, so another file cannot reach them (measured: `#check @Score.Nightly.consistent` from a scratch file is an unknown identifier). It imports `Score`, and `Score.lean` does not import it, so there is no cycle and no edit to `Score.lean`. `Main.lean` imports it, so the default target `mitos-score` builds it with no lakefile change.
- `eval/score/Main.lean`, 35 → 78 lines. It gains `scoreDir`, `fixtureName`, `scoreAll` (the walker over a fixtures root) and two modes, `--numbers` and `--all`. A lone argument that starts with `-` prints the usage. `sortPaths` and `loadRepos` keep every byte, and the single-fixture mode prints the same bytes.

### How the scorer works on `main` (what this row builds on)
1. `Main.main` takes one fixture directory, parses `labels.tsv` (`parseLabels`, `Score.lean:65`), reads `repos/` (`loadRepos`), calls `score` (`:98`) and prints `Scorecard.render` (`:104`). It exits 0, 1 on a scorer error, or 2 on bad usage. An IO error, such as a missing `labels.tsv`, is uncaught and exits 1.
2. `Scorecard` (`:92`) holds `facts` (the ingested `Located` list), `predicted : List (RepoKey × Status)` (`collapse` of `resolve facts`), `labels` and `unresolved`. It holds no edge records, so the derivation counts are gone once `score` returns. This row re-runs `resolve` on `c.facts`. That needs no re-ingest and no `Except`.
3. `edgeType`, `renderEdge`, `ratio` and `statusName` are public, and the sketch reuses all four.
4. CI builds `eval/score` and runs it on `eval/fixtures/toy` only (`ci.yml:296-301`), then posts that card on PRs. No job runs the go.mod card, and nothing computes a diff.

### Usage (caller's view)

```
lake --dir eval/score exe mitos-score <fixture-dir>                      # one card, as on main
lake --dir eval/score exe mitos-score --numbers eval/fixtures > n.tsv     # the lines a later run compares with
lake --dir eval/score exe mitos-score --all eval/fixtures [n-before.tsv]  # the nightly scorecard
```

- Every directory directly under the root is one fixture, taken in name order (`chain`, `gomod`, `toy` once P2-009a lands). No name is skipped and no list names them.
- A fixture fails, and its card is replaced by `Scorer error: …`, when its `labels.tsv` is missing, its `repos/` is missing, a file cannot be read, `parseLabels` or `score` fails, or `Nightly.checked` finds a problem: the per-type counts disagree with the card's own rows, or one of its numbers lines would not read back (a tab inside an extracted key). The messages hold no path. The other fixtures still score and print.
- `--all` prints, in this order: `## Nightly scorecard` with the fixture count and, when one failed, a bold line naming the failed fixtures; `### Every fixture`, one table row per fixture and edge type, then the D1 line; `### Against the baseline`; then each card or error, each after one empty line. A scored fixture's card is byte for byte what `mitos-score <fixture-dir>` prints (check 5).
- The numbers file has one line per record, tab-separated, and its first field names the kind:

| Kind | Fields after the kind | One line per |
|---|---|---|
| `rates` | fixture, edge type, precision, recall, confirmed precision, inferred precision, most derivations | edge type of the card, in the card's order |
| `edge` | fixture, the edge as the card prints it, `confirmed`, `inferred` or `not in the card`, derivations | repo-level edge the resolver made, in its order |
| `label` | fixture, the label as the card prints an edge | label, in `labels.tsv` order |

  The ratio fields are `Score.ratio` strings such as `0.83 (5/6)` or `n/a`, so a count that moves shows even when the rounded ratio does not. `parseNumbers` reads only these kinds, each with its own field count, and `Nightly.checked` reads every line the run writes, so the writer and the reader cannot drift apart.
- "Against the baseline" is one of: `No baseline given, so nothing was compared.`; `No change against the baseline.` exactly when this run's lines and the baseline's are the same set (`changed_eq_nil`); or the changes. For each fixture and edge type whose `rates` line changed, the baseline row and this run's row, with `none` on a side that has no such line. Then `**The hand labels changed.**` and each `label` line on one side only. Then each `edge` line on one side only. A fixture that failed in this run is left out of the comparison and gets the line `` `<name>` was not scored in this run, so it is not compared. ``
- Exit codes:
  - `<fixture-dir>`: as on `main`, and 2 for a lone argument that starts with `-`.
  - `--numbers`: 0 with every line on stdout; 1 with nothing on stdout and one `<fixture>: <error>` line on stderr per failed fixture, so a broken run cannot become the next baseline.
  - `--all`: 0 when every fixture scored; 1 when one did not, with the whole report printed; 1 with nothing printed when the baseline file has a line of an unknown kind or the wrong field count (`baseline line N: …` on stderr); 2 on bad usage.
  - The numbers, the D1 line included, never change the exit code. A fixtures root or baseline path that cannot be read is an uncaught IO error and exits 1.
- The output holds no path, time or random value, so two runs on one tree are byte equal, and a scratch copy of a fixture prints the same bytes as the original.
- P2-012 calls exactly the commands above (deferrals).

| #325 question | #332's answer | The opposite answer | What this row does | What depends on the answer |
|---|---|---|---|---|
| Q1, same-repo edges | kept, and a label makes one a hit | left out of the card | `derivations` counts every repo-level edge the resolver made (`derivations_keys`), so the D1 line and each type's "most derivations" are the same under both answers. An edge the card leaves out has the status `not in the card` in its `edge` line, and when it holds the most, the D1 line adds "which that fixture's card leaves out". | The card's own counts, and so the precision and recall in `rates`. N9 measures both answers. |
| Q2, a label kind no fact has | `score` fails | it scores as a miss | Under #332 that fixture's card is `Scorer error: label kind "go-mod" is not among the extracted facts`, the bold line names it, `--all` exits 1 and `--numbers` prints nothing. Under the miss answer the fixture scores, with one more `rates` line (`go-mod/runtime`, `n/a`, `0.00 (0/1)`, `n/a`, `n/a`, `0`) and one more `label` line. | The exit code, and whether a typo shows as a failure or as a row. N12 measures both. |
| Q3, `go.mod` under `testdata/`, `.x/`, `_x/` | every `go.mod` is read | those directories are skipped | Nothing. `Score.GoMod.reads` decides. `loadRepos` reads every file, and the fixture walker skips no directory. | Only a fixture that has such a directory, and `main` has none. |

### How a builder goes wrong here
- Adding a line to each card, or changing `render`. That moves the single-mode bytes that CI posts, P2-009b's F2 and F3, and #332's `native_decide` card theorems. The nightly output lives only in `--all` (N1, check 5).
- Counting derivations only for the card's predicted keys (W1). The D1 number would then depend on Q1, and an edge that the scorer drops would hide its derivations from the D1 tripwire. `derivations_keys` stops proving.
- Editing `Score.lean` to put edges or counts into `Scorecard`. That edit is outside the cell, and it collides with P2-009a's `collapse` edit and #332's edit of `score`.
- Recounting the per-type numbers with a rule that differs from `render`'s (W5). G5 fails the build, and on a real fixture `Nightly.checked` fails it with "the nightly numbers disagree with the card".
- A one-sided diff (W2): `changed_eq_nil` stops proving, and a fixture or label that disappeared would not show.
- `most` with `min` (W3), or a maximum that no edge has (W4): `le_most` or `most_mem` is false.
- A baseline of numbers only. A label swap, one hard label out and one easy label in, keeps every count but raises recall. The `label` lines show which label moved (N10, W7).
- Parsing the ratio strings back into numbers to print `+0.17` deltas. That needs a `Nat` parser, a ratio recomputation and string theorems that `decide` cannot reduce. The line-set diff shows both sides and needs none of these.
- A fixture list in the workflow (`--all toy gomod`) or a list of required names in code. Either is one more list to keep in step with `eval/fixtures/`. Discovery holds "every fixture", and a fixture that disappears shows against the baseline as `none` rows and as labels only in the baseline.
- Computing the baseline by running this head's scorer on `main`'s fixture tree. That measures changes to the fixtures, not to the code.
- Printing the scored fixtures' lines from `--numbers` when one failed (W11). A partial file could then become the next baseline, and every line of the failed fixture would read as removed.
- Reporting an IO error with Lean's message. That message holds the absolute path of the runner's checkout, so the post would differ between machines. The walker uses fixed messages.
- Making the helpers public. An agent then imports them, and they become interface.
- `native_decide`, or a `sorry`. Check 1 sees a `sorry` warning, and check 2 sees an extra axiom.
- Committing the scratch fixtures of N6 to N12. `eval/fixtures/` is outside this row's paths, and any directory there is scored every night.

types:
- Inputs, unchanged on `main`: `Score.Scorecard` with the fields `facts`, `predicted` and `labels`; `Score.score`; `Scorecard.render`; `Score.edgeType`, `Score.renderEdge`, `Score.ratio` and `Score.statusName`; `Score.parseLabels`; `Score.SourceFile`; `Mitos.Impl.resolve : List Located → Resolution`; `Edge.repoKey`; `RepoKey`'s `DecidableEq`. P2-001b keeps every one of these (built at 3d939da), and so does #332 (built at 856832b).
- `eval/score/Score/Nightly.lean`, the file in full:

```lean
import Score

namespace Score.Nightly

open Mitos

def d1Threshold : Nat := 8

def derivations (c : Scorecard) : List (RepoKey × Nat) :=
  let es := (Mitos.Impl.resolve c.facts).edges
  (es.map (·.repoKey)).eraseDups.map fun k => (k, es.countP (·.repoKey == k))

def most : List (RepoKey × Nat) → Nat
  | [] => 0
  | d :: ds => max d.2 (most ds)

private structure TypeCounts where
  edgeType : String
  predicted : Nat
  labelled : Nat
  tp : Nat
  confirmed : Nat
  confirmedTp : Nat
  inferred : Nat
  inferredTp : Nat

private def typeCounts (c : Scorecard) : List TypeCounts :=
  let pred := c.predicted.map (·.1)
  ((pred ++ c.labels).map edgeType).eraseDups.map fun t =>
    let p := pred.filter (edgeType · == t)
    let l := c.labels.filter (edgeType · == t)
    let trust (s : Status) :=
      c.predicted.filter (fun (e, s') => edgeType e == t && s' == s) |>.map (·.1)
    let hits (ks : List RepoKey) := (ks.filter c.labels.contains).length
    { edgeType := t, predicted := p.length, labelled := l.length, tp := (p.filter l.contains).length,
      confirmed := (trust .confirmed).length, confirmedTp := hits (trust .confirmed),
      inferred := (trust .inferred).length, inferredTp := hits (trust .inferred) }

private def TypeCounts.cardLines (t : TypeCounts) : List String :=
  let trust (s : Status) (n tp : Nat) :=
    s!"| {t.edgeType} | {statusName s} | {n} | {tp} | {n - tp} | {ratio tp n} |"
  [s!"| {t.edgeType} | {t.predicted} | {t.labelled} | {t.tp} | {t.predicted - t.tp} | " ++
      s!"{t.labelled - t.tp} | {ratio t.tp t.predicted} | {ratio t.tp t.labelled} |",
   trust .confirmed t.confirmed t.confirmedTp, trust .inferred t.inferred t.inferredTp]

private def consistent (c : Scorecard) (card : String) : Bool :=
  (typeCounts c).all fun t => t.cardLines.all (card.splitOn "\n").contains

def numbers (name : String) (c : Scorecard) : List String :=
  let ds := derivations c
  let line (fs : List String) := "\t".intercalate fs
  (typeCounts c).map (fun t => line ["rates", name, t.edgeType, ratio t.tp t.predicted,
      ratio t.tp t.labelled, ratio t.confirmedTp t.confirmed, ratio t.inferredTp t.inferred,
      toString (most (ds.filter (edgeType ·.1 == t.edgeType)))]) ++
    ds.map (fun (k, n) => line ["edge", name, renderEdge k,
      ((c.predicted.lookup k).map statusName).getD "not in the card", toString n]) ++
    c.labels.map fun k => line ["label", name, renderEdge k]

private def arity : String → Option Nat
  | "rates" => some 8
  | "edge" => some 5
  | "label" => some 3
  | _ => none

def parseNumbers (txt : String) : Except String (List String) := do
  let mut out := #[]
  let mut n := 0
  for l in txt.splitOn "\n" do
    n := n + 1
    if l.isEmpty then continue
    let fs := l.splitOn "\t"
    let tag := fs.headD ""
    let some k := arity tag | throw s!"line {n}: unknown line kind {repr tag}"
    unless fs.length == k do
      throw s!"line {n}: a line of kind `{tag}` has {k} tab-separated fields, found {fs.length}"
    out := out.push l
  return out.toList

private def problem (name : String) (c : Scorecard) : Option String :=
  if !consistent c (c.render name) then some "the nightly numbers disagree with the card"
  else match parseNumbers ("\n".intercalate (numbers name c)) with
    | .error e => some s!"a numbers line of this fixture would not read back ({e})"
    | .ok _ => none

structure Result where
  name : String
  card : Except String Scorecard

def checked (name : String) : Except String Scorecard → Except String Scorecard
  | .ok c => match problem name c with
    | some e => .error e
    | none => .ok c
  | .error e => .error e

def numbersAll (rs : List Result) : Except (List String) (List String) :=
  match rs.filterMap fun r => match r.card with | .error e => some s!"{r.name}: {e}" | .ok _ => none with
  | [] => .ok (rs.flatMap fun r => match r.card with | .ok c => numbers r.name c | .error _ => [])
  | es => .error es

def changed (cur base : List String) : List String :=
  cur.filter (!base.contains ·) ++ base.filter (!cur.contains ·)

private def fields (line : String) : List String := line.splitOn "\t"

private def kind (line : String) : String := (fields line).headD ""

private def fixtureOf (line : String) : String := ((fields line).drop 1).headD ""

private def row (run : String) (line : String) : String :=
  let fs := (fields line).drop 1
  "| " ++ " | ".intercalate (fs.take 2 ++ [run] ++ fs.drop 2) ++ " |\n"

private def header : String :=
  "| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision " ++
  "| Most derivations |\n|---|---|---|---|---|---|---|---|\n"

private def item (side : String) (line : String) : String :=
  match fields line with
  | ["edge", n, e, s, d] => s!"- `{n}`, {side}: {e}, {s}, derivations {d}\n"
  | ["label", n, e] => s!"- `{n}`, {side}: {e}\n"
  | _ => s!"- {side}: {line}\n"

private def diff (cur base : List String) : String := Id.run do
  let gone := base.filter (!cur.contains ·)
  let new := cur.filter (!base.contains ·)
  let of (k : String) (ls : List String) := ls.filter (kind · == k)
  let mut out := ""
  unless (of "rates" gone).isEmpty && (of "rates" new).isEmpty do
    out := out ++ header
    for k in ((of "rates" new ++ of "rates" gone).map fun l => (fields l).take 3).eraseDups do
      let absent := "\t".intercalate (k ++ List.replicate 5 "none")
      let side (ls : List String) := match ls.filter fun l => (fields l).take 3 == k with
        | [] => [absent]
        | ls => ls
      for l in side gone do out := out ++ row "baseline" l
      for l in side new do out := out ++ row "this run" l
  unless (of "label" gone).isEmpty && (of "label" new).isEmpty do
    out := out ++ "\n**The hand labels changed.**\n"
    for l in of "label" gone do out := out ++ item "label only in the baseline" l
    for l in of "label" new do out := out ++ item "label only in this run" l
  unless (of "edge" gone).isEmpty && (of "edge" new).isEmpty do
    out := out ++ "\nRepo-level edges that changed:\n"
    for l in of "edge" gone do out := out ++ item "only in the baseline" l
    for l in of "edge" new do out := out ++ item "only in this run" l
  return out

def summary (rs : List Result) (base : Option (List String)) : String := Id.run do
  let ok := rs.filterMap fun r => match r.card with | .ok c => some (r.name, c) | .error _ => none
  let failed := (rs.filter (!·.card.isOk)).map (·.name)
  let cur := ok.flatMap fun (n, c) => numbers n c
  let mut out := s!"## Nightly scorecard\n\n{rs.length} fixtures, {ok.length} scored.\n"
  unless failed.isEmpty do
    out := out ++ s!"\n**Not every fixture scored ({", ".intercalate (failed.map (s!"`{·}`"))}), " ++
      "so the numbers below cover the others only.**\n"
  out := out ++ "\n### Every fixture\n\n" ++ header
  for l in cur.filter (kind · == "rates") do out := out ++ row "this run" l
  let top := most (ok.flatMap fun (_, c) => derivations c)
  let at? := ok.findSome? fun (n, c) => ((derivations c).find? (·.2 == top)).map fun d => (n, c, d.1)
  match at? with
  | none => out := out ++ "\nNo fixture has a repo-level edge, so no derivations were counted.\n"
  | some (n, c, k) =>
    out := out ++ s!"\nMost derivations any repo-level edge has: {top}, {renderEdge k} in fixture `{n}`"
    unless c.predicted.any (·.1 == k) do out := out ++ ", which that fixture's card leaves out"
    out := out ++ s!". D1 reopens above {d1Threshold}.\n"
    if top > d1Threshold then
      out := out ++ s!"\n**Above {d1Threshold}: D1 reopens (`plan/phase-2.md`, Scope decisions).**\n"
  out := out ++ "\n### Against the baseline\n\n"
  match base with
  | none => out := out ++ "No baseline given, so nothing was compared.\n"
  | some b =>
    let b' := b.filter fun l => !failed.contains (fixtureOf l)
    if changed cur b' = [] then out := out ++ "No change against the baseline.\n"
    else out := out ++ diff cur b'
    for n in failed.filter fun n => b.any (fixtureOf · == n) do
      out := out ++ s!"\n`{n}` was not scored in this run, so it is not compared.\n"
  return out

private def cardOf (r : Result) : String :=
  match r.card with
  | .ok c => c.render r.name
  | .error e => s!"### Scorecard: fixture `{r.name}`\n\nScorer error: {e}\n"

def report (rs : List Result) (base : Option (List String)) : String :=
  summary rs base ++ String.join (rs.map fun r => "\n" ++ cardOf r)

theorem derivations_keys (c : Scorecard) :
    (derivations c).map (·.1) = ((Mitos.Impl.resolve c.facts).edges.map (·.repoKey)).eraseDups := by
  simp [derivations, List.map_map, Function.comp_def]

theorem le_most {ds : List (RepoKey × Nat)} {d : RepoKey × Nat} (h : d ∈ ds) :
    d.2 ≤ most ds := by
  induction ds with
  | nil => cases h
  | cons x xs ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

theorem most_mem {ds : List (RepoKey × Nat)} (h : ds ≠ []) : ∃ d ∈ ds, d.2 = most ds := by
  induction ds with
  | nil => exact absurd rfl h
  | cons x xs ih =>
    by_cases hx : most xs ≤ x.2
    · exact ⟨x, List.mem_cons_self, by simp [most, Nat.max_eq_left hx]⟩
    · have hne : xs ≠ [] := by rintro rfl; simp [most] at hx
      obtain ⟨d, hd, hde⟩ := ih hne
      exact ⟨d, List.mem_cons_of_mem _ hd, by simp [most]; omega⟩

theorem changed_eq_nil {cur base : List String} :
    changed cur base = [] ↔ ∀ l, l ∈ cur ↔ l ∈ base := by
  simp only [changed, List.contains_eq_mem, List.append_eq_nil_iff, List.filter_eq_nil_iff,
    Bool.not_eq_eq_eq_not, Bool.not_true, decide_eq_false_iff_not, Decidable.not_not]
  exact ⟨fun ⟨h1, h2⟩ l => ⟨h1 l, h2 l⟩,
    fun h => ⟨fun l => (h l).1, fun l => (h l).2⟩⟩

private def pinKey : RepoKey :=
  { requiringRepo := "a", providingRepo := "b", ident := { kind := "toy", key := "x" },
    scope := .runtime }

private def pinFiles (n : Nat) : List SourceFile :=
  [{ repo := "a", path := "deps.toy", text := String.join (List.replicate n "require x\n") },
   { repo := "b", path := "PROVIDES", text := "provide x\n" }]

private def pin (n : Nat) (labels : List RepoKey := [pinKey]) : List Result :=
  [{ name := "pin", card := checked "pin" (score (pinFiles n) labels) }]

private def pinNumbers (n : Nat) : List String :=
  match numbersAll (pin n) with
  | .ok ls => ls
  | .error _ => []

private def has (hay needle : String) : Bool := (hay.splitOn needle).length > 1

#guard pinNumbers 2 ==
  ["rates\tpin\ttoy/runtime\t1.00 (1/1)\t1.00 (1/1)\t1.00 (1/1)\tn/a\t2",
   "edge\tpin\t`a` → `b` (toy/runtime `x`)\tconfirmed\t2",
   "label\tpin\t`a` → `b` (toy/runtime `x`)"]

#guard (parseNumbers ("\n".intercalate (pinNumbers 2))).toOption == some (pinNumbers 2)

#guard (parseNumbers "rates\tpin\ttoy/runtime\t1.00 (1/1)\n").toOption.isNone

#guard (parseNumbers "card\tpin\n").toOption.isNone

#guard match score (pinFiles 1) [pinKey] with
  | .ok c => consistent c (c.render "pin") && !consistent c ""
  | .error _ => false

#guard has (summary (pin 8) none) "has: 8, `a` → `b` (toy/runtime `x`) in fixture `pin`. D1 reopens above 8.\n"

#guard !has (summary (pin 8) none) "**Above 8"

#guard has (summary (pin 9) none) "**Above 8: D1 reopens"

#guard has (summary (pin 1) none) "No baseline given, so nothing was compared."

#guard has (summary (pin 1) (some (pinNumbers 1))) "No change against the baseline."

#guard !has (summary (pin 1) (some [])) "No change"

#guard has (summary (pin 2) (some (pinNumbers 1))) "| pin | toy/runtime | baseline | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | n/a | 1 |"

#guard has (summary (pin 1 []) (some (pinNumbers 1))) "**The hand labels changed.**\n- `pin`, label only in the baseline: `a` → `b` (toy/runtime `x`)\n"

#guard has (summary (pin 1) (some ((pinNumbers 1).map (·.replace "pin" "gone")))) "| gone | toy/runtime | this run | none | none | none | none | none |"

#guard has (summary [{ name := "pin", card := .error "broken" }] (some (pinNumbers 1)))
  "`pin` was not scored in this run, so it is not compared."

#guard !has (summary [{ name := "pin", card := .error "broken" }] (some (pinNumbers 1))) "| none |"

#guard has (summary [{ name := "pin", card := .error "broken" }] none) "**Not every fixture scored (`pin`)"

#guard (numbersAll [{ name := "pin", card := .error "broken" }]) matches .error ["pin: broken"]

end Score.Nightly
```

- `eval/score/Main.lean`, the whole diff against `main`:

```diff
@@ -1,11 +1,18 @@
 import Score
+import Score.Nightly
 
 open Score
 
 def usage : String := "usage: mitos-score <fixture-dir>
+       mitos-score --all <fixtures-dir> [<baseline>]
+       mitos-score --numbers <fixtures-dir>
   <fixture-dir>/repos/<repo>/...   the fixture repos
   <fixture-dir>/labels.tsv         hand labels (src, dst, kind, key, scope; tab-separated)
-Prints the scorecard as Markdown."
+  <fixtures-dir>/<fixture>/        every directory is one fixture, taken in name order
+  <baseline>                       what --numbers printed on another run, such as main's
+Prints the scorecard as Markdown. --all prints the nightly scorecard: every fixture's numbers,
+the most derivations of one repo-level edge, the diff against <baseline>, then every card.
+--numbers prints the lines a later run reads as <baseline>, and none if a fixture fails."
 
 def sortPaths (ps : Array System.FilePath) : List System.FilePath :=
   ps.toList.mergeSort (·.toString ≤ ·.toString)
@@ -22,14 +29,50 @@
       out := out.push { repo, path, text := ← IO.FS.readFile p }
   return out.toList
 
+def scoreDir (dir : System.FilePath) : IO (Except String Scorecard) := do
+  match parseLabels (← IO.FS.readFile (dir / "labels.tsv")) with
+  | .ok labels => return score (← loadRepos dir) labels
+  | .error e => return .error e
+
+def fixtureName (dir : System.FilePath) : String :=
+  (dir.components.filter (!·.isEmpty)).getLast?.getD dir.toString
+
+def scoreAll (root : System.FilePath) : IO (List Nightly.Result) := do
+  let mut out := #[]
+  for d in sortPaths ((← root.readDir).map (·.path)) do
+    unless ← d.isDir do continue
+    let name := fixtureName d
+    let card ←
+      if !(← (d / "labels.tsv").pathExists) then pure (.error "labels.tsv is missing")
+      else if !(← (d / "repos").isDir) then pure (.error "repos/ is missing")
+      else try Nightly.checked name <$> scoreDir d catch _ => pure (.error "a file could not be read")
+    out := out.push { name, card }
+  return out.toList
+
 def main (args : List String) : IO UInt32 := do
-  let [dir] := args | IO.eprintln usage; return 2
-  let dir : System.FilePath := dir
-  let labels ← match parseLabels (← IO.FS.readFile (dir / "labels.tsv")) with
-    | .ok ls => pure ls
+  match args with
+  | [dir] =>
+    if dir.startsWith "-" then
+      IO.eprintln usage
+      return 2
+    match ← scoreDir dir with
+    | .ok c => IO.print (c.render (fixtureName dir)); return 0
     | .error e => IO.eprintln e; return 1
-  match score (← loadRepos dir) labels with
-  | .ok c =>
-    IO.print (c.render ((dir.components.filter (!·.isEmpty)).getLast?.getD dir.toString))
-    return 0
-  | .error e => IO.eprintln e; return 1
+  | ["--numbers", root] =>
+    match Nightly.numbersAll (← scoreAll root) with
+    | .ok ls => for l in ls do IO.println l
+                return 0
+    | .error es => for e in es do IO.eprintln e
+                   return 1
+  | "--all" :: root :: rest =>
+    let base ← match rest with
+      | [] => pure (Except.ok none)
+      | [b] => (·.map some) <$> Nightly.parseNumbers <$> IO.FS.readFile b
+      | _ => IO.eprintln usage; return 2
+    match base with
+    | .error e => IO.eprintln s!"baseline {e}"; return 1
+    | .ok base =>
+      let rs ← scoreAll root
+      IO.print (Nightly.report rs base)
+      return if rs.all (·.card.isOk) then 0 else 1
+  | _ => IO.eprintln usage; return 2
```

- The interface is `Score.Nightly.d1Threshold`, `derivations`, `most`, `numbers`, `parseNumbers`, `Result`, `checked`, `numbersAll`, `changed`, `summary`, `report` and the four theorems. `Main` uses `Result`, `checked`, `numbersAll`, `parseNumbers` and `report`. The rest is `private`.
- `TypeCounts` holds one edge type's counts once, and both the `rates` line and the three card rows that `consistent` looks for are printed from it. `TypeCounts.cardLines` copies the row text of `Scorecard.render`, because `render` lives in `Score.lean`, outside this cell. G5 and `Nightly.checked` fail when the two disagree (R3).

statements:
- `Score.Nightly.derivations_keys : (derivations c).map (·.1) = ((resolve c.facts).edges.map (·.repoKey)).eraseDups`. The count covers every repo-level edge the resolver made, each once, whatever the card keeps. Axioms `[propext, Quot.sound]`.
- `Score.Nightly.le_most : d ∈ ds → d.2 ≤ most ds`. The number printed as "most derivations" bounds every repo-level edge's count, so a wrong maximum cannot hide the D1 tripwire. Axioms `[propext]`.
- `Score.Nightly.most_mem : ds ≠ [] → ∃ d ∈ ds, d.2 = most ds`. The maximum is some edge's count, not a number above all of them. With `le_most` it fixes `most` exactly. Axioms `[propext, Quot.sound]`.
- `Score.Nightly.changed_eq_nil : changed cur base = [] ↔ ∀ l, l ∈ cur ↔ l ∈ base`. The report says "No change against the baseline" exactly when this run and the baseline hold the same lines. A line that appeared or disappeared always shows. Axioms `[propext, Classical.choice, Quot.sound]`.
- All four are general, with no `decide` on strings, and CI's `checks` job kernel-checks them through `lake --dir eval/score build`.
- The pins, in file order. Each is a `#guard` that the build evaluates, because string splitting and `render` do not reduce in the kernel (#332 needed `native_decide` for its card theorems). The pins that need a card run the real `score` on a two-repo toy fixture written in the file (`pinFiles n`: `a/deps.toy` with `n` lines `require x`, `b/PROVIDES` with `provide x`, one label `a` → `b`). The others use literal lines or a failed `Result`.
  - G1: the three numbers lines of `pinFiles 2`, exactly (`rates … 2`, `edge … confirmed 2`, `label …`).
  - G2: those lines read back unchanged through `parseNumbers`.
  - G3, G4: a `rates` line with 4 fields and a line of an unknown kind are refused.
  - G5: `consistent` holds for the card `render` prints and fails against an empty card.
  - G6, G7, G8: the D1 line at 8 derivations, with no bold line at 8 and the bold line at 9.
  - G9: with no baseline the report says nothing was compared.
  - G10: against its own lines the report says "No change against the baseline."
  - G11: against an empty baseline it does not say "No change".
  - G12: a changed `rates` line shows the baseline row.
  - G13: a label that only the baseline has shows under "The hand labels changed."
  - G14: a fixture that disappeared shows a `none` row.
  - G15, G16: a fixture that failed in this run is "not scored in this run, so it is not compared", and no `none` row stands for it.
  - G17: the bold line names a failed fixture.
  - G18: `numbersAll` returns the error, not lines, when a fixture failed.
- Not pinned in the build, and checked by the builder's runs: each card inside `--all` equals the single-mode card (check 5), and the walker's fixed messages (N6).

reuse: `Score.score`, `Scorecard`, `Scorecard.render`, `Score.edgeType`, `Score.renderEdge`, `Score.ratio`, `Score.statusName`, `Score.parseLabels` and `Score.SourceFile` unchanged; `loadRepos` and `sortPaths` in `Main.lean` unchanged; `Mitos.Impl.resolve`, `Edge.repoKey`; `List.countP`, `List.eraseDups`, `List.lookup`, `List.contains_eq_mem`, `List.filter_eq_nil_iff`, `Except.isOk`. The layout of `Score/GoMod.lean`. No new fixture directory and no lakefile change.

fixtures: build and run everything at the head. Outputs are compared by sha256. Scratch roots live under `<scratch>/p2010-fx`, never in the repository. The root `two` is a copy of `eval/fixtures/gomod` and `eval/fixtures/toy` only, so N2 to N5 and N10 stay checkable after P2-009a adds `chain`.
- N1, the single-fixture cards are unchanged. `mitos-score eval/fixtures/toy` hashes to `17c55e9cfa3a9db873c50c980cf2cbea62195fe2eebecde3edc0a13add38f21a` (P2-009b's F3) and `mitos-score eval/fixtures/gomod` to `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf` (F2), before and after the change, on all three bases.
- N2, `mitos-score --numbers <r>/two` prints these 27 lines and exits 0 (sha256 `1e767d18bbc39fed9389feac5f58b3bfd946889908bf9254a9937c53b8943000`):

```
rates	gomod	go-module/runtime	0.83 (5/6)	0.83 (5/6)	1.00 (4/4)	0.50 (1/2)	2
edge	gomod	`app` → `lib` (go-module/runtime `example.com/lib`)	confirmed	1
edge	gomod	`app` → `log` (go-module/runtime `example.com/log`)	inferred	1
edge	gomod	`app` → `log-fork` (go-module/runtime `example.com/log`)	inferred	1
edge	gomod	`lib` → `util` (go-module/runtime `example.com/util`)	confirmed	1
edge	gomod	`mono` → `lib` (go-module/runtime `example.com/lib`)	confirmed	2
edge	gomod	`mono` → `util` (go-module/runtime `example.com/util`)	confirmed	1
label	gomod	`app` → `lib` (go-module/runtime `example.com/lib`)
label	gomod	`app` → `log-fork` (go-module/runtime `example.com/log`)
label	gomod	`app` → `cli` (go-module/runtime `example.com/cli`)
label	gomod	`lib` → `util` (go-module/runtime `example.com/util`)
label	gomod	`mono` → `lib` (go-module/runtime `example.com/lib`)
label	gomod	`mono` → `util` (go-module/runtime `example.com/util`)
rates	toy	toy/runtime	0.71 (5/7)	0.83 (5/6)	1.00 (3/3)	0.50 (2/4)	1
edge	toy	`app` → `lib-pad` (toy/runtime `left-pad`)	inferred	1
edge	toy	`app` → `pad-fork` (toy/runtime `left-pad`)	inferred	1
edge	toy	`app` → `ui-kit` (toy/runtime `ui-kit`)	confirmed	1
edge	toy	`app` → `date-lib` (toy/runtime `naïve-date`)	confirmed	1
edge	toy	`ui-kit` → `lib-pad` (toy/runtime `left-pad`)	inferred	1
edge	toy	`ui-kit` → `pad-fork` (toy/runtime `left-pad`)	inferred	1
edge	toy	`web` → `date-lib` (toy/runtime `naïve-date`)	confirmed	1
label	toy	`app` → `lib-pad` (toy/runtime `left-pad`)
label	toy	`app` → `ui-kit` (toy/runtime `ui-kit`)
label	toy	`app` → `date-lib` (toy/runtime `naïve-date`)
label	toy	`ui-kit` → `lib-pad` (toy/runtime `left-pad`)
label	toy	`web` → `date-lib` (toy/runtime `naïve-date`)
label	toy	`web` → `ui-kit` (toy/runtime `ui-kit`)
```

  Each number in a `rates` line is the one F2 or F3 prints, and `mono` → `lib` with 2 is P2-009b's F6.
- N3, `mitos-score --all <r>/two` exits 0 (sha256 `c1226aa886ddd42f80151a396a8e8de5c6c6cbc6aa336814f4a4a86939944ae0`). It prints this summary, then an empty line and F2, then an empty line and F3:

```
## Nightly scorecard

2 fixtures, 2 scored.

### Every fixture

| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision | Most derivations |
|---|---|---|---|---|---|---|---|
| gomod | go-module/runtime | this run | 0.83 (5/6) | 0.83 (5/6) | 1.00 (4/4) | 0.50 (1/2) | 2 |
| toy | toy/runtime | this run | 0.71 (5/7) | 0.83 (5/6) | 1.00 (3/3) | 0.50 (2/4) | 1 |

Most derivations any repo-level edge has: 2, `mono` → `lib` (go-module/runtime `example.com/lib`) in fixture `gomod`. D1 reopens above 8.

### Against the baseline

No baseline given, so nothing was compared.
```

- N4, a run against its own numbers. `--all <r>/two <r>/n.tsv`, where `n.tsv` is N2's output, prints N3 with `No change against the baseline.` in place of `No baseline given, so nothing was compared.`, and exits 0 (sha256 `4fe81f4dbf784f4a6f7a4522f01e92b6aaed5fbf6eca40dda1db828072507924`). This is the command-line form of `changed_eq_nil`.
- N5, a moved baseline. `moved.tsv` is N2 with the gomod recall at `1.00 (6/6)`, `app` → `log` as `confirmed`, and a `chain` line that this tree lacks, as a baseline from after P2-009a would have against a tree before it (sha256 `ace695e2473a861c0ff85898b0ea0ef345f1b440c30fc55406fbc2bdc8a0692a`, command below). `--all <r>/two <r>/moved.tsv` exits 0 (sha256 `d7905796795257544ad2a496b092a631430dd7e20cf62702e57362747f07ed1e`), and its last section reads:

```
### Against the baseline

| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision | Most derivations |
|---|---|---|---|---|---|---|---|
| gomod | go-module/runtime | baseline | 0.83 (5/6) | 1.00 (6/6) | 1.00 (4/4) | 0.50 (1/2) | 2 |
| gomod | go-module/runtime | this run | 0.83 (5/6) | 0.83 (5/6) | 1.00 (4/4) | 0.50 (1/2) | 2 |
| chain | env/runtime | baseline | 1.00 (2/2) | 1.00 (2/2) | 1.00 (2/2) | n/a | 2 |
| chain | env/runtime | this run | none | none | none | none | none |

Repo-level edges that changed:
- `gomod`, only in the baseline: `app` → `log` (go-module/runtime `example.com/log`), confirmed, derivations 1
- `gomod`, only in this run: `app` → `log` (go-module/runtime `example.com/log`), inferred, derivations 1
```

  The unchanged `toy` lines do not appear. A changed `rates` key shows both sides, a key that disappeared shows `none`, and a status move shows as the edge's two lines.
- N6, errors and usage.
  - The root `err` holds `bad` (label scope `prod`), `nolab` (no `labels.tsv`), `norepos` (no `repos/`) and `ok` (`a` → `b`, one hit). `--all <r>/err` exits 1 (sha256 `8648b35a03e935db6774a6b03e77737e13384176d7c284ed7def13186097337b`). It starts:

```
## Nightly scorecard

4 fixtures, 1 scored.

**Not every fixture scored (`bad`, `nolab`, `norepos`), so the numbers below cover the others only.**

### Every fixture

| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision | Most derivations |
|---|---|---|---|---|---|---|---|
| ok | toy/runtime | this run | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | n/a | 1 |

Most derivations any repo-level edge has: 1, `a` → `b` (toy/runtime `x`) in fixture `ok`. D1 reopens above 8.

### Against the baseline

No baseline given, so nothing was compared.

### Scorecard: fixture `bad`

Scorer error: labels.tsv:1: unknown scope "prod"

### Scorecard: fixture `nolab`
```

  and goes on with `Scorer error: labels.tsv is missing`, then `norepos` with `Scorer error: repos/ is missing`, then `ok`'s card.
  - `--numbers <r>/err` prints nothing on stdout, exits 1, and writes `bad: labels.tsv:1: unknown scope "prod"`, `nolab: labels.tsv is missing` and `norepos: repos/ is missing` to stderr.
  - A baseline whose `rates` line has 7 fields makes `--all` print ``baseline line 1: a line of kind `rates` has 8 tab-separated fields, found 7`` and exit 1. A baseline line of kind `card` prints `baseline line 1: unknown line kind "card"` and exits 1.
  - `mitos-score --all`, `--all <root> a b`, `--numbers` and `-x` print the usage and exit 2. Without the guard, `-x` would try to read `-x/labels.tsv`.
- N7, the D1 boundary. Fixture `many` has `a/deps.toy` with n lines `require x` and `b/PROVIDES` with `provide x`, which gives n records under one repo-level edge. With n = 8 (`<r>/d1-8`) the run prints ``Most derivations any repo-level edge has: 8, `a` → `b` (toy/runtime `x`) in fixture `many`. D1 reopens above 8.`` and no bold line (sha256 `c68c5d70c1f315bc41b8f6dddf6276f3cea183ea8ece970820dd648cb29939ec`). With n = 9 (`<r>/d1-9`) it prints the line with 9 and then ``**Above 8: D1 reopens (`plan/phase-2.md`, Scope decisions).**`` (sha256 `a6c12fd1d9a0bb9b570a6c1a80f34ce6b2454198609532fabb643dbccce8bd01`). Both exit 0.
- N8, P2-009b's F6 reproduced: N2's `edge` line for `mono` → `lib` in `gomod` ends with `confirmed` and `2`, and the `gomod` `rates` line ends with `2`. P2-001b's bound records count under the same rule (`countP` over every record with the key).
- N9, Q1 both ways. Fixture `self`: `mono/deps.toy` has `require m` three times and `require x` once, `mono/PROVIDES` has `provide m`, `b/PROVIDES` has `provide x`. The labels are `mono` → `b` (`x`) and `mono` → `mono` (`m`).
  - On `main`, the row reads `| self | toy/runtime | this run | 1.00 (2/2) | 1.00 (2/2) | 1.00 (2/2) | n/a | 3 |` and the D1 line names `mono` → `mono` with 3 (sha256 `4a263d358305de3146bc5bb1302463bf8690ba388100363ea1ed666ea877ff16`).
  - With `score`'s `predicted := collapse (r.edges.filter fun e => e.requiringRepo != e.providingRepo)` in a scratch copy only, the row reads `1.00 (1/1) | 0.50 (1/2) | 1.00 (1/1) | n/a | 3`, the D1 line still names `mono` → `mono` with 3 and adds ", which that fixture's card leaves out", and `--numbers` prints the `edge` line for `mono` → `mono` with the status `not in the card` and `3` (sha256 of `--all` `e2089bdaae18eea75588d710ca5d80e47dfa57db485634e8506cbef938e623eb`). The D1 number does not move with Q1. The card's numbers do.
- N10, a label deleted. `<r>/lab` is `two` with the label `app` → `cli` deleted from `gomod/labels.tsv`. `--all <r>/lab <r>/n.tsv` exits 0 (sha256 `f82928dbce0d457691bde030de022a3888407bc9262d73433b359048b39b198d`), and its last section reads:

```
### Against the baseline

| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision | Most derivations |
|---|---|---|---|---|---|---|---|
| gomod | go-module/runtime | baseline | 0.83 (5/6) | 0.83 (5/6) | 1.00 (4/4) | 0.50 (1/2) | 2 |
| gomod | go-module/runtime | this run | 0.83 (5/6) | 1.00 (5/5) | 1.00 (4/4) | 0.50 (1/2) | 2 |

**The hand labels changed.**
- `gomod`, label only in the baseline: `app` → `cli` (go-module/runtime `example.com/cli`)
```

  The recall that went up came from a label, and the report says which.
- N11, a tab inside a key. Fixture `t` has `a/deps.toy` with `require p<TAB>q` and `b/PROVIDES` with `provide p<TAB>q`. `--all <r>/tab` exits 1 with ``Scorer error: a numbers line of this fixture would not read back (line 2: a line of kind `edge` has 5 tab-separated fields, found 6)`` (sha256 `68f8b4b846899ba5e31c2356f116119a6194863f54b54fc6c6b330416d07a96d`). `mitos-score <r>/tab/t` still prints its card and exits 0.
- N12, Q2 both ways. `<r>/typo/ok` is `err/ok` with a second label of kind `go-mod`. On `main`, `--all <r>/typo` exits 0 (sha256 `4239227eeeebdf4acfa3b31a150bcbc9f2e8e665b3f98ba04e476be1bf4ff41d`), and `--numbers` prints one more `rates` line, for `go-mod/runtime` with the fields `n/a`, `0.00 (0/1)`, `n/a`, `n/a` and `0`, and one more `label` line, ``label<TAB>ok<TAB>`a` → `b` (go-mod/runtime `x`)``. With #332's files it exits 1 with `Scorer error: label kind "go-mod" is not among the extracted facts` and the bold line ``**Not every fixture scored (`ok`), …`` (sha256 `59e697fecaef8ffe61d0bd708a41666cb1d58c92a7c49bf663d3fc76b5a813e6`).
- N13, contract only, after P2-009a. `--numbers eval/fixtures` prints the `chain` lines first, with edge type `env/runtime` (P2-001b's deferral) and a `chain` `rates` line whose most derivations is at least 2 (the row's "a requirement that has two derivations"; P2-001b's `twoBindings`). The `gomod` and `toy` lines are N2's bytes, because P2-009a's `collapse` change cannot move them: each `toy` repo-level edge has one record, and `mono` → `lib`'s two records are both `confirmed` (P2-009b F6). `--all eval/fixtures` exits 0. The builder records the `chain` lines and the hashes of both commands in the build notes. A `chain` most of 1 means the count or the fixture lost a derivation: stop and report.
- Commands for the scratch roots, from the repository root:

```
r=<scratch>/p2010-fx
mkdir -p $r/two && cp -r eval/fixtures/gomod eval/fixtures/toy $r/two/
mkdir -p $r/err/bad/repos/a $r/err/ok/repos/a $r/err/ok/repos/b $r/err/nolab/repos/a $r/err/norepos \
  $r/tab/t/repos/a $r/tab/t/repos/b $r/q1/self/repos/mono $r/q1/self/repos/b $r/typo/ok/repos/a $r/typo/ok/repos/b
printf 'require x\n' > $r/err/bad/repos/a/deps.toy
printf 'a\tb\ttoy\tx\tprod\n' > $r/err/bad/labels.tsv
printf 'require x\n' > $r/err/ok/repos/a/deps.toy
printf 'provide x\n' > $r/err/ok/repos/b/PROVIDES
printf 'a\tb\ttoy\tx\truntime\n' > $r/err/ok/labels.tsv
printf 'require x\n' > $r/err/nolab/repos/a/deps.toy
printf 'a\tb\ttoy\tx\truntime\n' > $r/err/norepos/labels.tsv
printf 'require p\tq\n' > $r/tab/t/repos/a/deps.toy
printf 'provide p\tq\n' > $r/tab/t/repos/b/PROVIDES
printf 'a\tb\ttoy\tx\truntime\n' > $r/tab/t/labels.tsv
for n in 8 9; do
  mkdir -p $r/d1-$n/many/repos/a $r/d1-$n/many/repos/b
  for i in $(seq $n); do printf 'require x\n'; done > $r/d1-$n/many/repos/a/deps.toy
  printf 'provide x\n' > $r/d1-$n/many/repos/b/PROVIDES
  printf 'a\tb\ttoy\tx\truntime\n' > $r/d1-$n/many/labels.tsv
done
printf 'require m\nrequire m\nrequire m\nrequire x\n' > $r/q1/self/repos/mono/deps.toy
printf 'provide m\n' > $r/q1/self/repos/mono/PROVIDES
printf 'provide x\n' > $r/q1/self/repos/b/PROVIDES
printf 'mono\tb\ttoy\tx\truntime\nmono\tmono\ttoy\tm\truntime\n' > $r/q1/self/labels.tsv
printf 'require x\n' > $r/typo/ok/repos/a/deps.toy
printf 'provide x\n' > $r/typo/ok/repos/b/PROVIDES
printf 'a\tb\ttoy\tx\truntime\na\tb\tgo-mod\tx\truntime\n' > $r/typo/ok/labels.tsv
lake --dir eval/score exe mitos-score --numbers $r/two > $r/n.tsv
cp -r $r/two $r/lab && sed -i '/example.com\/cli/d' $r/lab/gomod/labels.tsv
sed -e 's/^\(rates\tgomod\tgo-module\/runtime\t0.83 (5\/6)\t\)0.83 (5\/6)/\11.00 (6\/6)/' \
    -e 's/^\(edge\tgomod\t`app` → `log` \)\(.*\)\tinferred\t1$/\1\2\tconfirmed\t1/' $r/n.tsv > $r/moved.tsv
printf 'rates\tchain\tenv/runtime\t1.00 (2/2)\t1.00 (2/2)\t1.00 (2/2)\tn/a\t2\n' >> $r/moved.tsv
```

- Wrong variants, each built in a scratch copy of the head, one at a time. All twelve were measured:

| Variant | Edit | What fails |
|---|---|---|
| W1 | `derivations` lists only `c.predicted`'s keys | `derivations_keys` stops proving |
| W2 | `changed` keeps only `cur.filter (!base.contains ·)` | `changed_eq_nil` stops proving |
| W3 | `most` with `min` | `le_most` is false and stops proving |
| W4 | `most` adds 1 to the maximum | `most_mem` is false and stops proving (`le_most`'s proof also stops, though its statement still holds) |
| W5 | `tp` counts the predicted edges that are not labelled | G1, G5 and G6 |
| W6 | `consistent` is `true` | G5 |
| W7 | no "The hand labels changed." section | G13 |
| W8 | with no baseline the report says "No change against the baseline." | G9 |
| W9 | a failed fixture's baseline lines are compared | G16 |
| W10 | the bold D1 line at `top ≥ d1Threshold` | G7 |
| W11 | `numbersAll` returns the scored fixtures' lines when one failed | G18 |
| W12 | no `edge` lines | G1 |

### Checks, in order
From the repository root, at the head after the last rebase. `<scratch>` is a folder named for this agent.
1. `lake --dir eval/score build 2>&1 | grep -E '^(warning|error)'` prints nothing, and the build ends with `Build completed successfully`. A failed pin is an `error:` line (`Expression … did not evaluate to true`). The job count moves with P2-009a's module and with #332's `Policy`.
2. A scratch `Axioms.lean`, never committed, with `import Score.Nightly` and `#print axioms` for each of the four theorems. `cd eval/score && lake env lean <scratch>/Axioms.lean` prints the axiom lists under `statements`, each a subset of `[propext, Classical.choice, Quot.sound]`.
3. N1. In a detached worktree of `origin/main` (`git worktree add --detach <scratch>/p2010-main origin/main`), run `mitos-score eval/fixtures/toy`, `…/gomod` and, after P2-009a, `…/chain`, then the same at the head. Each pair is byte equal. Compare with the worktree, not with the hashes above, if `origin/main` has moved the scorer or the fixtures.
4. N2: `--numbers $r/two | sha256sum`.
5. N3: `--all $r/two | sha256sum`. Then check that the cards are the report's tail: `{ echo; mitos-score $r/two/gomod; echo; mitos-score $r/two/toy; } > c.md`, then `tail -c $(stat -c %s c.md) all.md | cmp - c.md`.
6. N4.
7. N5.
8. N6, with the exit codes and the stderr lines.
9. N7, N9 (its second half needs a scratch edit to `Score.lean` and is optional), N10, N11 and N12 (its #332 half once #332 has merged; before that, optional on a scratch copy with #332's files).
10. N13 on `eval/fixtures`, recorded in the build notes.
11. At least W1, W5, W6, W7 and W11 in a scratch copy, each failing the named check.
12. `git diff --name-only origin/main...HEAD` prints only `eval/score/Main.lean`, `eval/score/Score/Nightly.lean`, `tasks/P2-010-nightly-scorecard.md` and files under `ops/runs/`.
13. `lake exe mitos-gate runlog --head ops/runs`, and `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'` shows only `A` lines.
14. `.claude/scripts/plan-tasks.test.sh`. It passes once `P2-010` has left `plan-tasks.pending`, which the design-landing PR does.
15. In CI, `checks` and `gate` are green. `checks` builds `eval/score`, so it kernel-checks the four theorems and runs G1 to G18, and the toy card it posts must read as on `main`.

### Risks and stop conditions
Risks:
- R1. The numbers file is the baseline contract. A later change to its kinds or columns, or to `renderEdge`'s text, makes every line show as changed once, on the first run after it lands. That is honest, and it shows for one run only.
- R2. A baseline edited by hand or rewritten to CRLF differs on every line, so every line shows as changed. A line of an unknown kind or with the wrong field count stops the run with exit 1.
- R3. `TypeCounts.cardLines` copies the text of `render`'s three table rows. A later PR that changes those rows fails G5 in its own build, so it edits `cardLines` in the same PR, and its plan cell must name `eval/score/Score/Nightly.lean`. A shared count function needs `Score.lean` (follow-up).
- R4. The first nightly after this merges has no baseline and prints "No baseline given, so nothing was compared."
- R5. `resolve` runs twice per fixture, once in `score` and once in `derivations`. Measured over 3 runs each with the built binary: 6 to 7 ms for `--all` over two fixtures, 5 ms for one card. The reference resolver is O(n³) (P2-001b's deferrals), which is fine at fixture size.
- R6. `renderEdge` prints keys raw inside code spans, and the nightly will be posted. A backtick or a newline in a key, or `@` in an error message, reaches the post as it is. The PR comment of the toy card has the same exposure today. Escaping belongs in `Score.lean` (follow-up).
- R7. The D1 line names the first edge that has the top count. Other edges with the same count are not listed.
- R8. Fact and unresolved counts are not in the numbers file. A change that only moves unresolved requirements shows in the card but not in the diff.
- R9. CI does not run `--all` or `--numbers` until P2-012. Until then, N1 to N13 are the builder's and the verifier's, and G1 to G18 are what CI runs.

Stop conditions for the builder:
- S1. After `git fetch origin main`, run `git diff --stat eac85d2 origin/main -- eval/score eval/fixtures core/Mitos/Core/Graph.lean core/Mitos/Impl/Resolve.lean lean-toolchain`.
  - Changes from P2-001b, P2-009a or #332 are expected.
  - If it shows `eval/score/Main.lean`, or a file named `eval/score/Score/Nightly.lean`, stop: this design is amended first.
  - If the name or type of an input under `types` changed, stop for the same reason.
  - If `Scorecard.render`'s table rows changed text, update `TypeCounts.cardLines` to the new text (G5 fails until then) and say so in the PR body. If the card gained a table, stop and report.
  - If only bodies changed, go on, and re-run N1 to N12.
- S2. `ls eval/fixtures` lists `chain`. If it does not, P2-009a has not merged, and the plan's wave W6 has not started: stop.
- S3. On `eval/fixtures`, the `gomod` and `toy` lines of `--numbers` differ from N2: stop and report. P2-009b's F6 says they cannot move.
- S4. The chain fixture is not laid out as `labels.tsv` plus `repos/`, or it needs a flag to score: stop, because this design is amended.
- S5. A check fails and the fix is outside `touches`: stop and report. Never edit a label or a fixture to move a number, and never delete a pin.
- S6. Done: the PR is open on `main`, `gate` is green, checks 1 to 14 pass at the head, and every thread is answered. Report the head as merge-ready. No path here is the owner's, so an agent merges it.

cut_line: this row ships `Score/Nightly.lean` with its four theorems and 18 pins, the `Main.lean` diff, the build notes in this file and the run log. It leaves these to other rows:
- the nightly run, the artifacts, the baseline download, the post and any CI use of `--all` or `--numbers` (P2-012);
- the chain fixture and its numbers (P2-009a);
- Q1 to Q3 (#325, #332);
- escaping in the card, and a count function shared with `render` (the PR's follow-up issue).

It adds no fixture, no CI step and no change to the single-fixture card.

deferrals:
- To P2-012 (#213), as the contract:
  - Nightly: `lake --dir eval/score build`, then `mitos-score --numbers eval/fixtures > numbers.tsv`, uploaded as an artifact (for example `scorecard-numbers`), then `mitos-score --all eval/fixtures <baseline> > scorecard.md`, posted. Pass `<baseline>` only when the earlier file exists (R4). Keep each exit code: exit 1 fails the job, and the numbers never do. `--numbers` prints nothing when a fixture fails, so a broken run leaves no baseline even if the upload runs anyway.
  - "`main`'s" baseline. One option is the `scorecard-numbers` artifact of the last successful nightly on `main` (`gh run list --workflow nightly.yml --branch main --status success --limit 1`, then `gh run download <id> -n scorecard-numbers`, with `actions: read`). What "the diff against `main`'s" means for a nightly that runs on `main`, and for a PR job, is P2-012's call, and the owner merges P2-012.
  - `ci.yml`'s scorecard step (`:296-301`) may switch from `eval/fixtures/toy` to `--all eval/fixtures`, so the PR comment covers every fixture. That also lands P2-009b's deferral of running the go.mod card in CI, and it runs `Nightly.checked` on the real fixtures in every PR.
  - When the D1 line is bold, D1 is the owner's to reopen (plan, Scope decisions). The post makes that line visible.
  - `docs/process.md` names only the toy fixture (`:190`, `:492-494`). That wording is the owner's and moves with P2-012.
- To P2-009a (#210):
  - Keep `eval/fixtures/chain/` in the fixture layout (`labels.tsv` and `repos/<repo>/`), scored by `mitos-score eval/fixtures/chain` with no flag.
  - Keep `Scorecard`'s fields and `render`'s table rows, or name the change in its task file so this row's S1 follows it.
  - Put any binding reader behind `factsOf`, as go.mod did.
  - Then `--all` scores the chain fixture with no change here (N13). The two-derivation requirement is the number to check against "most derivations".
- From P2-001a (#203): the count is the number of records with one `repoKey`. Followed, over every repo-level edge the resolver made (`derivations_keys`).
- From P2-001b (#204): bound records count too. Followed by construction (`countP` over every record with the key). The sketch builds at 3d939da, and N1 to N5 are the same there.
- From P2-009b (#211): `gomod` is one of every fixture, and its most is 2 (N2, N8). F2 and F3 stay the single-mode bytes (N1).
- To #325 and #332: nothing to change; see the Q1 to Q3 table. If #332 merges first, N1 to N11 hold as measured, and N12 takes its #332 half.
- To the PR's follow-up issue (no row), all minor:
  - One count function in `Score.lean` that both `render` and `numbers` use, which retires `TypeCounts.cardLines` and `consistent` (R3). Revisit when `render` next changes.
  - Escaping of keys and error text in the card and the report (R6). It needs `Score.lean` for the card.
  - Fact and unresolved counts in the numbers file (R8), and every edge that ties for the most (R7).

owner_decisions:
- Settled by the plan: this row's cells; an agent merges it; eval code only, with the wiring in P2-012; the D1 threshold of 8 (`plan/phase-2.md:110-111`); and that the numbers never fail a run while a scorer error does (`docs/process.md:190`).
- No owner call is needed for this row. The cell's "a scorecard module" is one module. The meaning of "`main`'s" baseline in the nightly is P2-012's to set.
- The root's defaults in this design, not owner rulings:
  - D1. Two new modes, `--all` and `--numbers`, and the single mode keeps its bytes. Reason: CI's post, P2-009b's hashes and #332's card theorems all read it.
  - D2. Derivations are counted over every repo-level edge the resolver made, not only the card's. Reason: D1 measures the resolver's records per repo-level edge, so a scorer policy such as Q1 must not hide them.
  - D3. The baseline is the file `--numbers` printed, with three line kinds, compared as a set of lines, with both sides shown. No number is parsed back. Reason: the fewest definitions, and one general theorem (`changed_eq_nil`) for "no change".
  - D4. Every directory under the root is a fixture, and no list names them. Reason: "every fixture" is held by the code, and one more list would have to follow `eval/fixtures/`.
  - D5. A failing fixture's card says `Scorer error: …`, the others still print, and `--all` exits 1; `--numbers` then prints nothing. Reason: one broken fixture must not hide the others, and must not become the next baseline.
  - D6. The D1 tripwire is one bold line, and the exit code does not change. Reason: reopening D1 is the owner's reading, and a failed run would hide the card.
  - D7. The report leads with the summary, then the cards. Reason: the post opens on the D1 line and the diff.
  - D8. The per-type counts are checked against the card's text, at build time (G5) and for every fixture at run time. Reason: `render` is outside the cell, so the copy of its rows must fail loudly when they drift.
  - D9. No CI change here. `.github/` is P2-012's.

## Build notes
The builder fills this in: the base commit, S1's output, the hashes of checks 3 to 9, N13's `chain` lines and the hashes of `--numbers eval/fixtures` and `--all eval/fixtures`, the variants re-run in check 11, and the run-log path.

## Done when
- [ ] all `checks` pass locally, and `gate` is green
- [ ] N1 to N12 hold at the head, and N13's `chain` lines and hashes are in the build notes
- [ ] no `sorry`, no new axioms (checks 1 and 2)
- [ ] run-log record written (ops/runs/)

## Rationale

### Problem
Exit criterion 5 needs three things on top of today's one-fixture card: every fixture in one report, a diff against `main`'s card, and the largest derivation count of any repo-level edge. This row may not edit `Score.lean`, and `Scorecard` holds collapsed keys and statuses, not edge records. `main`'s scorer is a different build from the head's, so a diff needs a file that an earlier run wrote. The single-fixture card is pinned three ways: by CI's post, by P2-009b's hashes and by #332's `native_decide` theorems. And the inputs are files any PR can change. A label deleted or swapped can raise recall with no change to the code, so the diff has to show the labels too.

### Shape
`Score.Nightly` owns five decisions:
- how many derivations a repo-level edge has: the records of `resolve c.facts` with that key, for every key the resolver made;
- what one fixture comes to as lines: one `rates` line per edge type, one `edge` line per repo-level edge, one `label` line per label;
- that those lines agree with the card (`consistent`) and read back (`parseNumbers`);
- what changed against a baseline: the two-sided set difference of those lines;
- how the report reads.

`Main` owns walking the fixtures root, reading the files and the exit code. Everything else is reused from `Score`. The baseline needs no parser beyond a kind and a field count, because lines are compared as strings, and the diff copies cells instead of recomputing them. The four theorems pin the places where a wrong answer would hide a signal: a count that skips an edge, a maximum that misses one or invents one, and a diff that misses a disappearance. The 18 pins hold the report's sentences and the build-time check against `render`.

Interface depth: eleven names and four theorems, and callers see three commands. They hide the counting rule, the line format, the check against the card, the diff and the D1 rule.

### Tradeoffs accepted
- A numbers format that is only a contract between two runs of this tool, in exchange for a diff with no parsing (R1).
- A diff that shows "before" and "after" cells side by side, not computed deltas such as `+0.17`.
- `resolve` running twice per fixture (R5), and a copy of `render`'s row text checked against it (R3), in exchange for no edit to `Score.lean`.
- A fixture with a tab in a key fails instead of being escaped (N11). It is loud, and no fixture has one.
- Raw keys in the posted text (R6), as the PR comment already has.
- No baseline on the first nightly (R4).

### Alternatives considered
- A1. Put edges or counts into `Scorecard`, or make `collapse` return counts. That edits `Score.lean` outside the cell, in the file P2-009a and #332 edit.
- A2. Count only the card's predicted keys (Design A's D2). The D1 number then moves with Q1, and a dropped edge hides its derivations from the tripwire (W1).
- A3. Count distinct `Edge.key` values instead of records (Design B). P2-001a handed over records, and #101's `EdgesNodup` makes the two equal, so a second rule adds nothing.
- A4. A JSON summary with a schema, decoded into structures, and a per-edge delta type (Design B). The line set gives the same edge and label changes with no schema, no decoder and one theorem for "no change".
- A5. Numbers only in the baseline (Design A). A label swap keeps every count, and the diff would not say which label moved.
- A6. A floor of required fixture names in code (Design B). It is one more list to keep in step with `eval/fixtures/`, it blocks the build until `chain` exists, and a removed fixture already shows against the baseline.
- A7. Three modules and a `selftest.sh` (Design B). That is outside the cell, so the plan would need an owner edit. Its cases are here as pins on the pure functions (G9 to G18) and as the builder's runs (N6 to N12).
- A8. Refuse a fixture whose text would break Markdown, and blank `@` and backticks in error text (Design B). The renderer is in `Score.lean`, and a policy that refuses fixtures belongs with it (follow-up).
- A9. Diff the Markdown with `diff -u` in the workflow. That puts this row's code in `.github/`, and a line diff of cards is noisy.
- A10. A baseline made by running this head's scorer on `main`'s fixtures. It measures changes to the fixtures, not to the code.
- A11. One mode that writes the numbers to a file argument (Design B's `--json`). One more flag and an output path. Two modes that each print one thing to stdout cost one more run of 7 ms.
- A12. Let an IO error abort the run (Design A). One unreadable fixture would hide every card.

### Open questions and risks
- Q-a. What "the diff against `main`'s" means for the nightly that runs on `main`, and for a PR job. P2-012 decides; the code takes any numbers file.
- Q-b. Should a numbers line carry a format version? Not now (R1).
- Not verified: the run on CI's machine, and the chain fixture's numbers (N13, until P2-009a merges).

### Next implementation step
Run S1 and S2, add `Score/Nightly.lean` and the `Main.lean` diff as written, make the scratch roots, run checks 1 to 11, then write the build notes and the run log.

### Synthesis decision
The root's judge took Design A (opus, smallest surface) as the base and grafted the strongest safety ideas of Design B (sonnet, adversarial); these are the root's defaults, not owner rulings. A won on interface depth and fit: one module, as the cell names it, so no owner plan edit; a line-set diff with a general theorem instead of a JSON schema and decoder; two modes that print to stdout; and a builder who can start as soon as P2-009a lands, with no list of fixture names to keep in step. From B it took six things. The D1 count covers every repo-level edge the resolver made, not only the card's, because D1 measures the resolver and must not move with Q1; that reverses A's D2 and adds `derivations_keys`. The baseline carries `edge` and `label` lines beside the rates, so a label swap and an edge's status move show by name. The per-type counts are checked against the card's own rows, at build time and for each fixture at run time, so the copy of `render`'s counts fails loudly instead of drifting (A's R3). A fixture that failed this run is "not compared" rather than "removed", a bold line names it, and `--numbers` prints nothing, so a broken run cannot become the next baseline. Missing or unreadable files fail only their own fixture, with fixed messages, instead of aborting the run (A's R6). And B's build-time `#guard` pins and a second maximum theorem (`most_mem`) make the report's sentences and the D1 number checked in CI. B's JSON summary, its floor of required names, its three modules with `selftest.sh`, its Markdown refusal and its distinct-key count were left out for the reasons in A3 to A8. The red-flag screen found the copy of `render`'s rows (leakage, kept and pinned by G5 and `consistent`, with the shared count function as a follow-up), public helpers (made `private`), and B's hand-synced fixture list (dropped). The merged sketch was built and run on `main` at eac85d2, on #332 at 856832b and on P2-001b at 3d939da, and the hashes above were measured on that final text.
