# tasks/P2-010-nightly-scorecard.md

phase: 2
goal: `lake --dir eval/score exe mitos-score --all eval/fixtures [<baseline>]` prints one nightly scorecard: for each fixture and edge type the precision, recall, confirmed precision, inferred precision and most derivations; the most derivations any repo-level edge has, checked against the D1 threshold of 8; what changed against `<baseline>`, which is what `mitos-score --numbers eval/fixtures` printed on an earlier run, such as `main`'s; then every fixture's card. `mitos-score <fixture-dir>` prints exactly what it prints on `main`.
statement: none (tooling task, nothing in `statements.lock`). Four scorer theorems, not locked: `Score.Nightly.derivations_keys`, `Score.Nightly.le_most`, `Score.Nightly.most_mem`, `Score.Nightly.changed_eq_nil`. Also 21 build-time `#guard` pins in the same file (G1 to G21 under `statements`). The hardening follow-up for #552 (Hardening notes) adds `Score.Nightly.mem_tied`, the pins G22 to G28, and in `Score.lean` `Score.inert_safe`, `Score.inert_clean`, `Score.inert_injective` and `Score.inert_cases`. The follow-up for #600 (Follow-up notes for #600) adds `Score.plain_safe`, `Score.plain_clean`, `Score.plain_injective`, `Score.plain_cases`, `Score.logLine_safe`, `Score.logLine_head`, `Score.logLine_cases`, `Score.Chain.trims_keys`, `Score.chain_crlf_end_to_end` and the pins G29 to G32
touches: eval/score/Main.lean, eval/score/Score/Nightly.lean (new), tasks/P2-010-nightly-scorecard.md, ops/runs/. These are the row's own build (#551). The hardening follow-up for #552 (#588) also changed eval/score/Score.lean, eval/score/Score/Chain.lean, tasks/P2-009a-chain-fixture.md and tasks/P2-012-ci-wiring.md. The follow-up for #600 also changed eval/score/Score.lean and eval/score/Score/Chain.lean
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, eval/fixtures/, eval/score/Score.lean, eval/score/Score/GoMod.lean, eval/score/Policy.lean (if #332 has merged), eval/score/lakefile.toml, eval/score/lake-manifest.json, eval/score/lean-toolchain, examples/acme/, core/, eval/diff/, eval/mutants/, .github/, docs/, plan/, .claude/. This list bound the row's own build (#551). Each follow-up had its own file list, and both edit eval/score/Score.lean (see `touches`). Neither touched another path of this list
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
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file lists. The hardening follow-up for #552 had its own file list, which includes `eval/score/Score.lean`, and so did the follow-up for #600 (check 12 gives both). Where it changed an output, a pin or a rule, the text below is amended and says so, and Hardening notes records the whole change.

depth: build. Under `types` are the whole of `eval/score/Score/Nightly.lean` and the whole diff of `eval/score/Main.lean` as #551 merged them, with every proof and pin written in. The plan-time scratch build at `eac85d2` finished in 44 jobs without warnings. The scorer build now kernel-checks five theorems in `Score/Nightly.lean` and evaluates all 32 `#guard`s (four theorems and 21 pins before the hardening follow-up, and 28 pins before the follow-up for #600). The build notes record N1 to N13 with the chain fixture present.

revisit_when: re-check after #210 (P2-009a) merges. That also covers #204 (P2-001b), which P2-009a waits for. The re-check is S1 to S3 and N13. #332 changes no output here, whichever order it merges in (measured at 856832b).

modules:
- `eval/score/Score/Nightly.lean` *(new)*. It owns one topic, the nightly scorecard on top of one card: the derivation count per repo-level edge, the per-type counts and their check against the card's own text, the numbers file (three line kinds, written and read back), the line-set diff, the D1 line and the report. It copies the layout of `eval/score/Score/GoMod.lean`: imports, one namespace, `open Mitos`, definitions, theorems, then pins. Its helpers are `private`, so another file cannot reach them (measured: `#check @Score.Nightly.consistent` from a scratch file is an unknown identifier). It imports `Score`, and `Score.lean` does not import it, so there is no cycle and no edit to `Score.lean`. `Main.lean` imports it, so the default target `mitos-score` builds it with no lakefile change. Since the hardening follow-up the numbers file has a fourth line kind, `counts`, and the per-type counts and their row text live in `Score.lean` (`Scorecard.typeCounts`, `TypeCounts.row`, `TypeCounts.trustRow`), where `render` reads them too.
- `eval/score/Main.lean`, 35 → 78 lines. It gains `scoreDir`, `fixtureName`, `scoreAll` (the walker over a fixtures root) and two modes, `--numbers` and `--all`. A lone argument that starts with `-` prints the usage. `sortPaths` and `loadRepos` keep every byte, and the single-fixture mode prints the same bytes. Since the follow-up for #600, `main` is `run` inside a `try`, and `fail` writes every stderr line other than the usage through `Score.logLine`.

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
- A fixture fails, and its card is replaced by ``Scorer error: `…` `` (the error text is in a code span since the hardening follow-up), when its `labels.tsv` is missing, its `repos/` is missing, a file cannot be read, `parseLabels` or `score` fails, or `Nightly.checked` finds a problem: the per-type counts disagree with the card's own rows, or one of its numbers lines would not read back (a tab or a line feed inside the fixture's name; before the follow-up for #600 also a tab inside an extracted key, which is now escaped). The messages hold no path. The other fixtures still score and print.
- `--all` prints, in this order: `## Nightly scorecard` with the fixture count and, when one failed, a bold line naming the failed fixtures; `### Every fixture`, one table row per fixture and edge type, then the D1 line; `### Against the baseline`; then each card or error, each after one empty line. A scored fixture's card is byte for byte what `mitos-score <fixture-dir>` prints (check 5). Since the hardening follow-up the D1 line names every edge that has the top count, joined by `; `, in the order of the fixtures and then of each fixture's `edge` lines.
- The numbers file has one line per record, tab-separated, and its first field names the kind:

| Kind | Fields after the kind | One line per |
|---|---|---|
| `counts` | fixture, facts, requirements, provisions, bindings, unresolved requirements | fixture, before its other lines (since the hardening follow-up) |
| `rates` | fixture, edge type, precision, recall, confirmed precision, inferred precision, most derivations | edge type of the card, in the card's order |
| `edge` | fixture, the edge as the card prints it, `confirmed`, `inferred` or `not in the card`, derivations, edge identity | repo-level edge the resolver made, in its order |
| `label` | fixture, the label as the card prints an edge, edge identity | label, in `labels.tsv` order |

  The edge identity is a compact JSON array of the requiring repo, providing repo, kind, key and scope. Its strings are escaped so distinct keys stay distinct. Since the hardening follow-up the report prints an edge or a label from this identity, through `renderEdge`, and not from the text its line carries.

  The ratio fields are `Score.ratio` strings such as `0.83 (5/6)` or `n/a`, so a count that moves shows even when the rounded ratio does not. `parseNumbers` reads only these kinds, each with its own field count, and `Nightly.checked` reads every line the run writes, so the writer must reproduce the exact list of lines after parsing.
- "Against the baseline" is one of: `No baseline given, so nothing was compared.`; `No change against the baseline.` exactly when this run's lines and the baseline's, less the lines of any fixture that failed in this run, are the same set (`changed_eq_nil` applied to that filtered baseline); or the changes. For each fixture and edge type whose `rates` line changed, the baseline row and this run's row, with `none` on a side that has no such line. Then, since the hardening follow-up, a second table with the two rows of each fixture whose `counts` line changed. Then `**The hand labels changed.**` and each `label` line on one side only. Then each `edge` line on one side only. A fixture that failed in this run is left out of the comparison and, when the baseline holds lines for it, gets the line `` `<name>` was not scored in this run, so it is not compared. `` A baseline with no `counts` line at all was written before the hardening follow-up: this run's `counts` lines are then left out of the comparison, and the section ends with `The baseline has no fact counts, so they are not compared.`
- Exit codes:
  - `<fixture-dir>`: as on `main`, and 2 for a lone argument that starts with `-`.
  - `--numbers`: 0 with every line on stdout; 1 with nothing on stdout and one `<fixture>: <error>` line on stderr per failed fixture, so a broken run cannot become the next baseline. Since the follow-up for #600 each stderr line other than the usage starts with `mitos-score: ` and is escaped (`Score.logLine`).
  - `--all`: 0 when every fixture scored; 1 when one did not, with the whole report printed; 1 with nothing printed when the baseline file has a line of an unknown kind or the wrong field count (`baseline line N: …` on stderr); 2 on bad usage.
  - The numbers, the D1 line included, never change the exit code. A fixtures root or baseline path that cannot be read is an uncaught IO error and exits 1.
- An empty root prints `0 fixtures, 0 scored.` and `No fixture has a repo-level edge, so no derivations were counted.` and exits 0.
- The output holds no path, time or random value, so two runs on one tree are byte equal, and a scratch copy of a fixture prints the same bytes as the original.
- P2-012 calls exactly the commands above (deferrals).

| #325 question | #332's answer | The opposite answer | What this row does | What depends on the answer |
|---|---|---|---|---|
| Q1, same-repo edges | kept, and a label makes one a hit | left out of the card | `derivations` counts every repo-level edge the resolver made (`derivations_keys`), so the D1 line and each type's "most derivations" are the same under both answers. An edge the card leaves out has the status `not in the card` in its `edge` line, and when it holds the most, the D1 line adds "which that fixture's card leaves out". | The card's own counts, and so the precision and recall in `rates`. N9 measures both answers. |
| Q2, a label kind no fact has | `score` fails | it scores as a miss | Under #332 that fixture's card is ``Scorer error: `label kind "go-mod" is not among the extracted facts` ``, the bold line names it, `--all` exits 1 and `--numbers` prints nothing. Under the miss answer the fixture scores, with one more `rates` line (`go-mod/runtime`, `n/a`, `0.00 (0/1)`, `n/a`, `n/a`, `0`) and one more `label` line. | The exit code, and whether a typo shows as a failure or as a row. N12 measures both. |
| Q3, `go.mod` under `testdata/`, `.x/`, `_x/` | every `go.mod` is read | those directories are skipped | Nothing. `Score.GoMod.reads` decides. `loadRepos` reads every file, and the fixture walker skips no directory. | Only a fixture that has such a directory, and `main` has none. |

### How a builder goes wrong here
- Adding a line to each card, or changing `render`. That moves the single-mode bytes that CI posts, P2-009b's F2 and F3, and #332's `native_decide` card theorems. The nightly output lives only in `--all` (N1, check 5).
- Counting derivations only for the card's predicted keys (W1). The D1 number would then depend on Q1, and an edge that the scorer drops would hide its derivations from the D1 tripwire. `derivations_keys` stops proving.
- Editing `Score.lean` to put edges or counts into `Scorecard`. That edit is outside the cell, and it collides with P2-009a's `collapse` edit and #332's edit of `score`.
- Recounting the per-type numbers with a rule that differs from `render`'s (W5). G5 fails the build, and on a real fixture `Nightly.checked` fails it with "the nightly numbers disagree with the card". Since the hardening follow-up there is no second rule: `render` and `numbers` both read `Scorecard.typeCounts`, and a wrong count there moves the card's bytes, which `Policy`'s card theorems, G1 and N1 hold.
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
- `eval/score/Score/Nightly.lean`, the file in full as #551 merged it. Hardening notes lists what changed since:

```lean
import Score
import Lean.Data.Json

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

private def edgeIdentity (k : RepoKey) : String :=
  (Lean.toJson #[k.requiringRepo, k.providingRepo, k.ident.kind, k.ident.key, scopeName k.scope]).compress

def numbers (name : String) (c : Scorecard) : List String :=
  let ds := derivations c
  let line (fs : List String) := "\t".intercalate fs
  (typeCounts c).map (fun t => line ["rates", name, t.edgeType, ratio t.tp t.predicted,
      ratio t.tp t.labelled, ratio t.confirmedTp t.confirmed, ratio t.inferredTp t.inferred,
      toString (most (ds.filter (edgeType ·.1 == t.edgeType)))]) ++
    ds.map (fun (k, n) => line ["edge", name, renderEdge k,
      ((c.predicted.lookup k).map statusName).getD "not in the card", toString n, edgeIdentity k]) ++
    c.labels.map fun k => line ["label", name, renderEdge k, edgeIdentity k]

private def arity : String → Option Nat
  | "rates" => some 8
  | "edge" => some 6
  | "label" => some 4
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
  else
    let ls := numbers name c
    match parseNumbers ("\n".intercalate ls) with
    | .error e => some s!"a numbers line of this fixture would not read back ({e})"
    | .ok readBack =>
      if readBack == ls then none else some "the numbers lines of this fixture changed on readback"

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
  | ["edge", n, e, s, d, _] => s!"- `{n}`, {side}: {e}, {s}, derivations {d}\n"
  | ["label", n, e, _] => s!"- `{n}`, {side}: {e}\n"
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
   "edge\tpin\t`a` → `b` (toy/runtime `x`)\tconfirmed\t2\t[\"a\",\"b\",\"toy\",\"x\",\"runtime\"]",
   "label\tpin\t`a` → `b` (toy/runtime `x`)\t[\"a\",\"b\",\"toy\",\"x\",\"runtime\"]"]

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

#guard has (summary [] none) "No fixture has a repo-level edge, so no derivations were counted."

#guard match (pin 2).head?.bind (·.card.toOption) with
  | some c => has (summary [{ name := "pin", card := .ok { c with predicted := [] } }] none)
      "in fixture `pin`, which that fixture's card leaves out."
  | none => false

private def collisionLabel (src dst : String) : RepoKey :=
  { pinKey with requiringRepo := src, providingRepo := dst }

#guard
  let old := collisionLabel "a` → `b" "c"
  let new := collisionLabel "a" "b` → `c"
  match numbersAll (pin 1 [old]), numbersAll (pin 1 [new]) with
  | .ok before, .ok after =>
    let report := summary (pin 1 [new]) (some before)
    renderEdge old == renderEdge new &&
      (before.filter (kind · != "label")) == (after.filter (kind · != "label")) &&
      has report "label only in the baseline" && has report "label only in this run"
  | _, _ => false

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
- Since the hardening follow-up: `TypeCounts` and `Scorecard.typeCounts` are public in `Score.lean`, `TypeCounts.cardLines` is gone, and `render` prints its rows through `TypeCounts.row` and `TypeCounts.trustRow`, which `consistent` looks for. The interface gains `Score.Nightly.tied` and `mem_tied`.

statements:
- `Score.Nightly.derivations_keys : (derivations c).map (·.1) = ((resolve c.facts).edges.map (·.repoKey)).eraseDups`. The count covers every repo-level edge the resolver made, each once, whatever the card keeps. Axioms `[propext, Quot.sound]`.
- `Score.Nightly.le_most : d ∈ ds → d.2 ≤ most ds`. The number printed as "most derivations" bounds every repo-level edge's count, so a wrong maximum cannot hide the D1 tripwire. Axioms `[propext]`.
- `Score.Nightly.most_mem : ds ≠ [] → ∃ d ∈ ds, d.2 = most ds`. The maximum is some edge's count, not a number above all of them. With `le_most` it fixes `most` exactly. Axioms `[propext, Quot.sound]`.
- `Score.Nightly.changed_eq_nil : changed cur base = [] ↔ ∀ l, l ∈ cur ↔ l ∈ base`. The report says "No change against the baseline" exactly when this run and the baseline, less the lines of any fixture that failed in this run, hold the same lines. A line that appeared or disappeared always shows. Axioms `[propext, Classical.choice, Quot.sound]`.
- All four are general, with no `decide` on strings, and CI's `checks` job kernel-checks them through `lake --dir eval/score build`.
- From the hardening follow-up, also kernel-checked by that build:
  - `Score.Nightly.mem_tied : k ∈ tied top ds ↔ (k, top) ∈ ds`. The D1 line lists exactly the edges whose count is the top one, each fixture's in the order `derivations` gives them. With `most_mem`, the list is not empty when a fixture has an edge. Axioms `[propext, Quot.sound]`.
  - `Score.inert_safe : ∀ c ∈ (inert s).toList, c ∉ breaks`, where `breaks` is the backtick, the pipe, the line feed, the carriage return and `@`, and since the follow-up for #600 also `[`, every other character below U+0020, and U+007F. It holds for every string. This is the property R6 asked for: text that went through `inert` cannot mention anyone, close a code span, add a table cell or start a line.
  - `Score.inert_injective : inert s = inert t → s = t`. Two different names never print the same. `renderEdge` prints each name of an edge in its own code span, which `inert_safe` keeps closed, so two different edges print differently. That last step is an argument, not a theorem about `renderEdge`, and G21 pins it for the pair that collided on `main`.
  - `Score.inert_clean`: a string with no backslash and none of those five characters prints unchanged. This is why the cards of `toy`, `chain` and `gomod` keep their bytes. Since the follow-up for #600 its premise also rules out the characters that follow-up escapes, which is every key of `Score.escapes`, and those three cards hold none of them.
  - `Score.inert_cases`: what each of the six characters prints as (`\x60`, `\x7c`, `\n`, `\x0d`, `\x40`, `\\`), and that `naïve-date` prints as it is. One `decide` case per character. Since the follow-up for #600 it keeps those seven cases and adds `[` (`\x5b`), the tab (`\t`), U+0000, U+001B and U+007F (`\x00`, `\x1b`, `\x7f`), and that `&<*_~` prints as it is.
  - The four `inert` theorems depend on `[propext, Classical.choice, Quot.sound]`.
- From the follow-up for #600, also kernel-checked by that build (Follow-up notes for #600 says what each is for):
  - `Score.plain_safe : ∀ c ∈ (plain s).toList, c ∉ plainBreaks`, where `plainBreaks` is `breaks` and `&`, `<`, `*`, `_` and `~`. `plain` is what a place outside a code span prints.
  - `Score.plain_injective : plain s = plain t → s = t`, `Score.plain_clean` (a string with no key of `Score.plainEscapes` prints unchanged, which is why every table row keeps its bytes) and `Score.plain_cases` (one case per character, and `go-module/runtime` and `0.83 (5/6)` as they are).
  - `Score.logLine_head : (logLine s).toList.head? = some 'm'` and `Score.logLine_safe : ∀ c ∈ (logLine s).toList, c ∉ breaks`. A stderr line starts with the scorer's name and holds no `[`, no line feed and no carriage return, whatever the text. `Score.logLine_cases` holds a name of each command form and one with a line feed.
  - `inert` and `plain` are one function, `Score.escaped`, over the tables `Score.escapes` and `Score.plainEscapes`. Each of the four statements is proved once for any table, from facts about the table that `decide` checks.
  - The seven depend on `[propext, Classical.choice, Quot.sound]`.
- The pins, in file order. Each is a `#guard` that the build evaluates, because string splitting and `render` do not reduce in the kernel (#332 needed `native_decide` for its card theorems). The pins that need a card run the real `score` on a two-repo toy fixture written in the file (`pinFiles n`: `a/deps.toy` with `n` lines `require x`, `b/PROVIDES` with `provide x`, one label `a` → `b`). The others use literal lines or a failed `Result`.
  - G1: the numbers lines of `pinFiles 2`, exactly (`rates … 2`, `edge … confirmed 2`, `label …`). Since the hardening follow-up there are four, and the first is `counts pin 3 2 1 0 0`.
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
  - G19: the report names the absence of repo-level edges.
  - G20: the report identifies a maximum-count edge absent from the single-fixture card.
  - G21: a label swap between two different repo keys with identical display text is reported on both sides while rates and predictions stay equal. Since the hardening follow-up the premise is gone: G21's two keys, which printed the same on `main`, now print differently, because each name is escaped inside its own code span. G21 pins that: `renderEdge old != renderEdge new`, the report has `label only in the baseline: <old>` and `label only in this run: <new>`, and the other lines stay equal. This is #552 item 3.
  - G22: three fixtures, two of which hold three edges with the top count of 2. The D1 line lists all three, in fixture order and then edge order, joined by `; ` (R7).
  - G23: a run with one more unresolved requirement than its baseline shows the counts table, with the baseline row and this run's row (R8).
  - G24: a baseline written before the `counts` kind, given as literal text, is read by `parseNumbers`, equals this run's lines without the `counts` line, and the report says `No change against the baseline.` and then that the counts are not compared, with no `none` row (R8).
  - G25: a fixture whose lines parse but do not read back as the same list fails with "the numbers lines of this fixture changed on readback". The input is an empty fixture whose name holds tabs and a line feed, chosen so that its one `counts` line reads back as two well-formed ones (#552 item 2).
  - G26: the report built from names, keys, kinds, error text and baseline lines that hold a backtick, a pipe, a line feed, a carriage return, `@` and a backslash has exactly as many of each of the first five as the same report built from `x` and `y`. So no place that prints such text skips `inert` (R6).
  - G27: the unresolved line of that report prints the hostile path escaped, text for text.
  - G28: the edge identity of a hostile key parses back to the same key, which is what lets the report print from it.
  - G29, from the follow-up for #600, as are G30 to G32: G26's report built from a second hostile string, which holds `[`, U+001B, U+0000, U+007F and `&<*_~`, has as many of G26's five characters and of `[` and those three control characters as the report built from `x` and `y`. So no place skips the escaping of a `[` or a control character (#600 items 4 and 6).
  - G30: outside its code spans, that report has as many `&`, `<`, `*`, `_` and `~` as the report built from `x` and `y`. So every place that prints input text outside a code span calls `plain` (#600 item 5).
  - G31: the unresolved line of that report prints the key's control characters escaped, text for text (#600 item 6).
  - G32: a fixture whose key holds a tab scores, and its three numbers lines are pinned: the `edge` line holds the key as `p\tq` in its text and as `p\u0009q` in its identity, so it reads back (N11).
- Not pinned in the build, and checked by the builder's runs: each card inside `--all` equals the single-mode card (check 5), and the walker's fixed messages (N6). Since the follow-up for #600 also that `Main` writes every stderr line through `fail` and catches an I/O error (N14).

reuse: `Score.score`, `Scorecard`, `Scorecard.render`, `Score.edgeType`, `Score.renderEdge`, `Score.ratio`, `Score.statusName`, `Score.parseLabels` and `Score.SourceFile` unchanged; `loadRepos` and `sortPaths` in `Main.lean` unchanged; `Mitos.Impl.resolve`, `Edge.repoKey`; `List.countP`, `List.eraseDups`, `List.lookup`, `List.contains_eq_mem`, `List.filter_eq_nil_iff`, `Except.isOk`. The layout of `Score/GoMod.lean`. No new fixture directory and no lakefile change.

fixtures: build and run everything at the head. Outputs are compared by sha256. Scratch roots live under `<scratch>/p2010-fx`, never in the repository. The root `two` is a copy of `eval/fixtures/gomod` and `eval/fixtures/toy` only, so N2 to N5 and N10 stay checkable after P2-009a adds `chain`.
- N1, the single-fixture cards are unchanged. `mitos-score eval/fixtures/toy` hashes to `17c55e9cfa3a9db873c50c980cf2cbea62195fe2eebecde3edc0a13add38f21a` (P2-009b's F3) and `mitos-score eval/fixtures/gomod` to `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf` (F2), before and after the change, on all three bases.
- N2, `mitos-score --numbers <r>/two` prints these 29 lines and exits 0 (sha256 `86af9dd3c091b6fc8e1e57a2e33eb34a55e15d27279cbbe68f820856df417136`). Before the hardening follow-up it printed the 27 lines other than the two `counts` lines (sha256 `bb6f3e4d31015590ee88fb4eb2be92c3be7bcf387df7d910c9793962cd158dec`):

```
counts	gomod	15	7	8	0	1
rates	gomod	go-module/runtime	0.83 (5/6)	0.83 (5/6)	1.00 (4/4)	0.50 (1/2)	2
edge	gomod	`app` → `lib` (go-module/runtime `example.com/lib`)	confirmed	1	["app","lib","go-module","example.com/lib","runtime"]
edge	gomod	`app` → `log` (go-module/runtime `example.com/log`)	inferred	1	["app","log","go-module","example.com/log","runtime"]
edge	gomod	`app` → `log-fork` (go-module/runtime `example.com/log`)	inferred	1	["app","log-fork","go-module","example.com/log","runtime"]
edge	gomod	`lib` → `util` (go-module/runtime `example.com/util`)	confirmed	1	["lib","util","go-module","example.com/util","runtime"]
edge	gomod	`mono` → `lib` (go-module/runtime `example.com/lib`)	confirmed	2	["mono","lib","go-module","example.com/lib","runtime"]
edge	gomod	`mono` → `util` (go-module/runtime `example.com/util`)	confirmed	1	["mono","util","go-module","example.com/util","runtime"]
label	gomod	`app` → `lib` (go-module/runtime `example.com/lib`)	["app","lib","go-module","example.com/lib","runtime"]
label	gomod	`app` → `log-fork` (go-module/runtime `example.com/log`)	["app","log-fork","go-module","example.com/log","runtime"]
label	gomod	`app` → `cli` (go-module/runtime `example.com/cli`)	["app","cli","go-module","example.com/cli","runtime"]
label	gomod	`lib` → `util` (go-module/runtime `example.com/util`)	["lib","util","go-module","example.com/util","runtime"]
label	gomod	`mono` → `lib` (go-module/runtime `example.com/lib`)	["mono","lib","go-module","example.com/lib","runtime"]
label	gomod	`mono` → `util` (go-module/runtime `example.com/util`)	["mono","util","go-module","example.com/util","runtime"]
counts	toy	11	7	4	0	2
rates	toy	toy/runtime	0.71 (5/7)	0.83 (5/6)	1.00 (3/3)	0.50 (2/4)	1
edge	toy	`app` → `lib-pad` (toy/runtime `left-pad`)	inferred	1	["app","lib-pad","toy","left-pad","runtime"]
edge	toy	`app` → `pad-fork` (toy/runtime `left-pad`)	inferred	1	["app","pad-fork","toy","left-pad","runtime"]
edge	toy	`app` → `ui-kit` (toy/runtime `ui-kit`)	confirmed	1	["app","ui-kit","toy","ui-kit","runtime"]
edge	toy	`app` → `date-lib` (toy/runtime `naïve-date`)	confirmed	1	["app","date-lib","toy","naïve-date","runtime"]
edge	toy	`ui-kit` → `lib-pad` (toy/runtime `left-pad`)	inferred	1	["ui-kit","lib-pad","toy","left-pad","runtime"]
edge	toy	`ui-kit` → `pad-fork` (toy/runtime `left-pad`)	inferred	1	["ui-kit","pad-fork","toy","left-pad","runtime"]
edge	toy	`web` → `date-lib` (toy/runtime `naïve-date`)	confirmed	1	["web","date-lib","toy","naïve-date","runtime"]
label	toy	`app` → `lib-pad` (toy/runtime `left-pad`)	["app","lib-pad","toy","left-pad","runtime"]
label	toy	`app` → `ui-kit` (toy/runtime `ui-kit`)	["app","ui-kit","toy","ui-kit","runtime"]
label	toy	`app` → `date-lib` (toy/runtime `naïve-date`)	["app","date-lib","toy","naïve-date","runtime"]
label	toy	`ui-kit` → `lib-pad` (toy/runtime `left-pad`)	["ui-kit","lib-pad","toy","left-pad","runtime"]
label	toy	`web` → `date-lib` (toy/runtime `naïve-date`)	["web","date-lib","toy","naïve-date","runtime"]
label	toy	`web` → `ui-kit` (toy/runtime `ui-kit`)	["web","ui-kit","toy","ui-kit","runtime"]
```

  Each number in a `rates` line is the one F2 or F3 prints, and `mono` → `lib` with 2 is P2-009b's F6. Each `counts` line holds the numbers of its card's first line: `15 facts (7 requirements, 8 provisions), … 1 requirements unresolved` for `gomod`, and `11 facts (7 requirements, 4 provisions), … 2 requirements unresolved` for `toy`.
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
- N5, a moved baseline. `moved.tsv` is N2 with the gomod recall at `1.00 (6/6)`, `app` → `log` as `confirmed`, and a `chain` line that this tree lacks, as a baseline from after P2-009a would have against a tree before it (sha256 `d9c54d27bb99d0a97fb0cf5f2a10789963bc1154809667aabb47fd890c65a89a` with N2's two `counts` lines, `43062bf21b671aece74bc63ca785f64e0d44373ad6fb4f451c28746a0071fda9` before them; command below). `--all <r>/two <r>/moved.tsv` exits 0 (sha256 `d7905796795257544ad2a496b092a631430dd7e20cf62702e57362747f07ed1e`), and its last section reads:

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
  - The root `err` holds `bad` (label scope `prod`), `nolab` (no `labels.tsv`), `norepos` (no `repos/`) and `ok` (`a` → `b`, one hit). `--all <r>/err` exits 1 (sha256 `d763685424c5b0c34df3638912c3fc9de34a488c0f1630fcf7a1200fc8264c97`; `8648b35a03e935db6774a6b03e77737e13384176d7c284ed7def13186097337b` before the hardening follow-up put the three error texts in code spans). It starts:

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

Scorer error: `labels.tsv:1: unknown scope "prod"`

### Scorecard: fixture `nolab`
```

  and goes on with ``Scorer error: `labels.tsv is missing` ``, then `norepos` with ``Scorer error: `repos/ is missing` ``, then `ok`'s card.
  - `--numbers <r>/err` prints nothing on stdout, exits 1, and writes `bad: labels.tsv:1: unknown scope "prod"`, `nolab: labels.tsv is missing` and `norepos: repos/ is missing` to stderr. Since the follow-up for #600 each of these three lines, and each `baseline …` line below, starts with `mitos-score: `.
  - A baseline whose `rates` line has 7 fields makes `--all` print `baseline line 1: a line of kind rates has 8 tab-separated fields, found 7` and exit 1. (The message had backticks around the kind before the hardening follow-up. It lost them because the same message is printed inside a code span in N11.) A baseline line of kind `card` prints `baseline line 1: unknown line kind "card"` and exits 1.
  - `mitos-score --all`, `--all <root> a b`, `--numbers` and `-x` print the usage and exit 2. Without the guard, `-x` would try to read `-x/labels.tsv`.
- N7, the D1 boundary. Fixture `many` has `a/deps.toy` with n lines `require x` and `b/PROVIDES` with `provide x`, which gives n records under one repo-level edge. With n = 8 (`<r>/d1-8`) the run prints ``Most derivations any repo-level edge has: 8, `a` → `b` (toy/runtime `x`) in fixture `many`. D1 reopens above 8.`` and no bold line (sha256 `c68c5d70c1f315bc41b8f6dddf6276f3cea183ea8ece970820dd648cb29939ec`). With n = 9 (`<r>/d1-9`) it prints the line with 9 and then ``**Above 8: D1 reopens (`plan/phase-2.md`, Scope decisions).**`` (sha256 `a6c12fd1d9a0bb9b570a6c1a80f34ce6b2454198609532fabb643dbccce8bd01`). Both exit 0.
- N8, P2-009b's F6 reproduced: N2's `edge` line for `mono` → `lib` in `gomod` has status `confirmed` and derivation count `2`, and the `gomod` `rates` line ends with `2`. P2-001b's bound records count under the same rule (`countP` over every record with the key).
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
- N11, a tab inside a key. Fixture `t` has `a/deps.toy` with `require p<TAB>q` and `b/PROVIDES` with `provide p<TAB>q`. `--all <r>/tab` exits 1 with ``Scorer error: `a numbers line of this fixture would not read back (line 3: a line of kind edge has 6 tab-separated fields, found 7)` `` (sha256 `8e07536a7ae48f93deaaa32d80f5ec0b55c2bb2da1e551a850bf40472a57bec1`). Before the hardening follow-up the text had no code span, said `line 2`, because no `counts` line came first, and had backticks around `edge` (sha256 `9439a16b42fcf66fae9be3425f208d010b576b0a74e9fef3e9679f2a396da3b6`). `mitos-score <r>/tab/t` still prints its card and exits 0. Since the follow-up for #600 the tab is escaped, so the fixture scores: `--all <r>/tab` exits 0 (sha256 `35eb305188c5fc2a1e7aea02e71f0a7b50e9d196f129c329fab2783a54c5223b`) and prints the key as `p\tq`, `--numbers <r>/tab` exits 0 with four lines (sha256 `fb112135353e647a2e4c8693e25e41559db40d386d7840cd9f30eed993d499ff`), and the single-fixture card has `p\tq` where it had the tab (sha256 `816ed249795626c5ce9656b150568a87573a722e8a14fee0b7a9de24de0e60fc`). G32 pins the lines. What still fails a fixture this way is a tab or a line feed in its name (G25).
- N14, hostile names, from the follow-up for #600. The root `<r>/hostile` holds four fixtures whose directory names are `::warning::v2` (label scope `prod`), `x##[error]v1` (no `repos/`), `n`, a line feed and `::error::second line` (no `labels.tsv`), and `&#64;m <b>[l](u) *e* _e_`, which scores and has a key with U+001B and `##[warning]` in it and an unresolved key with a tab. The runs are `--all <r>/hostile`, `--numbers <r>/hostile`, `mitos-score` on each of the four, and `--all` with a root and with a baseline that do not exist and whose names hold a line feed and `::error::`. Every run exits as on `main`. With the stdout and stderr of the eight runs as `$out/*.out` and `$out/*.err`, every stderr line starts with `mitos-score: `, no stdout line starts with `::` after its blanks, and no line of either holds `##[` or U+001B:

```sh
! grep -v '^mitos-score: ' "$out"/*.err &&
  ! grep -E '^[[:space:]]*::' "$out"/*.out &&
  ! grep -F -e '##[' -e $'\x1b' "$out"/*.out "$out"/*.err
```

  On `main` at `7c3afc8` the same outputs hold 10 lines that the runner reads as a command, 7 on stderr and 3 on stdout, and one of the 10 holds a raw U+001B.
- N12, Q2 both ways. `<r>/typo/ok` is `err/ok` with a second label of kind `go-mod`. On `main`, `--all <r>/typo` exits 0 (sha256 `4239227eeeebdf4acfa3b31a150bcbc9f2e8e665b3f98ba04e476be1bf4ff41d`), and `--numbers` prints one more `rates` line, for `go-mod/runtime` with the fields `n/a`, `0.00 (0/1)`, `n/a`, `n/a` and `0`, and one more `label` line, ``label<TAB>ok<TAB>`a` → `b` (go-mod/runtime `x`)<TAB>["a","b","go-mod","x","runtime"]``. With #332's files it exits 1 with ``Scorer error: `label kind "go-mod" is not among the extracted facts` `` and the bold line ``**Not every fixture scored (`ok`), …`` (sha256 `b754961cacc06526438d605cad0e732d5c5f2f4475a478c967c64c435b2f279f`; `59e697fecaef8ffe61d0bd708a41666cb1d58c92a7c49bf663d3fc76b5a813e6` before the hardening follow-up put the error text in a code span).
- N13, the chain fixture after P2-009a. `--numbers eval/fixtures` prints the `chain` lines first, with edge type `env/runtime` (P2-001b's deferral) and a `chain` `rates` line whose most derivations is at least 2 (the row's "a requirement that has two derivations"; P2-001b's `twoBindings`). The `gomod` and `toy` lines are N2's bytes, because P2-009a's `collapse` change cannot move them: each `toy` repo-level edge has one record, and `mono` → `lib`'s two records are both `confirmed` (P2-009b F6). `--all eval/fixtures` exits 0. The builder records the `chain` lines and the hashes of both commands in the build notes. A `chain` most of 1 means the count or the fixture lost a derivation: stop and report.
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
    -e 's/^\(edge\tgomod\t`app` → `log` \)\(.*\)\tinferred\t1\t/\1\2\tconfirmed\t1\t/' $r/n.tsv > $r/moved.tsv
printf 'rates\tchain\tenv/runtime\t1.00 (2/2)\t1.00 (2/2)\t1.00 (2/2)\tn/a\t2\n' >> $r/moved.tsv
h=$r/hostile
v2='::warning::v2'; v1='x##[error]v1'; nl=$'n\n::error::second line'; mk='&#64;m <b>[l](u) *e* _e_'
mkdir -p "$h/$v2/repos/a" "$h/$v1" "$h/$nl/repos/a" "$h/$mk/repos/a" "$h/$mk/repos/b"
printf 'a\tb\ttoy\tx\tprod\n' > "$h/$v2/labels.tsv"
printf 'require x\n' > "$h/$v2/repos/a/deps.toy"
printf 'a\tb\ttoy\tx\truntime\n' > "$h/$v1/labels.tsv"
printf 'require x\n' > "$h/$nl/repos/a/deps.toy"
printf 'require k\x1b[31m##[warning]k\nrequire t\tu\n' > "$h/$mk/repos/a/deps.toy"
printf 'provide k\x1b[31m##[warning]k\n' > "$h/$mk/repos/b/PROVIDES"
printf 'a\tb\ttoy\tk\x1b[31m##[warning]k\truntime\n' > "$h/$mk/labels.tsv"
```

- Wrong variants, each built in a scratch copy of the head, one at a time. All twelve were measured:

| Variant | Edit | What fails |
|---|---|---|
| W1 | `derivations` lists only `c.predicted`'s keys | `derivations_keys` stops proving |
| W2 | `changed` keeps only `cur.filter (!base.contains ·)` | `changed_eq_nil` stops proving |
| W3 | `most` with `min` | `le_most` is false and stops proving |
| W4 | `most` adds 1 to the maximum | `most_mem` is false and stops proving (`le_most`'s proof also stops, though its statement still holds) |
| W5 | `tp` counts the predicted edges that are not labelled | at least G1, G5 and G6. Since the hardening follow-up, where the count is `Scorecard.typeCounts` in `Score.lean`: G1, G12, G24 and three card theorems in `Policy.lean`, and no longer G5 or G6, because `render` reads the same count |
| W6 | `consistent` is `true` | G5 |
| W7 | no "The hand labels changed." section | G13 |
| W8 | with no baseline the report says "No change against the baseline." | G9 |
| W9 | a failed fixture's baseline lines are compared | G16 |
| W10 | the bold D1 line at `top ≥ d1Threshold` | G7 |
| W11 | `numbersAll` returns the scored fixtures' lines when one failed | G18 |
| W12 | no `edge` lines | G1 |

### Checks, in order
From the repository root, at the head after the last rebase. `<scratch>` is a folder named for this agent.
1. Save the full build output and require a successful exit, the success line, and no warning or error lines:

   ```sh
   lake --dir eval/score build > "$scratch/build.log" 2>&1 &&
     rg '^Build completed successfully' "$scratch/build.log" &&
     ! rg '^(warning|error):' "$scratch/build.log"
   ```

   Inspect the saved log on failure. A failed pin reports `Expression … did not evaluate to true`.
   If `main` emits a warning too, compare the diagnostics and record the shared warning in the build notes.
2. A scratch `Axioms.lean`, never committed, with `import Score.Nightly` and `#print axioms` for each of the four theorems, and for `mem_tied` and the four `inert` theorems since the hardening follow-up, and for the three `plain` and three `logLine` theorems since the follow-up for #600. `cd eval/score && lake env lean <scratch>/Axioms.lean` prints the axiom lists under `statements`, each a subset of `[propext, Classical.choice, Quot.sound]`.
3. N1. In a detached worktree of `origin/main` (`git worktree add --detach <scratch>/p2010-main origin/main`, then `lake --dir eval/score build` in it), run `mitos-score eval/fixtures/toy`, `…/gomod` and, after P2-009a, `…/chain`, then the same at the head. Each pair is byte equal. Compare with the worktree, not with the hashes above, if `origin/main` has moved the scorer or the fixtures.
4. N2: `--numbers $r/two | sha256sum`.
5. N3: `--all $r/two | sha256sum`. Then check that the cards are the report's tail: `{ echo; mitos-score $r/two/gomod; echo; mitos-score $r/two/toy; } > c.md`, then `tail -c $(stat -c %s c.md) all.md | cmp - c.md`.
6. N4.
7. N5.
8. N6, with the exit codes and the stderr lines.
9. N7, N9 (its second half needs a scratch edit to `Score.lean` and is optional), N10, N11 and N12 (its #332 half once #332 has merged; before that, optional on a scratch copy with #332's files).
10. N13 on `eval/fixtures`, recorded in the build notes.
11. At least W1, W5, W6, W7 and W11 in a scratch copy, each failing the named check.
12. `git diff --name-only origin/main...HEAD` prints only `eval/score/Main.lean`, `eval/score/Score/Nightly.lean`, `tasks/P2-010-nightly-scorecard.md` and files under `ops/runs/`. That is the list of the row's own build (#551). For the hardening follow-up (#588) the list was `eval/score/Score.lean`, `eval/score/Score/Chain.lean`, `eval/score/Score/Nightly.lean`, `tasks/P2-009a-chain-fixture.md`, `tasks/P2-010-nightly-scorecard.md`, `tasks/P2-012-ci-wiring.md` and files under `ops/runs/`. For the follow-up for #600 it is `eval/score/Main.lean`, `eval/score/Score.lean`, `eval/score/Score/Chain.lean`, `eval/score/Score/Nightly.lean`, `tasks/P2-010-nightly-scorecard.md` and files under `ops/runs/`.
13. `lake exe mitos-gate runlog --head ops/runs`, and `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'` shows only `A` lines.
14. `.claude/scripts/plan-tasks.test.sh`. It passes once `P2-010` has left `plan-tasks.pending`, which the design-landing PR does.
15. In CI, `checks` and `gate` are green. `checks` builds `eval/score`, so it kernel-checks the theorems and runs every pin (G1 to G28 since the hardening follow-up, G1 to G32 since the follow-up for #600), and the toy card it posts must read as on `main`.

### Risks and stop conditions
Risks:
- R1. The numbers file is the baseline contract. A later change to its kinds or columns, or to `renderEdge`'s text, makes every line show as changed once, on the first run after it lands. That is honest, and it shows for one run only. The `counts` kind of the hardening follow-up did not cost that run: against a baseline with no `counts` line, the counts are left out and the rest is compared (G24). The other direction does stop: a scorer from before that change reads a `counts` line as `unknown line kind "counts"` and exits 1, which matters only for a revert, or for a nightly dispatched on a branch from before it.
- R2. A baseline edited by hand or rewritten to CRLF differs on every line, so every line shows as changed. A line of an unknown kind or with the wrong field count stops the run with exit 1.
- R3. `TypeCounts.cardLines` copies the text of `render`'s three table rows. A later PR that changes those rows fails G5 in its own build, so it edits `cardLines` in the same PR, and its plan cell must name `eval/score/Score/Nightly.lean`. A shared count function needs `Score.lean` (follow-up). Settled by the hardening follow-up: `render` and `numbers` read `Scorecard.typeCounts`, and both print a row through `TypeCounts.row` and `trustRow`.
- R4. The first nightly after this merges has no baseline and prints "No baseline given, so nothing was compared."
- R5. `resolve` runs up to five times per fixture in `--all` (in `score`, in `checked` through `numbers`, and in `summary`'s `cur`, `top` and `at?`) and three times in `--numbers`. Measured over 3 runs each with the built binary: 6 to 7 ms for `--all` over two fixtures, 5 ms for one card. The reference resolver is O(n³) (P2-001b's deferrals), which is fine at fixture size.
- R6. `renderEdge` prints keys raw inside code spans, and the nightly will be posted. A backtick or a newline in a key, or `@` in an error message, reaches the post as it is. The PR comment of the toy card has the same exposure today. Escaping belongs in `Score.lean` (follow-up). Settled by the hardening follow-up: `Score.inert` and `inert_safe` (Hardening notes, with what it does not cover).
- R7. The D1 line names the first edge that has the top count. Other edges with the same count are not listed. Settled by the hardening follow-up: the line lists every such edge (`mem_tied`, G22).
- R8. Fact and unresolved counts are not in the numbers file. A change that only moves unresolved requirements shows in the card but not in the diff. Settled by the hardening follow-up: the `counts` line and its table in the diff (G23, G24).
- R9. CI does not run `--all` or `--numbers` until P2-012. Until then, N1 to N13 are the builder's and the verifier's, and G1 to G21 are what CI runs. Settled since: `checks` runs every pin in each PR's build, which is G1 to G28 since the hardening follow-up and G1 to G32 since the follow-up for #600, and since P2-012 `nightly.yml` runs both modes on `eval/fixtures`.

Stop conditions for the builder:
- S1. After `git fetch origin main`, run `git diff --stat eac85d2 origin/main -- eval/score eval/fixtures core/Mitos/Core/Graph.lean core/Mitos/Impl/Resolve.lean lean-toolchain`.
  - Changes from P2-001b, P2-009a or #332 are expected.
  - If it shows `eval/score/Main.lean`, or a file named `eval/score/Score/Nightly.lean`, stop: this design is amended first.
  - If the name or type of an input under `types` changed, stop for the same reason.
  - If `Scorecard.render`'s table rows changed text, say so in the PR body. As #551 merged, the builder also updated `TypeCounts.cardLines`, the copy of that text, and G5 failed until then. Since the hardening follow-up there is no copy: `render` prints its rows through `TypeCounts.row` and `TypeCounts.trustRow` in `Score.lean`, and `consistent` looks for the same two. If the card gained a table, stop and report.
  - If only bodies changed, go on, and re-run N1 to N12.
- S2. `ls eval/fixtures` lists `chain`. If it does not, P2-009a has not merged, and the plan's wave W6 has not started: stop.
- S3. On `eval/fixtures`, the `gomod` and `toy` lines of `--numbers` differ from N2: stop and report. P2-009b's F6 says they cannot move.
- S4. The chain fixture is not laid out as `labels.tsv` plus `repos/`, or it needs a flag to score: stop, because this design is amended.
- S5. A check fails and the fix is outside `touches`: stop and report. Never edit a label or a fixture to move a number, and never delete a pin.
- S6. Done: the PR is open on `main`, `gate` is green, checks 1 to 14 pass at the head, and every thread is answered. Report the head as merge-ready. No path here is the owner's, so an agent merges it.

cut_line: this row ships `Score/Nightly.lean` with its four theorems and 21 pins, the `Main.lean` diff, the build notes in this file and the run log. It leaves these to other rows:
- the nightly run, the artifacts, the baseline download, the post and any CI use of `--all` or `--numbers` (P2-012);
- the chain fixture and its numbers (P2-009a);
- Q1 to Q3 (#325, #332);
- escaping in the card, and a count function shared with `render` (the PR's follow-up issue).

It adds no fixture, no CI step and no change to the single-fixture card.

deferrals:
- To P2-012 (#213), as the contract:
  - Nightly: build the scorer and write the Markdown report with `--all`, passing the prior baseline only when available. Write `--numbers` to a temporary path. If scoring fails, remove the temporary output and preserve the failure status. Move the temporary file to the artifact path `numbers.tsv` only after a successful exit, then upload it as `scorecard-numbers`. A successful run over an empty root may publish an empty baseline. P2-012's scorecard step already stages its numbers this way before moving them into the upload path.
  - "`main`'s" baseline. The root's default (owner_decisions, Q-a): the `numbers.tsv` in the `scorecard-numbers` artifact of `main`'s newest nightly that uploaded it, chosen by the artifact and not by a successful run. P2-012 owns the fetch, as its C1 specifies (`actions: read`), and decides whether a PR job compares against it; the owner merges P2-012.
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
- To the PR's follow-up issue (#552, no row): none left. The hardening follow-up settled all four, and Hardening notes records them:
  - R3, one count function in `Score.lean` that both `render` and `numbers` use. It retired `TypeCounts.cardLines`. `consistent` and G5 stay, because no pin is deleted: they still fail when `render` stops printing a row.
  - R6, escaping of keys and error text in the card and the report.
  - R8, fact and unresolved counts in the numbers file, and R7, every edge that ties for the most.

owner_decisions:
- Settled by the plan: this row's cells; an agent merges it; eval code only, with the wiring in P2-012; the D1 threshold of 8 (`plan/phase-2.md:110-111`); and that the numbers never fail a run while a scorer error does (`docs/process.md:190`).
- This row's code needs no owner call: the cell's "a scorecard module" is one module, and `--all` takes any numbers file. Where `main`'s baseline is stored has a root's default, which answers #160 item 3: the `numbers.tsv` in the `scorecard-numbers` artifact of `main`'s newest nightly that uploaded it, fetched as P2-012's C1 specifies, and the diff against it is `--all`'s line-set diff (D3). P2-012 owns the fetch, and the owner can overrule the default.
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
- Base `5914856`. S1 reported 19 changed files since `eac85d2` across core, the chain fixture, and scorer internals. The CLI entry point and scorecard table rows match the design. S2 and S4 passed with `chain` present in the standard fixture layout.
- Both scorer builds succeeded. They emitted the same existing `Mitos/Core/Graph.lean` warning about importing `Mathlib.Data.List.Nodup` without a module header. The scorer changes emitted no diagnostics. The four axiom lists matched the lists above.
- N1–N13 passed with the merged scorer policy. N1 compared all three cards byte for byte against a detached `main` build. N3 preserved both fixture cards as the report tail. The optional pre-merge policy variants were omitted.
- Scratch mutations W1, W5, W6, W7 and W11 each failed the expected theorem or guard. The plan-task self-test passed.
- Local `lake check` and `lake comparator --paranoid` could not start their inner checks because bubblewrap could not set up its UID map in this environment.
- The verifier passed both sandboxed core checks, and the hosted `gate` passed at `e133cbc`. [Verification findings](https://github.com/kitimark/mitos/issues/552) [Gate run](https://github.com/kitimark/mitos/actions/runs/44910456966/job/136864955296)
- CodeRabbit review added G21 and the lossless edge identity, and clarified how P2-012 publishes the baseline. Re-ran N1–N13 and the five scratch variants on the revised format.
- Run logs `ops/runs/2026-11-21/P2-010-builder-1.json` and `ops/runs/2026-11-21/P2-010-builder-2.json`.

| Output | SHA-256 |
|---|---|
| chain | `bfb0175368f5f5f1f77eae4da9bc0f5a83e6c08935d7806071557add1116e1c6` |
| gomod | `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf` |
| toy | `17c55e9cfa3a9db873c50c980cf2cbea62195fe2eebecde3edc0a13add38f21a` |
| N2 | `bb6f3e4d31015590ee88fb4eb2be92c3be7bcf387df7d910c9793962cd158dec` |
| N3 | `c1226aa886ddd42f80151a396a8e8de5c6c6cbc6aa336814f4a4a86939944ae0` |
| N4 | `4fe81f4dbf784f4a6f7a4522f01e92b6aaed5fbf6eca40dda1db828072507924` |
| N5 | `d7905796795257544ad2a496b092a631430dd7e20cf62702e57362747f07ed1e` |
| N6-all | `8648b35a03e935db6774a6b03e77737e13384176d7c284ed7def13186097337b` |
| N6-numbers | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| N7-8 | `c68c5d70c1f315bc41b8f6dddf6276f3cea183ea8ece970820dd648cb29939ec` |
| N7-9 | `a6c12fd1d9a0bb9b570a6c1a80f34ce6b2454198609532fabb643dbccce8bd01` |
| N9 | `4a263d358305de3146bc5bb1302463bf8690ba388100363ea1ed666ea877ff16` |
| N10 | `f82928dbce0d457691bde030de022a3888407bc9262d73433b359048b39b198d` |
| N11 | `9439a16b42fcf66fae9be3425f208d010b576b0a74e9fef3e9679f2a396da3b6` |
| N12 | `59e697fecaef8ffe61d0bd708a41666cb1d58c92a7c49bf663d3fc76b5a813e6` |
| N13-numbers | `decac0064d68dd72da77b27606e60138e3147f3a1719b6254a2e4ccf51228228` |
| N13-all | `b0d59f2c7e4b5c0a07ed3b4524cc3315cdb84daf1b62b37a3c9eede58ef23315` |

N13 chain rows:

```tsv
rates	chain	env/runtime	0.75 (3/4)	0.75 (3/4)	1.00 (1/1)	0.67 (2/3)	2
edge	chain	`web` → `orders` (env/runtime `DATABASE_URL`)	confirmed	2	["web","orders","env","DATABASE_URL","runtime"]
edge	chain	`web` → `jobs` (env/runtime `QUEUE_URL`)	inferred	1	["web","jobs","env","QUEUE_URL","runtime"]
edge	chain	`web` → `billing` (env/runtime `QUEUE_URL`)	inferred	1	["web","billing","env","QUEUE_URL","runtime"]
edge	chain	`web` → `mail` (env/runtime `SMTP_HOST`)	inferred	1	["web","mail","env","SMTP_HOST","runtime"]
label	chain	`web` → `orders` (env/runtime `DATABASE_URL`)	["web","orders","env","DATABASE_URL","runtime"]
label	chain	`web` → `jobs` (env/runtime `QUEUE_URL`)	["web","jobs","env","QUEUE_URL","runtime"]
label	chain	`web` → `mail` (env/runtime `SMTP_HOST`)	["web","mail","env","SMTP_HOST","runtime"]
label	chain	`web` → `logs` (env/runtime `LOG_SINK`)	["web","logs","env","LOG_SINK","runtime"]
```

The nightly maximum is 2 for `web` → `orders` (env/runtime `DATABASE_URL`).

## Hardening notes
The follow-up for #552 items 1 to 3, built on `main` at `00fae4d`. It edits `eval/score/Score.lean` and `eval/score/Score/Nightly.lean`, and no fixture, label or workflow. Run log `ops/runs/2026-11-28/P2-scorecard-hardening-builder-1.json`. The same PR settles #549 items 2 and 3, recorded in `tasks/P2-009a-chain-fixture.md`.

What it does:
- R6, escaping. The property, stated first: no text that comes from a fixture, a label file or a baseline can put a backtick, a pipe, a line feed, a carriage return or an `@` into the card or the report. So such text cannot mention a user or a team, end the code span it is printed in, add a cell to a table row, or start a line. Starting a line is what a heading, a list item, an HTML block and a workflow command in CI's log each need, and CI prints the cards to its log and posts them as a comment.
  - One function enforces it, `Score.inert`. It maps each of those five characters, and the backslash, to a fixed text (`\x60`, `\x7c`, `\n`, `\x0d`, `\x40`, `\\`) from one table, `Score.escapes`. `Score.code` is `inert` inside a code span. The line feed, the carriage return and the backslash get the text Lean's `repr` prints for them, and the other three the same `\xNN` form. So the toy card's line for the CRLF requirement, `"ui-kit\x0d"`, which `repr` printed on `main`, keeps its bytes.
  - Proved for every string: `inert_safe`, `inert_injective` and `inert_clean` (under `statements`). `inert_cases` holds one case per character.
  - Every place that prints such text calls `inert` or `code` once: the card's header, its table rows, `renderEdge`, the unresolved lines, the report's rows, its D1 line, its diff items and the error cards. G26 holds that none skips it.
  - The numbers file keeps raw fixture names and edge types, because it is data and not Markdown. The third field of an `edge` or `label` line is the escaped text, and the identity field is JSON. The report prints an edge from the identity (`keyOf`, G28) and escapes every cell it copies from a line, so a baseline cannot inject text either.
  - Error text is printed in a code span. It quotes label fields, such as an unknown scope, and a code span is the one place where escaped text cannot become a link or emphasis. This moves N6, N11 and N12.
  - What the property does not cover. An edge type or a fixture name in a table cell is escaped but stands outside a code span, so the card's rows keep their bytes. In a scored card the edge type is a reader's own kind, because `score` refuses a label kind that no fact has, and the single-fixture card prints the name in a code span. So this reaches only the report's table cells: a fixture directory name, or a cell of a baseline, could show as emphasis or a bare link there, and could not mention, break the row or leave its cell. In an unresolved line, a key that holds a double quote, a tab or another control character prints as it is, where `repr` printed an escape on `main`, and no fixture has one. A tab in a key still fails the fixture (N11). What goes to stderr is not Markdown and is not escaped. The follow-up for #600 settled these, except the bare link and the double quote (Follow-up notes for #600).
- R3, one count. `Scorecard.factCounts` and `Scorecard.typeCounts` are in `Score.lean`. `render` prints its header from the first and its rows from the second, through `TypeCounts.row` and `TypeCounts.trustRow`, and `numbers` reads the same two. `TypeCounts.cardLines` is gone. `consistent`, G5 and the run-time check stay.
- R7, ties. `tied top ds` is the edges of one fixture whose count is `top` (`mem_tied`), and the D1 line joins them over the fixtures with `; `. The line still starts `Most derivations any repo-level edge has: <n>, `, which is all the nightly step reads, so `.github/workflows/nightly.yml` needs no change. On `eval/fixtures` there is a real tie at 2.
- R8, counts. The numbers file has one `counts` line per fixture. The report shows a counts table when one changed. A baseline with no `counts` line is still read (G24, and the command-line run below).
- #552 item 2. G25 fails when the readback-equality check in `problem` answers `none`.
- #552 item 3. Two edges or labels that differ in identity print differently, and the report prints each from its identity, so its two sides differ (G21, with the argument under `inert_injective`).
- `parseNumbers`' field-count message lost the backticks around the kind, because it is printed inside a code span.

Outputs, by sha256, with the scratch roots of `fixtures`. The first four rows and N3, N4, N5, N7, N9 and N10 are byte for byte what `main` prints, and every exit code is the same:

| Output | `main` at `00fae4d` | Head | What moved |
|---|---|---|---|
| `toy` card | `17c55e9c…` | same | |
| `gomod` card | `889671a4…` | same | |
| `chain` card | `bfb01753…` | same | |
| N3, N4, N5, N7-8, N7-9, N9, N10 | as under `fixtures` | same | |
| N2 | `bb6f3e4d…` | `86af9dd3c091b6fc8e1e57a2e33eb34a55e15d27279cbbe68f820856df417136` | two `counts` lines |
| N6-all | `8648b35a…` | `d763685424c5b0c34df3638912c3fc9de34a488c0f1630fcf7a1200fc8264c97` | three error texts in code spans |
| N11 | `9439a16b…` | `8e07536a7ae48f93deaaa32d80f5ec0b55c2bb2da1e551a850bf40472a57bec1` | code span, `line 3`, no backticks around `edge` |
| N12 | `59e697fe…` | `b754961cacc06526438d605cad0e732d5c5f2f4475a478c967c64c435b2f279f` | error text in a code span |
| N13-numbers | `decac006…` | `94ef8bb3fd2f5d5f2f4ee737f38fc8df97a7153432337af55f1147a9306e102f` | three `counts` lines |
| N13-all | `b0d59f2c…` | `67b97c5bb1d3685f918d9e73216c3cd6114e4fe1ecfbe1b04d7f1e70fea0faa4` | the D1 line |

The three new lines of N13-numbers, each before its fixture's other lines, are `counts chain 14 4 5 5 1`, `counts gomod 15 7 8 0 1` and `counts toy 11 7 4 0 2`, tab-separated. The D1 line of N13-all now reads:

```
Most derivations any repo-level edge has: 2, `web` → `orders` (env/runtime `DATABASE_URL`) in fixture `chain`; `mono` → `lib` (go-module/runtime `example.com/lib`) in fixture `gomod`. D1 reopens above 8.
```

Runs of the built binary:
- `--all eval/fixtures <main's --numbers output>` exits 0 and ends its baseline section with `No change against the baseline.` and `The baseline has no fact counts, so they are not compared.` Against its own `--numbers` output it prints `No change against the baseline.` alone.
- `main`'s binary given the head's numbers prints `baseline line 1: unknown line kind "counts"` and exits 1 (R1).
- A scratch root with a backtick, a pipe, `@` and a carriage return in a fixture name, a repo name, two keys and a label scope, and a second fixture whose name holds a line feed: `main`'s `--all` output has 12 `@` and 46 lines, and the head's has no `@` and 44 lines. Both exit 1, because two of its three fixtures fail.

Wrong variants, each one edit built in the worktree and then put back. All 43 failed the build (exit 1):

| Edit | What fails |
|---|---|
| the readback check in `problem` answers `none` | G25 |
| one of the five characters has no row in `escapes` (five builds) | `escape_safe`, which `inert_safe` rests on, and `inert_cases` |
| the backslash has no row | `keyed_ne_plain`, which `inert_injective` rests on, and `inert_cases` |
| `inert` returns its input | `inert_safe`, `inert_clean`, `inert_injective`, `inert_cases` |
| one print site prints raw text (20 builds: the card's header, a type row, a trust row, `renderEdge`'s repo, type and key, the unresolved path and key, the error card's name and text, a report row, the D1 line's fixture name, the failed names, the not-scored line, an item's name, status, count and unreadable line, an identity that does not parse, a label item printed from its line's text) | G26 each time, and G17 or G27 for three of them |
| the D1 line names the first top edge only | G22 |
| `tied` keeps one edge per fixture | `mem_tied`, G22 |
| no `counts` line | G1, G23, G24, G25 |
| `parseNumbers` refuses `counts` | G1 and fourteen more pins |
| no counts table in the diff | G23 |
| a baseline with no `counts` line is compared as if it had them | G24 |
| W1 | `derivations_keys`, G20 |
| W5 | G1, G12, G24 and three card theorems of `Policy.lean` |
| W6 | G5 |
| W7 | G13, G21 |
| W11 | G18 |

The other four of the 43 are the reader variants in `tasks/P2-009a-chain-fixture.md`.

The build prints the one warning `main` prints, for `Mitos/Core/Graph.lean`. The axioms of the nine theorems are the lists under `statements`.

## Follow-up notes for #600
The follow-up for #600, the minor findings of #588's verdict, built on `main` at `7c3afc8`. It edits `eval/score/Score.lean`, `eval/score/Score/Chain.lean`, `eval/score/Score/Nightly.lean` and `eval/score/Main.lean`, and no fixture, label or workflow. Run log `ops/runs/2026-11-28/P2-010-followups-builder-1.json`.

What it does, by the item of #600:
- Items 1 to 3, lines of this file that #588 left stale: S1's `cardLines` bullet, R9, A7, `touches`, `must_not_touch` and check 12. Each now says what holds on `main`, and keeps what #551 said.
- Item 4, workflow commands. The property, stated first: no text that comes from a fixture, a label file, a baseline or a path can make a line of the scorer's stdout or stderr that GitHub's runner reads as a workflow command.
  - The runner reads both streams, line by line, and a line ends at a line feed or a carriage return. It reads a command when the line starts with `::` after its leading blanks, or when it holds `##[` anywhere. These are `ActionCommand.TryParseV2` and `TryParse` in actions/runner, read at its commit `4812b90`, and `startsCommand` in `gate/MitosGate/Util.lean` models the same two rules.
  - #588 kept input text from starting a line of the card. On `main` a key or a name still put `##[error]` into the card, which CI prints to its log, and both forms reached stderr at the start of a line (N14).
  - `inert` now escapes `[` as `\x5b`. The card's and the report's own text holds no `[`, and the usage, the one stderr text that does not pass through `logLine`, holds no `#`. So no line the scorer prints holds `##[`.
  - `Score.logLine s` is `mitos-score: ` and then `inert s`. `Main.fail` prints it. `fail` writes every stderr line other than the usage: the single-fixture error, each `--numbers` error, the baseline error, and an I/O error. `main` now catches the I/O error, which Lean printed as `uncaught exception: …` with the path as it is. The exit code stays 1.
  - Proved: `logLine_head` (the line starts with `m`, so not with blanks and `::`) and `logLine_safe` (it holds no `[`, no line feed and no carriage return, so it is one line without `##[`). That these two facts stop both parsers is an argument, not a theorem about the runner.
  - Not covered: `--numbers` prints names as they are on stdout, because the numbers file is data. `nightly.yml` writes it to a file and not to the log. Like the gate's model, the argument reads the runner's matching as ordinal.
- Item 5, text outside a code span. The finding is real. Four places print input text outside a code span: the edge type in `renderEdge`, the edge type in the card's two tables, every cell of a report row (a fixture name, an edge type or a cell of a baseline line), and the status and the count of a diff item. There an entity is decoded, so `&#64;` spells the `@` that `inert` escapes, and `<`, `[`, `*`, `_` and `~` open HTML, a link, emphasis and strikethrough. The decoding is CommonMark's rule. Whether GitHub then notifies the user was not measured.
  - `Score.plain` is `inert` with five more rows: `&`, `<`, `*`, `_` and `~` print as `\x26`, `\x3c`, `\x2a`, `\x5f` and `\x7e`. Those four places call `plain`. A code span still calls `inert`, so a key such as `DATABASE_URL` keeps its bytes there.
  - Proved for every string: `plain_safe`, `plain_injective` and `plain_clean` (under `statements`). G30 holds that none of the four places skips `plain`.
  - Not covered, because only a code span stops them: a bare `www.` or `https://` address, an issue reference such as `#1`, an emoji code and `$` math still render in a cell outside a code span. A name with `_` reads `\x5f` there. Markdown's own `\_` would read better, but the output would then hold the character, and no statement about single characters would hold.
- Item 6, control characters. `inert` escapes every character below U+0020, and U+007F: the tab as `\t` and the others as `\xNN`. That is the text Lean's `repr` prints, which the unresolved line printed before #588. `inert_safe` now says that no such character survives, and G31 pins the unresolved line. A double quote in an unresolved key still prints as it is.
  - This retires N11's failure. A key with a tab is escaped in its `edge` line, so the line reads back and the fixture scores (G32). The check that every numbers line reads back stays, and a fixture whose name holds a tab or a line feed still fails on it (G25).
- Item 7, chain keys. The chain format is specified in `tasks/P2-009a-chain-fixture.md`, which says that a binding's target loses the whitespace around it and that a blank key gives no fact. On `main` a `needs` or `serves` key kept that whitespace. So `serves db ` gave `svc/"db "`, which no target can name, and in a file with CRLF line ends every `needs` and `serves` key ended in a carriage return while the bound key and the target did not, so nothing resolved. A key that keeps the whitespace can never meet a target that loses it, so the keys now lose it too.
  - In `Score.Chain.ofLine`, the key of a `needs` or `serves` line is what stands after the verb with the whitespace around it removed (`trim`), and its span starts after the blanks that follow the verb (`keySpan`, private). A blank key still gives no fact (`skips_blank_keys`). A binding's key keeps its rule: it ends at the first space, so `binds  db` has an empty key and gives no fact (`skips_incomplete_bindings`). `requires_env` keeps its text and its proof.
  - `Score.Chain.trims_keys`: `needs A `, `needs  A` before a carriage return, `serves db` before a tab and `serves  db` give the keys `A`, `A`, `db` and `db`, each with its span on the key.
  - `Score.chain_crlf_end_to_end`: three chain files with CRLF line ends, a blank after a `serves` key and two blanks before a `needs` key score to the one edge `web` → `orders`. So `ingest` accepts each span, and the trimmed keys meet the binding's key and target.
  - No fixture line has such whitespace, so the `chain` card keeps its bytes.
  - `tasks/P2-009a-chain-fixture.md` was outside this follow-up's paths. Its format rule, its statement list and its count of the reader's theorems (seven, now eight) do not name this change yet.
- Item 8 names a count in #588's PR body, which is not in the repository.

Outputs, by sha256, with the scratch roots of `fixtures`. The cards of `toy`, `gomod` and `chain`, and N2 to N5, N6's report, N7, N9, N10, N12 and N13, are byte for byte what `main` at `7c3afc8` prints, and their exit codes are the same. What moved:

| Output | `main` at `7c3afc8` | Head |
|---|---|---|
| N6, stderr of `--numbers <r>/err` | three lines | the same three, each after `mitos-score: ` |
| N6, stderr of the two baseline errors | one line each | the same line after `mitos-score: ` |
| N11, `--all <r>/tab` | exit 1, `8e07536a…` | exit 0, `35eb305188c5fc2a1e7aea02e71f0a7b50e9d196f129c329fab2783a54c5223b` |
| N11, `--numbers <r>/tab` | exit 1, nothing on stdout | exit 0, `fb112135353e647a2e4c8693e25e41559db40d386d7840cd9f30eed993d499ff` |
| N11, `mitos-score <r>/tab/t` | exit 0, the tab as it is | exit 0, `p\tq`, `816ed249795626c5ce9656b150568a87573a722e8a14fee0b7a9de24de0e60fc` |

N14, the eight hostile runs: on `main` their outputs hold 10 lines that the runner reads as a command, 7 on stderr and 3 on stdout, and one of the 10 holds a raw U+001B. At the head they hold none, and the three checks under N14 pass. Each exit code is the one `main` gives.

Wrong variants, each one edit built in the worktree and then put back. Of the 19, 17 failed the build (exit 1). The last two build, because no statement reaches `Main`'s I/O, and N14 fails on them:

| Edit | What fails |
|---|---|
| `escapes` has no `[` row | `inert_safe`, `plain_safe`, `inert_cases`, `plain_cases`, `logLine_cases` |
| `escapes` has no control rows | `inert_safe`, `plain_safe`, `inert_cases`, `plain_cases` |
| `escapes` has no tab row, so the tab prints as `\x09` | `inert_cases` |
| `plainEscapes` is `escapes` | `plain_safe`, `plain_cases` |
| `plainEscapes` has no `&` row, or no `_` row (two builds) | `plain_safe`, `plain_cases` |
| one of the places outside a code span calls `inert` (six builds: `renderEdge`'s type, a type row, a trust row, a report row, an item's status, an item's count) | G30 each time |
| `logLine` has no prefix | `logLine_safe`, `logLine_head`, `logLine_cases` |
| `logLine` does not escape | `logLine_safe`, `logLine_cases` |
| a `needs` key, or a `serves` key, is not trimmed (two builds) | `Score.Chain.trims_keys` |
| a key's span starts at the blanks before it | `Score.Chain.trims_keys` |
| `fail` prints its text as it is | N14: 7 command lines |
| `main` does not catch an I/O error | N14: 4 command lines |

A failed module stops the build before the modules that import it, so a row lists the statements of the first module that fails. The build has 1046 jobs and prints the one warning `main` prints, for `Mitos/Core/Graph.lean`. The axioms of the theorems under `statements` and of the two chain theorems are subsets of `[propext, Classical.choice, Quot.sound]`.

## Done when
- [x] the builder's local checks and the verifier's sandboxed core checks passed, and `gate` is green
- [x] N1 to N12 hold at the head, and N13's `chain` lines and hashes are in the build notes
- [x] no `sorry`, no new axioms (checks 1 and 2)
- [x] run-log record written (ops/runs/)

## Rationale

This section is the design's reasoning as #551 merged it. The hardening follow-up retired two of the tradeoffs below: the copy of `render`'s row text (R3) and raw keys in the posted text (R6). The follow-up for #600 retired a third, the fixture that fails on a tab in a key (N11).

### Problem
Exit criterion 5 needs three things on top of today's one-fixture card: every fixture in one report, a diff against `main`'s card, and the largest derivation count of any repo-level edge. This row may not edit `Score.lean`, and `Scorecard` holds collapsed keys and statuses, not edge records. `main`'s scorer is a different build from the head's, so a diff needs a file that an earlier run wrote. The single-fixture card is pinned three ways: by CI's post, by P2-009b's hashes and by #332's `native_decide` theorems. And the inputs are files any PR can change. A label deleted or swapped can raise recall with no change to the code, so the diff has to show the labels too.

### Shape
`Score.Nightly` owns five decisions:
- how many derivations a repo-level edge has: the records of `resolve c.facts` with that key, for every key the resolver made;
- what one fixture comes to as lines: one `rates` line per edge type, one `edge` line per repo-level edge, one `label` line per label;
- that those lines agree with the card (`consistent`) and read back (`parseNumbers`);
- what changed against a baseline: the two-sided set difference of those lines;
- how the report reads.

`Main` owns walking the fixtures root, reading the files and the exit code. Everything else is reused from `Score`. The baseline needs no parser beyond a kind and a field count, because lines are compared as strings, and the diff copies cells instead of recomputing them. The four theorems pin the places where a wrong answer would hide a signal: a count that skips an edge, a maximum that misses one or invents one, and a diff that misses a disappearance. The 21 pins hold the report's sentences and the build-time check against `render`.

Interface depth: eleven names and four theorems, and callers see three commands. They hide the counting rule, the line format, the check against the card, the diff and the D1 rule.

### Tradeoffs accepted
- A numbers format that is only a contract between two runs of this tool, in exchange for a diff with no parsing (R1).
- A diff that shows "before" and "after" cells side by side, not computed deltas such as `+0.17`.
- `resolve` running several times per fixture (R5), and a copy of `render`'s row text checked against it (R3), in exchange for no edit to `Score.lean`.
- A fixture with a tab in a key fails instead of being escaped (N11). It is loud, and no fixture has one. Since the follow-up for #600 the tab is escaped and the fixture scores (G32).
- Raw keys in the posted text (R6), as the PR comment already has.
- No baseline on the first nightly (R4).

### Alternatives considered
- A1. Put edges or counts into `Scorecard`, or make `collapse` return counts. That edits `Score.lean` outside the cell, in the file P2-009a and #332 edit.
- A2. Count only the card's predicted keys (Design A's D2). The D1 number then moves with Q1, and a dropped edge hides its derivations from the tripwire (W1).
- A3. Count distinct `Edge.key` values instead of records (Design B). P2-001a handed over records, and #101's `EdgesNodup` makes the two equal, so a second rule adds nothing.
- A4. A JSON summary with a schema, decoded into structures, and a per-edge delta type (Design B). The line set gives the same edge and label changes with no schema, no decoder and one theorem for "no change".
- A5. Numbers only in the baseline (Design A). A label swap keeps every count, and the diff would not say which label moved.
- A6. A floor of required fixture names in code (Design B). It is one more list to keep in step with `eval/fixtures/`, it blocks the build until `chain` exists, and a removed fixture already shows against the baseline.
- A7. Three modules and a `selftest.sh` (Design B). That is outside the cell, so the plan would need an owner edit. The pure-function pins now cover G9 to G21, and the builder's runs cover N6 to N12. The two follow-ups added pins of the same kind, G22 to G28 and G29 to G32, and the run N14.
- A8. Refuse a fixture whose text would break Markdown, and blank `@` and backticks in error text (Design B). The renderer is in `Score.lean`, and a policy that refuses fixtures belongs with it (follow-up).
- A9. Diff the Markdown with `diff -u` in the workflow. That puts this row's code in `.github/`, and a line diff of cards is noisy.
- A10. A baseline made by running this head's scorer on `main`'s fixtures. It measures changes to the fixtures, not to the code.
- A11. One mode that writes the numbers to a file argument (Design B's `--json`). One more flag and an output path. Two modes that each print one thing to stdout cost one more run of 7 ms.
- A12. Let an IO error abort the run (Design A). One unreadable fixture would hide every card.

### Open questions and risks
- Q-a. Where `main`'s baseline is stored and how the diff against it is made. Default, the root's: the `numbers.tsv` in the `scorecard-numbers` artifact of `main`'s newest nightly that uploaded it, fetched as P2-012's C1 specifies, and compared by `--all`'s line-set diff (D3). This answers #160 item 3. P2-012 owns the fetch and whether a PR job compares against it, and the owner can overrule the default; the code takes any numbers file.
- Q-b. Should a numbers line carry a format version? Not now (R1).
- The builder passed N13 after P2-009a merged and recorded the chain rows and hashes in the build notes. P2-012 later ran `--all` and `--numbers` successfully in its hosted nightly dispatch. [Hosted nightly scorecard job](https://github.com/kitimark/mitos/actions/runs/45142033243/job/137582137625)

### Next implementation step
Run S1 and S2, add `Score/Nightly.lean` and the `Main.lean` diff as written, make the scratch roots, run checks 1 to 11, then write the build notes and the run log.

### Synthesis decision
The root's judge took Design A (opus, smallest surface) as the base and grafted the strongest safety ideas of Design B (sonnet, adversarial); these are the root's defaults, not owner rulings. A won on interface depth and fit: one module, as the cell names it, so no owner plan edit; a line-set diff with a general theorem instead of a JSON schema and decoder; two modes that print to stdout; and a builder who can start as soon as P2-009a lands, with no list of fixture names to keep in step. From B it took six things. The D1 count covers every repo-level edge the resolver made, not only the card's, because D1 measures the resolver and must not move with Q1; that reverses A's D2 and adds `derivations_keys`. The baseline carries `edge` and `label` lines beside the rates, so a label swap and an edge's status move show by name. The per-type counts are checked against the card's own rows, at build time and for each fixture at run time, so the copy of `render`'s counts fails loudly instead of drifting (A's R3). A fixture that failed this run is "not compared" rather than "removed", a bold line names it, and `--numbers` prints nothing, so a broken run cannot become the next baseline. Missing or unreadable files fail only their own fixture, with fixed messages, instead of aborting the run (A's R6). And B's build-time `#guard` pins and a second maximum theorem (`most_mem`) make the report's sentences and the D1 number checked in CI. B's JSON summary, its floor of required names, its three modules with `selftest.sh`, its Markdown refusal and its distinct-key count were left out for the reasons in A3 to A8. The red-flag screen found the copy of `render`'s rows (leakage, kept and pinned by G5 and `consistent`, with the shared count function as a follow-up), public helpers (made `private`), and B's hand-synced fixture list (dropped). The merged sketch was built and run on `main` at eac85d2, on #332 at 856832b and on P2-001b at 3d939da, and the hashes above were measured on that final text.
