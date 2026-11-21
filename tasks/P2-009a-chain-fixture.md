# tasks/P2-009a-chain-fixture.md

phase: 2
goal: `lake --dir eval/score exe mitos-score eval/fixtures/chain` prints precision and recall for the chain edge type `env/runtime` against hand labels, a repo-level edge is `confirmed` when any of its records is, a chain file is read by the chain reader and by no other reader, and the toy and go.mod scorecards keep their bytes.
statement: none (tooling task). The scorer's own theorems, not locked: `Score.collapse_union`, `Score.factsOf_chain`, `Score.chain_union_end_to_end`, `Score.Chain.reads_cases`, `Score.Chain.facts_line_forms`, `Score.Chain.facts_ai`, `Score.Chain.skips_incomplete_bindings`, `Score.Chain.requires_env`
touches: eval/fixtures/chain/ (new), eval/score/Score/Chain.lean (new), eval/score/Score.lean (one import; one guard line in `factsOf` and `factsOf_chain`; one changed line of `collapse` with `collapse_union` and its two private helpers; the header line of `render`; `chain_union_end_to_end` and its private input at the end), this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, core/, examples/acme/, eval/fixtures/toy/, eval/fixtures/gomod/, eval/score/Main.lean, eval/score/lakefile.toml, eval/score/lake-manifest.json, eval/score/Score/GoMod.lean, eval/diff/, eval/mutants/, .github/, docs/, plan/, .claude/
checks: S1 (P2-001b's contract on `main`), the scorer builds with no new warning (check 1), axioms (check 2), toy scorecard unchanged (check 3), go.mod scorecard unchanged (check 4), the chain scorecard is F2 (check 5), fixture bytes and fact lines (check 6), labels against the labelling rules (check 7, local), changed paths (check 8), the run-log check (check 9), `plan-tasks.test.sh` (check 10), `gate` green in CI (check 11)
budget: 6 iterations · 1h wall · 400k tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- This is plan row P2-009a in `plan/phase-2.md`, core track, wave W5, issue #210.
  It waits for P2-001b (#204), and P2-010 (#212) waits for it. An agent carries and merges it.
  Any builder (Claude, Codex or Grok Bot) can take it: every line of Lean is written below, and
  no proof is left to find. For a Claude builder the role is PR owner, routine, on `sonnet` at
  `high`. No path here is a trust path.
- The row's cells. Owns: `eval/fixtures/chain/` *(new)*, a chain module in `eval/score/Score/`
  *(new)*, and `collapse` and one import in `eval/score/Score.lean`. Reads: the resolver as
  P2-001b leaves it. Also must not touch: `eval/fixtures/toy/`.
- State at design time, 2026-11-15:
  - `main` is at eac85d2. Since c384e70, where the two candidate designs were written, the
    P1-020 task file and its two architect run logs under `ops/runs/2026-11-15/` changed.
  - P2-001b's design is merged (#307), but its build is not. The branch `claude/p2-001b-chains`
    is at 3d939da with no PR, and #204 is open. The branch's base, 2277138, is on `main`. Between
    it and eac85d2 the only change under `core/`, `eval/` and `examples/` is the new `eval/diff/`
    (P2-008, a32a9fc), so `eval/score/` and `eval/fixtures/` are the same bytes on both.
  - The branch follows `tasks/P2-001b-chains.md` except for that file's D2 fallback: the chain
    spec fixtures sit in `Spec/Adequacy.lean`, so the deferral's `Spec.Chains.chain` is
    `Spec.Adequacy.chain` there. The branch also carries the owner's ruling on O1 (#160 item 1):
    a binding from an identity to itself is ruled out, and `boundB` gains
    `&& p.fact.ident != r.fact.ident`
    ([ruling](https://github.com/kitimark/mitos/issues/204#issuecomment-6898646864)). This row
    imports no spec fixture, and its fixture has no self-binding, so neither moves anything here.
- Inputs from other rows:
  - P2-001b's deferral to this row: a chain edge shows as `env/runtime` from `web` to `orders`,
    names no binding repo, and `collapse` merges the records of one requirement and provider.
  - P2-001b's Usage gives the binding fact's shape:
    `.binds { kind := "svc", key := "orders-db" }` with ident `env/DATABASE_URL`.
  - P2-009b's call-site pattern for the next format: a `Score/<Format>.lean` with `reads` and
    `facts`, one import, and one more guard line in `factsOf`. Its deferral also says the go.mod
    guard stays the first line.
- The other `eval/score` work. P2-009b merged (#324). P2-010 owns `Main.lean` and a scorecard
  module. Open PR #332 (for #325) at 856832b changes `score` in `Score.lean` (a label's kind must
  be among the facts), adds four `reads` cases to `Score/GoMod.lean`, and adds a `Policy` library
  with its lakefile entry. Measured at 3d939da in both orders: this design's `Score.lean` diff
  applies on top of #332 with a 10-line offset, and #332's applies on top of this design with a
  22-line offset. Either way the build is clean in 46 jobs, `Policy`'s theorems hold, and F2, F3
  and F4 keep their hashes (F8). #332's label-kind check accepts this fixture's kind `env`.
- Where the plan, the earlier task files and `main` disagree. Each item is the root's default,
  with its reason, and the owner sees them when merging the PR that lands this file.
  - The cell names no call in `factsOf`. No plugin emits `binds`, and no reader on `main` reads a
    chain file, so without a call the fixture scores 0 facts (W3). The design adds one guard
    line, the pattern P2-009b's Usage set for the next format.
  - The plan's Shared files 4 says the `eval/score` rows edit `Score.lean` "only as their cells
    say". Beyond the cell, this design adds the guard line (W3), the header line of `render` (W5),
    and two theorems, `factsOf_chain` and `chain_union_end_to_end`. Until P2-012 runs the chain
    card in CI, those two are the only CI checks on the guard and on the pipeline (W3, W4, W9).
  - "Scorer edge types for chain edges": `Score.edgeType` reads the repo key's identity kind and
    scope, and a bound record copies both from its requirement (`mkBoundEdge` reuses `mkEdge`'s
    four repo-level fields). So `env/runtime` needs no code, and `requires_env` pins the two
    fields it reads. There is no edge type by rule (A2).
  - The plan says the `confirmed` numbers "move from the Phase 1 baseline when P2-009a lands".
    Measured: the toy and go.mod cards keep their bytes (F3, F4). The records of one repo-level
    edge share one requirement and either share one provision fact or are all `inferred`, so their
    statuses differ only through an AI origin, and neither existing fixture has one. The move shows
    on the chain card only (W1).
  - `render` counts every fact that is not a requirement as a provision, so the chain card would
    print 10 provisions for 5 (W5). The design counts provisions and bindings directly, and prints
    bindings only when there are some, so the toy and go.mod headers keep their bytes.
  - P2-001b's deferral says `collapse` merges "a direct and a bound record of one requirement and
    provider". After the O1 ruling, no input has a direct and a bound record that end at one
    provision fact. A direct and a bound record to one provider repo, through two provision
    facts, are both `inferred`, and so is their union (measured on a scratch input, Q3). So this
    fixture's requirement with two derivations has two bound records, one human-declared and one
    AI-proposed, and the union rule is what decides its status.
  - P2-001b's deferral says a chain fixture "can copy `Spec.Chains.chain`". The design copies that
    input's shape as fixture files (`web`, `deploy`, `orders`; `env DATABASE_URL` bound to
    `svc orders-db`). The scorer imports no spec fixture, whose module differs between P2-001b's
    design and its branch.
  - `docs/process.md` (`:190`, `:492`) and `ci.yml` (`:298-299`) name only the toy fixture.
    Neither is this row's (P2-012).
- Landing this file: `.claude/scripts/plan-tasks.pending` lists `P2-009a`, and
  `plan-tasks.test.sh` fails a listed row that has a valid task file. So the PR that lands this
  design deletes that line, and `.claude/` makes that PR the owner's to merge. The build PR stays
  agent-merged. Issue #210 links this file as build depth for the union half, and as contract
  only for the chain half until #204 merges.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build for the union half; contract for the chain half on `main` until P2-001b merges, with
its final text measured against P2-001b's build. Under `types` are all of
`eval/score/Score/Chain.lean` and the whole diff of `eval/score/Score.lean`, as final text with
every proof written in. Both halves were measured in scratch worktrees:
- (a) P2-001b's unmerged branch head 3d939da plus this design. `lake --dir eval/score build` from
  an empty `eval/score/.lake` ends with `Build completed successfully (44 jobs)` and no
  `warning:` line, and F1 to F6 hold.
- (b) The union half alone (the changed `collapse` line, `collapse_union` and its two helpers) on
  `main` at eac85d2. It builds in 42 jobs with no warning, and the toy and go.mod cards keep their
  hashes (F7).

The chain half names `FactKind.binds`, so on `main` it is the contract C1 to C4 until P2-001b
merges.

revisit_when: re-check after P2-001b (#204) merges. Run S1.

Contract with P2-001b. This row needs exactly these four things. All four hold on P2-001b's
branch at 3d939da, and all but C2's O1 conjunct are in `tasks/P2-001b-chains.md` on `main`:
- C1. `Mitos.FactKind.binds (to : Identity)`, deriving `DecidableEq` and `Repr`.
- C2. `Mitos.Impl.resolve` writes one record per `(r, b, p)` with `boundB r b p`: `r` requires,
  `b.fact.ident == r.fact.ident`, `b.fact.kind == .binds p.fact.ident`, `p` provides, and, after
  the O1 ruling, `p.fact.ident != r.fact.ident`. The record's repo-level fields are the
  requirement's repo, the provision's repo, and the requirement's identity and scope. Its
  `assumes` holds the binding's origin. It is `confirmed` only when no origin under it is AI and
  every derivation of the requirement ends at the record's provision fact. F2 and F5 rest on each
  clause.
- C3. `Edge` extends `RepoKey` and keeps `key`, `assumes` and `status`, and any field P2-001b adds
  has a default (`through : List String := []`). So `unionRecord` builds before and after
  P2-001b.
- C4. P2-001b leaves `eval/score/` and `eval/fixtures/` alone (its `must_not_touch`).

modules: one topic per file.
- `eval/score/Score/Chain.lean` *(new)*: how the scorer reads the chain fixture's declaration
  files, meaning which files are chain files and which facts and origin it takes from each. 83
  lines. It copies the layout of `eval/score/Score/GoMod.lean` (imports, one namespace,
  `open Mitos`, the definitions, then the theorems), and its line parser copies the shape of
  `Score.declared`.
- `eval/score/Score.lean`: the dispatch, the repo-level view and the card. 143 → 180 lines.
  Changes: one import; one guard line in `factsOf`, with `factsOf_chain` below the function (7
  lines); one changed line in `collapse`, with `collapse_union` and its two private helpers (14
  lines); two `let`s and one changed line in `render`, plus one new line (4 lines);
  `chain_union_end_to_end` and its private input at the end of the file (12 lines). Nothing else
  changes.
- `eval/fixtures/chain/` *(new)*: `.gitattributes` (`* -text`, the toy's), `labels.tsv` (4 lines),
  and 9 files in 7 repos under `repos/`, 1 to 4 lines each. It copies the layout of
  `eval/fixtures/toy/`.

### How the scorer reads a fixture (`main`, then P2-001b)
1. `loadRepos` (`eval/score/Main.lean:13`) walks `repos/<repo>/` in sorted order and gives each
   file as a `SourceFile` with its repo, its path relative to the repo, and its text. `deploy`'s
   files arrive as `CHAIN`, `CHAIN.ai`, `mail.yaml`, in that order.
2. `factsOf` (`Score.lean:42`) sends go.mod files to `Score.GoMod`. Every other file goes to the
   toy reader, which reads lines starting `require `, and to the `PROVIDES` reader. Neither emits
   `binds`.
3. `ingest` numbers the facts and stops with exit 1 on a span that does not cite its
   `ident.key`. For a binding, that key is the bound key, not its target.
4. After P2-001b, `Mitos.Impl.resolve` writes one record per derivation, direct or bound (C2).
5. `collapse` groups records by `RepoKey`. On `main`, a group is `inferred` if any record in it is.
6. `edgeType k` is `s!"{k.ident.kind}/{scopeName k.scope}"`. A label is five tab-separated fields
   and names no rule and no binding repo.
7. The `Score` library builds `Score` and what it imports, so a new `Score/` module needs no
   lakefile change.
8. CI builds `eval/score` and runs only the toy fixture (`ci.yml:298-299`). Until P2-012, the
   build is what CI checks of this row.

### Usage (caller's view)

```
lake --dir eval/score exe mitos-score eval/fixtures/chain
```

It prints F2 and exits 0. The toy and go.mod runs print what they print on `main`.

The chain format exists for fixtures only, one fact per line:

```
needs DATABASE_URL              requirement  env/DATABASE_URL, scope runtime
binds DATABASE_URL orders-db    binding      of env/DATABASE_URL, to svc/orders-db
serves orders-db                provision    svc/orders-db
```

- A file named `CHAIN` at a repo's root is human-declared, with origin
  `.humanDeclaredOutsideSource "<repo>/CHAIN"`.
- A file named `CHAIN.ai` at a repo's root is AI-proposed, with origin `.ai "<repo>/CHAIN.ai"`.
- A binding line needs a key and a non-blank target. Incomplete binding lines and unrecognized
  lines give no fact.
- The span anchors the first key. For a binding that is the bound key, and the binding's target
  is not anchored (P2-001b, O2).

Call sites:
- `Score.factsOf` reads `if Chain.reads f.path then Chain.facts f.repo f.path f.text else` on its
  second line, after the go.mod guard. A chain file gets the chain reader's facts and nothing
  else (`factsOf_chain`). Every other file keeps its reader.
- `Score.score` calls `collapse` unchanged. The card's header names bindings when there are some.
- P2-010 runs the scorer on each fixture directory. `chain` is one more directory, and it calls
  nothing here.
- The interface is `Score.Chain.reads`, `Score.Chain.facts` and five theorems. `origin`, the three
  verb prefixes, `env`, `svc` and `ofLine` are `private`, and so are the inputs of the theorems in
  `Score.lean`.

### How a builder goes wrong here
- Taking the cell literally, with no call in `factsOf`. `factsOf_chain` and
  `chain_union_end_to_end` fail. With both deleted, the card reads 0 facts and recall 0.00 (0/4)
  (W3).
- Appending `Chain.facts` to the toy's line instead of adding a guard. `factsOf_chain` fails. With
  it deleted the card is byte for byte F2, because the toy reads no `needs` line, so that theorem
  is the only check that sees it (W4). A `CHAIN` file with a `require ` line would also feed the
  toy.
- Putting the chain guard above the go.mod guard. The behaviour is the same, but `hg` in
  `factsOf_chain`'s proof goes unused, and the build prints a linter warning that check 1 looks
  for (W10). Keep go.mod first, as P2-009b's deferral says, so the next format's guard is the
  third line.
- `collapse` as "last record wins" (`then e.status`). `collapse_union` and
  `chain_union_end_to_end` fail (W2).
- Keeping the Phase 1 rule. Both fail, and with both deleted the trust rows read `confirmed` 0 and
  `inferred` 4 (W1).
- An `origin` that is never AI. `facts_ai` fails. With it deleted, `web → mail` reads `confirmed`
  (W6).
- `reads` as `path == "CHAIN"` only. `reads_cases` and `chain_union_end_to_end` fail (W7).
- A binding whose `ident` is its target. `facts_line_forms` and `facts_ai` fail (W8).
- Bindings counted as `c.facts.length - reqs - provs`. It is right today, but a fourth `FactKind`
  would print as bindings. The `matches .binds _` count leaves it out, so the header's parts stop
  adding up and a reader sees it.
- `native_decide`, which adds `Lean.ofReduceBool`. `decide` and `decide +kernel` check all eight
  theorems in the kernel, and the `Score` module builds in a few seconds.
- A `sorry`. The build still succeeds, with a warning that check 1 looks for.
- Labels that follow the scorer: adding `web → billing` because it is predicted, or dropping
  `web → logs` because it is a miss. The labels state what `deploy`'s human-declared bindings
  connect (L1 to L4), and check 7 derives them from the files.
- Leaving the header alone. The card then says 10 provisions (W5).
- An edit to `Main.lean` (P2-010 owns it) or to the lakefile (the import is enough).

types:
- Inputs. From P2-001b, as on 3d939da: `FactKind.binds (to : Identity)` and `Mitos.Impl.resolve`
  (C1 to C4). From `main`: `Mitos.lines`, `Mitos.utf8Len`, and `Score.SourceFile`, `GoMod.reads`,
  `ingest`, `edgeType`, `parseLabels` and `score`, all unchanged.
- `eval/score/Score/Chain.lean`, the file in full:

```lean
import Mitos.Core.Graph
import Mitos.Core.Lines

namespace Score.Chain

open Mitos

def reads (path : String) : Bool := path == "CHAIN" || path == "CHAIN.ai"

private def origin (repo path : String) : Assumption :=
  if path == "CHAIN.ai" then .ai s!"{repo}/{path}"
  else .humanDeclaredOutsideSource s!"{repo}/{path}"

private def needsChars : List Char := "needs ".toList

private def bindsChars : List Char := "binds ".toList

private def servesChars : List Char := "serves ".toList

private def env (key : List Char) : Identity := { kind := "env", key := String.ofList key }

private def svc (key : List Char) : Identity := { kind := "svc", key := String.ofList key }

private def ofLine (o : Nat) (l : List Char) : Option Fact :=
  if needsChars.isPrefixOf l then
    let key := l.drop needsChars.length
    some { kind := .requires, ident := env key,
           span := { start := o + utf8Len needsChars, len := utf8Len key } }
  else if bindsChars.isPrefixOf l then
    let (key, rest) := (l.drop bindsChars.length).span (· != ' ')
    let target := rest.drop 1
    if key.isEmpty || target.all Char.isWhitespace then none
    else
      some { kind := .binds (svc target), ident := env key,
             span := { start := o + utf8Len bindsChars, len := utf8Len key } }
  else if servesChars.isPrefixOf l then
    let key := l.drop servesChars.length
    some { kind := .provides, ident := svc key,
           span := { start := o + utf8Len servesChars, len := utf8Len key } }
  else none

def facts (repo path text : String) : List (Fact × Assumption) :=
  ((lines text.toList).filterMap fun (o, l) => ofLine o l).map (·, origin repo path)

theorem reads_cases :
    ["CHAIN", "CHAIN.ai", "sub/CHAIN", "CHAIN.bak", "PROVIDES"].map reads =
      [true, true, false, false, false] := by decide

theorem facts_line_forms :
    facts "deploy" "CHAIN" "needs A\nbinds A db\nserves db\n# needs B\n" =
      [({ kind := .requires, ident := ⟨"env", "A"⟩, span := ⟨6, 1⟩ },
          .humanDeclaredOutsideSource "deploy/CHAIN"),
        ({ kind := .binds ⟨"svc", "db"⟩, ident := ⟨"env", "A"⟩, span := ⟨14, 1⟩ },
          .humanDeclaredOutsideSource "deploy/CHAIN"),
        ({ kind := .provides, ident := ⟨"svc", "db"⟩, span := ⟨26, 2⟩ },
          .humanDeclaredOutsideSource "deploy/CHAIN")] := by decide

theorem facts_ai :
    facts "deploy" "CHAIN.ai" "binds A db\n" =
      [({ kind := .binds ⟨"svc", "db"⟩, ident := ⟨"env", "A"⟩, span := ⟨6, 1⟩ },
          .ai "deploy/CHAIN.ai")] := by decide

theorem skips_incomplete_bindings :
    facts "deploy" "CHAIN" "binds A\nbinds A \nbinds A  \nbinds  db\n" = [] := by
  decide

theorem requires_env {repo path text : String} {p : Fact × Assumption}
    (h : p ∈ facts repo path text) (hk : p.1.kind = .requires) :
    p.1.ident.kind = "env" ∧ p.1.scope = .runtime := by
  obtain ⟨f, hf, rfl⟩ := List.mem_map.1 h
  obtain ⟨⟨o, l⟩, -, hl⟩ := List.mem_filterMap.1 hf
  simp only [ofLine] at hl
  split at hl
  · cases hl; exact ⟨rfl, rfl⟩
  · split at hl
    · split at hl
      · cases hl
      · cases hl; cases hk
    · split at hl
      · cases hl; cases hk
      · cases hl

end Score.Chain
```

- `eval/score/Score.lean`, the whole diff against eac85d2, which is the same as against 3d939da:

```diff
@@ -1,6 +1,7 @@
 import Mitos.Core
 import Mitos.Impl.Resolve
 import Plugins.ToyRequire
+import Score.Chain
 import Score.GoMod
 
 namespace Score
@@ -41,6 +42,7 @@ def declared (src : String) : List Fact :=
 
 def factsOf (f : SourceFile) : List (Fact × Assumption) :=
   if GoMod.reads f.path then GoMod.facts f.text else
+  if Chain.reads f.path then Chain.facts f.repo f.path f.text else
   let fromPlugin := (ToyRequire.extractor.run f.text).map (·, .extractor "ToyRequire")
   let fromDecl :=
     if f.path == "PROVIDES" then
@@ -48,6 +50,13 @@ def factsOf (f : SourceFile) : List (Fact × Assumption) :=
     else []
   fromPlugin ++ fromDecl
 
+theorem factsOf_chain {f : SourceFile} (h : Chain.reads f.path = true) :
+    factsOf f = Chain.facts f.repo f.path f.text := by
+  have hg : GoMod.reads f.path = false := by
+    simp only [Chain.reads, Bool.or_eq_true, beq_iff_eq] at h
+    rcases h with h | h <;> rw [h] <;> decide
+  simp [factsOf, hg, h]
+
 def ingest (files : List SourceFile) : Except String (List Located) := do
   let mut out : Array Located := #[]
   for f in files do
@@ -80,9 +89,22 @@ def parseLabels (txt : String) : Except String (List RepoKey) := do
 def collapse (es : List Edge) : List (RepoKey × Status) :=
   es.foldl (init := []) fun acc e =>
     if acc.any (·.1 == e.repoKey) then
-      acc.map fun (k, s) => (k, if k == e.repoKey && e.status == .inferred then .inferred else s)
+      acc.map fun (k, s) => (k, if k == e.repoKey && e.status == .confirmed then .confirmed else s)
     else acc ++ [(e.repoKey, e.status)]
 
+private def unionKey (dst : String) : RepoKey :=
+  { requiringRepo := "web", providingRepo := dst, ident := { kind := "env", key := "K" },
+    scope := .runtime }
+
+private def unionRecord (dst : String) (s : Status) : Edge :=
+  { unionKey dst with key := .direct 0 0, assumes := [], status := s }
+
+theorem collapse_union :
+    collapse [unionRecord "a" .inferred, unionRecord "a" .confirmed, unionRecord "b" .confirmed,
+        unionRecord "b" .inferred, unionRecord "c" .inferred, unionRecord "c" .inferred] =
+      [(unionKey "a", .confirmed), (unionKey "b", .confirmed), (unionKey "c", .inferred)] := by
+  decide
+
 def ratio (n d : Nat) : String :=
   if d = 0 then "n/a" else
     let x := (n * 100 + d / 2) / d
@@ -105,8 +127,11 @@ def Scorecard.render (c : Scorecard) (name : String) : String := Id.run do
   let pred := c.predicted.map (·.1)
   let types := (pred ++ c.labels).map edgeType |>.eraseDups
   let reqs := c.facts.filter (·.fact.kind == .requires) |>.length
+  let provs := c.facts.filter (·.fact.kind == .provides) |>.length
+  let binds := c.facts.filter (·.fact.kind matches .binds _) |>.length
   let mut out := s!"### Scorecard: fixture `{name}`\n\n"
-  out := out ++ s!"{c.facts.length} facts ({reqs} requirements, {c.facts.length - reqs} provisions), "
+  out := out ++ s!"{c.facts.length} facts ({reqs} requirements, {provs} provisions"
+  out := out ++ (if binds = 0 then "), " else s!", {binds} bindings), ")
   out := out ++ s!"{pred.length} repo-level edges predicted, {c.labels.length} hand-labelled, "
   out := out ++ s!"{c.unresolved.length} requirements unresolved.\n\n"
   out := out ++ "| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n"
@@ -140,4 +165,16 @@ def Scorecard.render (c : Scorecard) (name : String) : String := Id.run do
       out := out ++ s!"`{repr l.fact.ident.key}`\n"
   return out
 
+private def chainUnionFiles : List SourceFile :=
+  [{ repo := "deploy", path := "CHAIN", text := "binds A db\n" },
+   { repo := "deploy", path := "CHAIN.ai", text := "binds A db\n" },
+   { repo := "orders", path := "CHAIN", text := "serves db\n" },
+   { repo := "web", path := "CHAIN", text := "needs A\n" }]
+
+theorem chain_union_end_to_end :
+    (score chainUnionFiles []).toOption.map (fun c => (c.facts.length, c.predicted)) =
+      some (4, [({ requiringRepo := "web", providingRepo := "orders", ident := ⟨"env", "A"⟩,
+                   scope := .runtime }, .confirmed)]) := by
+  decide +kernel
+
 end Score
```

- Inside `namespace Score`, `Chain.reads` is `Score.Chain.reads`. `reads` takes the path as
  `loadRepos` builds it, relative to the repo, so only a file at the repo's root is a chain file,
  as with `PROVIDES`.
- The union rule is one token pair in `collapse`. The fold's insert, its first-seen order and its
  key test keep their text.
- `unionRecord` uses `.direct` keys, so `collapse_union` builds on `main` before P2-001b (F7):
  `collapse` reads only `repoKey` and `status`.
- `chain_union_end_to_end` runs the real `score` (the dispatch, the reader, `ingest`,
  `Mitos.Impl.resolve` and `collapse`) on four one-line files. `decide +kernel` leaves the whole
  evaluation to the kernel and adds no axiom (check 2). It sits at the end of the file, so #332's
  hunk in `score` keeps its context (F8).

statements:
- `Score.collapse_union`: a repo-level edge is `confirmed` when any of its records is, in either
  order (`a`, `b`), and stays `inferred` when none is (`c`). Keys stay apart, in first-seen order.
  It fails for the Phase 1 rule (W1) and for "last record wins" (W2), both measured. By reading,
  it also fails for "first record wins" (`a`) and for "always confirmed" (`c`). No axioms.
- `Score.factsOf_chain : Chain.reads f.path = true → factsOf f = Chain.facts f.repo f.path
  f.text`. A chain file gets the chain reader's facts, in its order, and no other reader's. It
  fails with no guard (W3) and with an append to the toy's line (W4).
- `Score.chain_union_end_to_end`: on a human-declared and an AI-proposed binding of one
  requirement to one provision, `score` reads 4 facts and predicts one repo-level edge, `web` →
  `orders` with `env` and `runtime`, and it is `confirmed`. It is the one CI check, before
  P2-012, that runs the union rule on bound records, the chain edge type, and a `score` that keeps
  its bound records (W9).
- `Score.Chain.reads_cases`: the chain files are `CHAIN` and `CHAIN.ai` at a repo's root. A nested
  `CHAIN`, a longer name and `PROVIDES` are not chain files. No axioms.
- `Score.Chain.facts_line_forms`: the three verbs, the kinds `env` and `svc`, the binding's target,
  the byte spans, an ignored line, and the declared origin.
- `Score.Chain.facts_ai`: a `CHAIN.ai` line carries `.ai "<repo>/CHAIN.ai"`, the origin the union
  rule needs to show at all.
- `Score.Chain.skips_incomplete_bindings`: a missing key or missing or blank target yields no fact.
- `Score.Chain.requires_env`: every requirement the chain reader gives has kind `env` and scope
  `.runtime`. A chain record's repo key takes both from its requirement (C2), so every chain
  repo-level edge has edge type `env/runtime`. This is the row's "scorer edge type for chain
  edges".
- Each depends on a subset of `[propext, Classical.choice, Quot.sound]` (check 2).
- Not a theorem: the card's numbers. F2 holds them, and CI does not run the chain card until
  P2-012.

reuse:
- `Mitos.lines` and `Mitos.utf8Len`.
- `Score.declared`'s per-line prefix shape, and `Score.GoMod`'s interface (`reads`, `facts`), its
  guard-line call site and its `reads` (in `factsOf_chain`).
- `Score.ingest`, `edgeType`, `parseLabels` and `score` unchanged, and `render` with one count
  line.
- `loadRepos` and `Main.lean` unchanged.
- The layout and `.gitattributes` of `eval/fixtures/toy/`.
- From P2-001b: `FactKind.binds` and `Impl.resolve`, with its Usage example as the fixture's first
  chain.
- `List.mem_map` and `List.mem_filterMap`.

fixtures:
- F1, the fixture. Each case is there for one property. One false positive and one miss are on
  purpose, so the card can show that the scorer measures something.

| Repo | File | What it holds | Exercises |
|---|---|---|---|
| web | `CHAIN` | `needs DATABASE_URL`, `needs QUEUE_URL`, `needs SMTP_HOST`, `needs LOG_SINK` | four `env` requirements; byte offsets on the fourth |
| deploy | `CHAIN` | `binds DATABASE_URL orders-db`, `binds QUEUE_URL jobs-queue` | human-declared bindings |
| deploy | `CHAIN.ai` | `binds DATABASE_URL orders-db`, `binds QUEUE_URL billing-queue`, `binds SMTP_HOST mail-relay` | AI proposals: one agrees with `deploy/CHAIN`, one disagrees, one agrees with `mail.yaml` |
| deploy | `mail.yaml` | `SMTP_HOST: mail-relay`, `LOG_SINK: log-store` | real bindings in a format no reader reads |
| orders | `CHAIN` | `serves orders-db` | the provider of two derivations |
| jobs | `CHAIN` | `serves jobs-queue` | the declared provider of `QUEUE_URL` |
| billing | `CHAIN` | `serves billing-queue` | the AI's wrong provider |
| mail | `CHAIN` | `serves mail-relay` | a provider the scorer reaches only through an AI binding |
| logs | `CHAIN` | `serves log-store` | the provider behind a binding no reader sees |

  Labelling rules. A reader of the repos writes the labels; the scorer's output never does.
  - L1. One label per requirement that a human-declared binding in `deploy` connects to a service
    a repo serves. The fields are the repo that `needs` the key, the repo that `serves` the bound
    service, `env`, the key and `runtime`.
  - L2. A human-declared binding counts in any file of `deploy`, whether a reader reads that file
    or not (`CHAIN` and `mail.yaml`).
  - L3. An AI-proposed binding (`CHAIN.ai`) is never the evidence for a label. One that agrees
    with a human-declared binding adds a derivation to a labelled edge, or is the only derivation
    the scorer sees. One that agrees with none is a false positive.
  - L4. Two derivations of one requirement to one provider give one label (the union view).

  Each edge, its source and its place in F2:

| Edge | Source | Labelled | In F2 |
|---|---|---|---|
| `web` → `orders`, `DATABASE_URL` | `deploy/CHAIN` line 1 and `deploy/CHAIN.ai` line 1 | yes, one label (L1, L4) | true positive, `confirmed`: the declared record is `confirmed`, the AI one is `inferred`, and the union takes `confirmed` (2 records, F5) |
| `web` → `jobs`, `QUEUE_URL` | `deploy/CHAIN` line 2 | yes (L1) | true positive, `inferred`: the AI's competing binding ends at another provider, so not every derivation of `QUEUE_URL` ends at one provision |
| `web` → `billing`, `QUEUE_URL` | `deploy/CHAIN.ai` line 2 | no (L3) | false positive, `inferred` |
| `web` → `mail`, `SMTP_HOST` | label: `deploy/mail.yaml` line 1; prediction: `deploy/CHAIN.ai` line 3 | yes (L2, L3) | true positive, `inferred`: its only derivation the scorer sees is AI-proposed, the card's case for the AI clause (W6) |
| `web` → `logs`, `LOG_SINK` | `deploy/mail.yaml` line 2 | yes (L2) | a miss: no reader reads YAML, and `LOG_SINK` is unresolved at bytes 57+8 |

  The fixture, byte for byte, from the repository root:

```
d=eval/fixtures/chain
mkdir -p $d/repos/billing $d/repos/deploy $d/repos/jobs $d/repos/logs $d/repos/mail $d/repos/orders $d/repos/web
printf '* -text\n' > $d/.gitattributes
printf 'web\torders\tenv\tDATABASE_URL\truntime\nweb\tjobs\tenv\tQUEUE_URL\truntime\nweb\tmail\tenv\tSMTP_HOST\truntime\nweb\tlogs\tenv\tLOG_SINK\truntime\n' > $d/labels.tsv
printf 'serves billing-queue\n' > $d/repos/billing/CHAIN
printf 'binds DATABASE_URL orders-db\nbinds QUEUE_URL jobs-queue\n' > $d/repos/deploy/CHAIN
printf 'binds DATABASE_URL orders-db\nbinds QUEUE_URL billing-queue\nbinds SMTP_HOST mail-relay\n' > $d/repos/deploy/CHAIN.ai
printf 'SMTP_HOST: mail-relay\nLOG_SINK: log-store\n' > $d/repos/deploy/mail.yaml
printf 'serves jobs-queue\n' > $d/repos/jobs/CHAIN
printf 'serves log-store\n' > $d/repos/logs/CHAIN
printf 'serves mail-relay\n' > $d/repos/mail/CHAIN
printf 'serves orders-db\n' > $d/repos/orders/CHAIN
printf 'needs DATABASE_URL\nneeds QUEUE_URL\nneeds SMTP_HOST\nneeds LOG_SINK\n' > $d/repos/web/CHAIN
```

  `cd eval/fixtures/chain && find . -type f | LC_ALL=C sort | xargs sha256sum` then prints:

```
705fd4d6451a31d36b3df7de96f83f30ac976c9b4a6d1e51671d8e2f33e2d0da  ./.gitattributes
e2fe5e33766f15e22cdbc4a5ed9e04fe412f793ad0057d6463ca519161d614a7  ./labels.tsv
110285587c998057363a10ab8a3cc74b0e87faf85db956fd6ccf39fac67647a6  ./repos/billing/CHAIN
5170d61f6581ffdf346db72a27e1765146382541f5ee5e663ce25d234027a596  ./repos/deploy/CHAIN
ce6395b1c4f2902c2cf3d68706fce2c5e9ca7e81a1fa5d8d160b4d5691738ceb  ./repos/deploy/CHAIN.ai
95c521178553e1c3f733433671b65271cd7616b15af5f1cc6dcc9f98435724ac  ./repos/deploy/mail.yaml
166817a787971c91f1857fac1cfa11bd200185320bcfcda7172735f0e6901550  ./repos/jobs/CHAIN
a1c6127d5001246b3d0cf2221d4ba8f34e6d4b6fd9515af1013ff0e7b854c2cb  ./repos/logs/CHAIN
bcadafb620aad83857e0fcfd9274ca7920a0a8fd0f6b10b18256ace961a3ad07  ./repos/mail/CHAIN
bc9b12be528d61700c9c4e5e9b063cbf241383b2fa6d8824e99ee845721b16d4  ./repos/orders/CHAIN
227d02c06026d9d8de78f8e2c31c23bcd4f6db02ebabc345e2b7142995355b5f  ./repos/web/CHAIN
```

- F2, the chain scorecard. `lake --dir eval/score exe mitos-score eval/fixtures/chain` prints
  exactly this and exits 0. The output is 769 bytes, with sha256
  `bfb0175368f5f5f1f77eae4da9bc0f5a83e6c08935d7806071557add1116e1c6`.

```
### Scorecard: fixture `chain`

14 facts (4 requirements, 5 provisions, 5 bindings), 4 repo-level edges predicted, 4 hand-labelled, 1 requirements unresolved.

| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |
|---|---|---|---|---|---|---|---|
| env/runtime | 4 | 4 | 3 | 1 | 1 | 0.75 (3/4) | 0.75 (3/4) |

| Edge type | Trust level | Predicted | TP | FP | Precision |
|---|---|---|---|---|---|
| env/runtime | confirmed | 1 | 1 | 0 | 1.00 (1/1) |
| env/runtime | inferred | 3 | 2 | 1 | 0.67 (2/3) |

False positives (predicted, not labelled):
- `web` → `billing` (env/runtime `QUEUE_URL`), inferred

Misses (labelled, not predicted):
- `web` → `logs` (env/runtime `LOG_SINK`)

Unresolved requirements:
- `web/CHAIN` bytes 57+8: `"LOG_SINK"`
```

  The 14 facts are the 14 lines of the `CHAIN` and `CHAIN.ai` files; `mail.yaml` gives none. The
  only edge type is `env/runtime`. No `toy/` row appears, which is what the guard is for.
- F3, the toy scorecard is unchanged. `mitos-score eval/fixtures/toy` prints sha256
  `17c55e9cfa3a9db873c50c980cf2cbea62195fe2eebecde3edc0a13add38f21a` before and after: the same
  bytes on `main`, on 3d939da, with this design on 3d939da, and with its union half on `main`.
  Every toy repo-level edge has one record, and the toy has no binding, so its header keeps its
  text.
- F4, the go.mod scorecard is unchanged: sha256
  `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf`, before and after. Its
  two-record edge `mono → lib` has one status (P2-009b, F6).
- F5, the records, printed by a scratch file that copies `loadRepos` from `Main.lean` and runs
  `Mitos.Impl.resolve (ingest files)` at 3d939da. There are 5 records over 4 repo-level edges,
  each with `through = ["deploy"]`: `(.bound 10 1 9, "orders", confirmed)`,
  `(.bound 10 3 9, "orders", inferred)`, `(.bound 11 2 6, "jobs", inferred)`,
  `(.bound 11 4 0, "billing", inferred)` and `(.bound 12 5 8, "mail", inferred)`.
  `unresolved = [13]`. So `web → orders` has 2 records and the others have 1. P2-010's "most
  derivations any repo-level edge has" reads 2 here; D1's threshold is 8.
- F6, wrong variants, each built and run on 3d939da from this file's text. They show what each
  check can see.

| Variant | What fails | What F2 shows |
|---|---|---|
| W1, `collapse` keeps the Phase 1 rule | `collapse_union`, `chain_union_end_to_end` | with both deleted: `confirmed` 0, `inferred` 4 (3 TP, 1 FP), 0.75 (3/4) |
| W2, `collapse` as last record wins | `collapse_union`, `chain_union_end_to_end` | not reached |
| W3, no guard line in `factsOf` | `factsOf_chain`, `chain_union_end_to_end` | with both deleted: `0 facts (0 requirements, 0 provisions), 0 repo-level edges predicted, 4 hand-labelled`, recall 0.00 (0/4) |
| W4, `Chain.facts` appended to the toy's line | `factsOf_chain` | with it deleted: byte for byte F2 (`bfb01753…`) |
| W5, `render` left as on `main` | nothing in the build | `14 facts (4 requirements, 10 provisions)`, the rest unchanged |
| W6, `origin` never AI | `facts_ai` | with it deleted: `confirmed` 2 (2/2), `inferred` 2 (1/2); `web → mail` reads `confirmed` |
| W7, `reads` is `path == "CHAIN"` only | `reads_cases`, `chain_union_end_to_end` | with both deleted (and `factsOf_chain`'s first proof line adapted): `11 facts (4 requirements, 5 provisions, 2 bindings)`, 2 predicted, precision 1.00 (2/2), recall 0.50 (2/4), `confirmed` 2, no false positive |
| W8, a binding's `ident` is its target | `facts_line_forms`, `facts_ai` | not reached |
| W9, `score` keeps only records with no `through` | `chain_union_end_to_end` | not reached |
| W10, the chain guard above the go.mod guard | a linter warning on `hg` in `factsOf_chain` (check 1) | byte for byte F2 |

- F7, the union half alone on `main` at eac85d2: the changed `collapse` line, `collapse_union` and
  its two helpers. `lake --dir eval/score build` ends with `Build completed successfully (42
  jobs)` and no warning, and F3 and F4 hold. So the union rule does not wait on P2-001b. Only the
  chain half does.
- F8, with #332 at 856832b, at 3d939da, in both orders (Context). The build is clean in 46 jobs,
  `Policy`'s theorems hold, and F2, F3 and F4 keep their hashes.

### Checks, in order

From the repository root, at the head after the last rebase.

1. Set `base_log` to the saved scorer build log from a checkout of `origin/main`. Save the
   feature build output, check its exit status and success line, and compare diagnostics:

   ```bash
   log=$(mktemp)
   test -r "$base_log" &&
     lake --dir eval/score build >"$log" 2>&1 &&
     grep -F 'Build completed successfully' "$log" &&
     diff -u <(grep -E '^(warning|error):' "$base_log") <(grep -E '^(warning|error):' "$log")
   ```

   The merged P2-001b baseline emits the `Mitos/Core/Graph.lean` warning about importing a
   Mathlib module from a file that does not use the module system. The diagnostics diff is empty.
2. A scratch file `Axioms.lean`, never committed, holds `import Score` and then a `#print axioms`
   line for each of `Score.collapse_union`, `Score.factsOf_chain`, `Score.chain_union_end_to_end`,
   `Score.Chain.reads_cases`, `Score.Chain.facts_line_forms`, `Score.Chain.facts_ai`,
   `Score.Chain.skips_incomplete_bindings` and `Score.Chain.requires_env`.
   `cd eval/score && lake env lean <scratch>/Axioms.lean` prints the following, measured:
   - `collapse_union` and `reads_cases`: no axioms.
   - the other six: `[propext, Classical.choice, Quot.sound]`.

   None names `Lean.ofReduceBool` or `sorryAx`.
3. `lake --dir eval/score exe mitos-score eval/fixtures/toy | sha256sum` prints F3's hash, before
   the first edit and at the head.
4. The same for `eval/fixtures/gomod`, which prints F4's hash. If `origin/main` moved either
   fixture or the scorer since eac85d2, compare with a detached worktree of `origin/main`
   instead.
5. `lake --dir eval/score exe mitos-score eval/fixtures/chain | sha256sum` prints F2's hash. If it
   differs, `diff` the output with F2 and read S3.
6. `cd eval/fixtures/chain && find . -type f | LC_ALL=C sort | xargs sha256sum` prints F1's eleven
   lines, and `git ls-files --eol eval/fixtures/chain` shows `i/lf` and `attr/-text` on all
   eleven files (measured). `cat $(find eval/fixtures/chain/repos -name CHAIN -o -name CHAIN.ai) |
   grep -c .` prints 14, the card's fact count, so no line of a chain file is silently not a fact.
7. The labels against L1 to L4, a local check on the hand labels, not their source. From the
   repository root, `bash <scratch>/derive-labels.sh` prints `labels match L1 to L4` and nothing
   else (measured):

```
d=eval/fixtures/chain/repos
{ awk '$1 == "binds" { print $2 "\t" $3 }' $d/deploy/CHAIN
  awk -F': ' 'NF == 2 { print $1 "\t" $2 }' $d/deploy/mail.yaml; } |
while IFS=$'\t' read -r key svc; do
  for req in $d/*/CHAIN; do
    grep -qx "needs $key" "$req" || continue
    for prov in $d/*/CHAIN; do
      grep -qx "serves $svc" "$prov" || continue
      printf '%s\t%s\tenv\t%s\truntime\n' "$(basename "$(dirname "$req")")" "$(basename "$(dirname "$prov")")" "$key"
    done
  done
done | LC_ALL=C sort -u | diff - <(LC_ALL=C sort eval/fixtures/chain/labels.tsv) && echo "labels match L1 to L4"
```

   It reads the human-declared bindings only (L2, L3) and merges duplicates (L4). It shares no code
   with the scorer.
8. `git diff --name-only origin/main...HEAD` prints only the eleven files of F1,
   `eval/score/Score.lean`, `eval/score/Score/Chain.lean`, `tasks/P2-009a-chain-fixture.md`, and
   files under `ops/runs/`.
9. `lake exe mitos-gate runlog --head ops/runs` passes. Also,
   `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
   shows only `A` lines.
10. `.claude/scripts/plan-tasks.test.sh` passes once `P2-009a` has left
    `.claude/scripts/plan-tasks.pending`, which the PR that lands this file does.
11. In CI, the `checks` job and the PR's `gate` are green. `checks` builds `eval/score`, so the
    kernel checks the eight theorems, and it runs the toy scorecard, which must read as on `main`.

### Risks and stop conditions

Risks:
- R1. At design time, P2-001b could still change before merging. C1 to C4 name what this row reads.
  S1 checks that the dependency landed, that the binding constructor exists, and that scorer and
  fixture changes stay within the expected diff. The build checks C3 through `unionRecord`.
  Check 5 exercises C2's effect on the scorecard, and F5 records the resolver output. Inspect the
  resolver's assumption construction for C2's `assumes` clause, which the card does not print.
- R2. #332 may merge first. Measured: there is no conflict and no card moves (F8).
- R3. CI never runs the chain card until P2-012, so a later PR can move F2 unnoticed. CI runs the
  eight theorems through the build, and `chain_union_end_to_end` is the one that runs the whole
  pipeline.
- R4. The toy reader still reads every file that is not a go.mod or chain file, including
  `deploy/mail.yaml`. That file has no `require ` line, so it gives no fact. A YAML file with such
  a line would give a toy requirement (P2-009b, R4).
- R5. A reader for YAML or for real deployments, in a later phase, moves F2: `LOG_SINK` becomes a
  hit, and `web → mail` gains a declared record and turns `confirmed`. The labels stay. That is
  the card doing its job.
- R6. `reads` sees a repo's root only. A nested `CHAIN` is not read (`reads_cases`).
- R7. What this row cannot see, by reading: the card, the labels and `chain_union_end_to_end` hold
  repo-level keys and statuses only. A resolver that writes `through := []` on a bound record, or
  swaps the binding and provision ids in its key, leaves all three the same. P2-001b's `Sound`
  (its `c.through = e.through` conjunct) and P2-005b's chain mutants own those. This row does not
  claim them.

Stop conditions for the builder:
- S1. Before writing, after `git fetch origin main`:
  - `gh api repos/kitimark/mitos/issues/204 --jq .state` prints `closed`, and a merged PR closed
    it.
  - `git grep -n 'binds (to : Identity)' origin/main -- core/Mitos/Core/Fact.lean` prints one
    line.

  If either fails, stop: this design is amended first. Then run
  `git diff --stat eac85d2 origin/main -- eval/score eval/fixtures`. If it prints `Score.lean` or
  the files #332 adds or changes, apply this design's hunks to the new text; F2 to F4 must still
  hold. If it prints any other file, stop and report. If check 5 then differs, compare F5's
  records with C2 and report.
- S2. A check fails and the fix is outside `touches`: stop and report.
- S3. Check 5 differs. Never edit `labels.tsv` to match the scorer. Find which side is wrong: the
  labels by L1 to L4 and check 7, the reader by F6, the resolver by C2 and F5. A wrong resolver is
  a stop, because it is P2-001b's spec.
- S4. A theorem here does not build as written: report it. Never weaken its statement or switch
  it to `native_decide`; the verifier compares each statement with this file's text, and check 2
  lists the axioms.
- S5. The builder stops when the PR is open on `main`, `gate` is green, checks 1 to 10 pass at the
  head and every thread is answered, and reports that head as merge-ready. No path here is the
  owner's, so an agent merges it.

cut_line: this row ships:
- the fixture;
- `Score/Chain.lean` with its five theorems;
- the changes to `Score.lean`: `collapse` and `collapse_union`; the import, the guard and
  `factsOf_chain`; the header; `chain_union_end_to_end`;
- the build notes, which the builder adds to this file, and the run log.

It leaves to other rows or issues:
- the CI and nightly runs of the chain card, to P2-012;
- the scorecard over every fixture and the derivation count, to P2-010;
- a binding reader for a real format, to a later phase;
- Q1 and Q2, to the PR's follow-up issue, and Q3, to the owner through the root.

If the budget bites, the two halves land apart in this order: the union half first (F7, no
P2-001b needed), then the reader and the fixture. Within the chain half, `chain_union_end_to_end`
is cut first, because every case it catches today another check also catches. Never cut
`collapse_union`, `factsOf_chain`, `facts_ai` or `requires_env`, because each is the only CI check
on its clause.

deferrals:
- To P2-010 (#212): `chain` is one of "every fixture". Its most derivations per repo-level edge is
  2 (F5), and F2 is `main`'s chain card, the baseline of its diff. If P2-010 moves `score` or
  `render` into its scorecard module, `chain_union_end_to_end` and the header's bindings count
  move with them and keep building.
- To P2-012 (#213): run `mitos-score eval/fixtures/chain` beside the toy in `ci.yml`'s scorecard
  step (`:298-299`) and in the nightly post. `docs/process.md` names only the toy fixture
  (`:190`, `:492`); that wording is the owner's and moves with P2-012. Until then, checks 3 to 7
  are the builder's and the verifier's, and the PR body carries F2.
- To P2-005b (#206): nothing from this row's code. `collapse` is scorer code outside
  `eval/mutants/`, and `collapse_union` is its check. R7's blind spots are its chain mutants' to
  catch, with P2-001b's theorems.
- From P2-001b (#204): its deferral is followed. A chain edge shows as `env/runtime` from `web` to
  `orders` and does not name `deploy`, and the records of one requirement and provider are merged
  (2 on `web → orders`). Its chain spec fixture's shape is copied as files, not imported. Its
  "direct and bound record" case goes back to the owner as Q3, through the root.
- From P2-009b (#211): its deferral is followed. The chain guard is the second line, and the go.mod
  guard stays first. Its R2 import conflict is moot because P2-009b merged first.
- To the PR's follow-up issue, no row (all minor):
  - a binding's target is not anchored, so a typo in it gives an unresolved requirement and not an
    `ingest` error (P2-001b's follow-up, seen from the scorer);
  - the toy reader still reads every unguarded file (R4);
  - Q1 and Q2.

owner_decisions:
- Settled by the plan:
  - the union view's status rule (a repo-level edge is `confirmed` if any of its derivations is);
  - chain facts are synthetic and rest on declaration assumptions;
  - the fixture is `eval/fixtures/chain/` with a chain module under `eval/score/Score/`;
  - an agent merges this row.
- Settled by the owner since: O1, a self-binding is ruled out (#204). The fixture has none.
- This design's defaults, chosen by the root's judge with their reasons, not owner rulings:
  - D1. One fixture format, `CHAIN` and `CHAIN.ai`, read by `Score.Chain` alone through one guard
    line in `factsOf`. Reason: no extractor emits `binds`, and W3. This is where the plan and this
    design part: the cell names no call.
  - D2. The origin is set per file: `CHAIN` is human-declared and `CHAIN.ai` is AI-proposed.
    Reason: the union view changes a status only through an AI origin, and without one no card
    shows the rule. The origin is per file, as `PROVIDES`'s is.
  - D3. Fixed kinds: `needs` gives `env` and `serves` gives `svc`, so the chain edge type is
    `env/runtime`. Reason: a grammar with kinds and scopes would test the resolver's scope rules,
    which are P2-001b's (A7).
  - D4. Labels follow human-declared bindings only (L3), including ones in a file no reader reads
    (L2). Reason: the labels then never follow the tool's own input.
  - D5. The header counts provisions and bindings directly and names bindings only when there are
    some. Reason: a correct header on the new card, with the toy and go.mod bytes unchanged.
  - D6. The union rule is pinned by a `decide` case beside `collapse` in `Score.lean`, not by a
    general statement in a module of its own. Reason: the row changes one token pair, and the case
    fails every wrong rule measured (A5).
  - D7. Two theorems in `Score.lean` beyond the cell, `factsOf_chain` and
    `chain_union_end_to_end`. Reason: W3, W4 and W9 are invisible to CI otherwise until P2-012.
  - D8. The fixture has an AI-only edge (`web → mail`) and a second miss (`web → logs`). Reason:
    the card then shows the AI clause (W6), at the cost of one repo and five lines.
  - D9. No CI change; `.github/` is P2-012's.
- No call needs the owner before the build. Q3 is a plan question and moves none of this row's
  code.

## Done when
- [x] S1 passes, or this file is amended first
- [x] `mitos-score eval/fixtures/chain` prints F2 at the head (check 5)
- [x] the toy and go.mod scorecards are unchanged (checks 3 and 4)
- [x] the labels agree with L1 to L4, and the fact count is the line count (checks 6 and 7)
- [ ] all `checks` pass locally, and `gate` is green
- [x] incomplete binding lines give no facts
- [x] no `sorry`, no new axioms (checks 1 and 2)
- [x] run-log record written (ops/runs/)

## Build notes

P2-001b merged in #545 at `1770a97`. The scorer and fixture diff from `eac85d2`
contains the expected #332 files. The merged core exports `Assumption` from
`Mitos.Core.Graph`, so the chain reader imports that module and `Mitos.Core.Lines` directly.

The scorer build succeeds with the same `Mitos/Core/Graph.lean` warning as the base.
All eight scorer theorems use only the axioms listed in check 2. The 11 fixture file hashes
and all three scorecard hashes match F1 to F4. The fixture has 14 fact lines. Independently
deriving the labels from the human declarations matches `labels.tsv`.

The resolver yields the five records in F5 and includes each binding's origin in that record's
`assumes`. The two records for `web → orders` have one confirmed and one inferred status.
The collapsed edge is confirmed.

The local environment cannot start Bubblewrap for the sandboxed core checks. The hosted
`checks` job runs those commands.

## Rationale

### Problem
The nightly scorecard needs a chain edge type and the union view's status rule (exit criterion 5).
Five things on `main` and in P2-001b shape this row:
- No extractor emits `binds`, so the fixture's bindings need a reader of their own, and a reader
  needs a call in `factsOf`, which the cell does not name.
- The edge type comes from the requirement's kind and scope. A bound record copies them, so a
  chain edge type needs requirements of their own kind, not code in `edgeType`.
- The records of one repo-level edge differ in status only through an AI origin. So the union
  rule is invisible on every existing card, and a fixture shows it only with an AI-proposed fact.
- After the O1 ruling, a requirement's two derivations to one provision are two bound records,
  never a direct and a bound one.
- CI builds the scorer but runs only the toy card, so what CI can hold for this row before P2-012
  is the build.

### Shape
`Score.Chain` owns the chain fixture format: which files are chain files (`reads`), and which
facts and origin a file gives (`facts`). `Score.lean` keeps the dispatch (`factsOf`), the
repo-level view (`collapse`) and the card (`render`). The union rule is one token pair in
`collapse`, and `collapse_union` holds it in the kernel from both orders and both outcomes.
`factsOf_chain` holds the dispatch for every chain file. `chain_union_end_to_end` runs the whole
pipeline on one two-derivation chain. The chain edge type falls out of `edgeType`, and
`requires_env` pins the two fields it reads; `facts_ai` holds the origin the rule needs. The
fixture puts each status case next to a labelling case: two derivations to one provider (union),
competing derivations (`inferred`), an AI-only derivation of a real edge (`inferred`, the AI
clause), an AI-only wrong edge (a false positive), and a binding no reader sees (a miss).

Interface depth: two public names and five theorems in the new module, plus three theorems in
`Score.lean`. They hide the file names, the verbs, the fixed kinds, the origins and the dispatch's
one decision. The module is small on purpose, because the fixture is data.

### Tradeoffs accepted
- We accept a guard line, a header line and two theorems outside the cell in exchange for a
  fixture that scores at all (W3), a header that is right (W5), and CI checks on the guard and the
  pipeline before P2-012 (W3, W4, W9).
- We accept 14 lines in `Score.lean` for a theorem about `collapse` in exchange for the union rule
  held where CI looks.
- We accept a `decide` case for the union rule, not a statement for every list, in exchange for
  one token pair of change and no fold-induction proofs to carry across toolchain bumps.
- We accept a fixture format of its own (three verbs, fixed kinds) instead of reusing the toy and
  `PROVIDES` readers, in exchange for a chain edge type of its own.
- We accept one more repo and five more fixture lines in exchange for a card that sees a lost AI
  origin (W6).
- We accept `"env"` spelled in the reader, in `requires_env`, in `chain_union_end_to_end` and in
  `labels.tsv`. A mismatch fails the build or shows up as misses.
- We accept two `decide` examples and one general theorem for the parser, instead of an `↔` that
  restates `ofLine`.
- We accept a chain card that CI does not run until P2-012, in exchange for staying out of
  `.github/`.

### Alternatives considered
- A1. Reuse the toy reader for requirements and `PROVIDES` for services, and add only a `bind`
  reader. Chain edges would then score as `toy/runtime`, the toy fixture's type, so there would be
  no chain edge type, and one fixture's facts would come from three readers.
- A2. An edge type by rule (`env/runtime` against a bound variant). It needs a rule in `RepoKey`
  or in the labels, and the union view merges records under one key, so a repo-level edge has no
  single rule.
- A3. A `join` on statuses in `Score/Chain.lean` that `collapse` calls, with the theorems on
  `join`. A `collapse` that stopped calling it would still pass.
- A4. Move `collapse` into the chain module, where its theorems could live. The union view is for
  every fixture, so the file would hold two topics, and P2-010 would read it as chain-specific.
- A5. A module of its own for the union view (`Score/Union.lean`, about 250 lines), with
  `collapse` split into a named step and general statements (`collapse_confirmed`,
  `collapse_inferred`, `collapse_nodup`) proved by fold induction. Its reason, that a theorem about
  `collapse` must sit in a module `Score` imports, does not hold: `collapse_union` sits in
  `Score.lean`, which CI builds. It moves `collapse` out of the file the cell names, and its
  `simp`-heavy proofs would be the longest proof text in `eval/score` to carry across P2-011's
  toolchain bump, for a rule the `decide` case already holds against every wrong rule measured.
- A6. A per-line AI origin, with an `ai` prefix or a `proposes` verb. The origin would depend on
  the line, and the file-name rule that `PROVIDES` uses would not carry over. No retraction runs on
  the card, so the finer assumption buys nothing here.
- A7. A grammar with kinds and scopes (`needs <kind> <key> [scope]`, `binds … to …`,
  `offers`) and nested `CHAIN` files, which adds the edge type `env/dev`. It tests the
  resolver's scope and rule behaviour, which P2-001b's theorems hold, and grows the reader and
  its failure modes.
- A8. A twelve-file fixture with a stale direct provider, a two-step chain as a labelled miss, a
  decoy binding, and an `awk` re-derivation of the resolver's rules. The script repeats the rules
  it checks; check 7 derives the labels from L1 to L4 instead.
- A9. Labelling AI-proposed lines like human ones. The labels would then follow the tool's input.
- A10. Five kernel-run wiring theorems. Two of them, an unrelated and a reversed binding, test
  `boundB`, which is P2-001b's spec. The plain and AI-only cases are held by `factsOf_chain`,
  `facts_ai` and the card. One end-to-end theorem, the union case, is kept (D7).
- A11. Leave the header as it is. The card would print 10 provisions for 5 (W5).
- A12. The smaller fixture without `SMTP_HOST`'s AI binding and the `LOG_SINK` miss. Its card is
  the same with and without the AI origin (W6), so only `facts_ai` would see a lost one.

### Open questions and risks
- Q1. Should a label or the card be able to say which repo binds (`Edge.through`)? `RepoKey` has no
  such field, so neither can today, and R7 follows from that.
  Default: keep the repo-level label and card schema. Revisit if a consumer needs binding-repo
  evidence.
- Q2. The plan's sentence that the `confirmed` numbers "move from the Phase 1 baseline" holds only
  for a fixture with an AI origin. Should the plan's text say so? The plan is the owner's.
  Default: record the observed hashes here and leave plan wording for the owner's decision.
- Q3. The plan says "a requirement with a direct and a bound derivation to the same provider is
  still `confirmed`". After the O1 ruling, no input has both ending at one provision fact, and
  through two provision facts in one repo both records are `inferred` (measured). Does "provider"
  there mean the provision fact or the repo? If the repo, P2-001b's `statusOf` compares fact ids
  and would need a change, which is spec. The plan and `core/` are the owner's, and this row's
  code is the same either way.
  Default: use the resolver's provision-fact semantics and leave any change to the owner as a
  spec decision.
- At design time, neither CI nor the merged P2-001b head had been checked. See Build notes.

### Next implementation step
Run S1, write the fixture with F1's `printf` lines, then `Score/Chain.lean` and the `Score.lean`
diff, then checks 1 to 7.

### Synthesis decision
Two runners and one judge. Runner A on `opus` took the smallest surface; runner B on `sonnet` took
the adversarial angle. The judge, on `opus`, is this file's author, and rebuilt every number here
from this file's own text at 3d939da and at eac85d2. A was measured on P2-001b's real branch, and
the judge reproduced its hashes byte for byte. B's chain half was measured on a hand-applied
sketch of P2-001b's task file, so its card had never run against the code that will merge.

| Criterion | A (`opus`) | B (`sonnet`) |
|---|---|---|
| Measured against the code that will merge | yes, P2-001b's branch at 3d939da | the union half on `main`; the chain half on a sketch |
| `Score.lean` edit near the cell, rebases with #332 | small hunks; #332 applies | `collapse` moved to a new 250-line module |
| Union rule held where CI looks | one `decide` case beside `collapse` | three general statements and five cases |
| What CI sees of the guard and the pipeline | nothing (W3 and W4 pass the build) | five kernel-run wiring theorems |
| The card shows every status clause | not the AI clause (W6, A's own measure) | yes |
| Public surface | two names | two names, plus a step function and a grammar with kinds and scopes |

Base: A, for safety and the smaller surface. From B: the bindings in the header, printed only when
there are some (D5); the kernel-run wiring check, cut to two theorems, the general
`factsOf_chain` and one `chain_union_end_to_end` with no tuple input, placed at the end of the file
so #332's hunk keeps its context; the fact-line count in check 6 and a labels check (check 7), here
derived from L1 to L4 rather than from the resolver's own rules; the blind spots (R7); and S4's
rule against weakening a statement. From A's own alternatives: the AI-only edge `web → mail` with
the `LOG_SINK` miss, so the card sees the AI clause (D8, W6). From the judge: the owner's O1 ruling
in C2; `main` at eac85d2 and #332 at 856832b, re-measured in both orders; the direct-plus-bound
measurement behind Q3; every variant re-run on the final text, W4, W9 and W10 new; and the
`matches .binds _` count in place of a subtraction. Rejected from B: the union module and its
fold proofs (A5), the grammar with kinds and scopes (A7), the twelve-file fixture and its
re-derivation of the resolver's rules (A8), labels on AI-proposed lines (A9), the other four
wiring theorems (A10), and hashing the statements' text, since the verifier reads each
statement against this file. Rejected from A: the header without bindings (A11) and the smaller
fixture (A12). These picks are the root's defaults with their reasons, not the owner's rulings.
