# tasks/P2-009b-gomod-fixture.md

phase: 2
goal: `lake --dir eval/score exe mitos-score eval/fixtures/gomod` prints precision and recall for the `go-module/runtime` edge type against hand labels, every go.mod file is read by `GoMod.extractor` and by no other reader, and the toy scorecard is unchanged.
statement: none (tooling task). The scorer's own theorems, not locked: `Score.GoMod.facts_eq`, `Score.GoMod.facts_kind`, and the five `reads` cases `reads_root`, `reads_nested`, `not_reads_longer_name`, `not_reads_backup`, `not_reads_directory`
touches: eval/fixtures/gomod/ (new), eval/score/Score/GoMod.lean (new), eval/score/Score.lean (one import, one line in `factsOf`), this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, examples/acme/, core/, eval/diff/, eval/fixtures/toy/, eval/score/Main.lean, eval/score/lakefile.toml, eval/score/lake-manifest.json, .github/, docs/, plan/, .claude/
checks: the scorer builds with no warning (check 1), axioms (check 2), toy scorecard unchanged (check 3), the go.mod scorecard is F2 (check 4), labels against Go's own parse (check 5, local), fixture bytes (check 6), changed paths (check 7), the run-log check (check 8), `plan-tasks.test.sh` (check 9), `gate` green in CI (check 10)
budget: 6 iterations · 1h wall · 400k tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-009b in `plan/phase-2.md` (go.mod track, wave W3), issue #211. It waits for P2-007
  (#208), which merged as f6b10cf (#286), and for P2-001a (#203), which moved the scorer to
  `Mitos.RepoKey`; both are on `main`. P2-010 (#212) waits for this row. An agent carries and
  merges it. Brief role: PR owner, `sonnet`, `high`. No proof is left to find, and no path is a
  trust path.
- The row's cells. Owns: `eval/fixtures/gomod/` *(new)*, a go.mod module in `eval/score/Score/`,
  one import and one call in `eval/score/Score.lean`. Reads: `examples/acme/Plugins/GoMod.lean`.
  Also must not touch: `eval/diff/`.
- Inputs from the go.mod rows: P2-006's deferral (identity kind `go-module`, scope `runtime`,
  origin `.extractor "GoMod"`, edge type `go-module/runtime`) and P2-007's call site
  (`tasks/P2-007-gomod-plugin.md`, Usage). This design takes both, and changes the call site from
  an append to a guard (D1).
- The other `eval/score` rows: P2-009a (#210, W5) edits `collapse` and adds one import, and
  P2-010 (#212, W6) owns `Main.lean` and a scorecard module. They merge one at a time
  (`plan/phase-2.md`, Shared files 4), so this row lands first and they rebase on it.
- Designed at `main` 85981fe on Lean v4.35.0 (Go 1.24.7 for check 5). `eval/`, `examples/` and
  `core/` are the same at 85981fe as at c280558, where the two runners built. The sketch, the
  fixture and every expected output below were built and run in a scratch copy of `main`
  (`git archive`), and the judge ran them again from this file's own text.
- Where the plan, the earlier task files and `main` disagree:
  - The cell says "one call". A plain call would let the toy reader read go.mod files too, so
    the call sits in a guard on the same line (D1, W1).
  - P2-006 and P2-007 say the call "is the toy's line in `factsOf` with the name changed". Taken
    literally it breaks the toy fixture (W5). Their task files are merged records and stay as
    they are.
  - The cell says "the scorer's go.mod edge type". `Score.edgeType` builds the type from a fact's
    kind and scope, so `go-module/runtime` needs no code. The row writes the reader, and
    `facts_kind` pins the two fields the edge type reads.
  - The plan says P2-009a's `collapse` change moves the `confirmed` numbers. It cannot move F2
    (F6).
  - `docs/process.md` (`:188`, `:483`) and `ci.yml` (`:292-297`) name only the toy fixture, and
    neither is this row's. No CI step prints F2 until P2-012.
- Landing this file. `.claude/scripts/plan-tasks.pending` lists P2-009b, and
  `plan-tasks.test.sh` (CI, blocking) fails once a listed row has a task file with a Design
  block. So the PR that lands this design also deletes the line `P2-009b` from that list.
  `.claude/` is the owner's path, so the owner merges that PR, as a489a5f did for the wave 1
  designs. The build PR itself stays agent-merged.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. Under `types` are all of `eval/score/Score/GoMod.lean` and the whole diff of
`eval/score/Score.lean`, as final text with every proof written in. In a scratch copy of `main` at
85981fe on Lean v4.35.0, `lake --dir eval/score build` ends with `Build completed successfully
(42 jobs)` and no `warning:` line, the toy scorecard is byte for byte the one `main` prints, and
the go.mod scorecard is F2. The named fixtures are F1 to F7.

revisit_when: none. P2-001a, P2-006 and P2-007 have merged, and the names used here are their
names on `main`. The builder still runs stop condition S1 first: P2-001b (#204) may change
`Score.lean` and the resolver before this row merges.

modules: one topic per file.
- `eval/score/Score/GoMod.lean` *(new)*: how the scorer reads go.mod: which repo files are go.mod
  files, and the facts it takes from one. 37 lines. It copies the layout of
  `examples/acme/Plugins/GoMod.lean`: imports, one namespace, `open Mitos`, the definitions, then
  the theorems.
- `eval/score/Score.lean`: two added lines, `import Score.GoMod` and the first line of the body
  of `factsOf`. 141 → 143 lines. Nothing else in the file changes.
- `eval/fixtures/gomod/` *(new)*: `.gitattributes` (`* -text`, the toy's), `labels.tsv` (6
  lines), and 8 go.mod files in 7 repos under `repos/`, 3 to 15 lines each. It copies the layout
  of `eval/fixtures/toy/`.

### How the scorer reads a fixture on `main`

1. `loadRepos` (`eval/score/Main.lean:13`) walks `repos/<repo>/` in sorted order and gives each
   file as a `SourceFile` with its repo, its path relative to the repo with the platform's
   separator (`/` on the Linux runner), and its text. `repos/mono/tools/go.mod` arrives as repo
   `mono`, path `tools/go.mod`.
2. `factsOf` (`Score.lean:41`) runs `ToyRequire.extractor` on every file, and the `PROVIDES`
   reader on files named `PROVIDES`. The toy reads any line that starts with `require `, so on a
   go.mod file it reads `require (` as a toy requirement of `(`.
3. `ingest` numbers the facts and stops with exit 1 on a span that does not cite its key.
4. `Mitos.Impl.resolve` makes one edge per requirement and provision with equal `Identity` (kind
   and key), between any two repos, one repo with itself included (`matchesB`,
   `core/Mitos/Core/Spec/Derivations.lean:5`). An edge is `confirmed` when its requirement has
   one provider and no AI origin.
5. `collapse` groups edges by `RepoKey`: the requiring repo, the providing repo, and the
   requirement's identity and scope. A group is `inferred` if any edge in it is.
6. `edgeType k` is `s!"{k.ident.kind}/{scopeName k.scope}"`, so the edge type comes from the
   facts and needs no code per format. A label is five tab-separated fields.
7. The `Score` library has no globs, so it builds `Score` and what `Score` imports. A module under
   `Score/` builds once `Score.lean` imports it, with no lakefile change.
8. CI builds `eval/score` and runs the scorer on `eval/fixtures/toy` only
   (`.github/workflows/ci.yml:292-297`), then posts that scorecard on the PR.

### Usage (caller's view)

```
lake --dir eval/score exe mitos-score eval/fixtures/gomod
```

It prints F2 and exits 0. The toy run prints what it prints on `main`.

Call sites:
- `Score.factsOf`, on its first line: `if GoMod.reads f.path then GoMod.facts f.text else`. A
  go.mod file gets the go.mod plugin's facts and nothing else. Every other file keeps the Phase 1
  readers, so the toy fixture, which has no go.mod file, scores as before.
- P2-010's scorecard runs the scorer on each fixture directory. `gomod` is one more directory, and
  it calls nothing here.
- The next format (package.json is deferred) copies this row: a `Score/<Format>.lean` with `reads`
  and `facts`, one import and one more guard line in `factsOf`.
- `labels.tsv` uses identity kind `go-module` and scope `runtime`. `facts_kind` pins both.
- The interface is `Score.GoMod.reads`, `Score.GoMod.facts` and seven theorems. `fileName` is
  `private`.

### How a builder goes wrong here

- P2-007's Usage taken literally, "the toy's line in `factsOf` with the name changed", in either
  of its two readings. A swap (W5) makes the toy fixture read no requirement: its card goes to 4
  facts, 0 requirements, 0 edges. An append (W1) makes the toy read every go.mod too: both tables
  of the go.mod card stay the same, but its header says 19 facts, 11 requirements and 5
  unresolved, and four toy requirements are listed (`"("` twice, `"example.com/util v0.2.0"`,
  `"example.com/lib v1.4.0"`). Only checks 3 and 4 see them.
- `GoMod.extractor` written without `_root_` inside `namespace Score.GoMod`. It resolves to
  `Score.GoMod.extractor` as soon as someone defines that name. The sketch writes
  `_root_.GoMod.extractor` and `_root_.GoMod.run_eq`.
- `reads` written as a plain suffix test (W2, `notgo.mod` is read) or as `path == "go.mod"` (W3,
  `tools/go.mod` is not). The build fails on `not_reads_longer_name` or on `reads_nested`. W3
  also drops `mono → util` (recall 0.67) and hands `mono/tools/go.mod` to the toy.
- `System.FilePath.fileName` for `reads`, because it is shorter. `decide` cannot reduce it (the
  reduction stops at `{ toString := "tools/go.mod" }.fileName`, measured), so the five cases
  could not be written, and CI would no longer check the path rule. The sketch works on
  `List Char`.
- `native_decide` for the `reads` theorems. It adds the axiom `Lean.ofReduceBool`. `decide`
  checks all five in the kernel; the whole module builds in under 1 s.
- A `sorry`. `lake --dir eval/score build` still succeeds with a warning, and CI stays green.
  Check 1 looks for the warning.
- `Models.GoMod.facts` called in place of `GoMod.extractor.run`. By `GoMod.run_eq` the list is the
  same, so no card shows it. The scorer measures the accepted plugin, and `Models.GoMod.facts`
  appears in statements only (`tasks/P2-007-gomod-plugin.md`, Usage).
- Labels that follow the scorer instead of the repos: `app → cli` dropped because it is a miss, or
  `app → log` added because it is predicted. The labels state what the go command builds against
  (rules L1 to L5), and check 5 compares them with Go's own parse.
- An editor or a git setting that rewrites the CRLF of `repos/util/go.mod`. Write the fixture with
  F1's `printf` lines, and run check 6.
- Comments in `labels.tsv`. The toy's were cut in #130 (c6f07bb). The labelling rules live here.
  The `//` lines in the fixture's go.mod files are fixture data, not code comments.
- A requirement between two modules of one repo added to the fixture. The resolver makes a
  self-edge such as `mono → mono`, and no rule says whether to label it (Q1).
- An edit to `Main.lean` (P2-010 owns it) or to the lakefile (the import is enough).

types:
- Inputs, as they are on `main`. From `examples/acme/Plugins/GoMod.lean`: `GoMod.extractor :
  Mitos.Extractor` and `GoMod.run_eq : ∀ (s : String), GoMod.extractor.run s =
  Models.GoMod.facts s`. From `examples/acme/Models/GoMod.lean`: `Models.GoMod.facts s :=
  (entries s).map fact`, where `fact` sets identity kind `"go-module"` and scope `.runtime`. From
  `Score.lean`: `SourceFile`, `factsOf`, `ingest`, `collapse`, `edgeType`, all unchanged except
  `factsOf`'s first line.
- `eval/score/Score/GoMod.lean`, the file in full:

```lean
import Mitos.Core
import Plugins.GoMod

namespace Score.GoMod

open Mitos

private def fileName : List Char := "go.mod".toList

def reads (path : String) : Bool :=
  path.toList == fileName || ('/' :: fileName).isSuffixOf path.toList

def facts (text : String) : List (Fact × Assumption) :=
  (_root_.GoMod.extractor.run text).map (·, .extractor "GoMod")

theorem reads_root : reads "go.mod" = true := by decide

theorem reads_nested : reads "tools/cmd/go.mod" = true := by decide

theorem not_reads_longer_name : reads "notgo.mod" = false := by decide

theorem not_reads_backup : reads "go.mod.orig" = false := by decide

theorem not_reads_directory : reads "go.mod/README" = false := by decide

theorem facts_eq (text : String) :
    facts text = (Models.GoMod.facts text).map (·, .extractor "GoMod") := by
  rw [facts, _root_.GoMod.run_eq]

theorem facts_kind {text : String} {p : Fact × Assumption} (h : p ∈ facts text) :
    p.1.ident.kind = "go-module" ∧ p.1.scope = .runtime := by
  rw [facts_eq] at h
  obtain ⟨f, hf, rfl⟩ := List.mem_map.1 h
  obtain ⟨e, -, rfl⟩ := List.mem_map.1 hf
  exact ⟨rfl, rfl⟩

end Score.GoMod
```

- `eval/score/Score.lean`, the whole diff:

```diff
@@ -1,6 +1,7 @@
 import Mitos.Core
 import Mitos.Impl.Resolve
 import Plugins.ToyRequire
+import Score.GoMod
 
 namespace Score
 
@@ -39,6 +40,7 @@
     else none
 
 def factsOf (f : SourceFile) : List (Fact × Assumption) :=
+  if GoMod.reads f.path then GoMod.facts f.text else
   let fromPlugin := (ToyRequire.extractor.run f.text).map (·, .extractor "ToyRequire")
   let fromDecl :=
     if f.path == "PROVIDES" then
```

- Inside `namespace Score`, `GoMod.reads` is `Score.GoMod.reads`. `reads` takes the path as
  `loadRepos` builds it, relative to the repo and `/`-separated.
- `facts_kind` does not name the model's entry type, so a model change that leaves kind and scope
  alone does not break it.
- Code that makes facts calls `GoMod.extractor.run`, and `Models.GoMod.facts` appears in
  statements only.

statements:
- `Score.GoMod.facts_eq : ∀ (text : String), Score.GoMod.facts text = List.map (fun x => (x,
  Mitos.Assumption.extractor "GoMod")) (Models.GoMod.facts text)`. The scorer takes the model's
  facts, in file order, each with origin `.extractor "GoMod"`, with nothing dropped, added or
  moved. It goes through `GoMod.run_eq`, so a plugin change that drops `run_eq` breaks this build.
- `Score.GoMod.facts_kind : p ∈ facts text → p.1.ident.kind = "go-module" ∧ p.1.scope =
  .runtime`. `mkEdge` gives an edge its requirement's identity and scope, so every edge from a
  go.mod requirement has edge type `go-module/runtime`, the row's "go.mod edge type". A model
  change to the kind breaks this build in CI, where the `checks` job runs `lake --dir eval/score
  build`, so `labels.tsv` moves in the same PR.
- The five `reads` cases. `reads path` holds exactly when the last `/`-separated part of `path` is
  `go.mod`. The cases pin both sides: the file at the root, one two directories down, a longer
  name, a longer extension, and a directory named `go.mod`.
- Each of the seven depends on `[propext, Classical.choice, Quot.sound]` only (check 2).
- Not a theorem: "the toy reads no go.mod file". It is the guard line in `Score.lean`, and a
  theorem there would be a third edit to that file. F2 and W1 pin it.

reuse: `GoMod.extractor` and `GoMod.run_eq` (`examples/acme/Plugins/GoMod.lean`);
`Models.GoMod.facts`; `Score.ingest`, `Score.collapse`, `Score.edgeType`, `Score.parseLabels` and
`Scorecard.render` unchanged; `loadRepos` in `eval/score/Main.lean`; the layout and
`.gitattributes` of `eval/fixtures/toy/`; `List.mem_map`, `List.isSuffixOf`.

fixtures:
- F1, the fixture. Each case is there for one property. Two cases are misses on purpose, as in
  the toy (`tasks/P1-007-fixture-scorecard.md`): a fixture where every number is 1.00 cannot show
  that the scorer measures anything.

| Repo | File | What it holds | Exercises |
|---|---|---|---|
| app | `go.mod` | a comment with `ç`; `module`, `go`, `toolchain`; a `require ( … )` block with `example.com/lib`, `example.com/log … // indirect`, `golang.org/x/text` and the quoted `"example.com/cli"`; `replace example.com/log => ../log-fork` | byte offsets after a 2-byte character; a block; `// indirect`; a module no repo provides; a quoted path and a `replace`, both outside the model's subset |
| cli | `go.mod` | `module example.com/cli` | the provider of the quoted requirement |
| lib | `go.mod` | `require example.com/util v0.2.0` on one line; `exclude example.com/log v0.2.0` | the one-line form; `exclude` is not a requirement |
| log | `go.mod` | `module example.com/log` | the module's home |
| log-fork | `go.mod` | `module example.com/log` | a fork that keeps the path, the `replace` target |
| mono | `go.mod`, `tools/go.mod` | two modules in one repo; both require `example.com/lib`, and `tools` also requires `example.com/util` in a block | a nested go.mod (`reads`); two edge records under one repo-level edge |
| util | `go.mod` | `module example.com/util` with CRLF line ends | `\r` stays out of the key (the toy's CRLF case is a miss, this one is a hit) |

  Labelling rules. A reader of the repos writes the labels; the scorer's output never does.
  - L1. One label per repo-level edge that is real: the requiring repo, the repo the go command
    takes the required module from, `go-module`, the module path, `runtime`.
  - L2. A `replace` with a directory moves the edge to the repo of that directory: `app →
    log-fork`, not `app → log`.
  - L3. A `// indirect` requirement is labelled.
  - L4. `exclude`, `retract`, `go` and `toolchain` lines, and the old path of a `replace`, are not
    requirements.
  - L5. A module that no fixture repo provides gets no label (`golang.org/x/text`).
  - Two go.mod files of one repo that require one module give one label (`mono → lib`).
  - A module path that two repos declare, required with no `replace`, needs a reader's call on
    which repo is its home. The fixture has none, and check 5 stops on one (`AMBIGUOUS`).

  Each edge, its source and its place in F2:

| Edge | Source | Labelled | In F2 |
|---|---|---|---|
| `app` → `lib` | `app/go.mod`, block | yes (L1) | true positive, `confirmed` |
| `app` → `log-fork` | `log … // indirect` with the `replace` | yes (L2, L3) | true positive, `inferred`: two repos declare `example.com/log` and the plugin does not read `replace` |
| `app` → `log` | the same requirement | no (L2) | false positive, `inferred` |
| `app` → `cli` | the quoted requirement | yes (L1) | a miss: the plugin does not read quoted paths |
| none | `golang.org/x/text` in `app/go.mod` | no (L5) | unresolved, bytes 162+17 |
| none | `exclude example.com/log` in `lib/go.mod` | no (L4) | no `lib → log` edge |
| `lib` → `util` | `lib/go.mod`, one line | yes (L1) | true positive, `confirmed` |
| `mono` → `lib` | `mono/go.mod` and `mono/tools/go.mod` | yes, one label | true positive, `confirmed`, 2 records (F6) |
| `mono` → `util` | `mono/tools/go.mod`, block | yes (L1) | true positive, `confirmed` |

  The fixture, byte for byte, from the repository root:

```
d=eval/fixtures/gomod
mkdir -p $d/repos/app $d/repos/cli $d/repos/lib $d/repos/log $d/repos/log-fork $d/repos/mono/tools $d/repos/util
printf '* -text\n' > $d/.gitattributes
printf 'app\tlib\tgo-module\texample.com/lib\truntime\napp\tlog-fork\tgo-module\texample.com/log\truntime\napp\tcli\tgo-module\texample.com/cli\truntime\nlib\tutil\tgo-module\texample.com/util\truntime\nmono\tlib\tgo-module\texample.com/lib\truntime\nmono\tutil\tgo-module\texample.com/util\truntime\n' > $d/labels.tsv
printf '// Façade over the shared libraries.\nmodule example.com/app\n\ngo 1.22\n\ntoolchain go1.22.4\n\nrequire (\n\texample.com/lib v1.4.0\n\texample.com/log v0.3.1 // indirect\n\tgolang.org/x/text v0.14.0\n\t"example.com/cli" v1.0.0\n)\n\nreplace example.com/log => ../log-fork\n' > $d/repos/app/go.mod
printf 'module example.com/cli\n\ngo 1.22\n' > $d/repos/cli/go.mod
printf 'module example.com/lib\n\ngo 1.21\n\nrequire example.com/util v0.2.0\n\nexclude example.com/log v0.2.0\n' > $d/repos/lib/go.mod
printf 'module example.com/log\n\ngo 1.21\n' > $d/repos/log/go.mod
printf 'module example.com/log\n\ngo 1.21\n' > $d/repos/log-fork/go.mod
printf 'module example.com/mono\n\ngo 1.22\n\nrequire example.com/lib v1.4.0\n' > $d/repos/mono/go.mod
printf 'module example.com/mono/tools\n\ngo 1.22\n\nrequire (\n\texample.com/lib v1.4.0\n\texample.com/util v0.2.0\n)\n' > $d/repos/mono/tools/go.mod
printf 'module example.com/util\r\n\r\ngo 1.21\r\n' > $d/repos/util/go.mod
```

  `cd eval/fixtures/gomod && find . -type f | LC_ALL=C sort | xargs sha256sum` then prints:

```
705fd4d6451a31d36b3df7de96f83f30ac976c9b4a6d1e51671d8e2f33e2d0da  ./.gitattributes
ccfb1f1527ef06ef1c362c4fdfd8d8c9514a1e99a83f7f183f2e602c9afe085a  ./labels.tsv
dd062f15c56cbe7cdd874b349378439c9f1fe4de7554a9ccb561c15939e00ae7  ./repos/app/go.mod
c7f6b020297a9931c1d10580a2e5c2ec5f5eb6be8c253cb9a85f45d82cac86c2  ./repos/cli/go.mod
a31850fb790e3108c3d75718987bc23e888ca244790ca2c786390df1fbb4b711  ./repos/lib/go.mod
560c7092a7b85ba8da9dc483b3896e6263d742114a15e43fde30fb7e3eefc759  ./repos/log-fork/go.mod
560c7092a7b85ba8da9dc483b3896e6263d742114a15e43fde30fb7e3eefc759  ./repos/log/go.mod
92c49a36d19a8de5413faaf7fc9c9e223c747d964093b9b677aac280268f29cd  ./repos/mono/go.mod
ecff009f97fed2a184feb24b34cc5c2249697fe4a743c22f58257180e3653228  ./repos/mono/tools/go.mod
853ee9c28c8f87d3a25c9ff5406c6c231757350105e964b79600a7c2db174ce5  ./repos/util/go.mod
```

- F2, the go.mod scorecard. `lake --dir eval/score exe mitos-score eval/fixtures/gomod` prints
  exactly this (sha256 of the output `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf`),
  and exits 0:

```
### Scorecard: fixture `gomod`

15 facts (7 requirements, 8 provisions), 6 repo-level edges predicted, 6 hand-labelled, 1 requirements unresolved.

| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |
|---|---|---|---|---|---|---|---|
| go-module/runtime | 6 | 6 | 5 | 1 | 1 | 0.83 (5/6) | 0.83 (5/6) |

| Edge type | Trust level | Predicted | TP | FP | Precision |
|---|---|---|---|---|---|
| go-module/runtime | confirmed | 4 | 4 | 0 | 1.00 (4/4) |
| go-module/runtime | inferred | 2 | 1 | 1 | 0.50 (1/2) |

False positives (predicted, not labelled):
- `app` → `log` (go-module/runtime `example.com/log`), inferred

Misses (labelled, not predicted):
- `app` → `cli` (go-module/runtime `example.com/cli`)

Unresolved requirements:
- `app/go.mod` bytes 162+17: `"golang.org/x/text"`
```

  Byte 162 is a byte offset: the `ç` on the first line is two bytes, so the character offset is
  161. A span in characters would fail `ingest`'s anchor check and the run would exit 1. The only
  edge type is `go-module/runtime`, and no `toy/` row appears, which is what the guard is for.
- F3, the toy scorecard is unchanged. With the design applied, `mitos-score eval/fixtures/toy`
  prints the same bytes as on `main`: sha256
  `17c55e9cfa3a9db873c50c980cf2cbea62195fe2eebecde3edc0a13add38f21a` before and after. The toy
  fixture has no file named `go.mod`.
- F4, the labels against Go. Go 1.24.7's `go mod edit -json` parses all eight files, lists
  `example.com/cli` among `app`'s requirements, and lists `replace` and `exclude` apart. The
  command of check 5 derives labels from that parse with L1 to L5 and prints `labels.tsv` line
  for line. It is a check on the hand labels, not their source.
- F5, wrong variants, each built and run in a scratch copy. They show what each check can see.

| Variant | What fails | What F2 shows |
|---|---|---|
| W1, the go.mod facts appended to the toy's | nothing in the build | header 19 facts (11 requirements), 5 unresolved; four toy requirements listed; both tables unchanged. The toy scorecard is unchanged too |
| W2, `reads` as `fileName.isSuffixOf path.toList` | `not_reads_longer_name` | not reached |
| W3, `reads` as `path.toList == fileName` | `reads_nested` | with that theorem deleted: 13 facts (6 requirements), recall 0.67 (4/6), `mono → util` a miss, and a toy `"("` from `mono/tools/go.mod` |
| W4, origin `.extractor "go.mod"` | `facts_eq` | nothing: the scorecard does not print origins |
| W5, the toy line swapped for the go.mod facts, on every file | nothing in the build | the same as F2, because every file of this fixture is a go.mod. The toy scorecard moves: `4 facts (0 requirements, 4 provisions), 0 repo-level edges predicted` |

- F6, edge records per repo-level edge, counted in a scratch script over
  `Mitos.Impl.resolve (ingest files)`: 7 records over 6 repo-level edges. `mono → lib` has 2 (one
  from `mono/go.mod`, one from `mono/tools/go.mod`), every other edge 1. On the toy fixture every
  edge has 1. So P2-010's "most derivations any repo-level edge has" reads 2 here, the first
  count above 1 from a real format. Under the direct rule a status depends only on the
  requirement's identity and origins, which every edge under one go.mod repo-level edge shares, so
  P2-009a's change to `collapse` cannot move F2.
- F7, the card if the owner turns D3 (no `// indirect` requirement is labelled): delete the line
  `app → log-fork` of `labels.tsv`. The card then reads 6 predicted, 5 labelled, precision 0.67
  (4/6), recall 0.80 (4/5), `inferred` 0.00 (0/2), and `app → log-fork` joins the false
  positives. `confirmed` stays 1.00 (4/4).

### Checks, in order

From the repository root, at the head after the last rebase.

1. `lake --dir eval/score build 2>&1 | grep -E '^(warning|error)'` prints nothing, and the build
   ends with `Build completed successfully`. A `sorry` prints `warning: Score/GoMod.lean:…:
   declaration uses `sorry``.
2. A scratch file `Axioms.lean`, never committed:

```lean
import Score

#print axioms Score.GoMod.facts_eq
#print axioms Score.GoMod.facts_kind
#print axioms Score.GoMod.reads_root
#print axioms Score.GoMod.reads_nested
#print axioms Score.GoMod.not_reads_longer_name
#print axioms Score.GoMod.not_reads_backup
#print axioms Score.GoMod.not_reads_directory
```

   `cd eval/score && lake env lean <scratch>/Axioms.lean` prints seven lines, each ending in
   `[propext, Classical.choice, Quot.sound]`.
3. `lake --dir eval/score exe mitos-score eval/fixtures/toy | sha256sum` prints F3's hash, before
   the first edit and at the head. If `origin/main` has moved the toy fixture or the scorer since
   85981fe, compare with the output of a detached worktree of `origin/main` instead
   (`git worktree add --detach <scratch>/main origin/main`).
4. `lake --dir eval/score exe mitos-score eval/fixtures/gomod | sha256sum` prints
   `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf`, the hash of F2. If it
   differs, `diff` the output with F2 and read S3.
5. Labels against Go, local only (CI has no Go). With `go` and `jq` on the path, this prints
   nothing:

```
cat > <scratch>/derive-labels.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$1/repos"
files=$(find . -name go.mod | LC_ALL=C sort)
declare -A provider
for f in $files; do
  repo=${f#./}; repo=${repo%%/*}
  m=$(go mod edit -json "$f" | jq -r .Module.Path)
  provider[$m]="${provider[$m]:+${provider[$m]} }$repo"
done
for f in $files; do
  repo=${f#./}; repo=${repo%%/*}
  dir=$(dirname "$f")
  go mod edit -json "$f" |
    jq -r '(.Replace // []) as $r | .Require[]? | .Path as $p |
      [$p, (($r | map(select(.Old.Path == $p)) | .[0].New.Path) // "")] | @tsv' |
    while IFS=$'\t' read -r path to; do
      if [ -n "$to" ]; then
        dst=$(realpath --relative-to=. -m "$dir/$to"); dst=${dst%%/*}
      else
        dst=${provider[$path]:-}
      fi
      case $dst in
        "") ;;
        *" "*) echo "AMBIGUOUS $repo $path: $dst" >&2; exit 1 ;;
        *) printf '%s\t%s\tgo-module\t%s\truntime\n' "$repo" "$dst" "$path" ;;
      esac
    done
done | awk '!seen[$0]++'
EOF
bash <scratch>/derive-labels.sh eval/fixtures/gomod | diff - eval/fixtures/gomod/labels.tsv
```

6. `cd eval/fixtures/gomod && find . -type f | LC_ALL=C sort | xargs sha256sum` prints F1's ten
   lines, and `git ls-files --eol eval/fixtures/gomod` shows `attr/-text` on all ten files and
   `i/crlf` on `repos/util/go.mod` only (measured with `git -c core.autocrlf=true add`).
7. `git diff --name-only origin/main...HEAD` prints only the ten files of F1,
   `eval/score/Score.lean`, `eval/score/Score/GoMod.lean`, `tasks/P2-009b-gomod-fixture.md` and
   files under `ops/runs/`.
8. `lake exe mitos-gate runlog --head ops/runs`, and
   `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
   shows only `A` lines.
9. `.claude/scripts/plan-tasks.test.sh`, because this file changes. It passes only once
   `P2-009b` has left `.claude/scripts/plan-tasks.pending`, which the PR that lands this file does.
10. In CI, the `checks` job and the PR's `gate` are green. `checks` builds `eval/score`, so the
    kernel checks the seven theorems, and it runs the toy scorecard, which must read as on `main`.

### Risks and stop conditions

Risks:
- R1. P2-001b (#204) may land first. Its cell allows `Score.lean` "if its build breaks", and it
  changes the resolver and the status rule. The fixture has no binding fact, so its derivations
  are Phase 1's matches and F2 should not move. S1 makes the builder check.
- R2. P2-009a also adds one import after `import Plugins.ToyRequire`. Whichever PR is second
  meets a one-line conflict there on rebase. Keep both imports; that is a conflict resolution, so
  the verifier reads it (CLAUDE.md, Verdicts).
- R3. CI never runs the go.mod scorecard until P2-012, so a later PR can move F2 unnoticed. Only
  the seven theorems run in CI, through the build.
- R4. The toy reader still takes every file that is not a go.mod. A later fixture with a file of
  another format and a line that starts `require ` reads it as a toy requirement. The toy card
  cannot move, because this row leaves the toy's behaviour alone. Dispatch by format is for the
  row that adds a third reader.
- R5. A change to the plugin or the model moves F2. A model that reads quoted paths turns the
  miss into a hit and recall to 6/6. That is the card doing its job, and the labels stay.
- R6. `reads` tests `/` only, and `loadRepos` joins with the platform's separator. CI runs on
  Linux. A Windows run would read no nested go.mod.

Stop conditions for the builder:
- S1. Before writing, after `git fetch origin main`, this prints nothing:

```
git diff --stat 85981fe origin/main -- eval/score eval/fixtures examples/acme/Plugins/GoMod.lean examples/acme/Models/GoMod.lean core/Mitos/Core/Graph.lean core/Mitos/Core/Spec/Derivations.lean core/Mitos/Impl/Resolve.lean lean-toolchain
```

  If it prints only `eval/score/Score.lean`, put the two lines into the new text and go on; F2
  and F3 must still hold. If it prints a core file, go on and run check 4; if F2 moves, stop and
  report. If it prints the plugin or the model, stop; this design is amended first.
- S2. A check fails and the fix is outside `touches`: stop and report.
- S3. Check 4 or 5 differs. Never edit `labels.tsv` to match the scorer. Find which side is wrong
  (the labels by L1 to L5 and check 5, the scorer by F5). A wrong plugin or model is a stop.
- S4. The builder stops when the PR is open on `main`, `gate` is green, checks 1 to 9 pass at the
  head and every thread is answered, and reports that head as merge-ready. No path here is the
  owner's, so an agent merges it.

cut_line: ships the fixture, `Score/GoMod.lean` with its seven theorems, the two lines in
`Score.lean`, the build notes in this file and the run log. It leaves the CI run of the go.mod
scorecard to P2-012, the scorecard over every fixture, its diff against `main` and the derivation
count to P2-010, quoted paths and `replace` to the model's follow-up (P2-006, deferrals), and Q1 to
Q3 to the PR's follow-up issue.

deferrals:
- To P2-012 (#213): run `mitos-score eval/fixtures/gomod` beside the toy in `ci.yml`'s scorecard
  step (`:292-297`) and in the nightly post, so a PR that moves F2 shows it. `docs/process.md`
  names only the toy fixture in its scorecard row (`:188`) and its paragraph at `:483`; that
  wording is the owner's and moves with P2-012. Until then checks 3 to 5 are the builder's and the
  verifier's, and the PR body carries F2.
- To P2-010 (#212): `gomod` is one of "every fixture". Its most derivations per repo-level edge is
  2 (F6). F2 is `main`'s go.mod scorecard, the baseline of its diff.
- To P2-009a (#210): it rebases on this row if this lands first (R2). Its `collapse` change cannot
  move F2 (F6). If it adds a reader to `factsOf`, the guard stays the first line, so go.mod files
  stay the go.mod plugin's alone.
- To P2-008 (#209): nothing shared. Its pinned go.mod files are real ones, and these are written
  for the scorecard. Check 5 is a small cousin of its runner and stays a scratch command.
- From P2-007 (#208): its call site, taken as a guard instead of an append (D1, W1, W5). Its task
  file is merged and is not edited.
- From P2-006 (#207): the identity kind, scope, origin and edge type. `facts_eq` and `facts_kind`
  state them.
- To the PR's follow-up issue, no row: Q1, Q2 and Q3.

owner_decisions:
- Settled by the plan: the fixture is `eval/fixtures/gomod/`, the go.mod code is a module under
  `eval/score/Score/`, `Score.lean` gets one import and one call, the differential run is P2-008's,
  and an agent merges this row.
- This design's defaults, not owner rulings:
  - D1. A go.mod file is read by the go.mod plugin only, and the toy and the `PROVIDES` reader keep
    every other file. The call is a guard on the first line of `factsOf`. Reason: W1 and W5. This
    is where the plan and this design part: the cell says "one call", and the one line holds the
    guard and the call.
  - D2. A written fixture under `example.com`, not copies of real pinned go.mod files. Reason:
    P2-008's pins are not on `main`; real files score 1.00 on this subset (P2-007's F4 matched Go
    on 84 of 84 facts), so they cannot show the two gaps; and they carry licences (#160 item 2).
  - D3. Labels follow `replace` (L2) and include `// indirect` requirements (L3). To turn L3, see
    F7.
  - D4. No requirement between two modules of one repo, because Q1 has no rule.
  - D5. No CI change here; `.github/` is P2-012's.
  - D6. A quoted path is a labelled miss, not left out of the labels, so the card shows the
    model's known gap, as the toy's CRLF file does. If the owner prefers a fixture with no known
    miss, the quoted line of `app/go.mod`, `repos/cli` and the `app → cli` label go. The card
    then reads 14 facts, 6 predicted, 5 labelled, precision 0.83 (5/6), recall 1.00 (5/5).

## Rationale

### Problem

The go.mod plugin is accepted, and the scorer must score it against hand labels so that the
nightly scorecard has a go.mod edge type (exit criterion 5). Four things on `main` shape it. The
toy reader runs on every file, and on a go.mod file it reads `require (` as a requirement.
`Score.lean` may gain only one import and one call. A module under `Score/` cannot import
`Score.lean`, which imports it, so it cannot take a `SourceFile`. And the edge type is derived from
the facts, so the go.mod edge type needs no code, only facts with the right kind and scope. CI
builds the scorer but runs only the toy fixture, so what CI can hold for this row is the build, not
the card.

### Shape

`Score.GoMod` owns two decisions: which paths are go.mod files (`reads`), and which facts and
origin the scorer takes from one (`facts`, a map over `GoMod.extractor.run`). `Score.factsOf`
owns the decision across formats: a go.mod file goes to `Score.GoMod` only, and every other file
to the Phase 1 readers. The edge type `go-module/runtime` falls out of `Score.edgeType`, and
`facts_kind` pins the two facts it reads. `facts_eq` pins that the scorer adds no filter, order or
origin of its own. The five `reads` cases pin the path rule from both sides, in the kernel, so the
rule is held by the build that CI does run. The fixture puts each case of the subset next to a
case outside it, and its labels state what Go builds against, which Go's own parse confirms (F4).

Interface depth: two names, seven theorems. They hide the file-name rule, the plugin choice, the
origin and the dispatch's one decision. The fixture is data, so the module is small on purpose.
The deeper shape, a reader table, hides more once a third format exists, and A3 says why not now.

### Synthesis decision

Two runners, A on opus and B on sonnet, and one judge on sonnet (this file's author) who read both
and picked the base; no separate cross-judge ran. No fable seat ran: the owner asked to avoid it
for its token cost. Both candidates built clean on `main`, and the judge re-ran each from its own
text: A's F2 hashes to
`889671a4…`, B's card to `5107ce2d…`, and both leave the toy card at `17c55e9c…`. The two
converged on the core: a new `Score/GoMod.lean` that imports `Plugins.GoMod`, one import and a
dispatch in `factsOf` instead of the P2-007 append, a hand-written fixture under `example.com`,
labels that include `// indirect`, and two known misses.

Rubric, five criteria:

| Criterion | A (opus) | B (sonnet) |
|---|---|---|
| Edit to `Score.lean` is small and rebases cleanly | 2 added lines, none changed | 1 line replaced by 3 |
| The path rule is held where CI runs | 5 `decide` cases and 2 theorems in the build | none: `decide` is stuck on `fileName` (re-measured), the card is not in CI |
| Labels are grounded, not a reader's call | all 6 derive from `go mod edit -json` with 5 written rules (check 5) | the fork with no `replace` needs a judgement; Go's parse only checked the requirements |
| The fixture tells the wrong dispatches apart | W1 to W4, each caught by a check | W1, `path ==`, `endsWith`, swap, each caught by the card, and one decoy file |
| Every number reproduces | yes, byte for byte | yes, byte for byte |

Base: A. It holds the rule in the kernel, which is the only place CI looks for this row, and its
diff to `Score.lean` is the smallest.

From B:
- the swap as a named wrong variant (W5), the likeliest misreading of P2-007's "the toy's line with
  the name changed", measured on A's sketch: the toy card drops to 0 requirements;
- the edge-by-edge table of F1, one line per label with its source and its place in F2, so a
  verifier can derive each label before reading the card;
- the note that a non-go.mod file with a `require ` line is still the toy's (R4), and that a model
  that grows closes a miss while the labels stay (R5);
- the path-separator assumption (R6), and `eval/score/lake-manifest.json` in `must_not_touch`;
- the observation that `decide` is stuck on `System.FilePath.fileName`, which is why `reads` works
  on `List Char`, and the owner decision on the quoted path (D6) with the number if it turns.

From the judge:
- `facts_kind` proved without naming the model's `Entry` type (`obtain ⟨e, -, rfl⟩`), so a model
  change that keeps kind and scope does not break it; checked with `#print axioms`;
- base commit 85981fe, line references re-read (`ci.yml:292-297`), the D3 card measured (F7), the
  eol check measured (check 6), and the edge record count re-run (F6).

Rejected:
- B's decoy `util/old-go.mod`. `not_reads_backup` and `not_reads_longer_name` hold the same rule
  in CI, and the card does not run there.
- B's `reads` as `FilePath.fileName` with no theorem. The fixture then holds the rule alone, and
  CI never sees it.
- B's flat names `Score.isGoMod` and `Score.goModFacts`. Each format would add two names to
  `Score`. A's `Score.<Format>.reads` and `.facts` scale by module.
- B's `if` inside the toy's own line. It rewrites a line P2-009a and P2-010 may also edit.
- B's label for a fork with no `replace` (`app → lib`, not `app → lib-fork`). It rests on a
  comment in the fork's file, where A's `replace` is something Go itself resolves.
- A's `// indirect` and `replace` on one requirement stay as they are. They are two defaults on one
  edge (D3), and F7 says what turning the first does.

### Tradeoffs accepted

- We accept a guard and a call on one line, read as the cell's "one call", in exchange for go.mod
  files that no other reader sees (W1, W5).
- We accept two public names, `reads` and `facts`, instead of one function returning an `Option`
  whose `none` would mean "not a go.mod file".
- We accept `reads` over `List Char`, a form the toy's helpers also use, instead of
  `System.FilePath.fileName`, in exchange for five cases the kernel checks.
- We accept `reads` as its definition plus five cases, not an `↔` theorem that restates the
  one-line definition.
- We accept two known misses in the fixture (a quoted path, a `replace`) in exchange for numbers
  that move when the model grows.
- We accept a scorecard that CI does not run until P2-012, in exchange for staying out of
  `.github/`.
- We accept the literal `"go-module"` in `facts_kind`, a second spelling of the model's string,
  because a mismatch fails the build.
- We accept that the toy reader still takes every non-go.mod file (R4), in exchange for a toy
  card that cannot move.

### Alternatives considered

- A1. Append the go.mod facts after the toy's (P2-007's call site as written). The toy reads every
  go.mod file, and four junk requirements reach the scorecard (W1).
- A2. Swap the toy's line for the go.mod facts. The toy fixture reads no requirement (W5).
- A3. A reader table in `Score.lean`: a `structure Reader` with `reads`, an extractor and an
  origin, and `factsOf` taking the first reader that reads the file, with the toy as the fallback.
  It is the deeper shape once a third format comes, but it rewrites `factsOf` and the toy's line,
  outside the cell, in the file P2-009a and P2-010 edit next. Revisit when a third reader arrives.
- A4. The toy limited to `*.toy` files, and the go.mod facts appended. Two calls, a changed rule for
  the Phase 1 reader in a go.mod row, and a toy file with another name would drop out unseen.
- A5. Real pinned go.mod files (D2). Nearly every requirement points out of the fixture, and the
  labels would say little.
- A6. go.mod repos inside `eval/fixtures/toy/`. One fixture with two edge types: the toy's header
  moves, P2-010's diff mixes two formats, and the toy is outside this row's cells.
- A7. `Score.GoMod.factsOf (f : SourceFile)`. `SourceFile` lives in `Score.lean`, which imports
  this module; moving it is a third edit to that file.
- A8. A fixture-level setting, a file `eval/fixtures/gomod/extractor`, read by `Main.lean`. It
  needs a new file format, and `Main.lean` is P2-010's.
- A9. Score `Models.GoMod.facts` in place of the plugin. The list is the same by `GoMod.run_eq`, and
  the scorer would measure the spec, not the accepted code.

### Open questions and risks

- Q1. A module that requires another module of its own repo gives a self-edge, because `matchesB`
  ignores repos. Should a label list it, or should the scorer leave self-edges out? The fixture
  has none until that is ruled.
- Q2. A label whose kind no fact has, such as `go-mod`, scores as a miss without an error. Should
  the scorer stop on it? That edits `Score.lean` beyond this cell, or P2-010's module.
- Q3. The go command ignores modules under `testdata/` and under directories whose names start
  with `.` or `_`; `reads` does not. It matters only on real repos, such as P2-008's pins. Should
  `reads` follow Go there?
- Q4. Should check 5 become a nightly step next to P2-012's Go refresh?
- Not verified: the run on CI's machine, and check 5 with a Go other than 1.24.7.

### Next implementation step

Run S1, write the fixture with F1's `printf` lines, then `Score/GoMod.lean` and the two lines in
`Score.lean`, then checks 1 to 4.

## Build notes

- Built the accepted design on `3fb20ca` with Lean v4.35.0 and Go 1.24.7. The S1 diff was
  empty. The implementation uses `List (Fact × Assumption)` in `Score.GoMod`, with the path
  guard at `factsOf` and the seven theorems beside their definitions.
- The scorer built without warnings. All seven `#print axioms` results contain only
  `propext`, `Classical.choice` and `Quot.sound`.
- The real CLI printed F2 with hash `889671a4d4c0eaed6b0680028ba965d63774aaaa48b7c070f860e3e5bade24cf`.
  It reports 15 facts, 6 predicted edges, 6 labels, 5 true positives, 1 false positive and
  1 miss. Precision and recall are both 0.83. The toy hash before and after is F3.
- Go's own `go mod edit -json` parse and L1 to L5 reproduce all six hand labels. All ten
  fixture hashes match F1. The quoted requirement and ignored `replace` remain measured gaps.
- The run log is `ops/runs/2026-11-15/P2-009b-builder-1.json`. Global checks and CI
  are recorded below when complete. The local
  bubblewrap probe cannot create a user namespace in this environment. Sandboxed checks
  retain their required policy and need CI evidence.
- Actual builder model is `gpt-6.1-sol` at high reasoning. The role table's Claude model
  names are unavailable in this environment. The user keeps the merge for this task.

## Done when
- [x] `mitos-score eval/fixtures/gomod` prints F2 at the head (check 4)
- [x] the toy scorecard is unchanged (check 3)
- [x] the labels agree with Go's parse (check 5), result in the PR body
- [ ] all `checks` pass locally, and `gate` is green
- [x] no `sorry`, no new axioms (checks 1 and 2)
- [x] run-log record written (ops/runs/)
