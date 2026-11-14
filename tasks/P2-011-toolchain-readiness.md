# tasks/P2-011-toolchain-readiness.md

phase: 2
goal: The next-toolchain canary passes on Lean v4.36 with every probe of the mutant runner still catching a known misread, and once v4.36.0 ships the repository is pinned to it with its records re-made.
statement: none locked (tooling task). `MitosGate.RunLog.sortLines_eq_of_perm` keeps its statement; PR B re-proves it without the deprecated lemmas.
touches: PR A (the probes): eval/mutants/Mutants/CrossCheck.lean, eval/mutants/Mutants/Output.lean, eval/mutants/Main.lean (the two probe loops of `leanCheck`), tasks/P1-006-mutation-testing.md (one note after each of its two Probes paragraphs) · PR B (the bump): lean-toolchain, eval/mutants/lean-toolchain, eval/score/lean-toolchain, examples/acme/lean-toolchain (and eval/diff/lean-toolchain once P2-008 has merged), any lake-manifest.json that Lake rewrites, examples/acme/accepted/*.json (re-recorded), gate/MitosGate/ContentId.lean (lines 44, 46, 49), the two version mentions in the gate 1 row of docs/process.md, the version mention in the docstring of gate/MitosGate/CheatsRun.lean, the Lean version in .coderabbit.yaml · both: this file, ops/runs/
must_not_touch: statements.lock (unless cut_line's lock case applies), models.lock, core/, eval/cheats/, models, .github/, eval/mutants/Mutants/Challenge.lean (the reader), eval/mutants/Mutants/CommentProbe.lean, eval/mutants/cases/, eval/score/, every gate/ file not named in touches
checks: PR A: build, `lake --dir eval/mutants build`, `lake --dir eval/mutants exe mitos-mutants src_dst_swapped edges_duplicated cheat_impl_macro`, one nightly dispatch on the branch · PR B: build, imports, lock, core `lake check`, comparator `--paranoid`, accept-toy `--paranoid --record`, scorecard, `mitos-lint-test`, cheats, `gate/*-test.sh`, the three mutant cases, one nightly dispatch on the branch
budget: PR A 8 iterations · 3h wall · 1M tokens; PR B 8 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

- Plan row P2-011 in `plan/phase-2.md`, issue #147. It is item 6 of "Before Phase 2 starts":
  recommended before P2-001a, never between two core PRs, and the bump lands after the release
  while no core PR is open. The owner merges what touches `gate/` or `lean-toolchain`.
- `touches` goes past the plan's Owns cell for this row. PR A also needs `Output.lean`, two loops
  of `Main.lean` and a note in P1-006's task file; PR B also needs three version mentions. The
  reason is under Diagnosis (7). The plan edit is the owner's; PR A starts once the owner has
  extended the cell.
- The probes come from P1-006, rounds 9 and 10 on #86 (`tasks/P1-006-mutation-testing.md`, "Lean
  cross-check (round 9)" and "Output check (round 10)"). The runner checks its hand-written line
  reader of the approved Challenge against Lean in three ways, and each check must catch a known
  misread in scratch sources every run, so a check that goes blind stops the runner.
- The canary is job `canary` of `.github/workflows/nightly.yml`. It points `lean-toolchain`,
  `examples/acme/lean-toolchain` and `eval/mutants/lean-toolchain` at the newest stable and rc
  above the pin, then runs `lake build`, core `lake check`, the comparator, the toy accept with
  `--paranoid`, `eval/cheats/run.sh` and `mitos-mutants` without `--paranoid`. It does not run
  `mitos-gate lock --check` or `mitos-lint-test`, and it does not build `eval/score`. CI does not
  build `eval/mutants` at all, so PR A's `gate` check says nothing about the probes.
- Roles (kitimark-mode table): PR A has no owner path and is routine against this sketch (sonnet,
  high), verified by opus at xhigh. PR B is trust-critical (`gate/`, `lean-toolchain`): opus at
  xhigh, verified by sonnet and by opus.
- Designed at plan time by one designer, with no arena and no Lean build. The type-check pass
  checks the sketches below against `main` before a builder starts.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. PR A's three files and PR B's three ContentId lines are sketched below in full; the
rest of PR B is a checklist with no new code. Not type-checked at design time.

revisit_when: PR A: none (it waits for no unmerged row). PR B: re-check when leanprover/lean4
publishes v4.36.0, and after #208 (P2-007, `accepted/GoMod.json`) or #209 (P2-008,
`eval/diff/lean-toolchain`) merges, since each adds a file the bump re-records or re-pins.

modules: one topic per file; no new file.
- PR A
  - `eval/mutants/Mutants/CrossCheck.lean`: the reader against Lean's build, and its probes. Adds
    `misreadLine`, `misread`, `hiddenIn` and the named probe lines; `Probe` loses its `lines` field
    for a function. About +25 and -20 lines. Layout: itself.
  - `eval/mutants/Mutants/Output.lean`: the parse and output checks, and their probes. New sources
    without the comment trick, `ParseProbe.lines` and `OutProbe.lines`, the `#guard`s that follow.
    About +30 and -30 lines. Layout: itself.
  - `eval/mutants/Main.lean`: the two probe loops of `leanCheck` read `p.lines`. About -6 lines.
  - `tasks/P1-006-mutation-testing.md`: one short note after each Probes paragraph.
- PR B
  - `gate/MitosGate/ContentId.lean`: three lemma names in `sortLines_eq_of_perm`.
  - the toolchain files, the records and the version mentions in `touches`.

types:
- `Mutants.CrossCheck.Probe := { path source : String, defs : List String, expect : List (String × String) }`
  (the `lines` field is gone)
- `Mutants.CrossCheck.misreadLine : String → Line`, `misread : String → List Line`
- `Mutants.CrossCheck.Probe.lines : Probe → List Line := misread ∘ source`
- `Mutants.CrossCheck.hiddenIn : String → String`
- `Mutants.Output.ParseProbe := { name source : String, expect : List (String × Nat) }`, with
  `ParseProbe.lines`
- `Mutants.Output.OutProbe := { path source : String, breaks : List String, expect : List (String × String) }`,
  with `OutProbe.lines`

statements: no new theorem. The fixtures are `#guard`s, like the files' others.
`sortLines_eq_of_perm` keeps its statement.

reuse: `readChallenge`, `importForm`, `theoremHole`, `sorrySuffix`, `holeName` (Mutants.Challenge);
`expected`, `problems`, `holeDecl`, `thmDecl`, `Probe.caught` (Mutants.CrossCheck); `declLines`,
`parseProblems`, `refutationGen`, `valuesGen`, `holesName`, `declKind`, `probeDefs`
(Mutants.Output); `Std.le_trans`, `Std.le_total`, `Std.le_antisymm` (Init); the canary as it is.

fixtures (names for this file; in Lean they are unnamed `#guard`s, as the file's others are):
- `probesAreMisreads`: for every cross-check, parse and output probe, `readChallenge` does not
  read its source as `misread` does (this replaces the old `[true, true, false]` guard).
- `decoyReaderKeeps`, `reverseReaderKeeps`: `readChallenge` keeps the hidden line as a comment
  line (index 4).
- `valueMisreadAsHole`: the value probe's lines are the list the old probe wrote by hand.
- `decoyExpected`: `expected` of the decoy's lines is the resolve hole at (3, 4) and the decoy at
  (5, 8).
- `decoyHiddenCaught` and `decoyLiveMissed`: against the declarations a correct build has, the
  decoy probe is caught with exactly `undeclared Mitos.Proofs.decoy`; against those of a build
  where the decoy is live (the mutant), it is not caught, so the runner would stop with "the
  cross-check missed a known misread". `reverseHiddenCaught` and `reverseLiveMissed` do the same
  for `Mitos.Impl.extra`.
- `b1Variable`, `b1Decls`, `b1ParseKeys`, `b1ParseDeclsOnly`, `b1Wants`, `b1Values`: b1's misread
  keeps the variable line, reads its holes and theorem at lines 3, 5 and 6, gives `command 4` and
  `missing 5` against Lean's commands, nothing against declarations alone, and the same `wants`
  and values as before.
- Runtime, every run: `probesCaught` (3, 5 and 2 probes caught). Once in PR A: `canaryRc` (a nightly
  dispatch on the branch) and the one-off mutants M1 to M3 (Done when).

cut_line: PR A ships now: the nine probes rebuilt on `misread`, and nothing else. It lands before
P2-001a (recommended) or after P2-001b, never between two core PRs (plan). PR B ships only when
(1) leanprover/lean4 has published v4.36.0, not an rc, (2) the canary for v4.36.0 has passed on
`main` after PR A, and (3) no core PR is open. Until then the bump is deferred, and #147 stays
open with this checklist. The three ContentId lines ride in PR B, because the deprecations are
warnings that fail no step (Diagnosis 5), so landing them alone would cost an owner merge and two
verdicts for no check. If the canary on v4.36.0 or on a later rc fails at a new step, that is a
new readiness round under #147 (a fresh PR owner with this file), not part of PR B. If
`lock --check` fails at v4.36.0, PR B stops and reports: a moved `statements.lock` is a spec
change, and the owner decides (`spec-approved`).

deferrals:
- Canary gaps (`.github/`, P2-012's path): the canary runs neither `mitos-gate lock --check` nor
  `mitos-lint-test` and builds neither `eval/score` nor, once P2-008 lands, `eval/diff`, so a bump
  can still surprise there. PR A reports the first three from an rc2 run by hand. To a
  `follow-up` issue the root files with PR A; P2-012 may take it as a ride-along if the owner adds
  it.
- CI never builds `eval/mutants`, so a PR that edits a probe has no CI signal for it. #107 items 2
  and 3 (P2-012) run `mitos-mutants --prepare` only on PRs that touch `core/`. To the same
  `follow-up` issue.
- Upstream: rc2's deprecation message on `String.le_*` names `Std.lt_irrefl`. Not filed; telling
  the Lean project is outside the repository (the owner's).
- A `CommentProbe` theorem for v4.36's opener (a doc comment's text may start with `--`): not
  planned. No probe depends on it, and if a later toolchain brings the v4.35 reading back, the
  checks stop the runner on the approved Challenge.
- From #147: nothing deferred.

owner_decisions:
- From the plan (#159, approved): P2-011 is item 6, recommended before P2-001a and never between two
  core PRs; the bump lands after the release while no core PR is open; the owner merges what
  touches `gate/` and `lean-toolchain`.
- From P1-006 round 9 (#86): the reader gets no new lexer rule. This design adds none.
- Waiting for the owner: the Owns-cell extension (Context). Defaults this design takes, which the
  owner can overrule: simulated misreads for the probes, and the deprecations in PR B.

### Diagnosis

Evidence:

1. The nightlies of 10 to 14 Nov 2026 all failed only in `canary (early warning) v4.36.0-rc2`,
   and `full` passed every time. The canary's error, from the first `lake build` of `leanCheck`:
   `Challenge/CrossCheckDecoy.lean:5:46: Unknown identifier Mitos.Impl.resolve`. Before it the 47
   cheat cases behaved as expected and `examples/acme` was accepted with `--paranoid`.
   `lake --dir eval/mutants build` also passed, so `Mutants.CommentProbe`'s four Lean facts hold
   on rc2.
2. Lean v4.35.0, `src/Lean/Parser/Term.lean`: `docComment` is
   `"/--" >> ppSpace >> … commentBody`, and `Command.lean`'s `moduleDoc` is `"/-!" >> … commentBody`.
   A symbol token's trailing whitespace is read by `whitespace`, which also consumes `--` line
   comments and plain block comments. So after a line `/--`, the line `-- -/` is skipped as
   whitespace, and the doc text starts on the line after it.
3. Lean v4.36.0-rc2, the same files: both use `docCommentOpen`, which keeps as the opener's
   trailing whitespace only the characters that satisfy `Char.isWhitespace`, because "the text of a
   documentation comment may begin with a comment marker". It came with lean4 PR 15064 ("rewrite the
   Verso docstring parser to produce accurate syntax", merged 18 Sep 2026, leanprover/lean4 commit
   1fae956). `finishCommentBlock` and `whitespace` are the same at both tags.
4. So on rc2 the decoy's `/--` closes at the `-/` of `-- -/` on line 4, where the reader
   (`leanScan`) closes it too, and line 5,
   `theorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry`, is live code.
   `Mitos.Impl.resolve` is declared only on line 7, hence the error at column 46. The real misread
   round 9 found is gone on v4.36: there Lean reads a doc comment's opener as the reader does.
5. rc2's `src/Init/Data/String/Lemmas/StringOrder.lean` deprecates `String.le_trans`, `le_total` and
   `le_antisymm` since 2026-10-09, with the message "Use `Std.lt_irrefl` instead" on every one of
   them, a slip in the attribute. Their bodies are `Std.le_trans`, `Std.le_total` and
   `Std.le_antisymm`. Those three exist with the same signatures at both tags
   (`src/Init/Data/Order/Lemmas.lean`), and `IsLinearOrder String` is an instance at both (v4.35.0
   `String.instIsLinearOrder`, rc2 `Compare.lean` by `.of_ord`). `Lemmas.lean`'s axiomatic
   instances turn it into `Trans`, `Antisymm` and `Total` for `≤`. The canary log shows the three
   warnings at `ContentId.lean:44:20`, `46:11` and `49:10`; they are warnings, and no step failed
   on them.
6. The release notes were not read. `RELEASES.md` points to the GitHub releases page, which this
   design session could not reach. The sources at the two tags, read from a clone, are the
   evidence instead.

Inference (from reading, not run):

7. Fixing the decoy alone does not make the canary pass. Nine of the ten probes rest on the v4.35
   opener, and the rest fail next on v4.36: the reverse probe builds and declares
   `Mitos.Impl.extra`, so the cross-check finds no difference; parse probe b1 finds `command 6` and
   `missing 8`, not `command 7`; parse probes namespace and exit, and output probe Exit, end in a
   doc comment with nothing after it, a parse error; parse probes decoy and reverse find no
   `missing 7`; output probe B1's `variable` sits in a line comment, so nothing differs. Only the
   value probe does not use the opener. Output's parse probes reuse `decoySource` and
   `reverseSource` (`Output.lean:319-320`), so a change to those in `CrossCheck.lean` alone would
   break the runner on v4.35.0 too. Hence `Output.lean` and `Main.lean` in `touches`.
8. `Std.le_trans`, `Std.le_total` and `Std.le_antisymm` elaborate for `String` on v4.35.0 through
   the instances in 5.
9. v4.36.0 keeps `docCommentOpen` (its docstring states the intent). Nothing below depends on it.
10. Once the probes build, the canary may show the next v4.36 difference. `src/Lean/Meta/Sorry.lean`
    is the same at both tags and `src/Lean/DeclarationRange.lean` only ignores a second write of a
    range, so `sorryOf` and `declOf` likely read rc2's builds as before.
11. In rc2 `String`'s order is defined on bytes, and `toList_lt_toList_iff` ties it to the order of
    the character lists, which is the same order for valid UTF-8, so `sortLines` and content ids
    sort as before.

### Usage (caller's view)

The runner is the caller, and its output does not change, on the pin and in the canary:

```
challenge (reader against Lean's build): AGREE on <n> declarations, 3 probes caught
challenge (reader against Lean's parse): AGREE on <n> commands, 5 probes caught
generated Challenges (as Lean built them): <n> state what they must, 2 probes caught (<s>s)
```

The canary's step summary reads `### canary v4.36.0-rc2: passed`.

A probe states only its source and what its check must find. What it misreads is
`misread source`: each line read alone, a `theorem Mitos.Proofs.… := sorry` line as a theorem, a
`def Mitos.… := sorry` line as a hole, an import as an import, and every other line as a comment
line, whatever comment it sits in or not. That is the shape of every misread rounds 6 to 10
found. A new cross-check probe:

```lean
{ path := "Challenge/CrossCheckX.lean", source := hiddenIn "def Mitos.Impl.x : String := sorry",
  defs := ["Mitos.Impl.x", "Mitos.Impl.resolve"], expect := [("undeclared", "Mitos.Impl.x")] }
```

`Main.lean` reads `p.lines` for all three probe kinds.

### Sketch, PR A

`eval/mutants/Mutants/CrossCheck.lean`, from `structure Probe` to the last probe `#guard`.
Everything above it is unchanged, and so are the two `#guard`s on `problems` at the end of the
file.

```lean
structure Probe where
  path   : String
  source : String
  defs   : List String
  expect : List (String × String)
  deriving Inhabited

def misreadLine (l : String) : Line :=
  let cs := l.toList
  if importForm cs then .imp l
  else if "def Mitos.".toList.isPrefixOf cs && sorrySuffix.isSuffixOf cs then .hole l
  else match theoremHole cs with
    | some (n, s) => .thm n s l
    | none => .keep l

def misread (src : String) : List Line := (src.splitOn "\n").map misreadLine

def Probe.lines (p : Probe) : List Line := misread p.source

def resolveHole : String := "def Mitos.Impl.resolve : Mitos.Resolver := sorry"
def decoyLine : String := "theorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry"
def extraHole : String := "def Mitos.Impl.extra : String := sorry"

def hiddenIn (line : String) : String := s!"import Mitos.Core\n\n{resolveHole}\n/-\n{line}\n-/\n"

def decoySource : String := hiddenIn decoyLine
def reverseSource : String := hiddenIn extraHole

def valueLine : String := "def Mitos.Impl.f : Nat → Nat | _ => 0 where g : Nat := sorry"

def probes : List Probe := [
  { path := "Challenge/CrossCheckDecoy.lean", source := decoySource,
    defs := ["Mitos.Impl.resolve"], expect := [("undeclared", "Mitos.Proofs.decoy")] },
  { path := "Challenge/CrossCheckReverse.lean", source := reverseSource,
    defs := ["Mitos.Impl.extra", "Mitos.Impl.resolve"],
    expect := [("undeclared", "Mitos.Impl.extra")] },
  { path := "Challenge/CrossCheckValue.lean", source := s!"import Mitos.Core\n\n{valueLine}\n",
    defs := ["Mitos.Impl.f"],
    expect := [("differs", "Mitos.Impl.f"), ("unread", "Mitos.Impl.f.g")] }]

def Probe.caught (p : Probe) (imps : List String) (ds : List Decl) : Bool :=
  let found := (problems p.lines p.defs imps ds).map (·.key)
  p.expect.all found.contains

#guard probes.all fun p => (readChallenge p.source).toOption != some p.lines
#guard (readChallenge decoySource).toOption.map (·[4]?) == some (some (.keep decoyLine))
#guard (readChallenge reverseSource).toOption.map (·[4]?) == some (some (.keep extraHole))
#guard (readChallenge s!"import Mitos.Core\n\n{valueLine}\n").toOption == none
#guard probes[2]!.lines == [.imp "import Mitos.Core", .keep "", .hole valueLine, .keep ""]

#guard expected (probes.head!.lines) ==
  [holeDecl 3 resolveHole, thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve"]
#guard (thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve").kind ==
  .thm (some ["Mitos.Spec.Sound", "Mitos.Impl.resolve"])
#guard holeName valueLine == "Mitos.Impl.f"
#guard holeNames (probes.head!.lines) == ["Mitos.Impl.resolve"]
#guard importNames (probes.head!.lines) == ["Mitos.Core"]

#guard (problems (probes.head!.lines) ["Mitos.Impl.resolve"] ["Init", "Mitos.Core"]
    [holeDecl 3 resolveHole]).map (·.key) == [("undeclared", "Mitos.Proofs.decoy")]
#guard !probes.head!.caught ["Init", "Mitos.Core"]
    [holeDecl 3 resolveHole, thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve"]
#guard probes[1]!.caught ["Init", "Mitos.Core"] [holeDecl 3 resolveHole]
#guard !probes[1]!.caught ["Init", "Mitos.Core"] [holeDecl 3 resolveHole, holeDecl 5 extraHole]
```

`eval/mutants/Mutants/Output.lean`, from `hiddenVariableSource` to the end. `probeDefs`, the
`#guard` on `parseProblems` with a `prelude` header, and the two `#guard`s on `outProblems` are
unchanged; the other probe `#guard`s are replaced by these.

```lean
def variableLine : String := "variable (h : False) in include h in"
def impactHole : String := "def Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry"
def totalLine : String :=
  "theorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry"

def hiddenVariableSource : String :=
  s!"import Mitos.Core\n\n{resolveHole}\n{variableLine}\n{impactHole}\n{totalLine}\n"

def trailingSource (code : String) : String :=
  s!"import Mitos.Core\n\n{resolveHole}\n{impactHole}\n{totalLine}\n{code}\n"

def probeDefs : List String := ["Mitos.Impl.resolve", "Mitos.Impl.impact"]

structure ParseProbe where
  name   : String
  source : String
  expect : List (String × Nat)

def ParseProbe.lines (p : ParseProbe) : List Line := misread p.source

def parseProbes : List ParseProbe := [
  { name := "b1", source := hiddenVariableSource, expect := [("command", 4), ("missing", 5)] },
  { name := "namespace", source := trailingSource "namespace Mitos.Impl", expect := [("command", 6)] },
  { name := "exit", source := trailingSource "#exit", expect := [("command", 6)] },
  { name := "decoy", source := decoySource, expect := [("missing", 5)] },
  { name := "reverse", source := reverseSource, expect := [("missing", 5)] }]

structure OutProbe where
  path   : String
  source : String
  breaks : List String
  expect : List (String × String)

def OutProbe.lines (p : OutProbe) : List Line := misread p.source

def outProbes : List OutProbe := [
  { path := "Challenge/OutputProbeB1.lean", source := hiddenVariableSource, breaks := ["resolve_total"],
    expect := [("differs", "Mitos.Refute.resolve_total")] },
  { path := "Challenge/OutputProbeExit.lean", source := trailingSource "#exit",
    breaks := ["resolve_total"], expect := [("missing", holesName)] }]

#guard parseProbes.all fun p => (readChallenge p.source).toOption != some p.lines
#guard outProbes.all fun p => (readChallenge p.source).toOption != some p.lines
#guard (misread hiddenVariableSource)[3]? == some (.keep variableLine)
#guard declLines (misread hiddenVariableSource) == [(3, resolveHole), (5, impactHole), (6, totalLine)]

#guard (parseProblems (misread hiddenVariableSource) [] ["Mitos.Core"] [
      { line := 3, col := 0, kind := declKind, text := resolveHole },
      { line := 4, col := 0, kind := "Lean.Parser.Command.in", text := variableLine },
      { line := 6, col := 0, kind := declKind, text := totalLine }]).map (·.key) ==
  [("command", 4), ("missing", 5)]
#guard parseProblems (misread hiddenVariableSource) [] ["Mitos.Core"]
    ((declLines (misread hiddenVariableSource)).map fun (i, t) =>
      { line := i, col := 0, kind := declKind, text := t }) == []

#guard (refutationGen [] probeDefs (misread hiddenVariableSource) ["resolve_total"]).toOption.map
    (·.wants) ==
  some [(holesName, .holes probeDefs), ("Mitos.Refute.resolve_total", .negated "resolve_total")]
#guard (valuesGen ["Mitos.Impl.Resolve"] (misread hiddenVariableSource)).toOption.map
    (fun g => (g.wants, g.imports)) ==
  some ([("Mitos.Proofs.resolve_total", .stated "resolve_total")], ["Mitos.Impl.Resolve", "Mitos.Core"])
```

`eval/mutants/Main.lean`, `leanCheck`. The two places that read a probe's source with
`readChallenge` (and throw on its error) read `p.lines`:

```lean
  let outProbes ← Output.outProbes.mapM fun p => do
    match Output.refutationGen a.impls Output.probeDefs p.lines p.breaks with
    | .ok g => pure (p, g, s!"{moduleOf p.path |>.replace "." "/"}Gen.lean")
    | .error e => throw s!"{p.path}: {e}"
```

```lean
    for p in Output.parseProbes do
      let (h, i, c) ← parsed p.source
      let found := (Output.parseProblems p.lines h i c).map (·.key)
      unless p.expect.all found.contains do
        throw s!"the parse check missed a known misread in probe {p.name}: expected {p.expect}, found {found}"
```

The cross-check loop already reads `p.lines` (through `p.caught` and `problems p.lines`) and is
unchanged.

`tasks/P1-006-mutation-testing.md`. After the round 9 Probes paragraph (the one that says "The
first two lists of lines are what `readChallenge` reads"):

> Amended by P2-011 (#147). Lean v4.36 (lean4 PR 15064) reads a doc comment's opener as the reader
> does, so there the decoy and the reverse are no misreads of `readChallenge`, and the decoy's
> theorem is live code that does not build. Each probe now reads its source with
> `CrossCheck.misread`, which reads every line alone, as the misreads of rounds 6 to 10 did. The
> decoy and the reverse hide their line in a plain block comment, which every toolchain and the
> reader read alike, and a `#guard` pins that `readChallenge` reads no probe as its probe does.

After the round 10 Probes paragraph:

> Amended by P2-011 (#147): these seven probes read their sources with `CrossCheck.misread` too,
> and each source holds its command on a line of its own, with no comment around it. The expected
> problems are in P2-011's task file.

### Sketch, PR B

`gate/MitosGate/ContentId.lean`, `sortLines_eq_of_perm` (lines 44, 46 and 49 change):

```lean
theorem sortLines_eq_of_perm {l₁ l₂ : List String} (h : l₁.Perm l₂) :
    sortLines l₁ = sortLines l₂ := by
  have trans : ∀ a b c : String, decide (a ≤ b) = true → decide (b ≤ c) = true →
      decide (a ≤ c) = true := fun _ _ _ hab hbc =>
    decide_eq_true (Std.le_trans (of_decide_eq_true hab) (of_decide_eq_true hbc))
  have total : ∀ a b : String, (decide (a ≤ b) || decide (b ≤ a)) = true := fun a b => by
    rcases Std.le_total (a := a) (b := b) with h | h <;> simp [h]
  apply List.Perm.eq_of_pairwise (le := fun a b => decide (a ≤ b) = true)
  · intro a b _ _ hab hba
    exact Std.le_antisymm (of_decide_eq_true hab) (of_decide_eq_true hba)
  · exact List.pairwise_mergeSort trans total _
  · exact List.pairwise_mergeSort trans total _
  · exact (List.mergeSort_perm _ _).trans (h.trans (List.mergeSort_perm _ _).symm)
```

If an instance is not found on v4.35.0, use the class fields, the same at both tags:
`Std.IsPreorder.le_trans _ _ _ h₁ h₂`, `Std.IsLinearPreorder.le_total a b` and
`Std.IsPartialOrder.le_antisymm _ _ h₁ h₂`. The code and the ids do not change; only the proof
does, so `gate/content-id-test.sh` and `gate/carry-test.sh` pass unchanged.

The bump, in order, at the head after the last rebase:

1. Preconditions: the three in cut_line.
2. Write `leanprover/lean4:v4.36.0` into `lean-toolchain`, `eval/mutants/lean-toolchain`,
   `eval/score/lean-toolchain`, `examples/acme/lean-toolchain`, and `eval/diff/lean-toolchain` if
   it exists.
3. The three ContentId lines above.
4. `lake build`, `lake exe mitos-gate imports`, `lake exe mitos-gate lock --check`,
   `cd core && lake check && lake comparator --paranoid`. Commit whatever `lake-manifest.json`
   Lake rewrites, and nothing by hand. `lake build` shows no `has been deprecated` line.
5. If `lock --check` fails, stop and report (cut_line).
6. `lake exe mitos-lint-test`: the scoped-token recheck that the gate 1 row of `docs/process.md`
   asks for at every bump, and the `Child.kill` timeout cases. Then change "v4.35.0" to "v4.36.0"
   in that row's two sentences, in `CheatsRun.lean`'s docstring and in `.coderabbit.yaml`.
7. Re-record each `examples/acme/accepted/*.json`:
   `lake exe mitos-gate accept --workspace examples/acme --plugin ToyRequire --model Models.ToyRequire.model --paranoid --record`,
   and the same for `GoMod` if `accepted/GoMod.json` exists.
8. `lake --dir eval/score build && lake --dir eval/score exe mitos-score eval/fixtures/toy`;
   `lake --dir eval/mutants build` and the three mutant cases.
9. Push, then one nightly dispatch on the branch: `full` runs paranoid mutation testing on the new
   pin, and the canary tries anything newer. The PR body says `Closes #147`.

### Probe by probe

| Check | Probe | v4.35.0 today | v4.36.0-rc2 today | After PR A, both toolchains |
|---|---|---|---|---|
| cross-check | decoy | `undeclared Mitos.Proofs.decoy` | build error at 5:46 (evidence) | the decoy in `/-` … `-/` after the hole: `undeclared Mitos.Proofs.decoy` |
| cross-check | reverse | `undeclared Mitos.Impl.extra` | missed, `extra` is declared (inference) | `extra` hidden the same way: `undeclared Mitos.Impl.extra` |
| cross-check | value | `differs Mitos.Impl.f`, `unread Mitos.Impl.f.g` | likely unchanged | unchanged |
| parse | b1 | `command 7` | missed: `command 6`, `missing 8` | `variable … in` on line 4: `command 4`, `missing 5` |
| parse | namespace | `command 9` | parse error: a doc comment with nothing after it | the command on line 6: `command 6` |
| parse | exit | `command 9` | the same | `#exit` on line 6: `command 6` |
| parse | decoy | `command 3`, `missing 5`, `missing 7` | missed: no `missing 7` | `missing 5` |
| parse | reverse | the same | the same | `missing 5` |
| output | B1 | `differs Mitos.Refute.resolve_total` | missed: the `variable` is in a line comment | the same expectation, the `variable` on line 4 |
| output | Exit | `missing Mitos.Refute.holes` | the probe does not build | the same expectation, `#exit` on line 6 |

Every kind of problem the probes pinned is still pinned: `undeclared` for a theorem and for a hole,
`differs` and `unread` (cross-check); `command` and `missing` (parse); `differs` and `missing`
(output). b1 now pins `missing` too. Parse probes decoy and reverse no longer pin `command 3` and
`missing 7`, which came from the doc comment taking in the hole on line 7; b1, namespace and exit
pin `command`. The checks themselves (`problems`, `parseProblems`, `outProblems`, `readParse`,
`built`, `declOf`) do not change. If a verifier still calls a changed expectation a weakened check,
PR A goes to the owner instead of an agent merge.

### Rationale

**Problem.** The mutant runner reads the approved Challenge with a hand-written line reader and
checks that reading against Lean in three ways. Each check shows it is not blind by catching a
known misread in scratch sources every run. Nine of those ten misreads come from one Lean
behavior: in v4.35.0 a doc comment's opener swallows the line comments after it. Lean v4.36 reads
the opener as the reader does, so the misreads vanish, their sources go live, and the runner
stops. Every check's probe must keep biting on both toolchains while the pin moves, with no check
weakened and no new lexer rule.

**Shape.** Data first. A probe is a Lean source and the problems its check must find. What it
misreads is derived: `misread source`, one deliberately naive reading (each line alone, the
declaration forms by their text, every other line a comment line). Each source hides or shows code
only with constructs that every toolchain and the reader read alike: a plain block comment for the
decoy and the reverse, a live line for b1, namespace and exit. No probe has anything
toolchain-specific left. The surface shrinks: `Probe` loses its `lines` field, and `Main.lean`
reads `p.lines` for all three probe kinds instead of calling the reader, and handling its errors,
for two of them. Each probe has one source of truth, its source, so there is no hand-synced list
of lines (design-red-flags, "Hand-synced list").

**Synthesis decision.** One designer, no arena. Base: B, the derived `misread`. From A, explicit
lines per probe, it keeps one idea: fixtures that pin what each probe misreads (`decoyExpected`,
`b1Decls`, `b1ParseKeys`), so a reader sees the misread without running `misread` in their head.

**Tradeoffs accepted.**
- We accept probes whose misread is simulated rather than a real bug of `readChallenge`, in
  exchange for probes that pass on every toolchain. On v4.36 no form the reader accepts is known
  to be misread, so no real misread is left to pin, and the guard that pinned realism
  (`[true, true, false]`) becomes one that pins the opposite for all ten probes.
- We accept that on v4.35.0, until the bump, the real opener misread still exists and no probe
  uses it, in exchange for one probe set. The checks still stop the runner on it in the approved
  Challenge, as round 9 showed.
- We accept a second, deliberately wrong reader in the code, `misread`, named for what it is and
  used only by probes.
- We accept that the bump waits for the release, and that the canary log keeps three deprecation
  warnings until then.

**Alternatives considered.**
- A: explicit `lines` per probe, plus a guard that their texts are the source's lines. It behaves
  the same, but every probe's text is written twice, and a new probe needs both; B derives the
  reading.
- Version-gated probes: keep the real misreads on v4.35 and simulated ones on v4.36, chosen by
  `Lean.versionString` or by asking Lean's parser at run time. Two ways to do one task, dead
  after the bump, and the canary would test a different probe set from the pin.
- Make the reader refuse the opener forms on which the two toolchains differ: a new lexer rule,
  which round 9 ruled out, and it would leave no real misread for the probes anyway.
- Drop the opener probes and rely on the checks of the approved Challenge: that removes the proof
  that the checks are not blind, a weakening and so the owner's call, and nothing needs it.
- Keep the old sources and put the resolve hole first, so the live decoy builds on v4.36: then
  v4.36 declares the decoy, the cross-check agrees, and the probe is missed. It trades a build
  error for a "missed" message.

**Open questions and risks.**
- Does the owner extend the Owns cell (Context)? Without `Output.lean` the canary cannot pass.
- Does `statements.lock` move at v4.36? The canary does not run `lock --check`. PR A reports it
  from an rc2 run, and if it moves, PR B needs `spec-approved`.
- Once the probes build, the dispatch run may show the next v4.36 difference (Diagnosis 10). In
  `eval/mutants`, and not weakening a check: PR A fixes it. Anywhere else: stop and report.
- `include h in` before a `def` (b1 and B1) builds on v4.35.0 today. Whether v4.36 still includes
  `h` shows only in the dispatch run.

**Next implementation step.** In `CrossCheck.lean`, add `misreadLine`, `misread` and `hiddenIn`,
replace the `lines` field of `Probe` by the function, and get `lake --dir eval/mutants build`
green on v4.35.0 with the cross-check `#guard`s above.

## Done when
- [ ] PR A merged by agents after a passing verdict: on v4.35.0 `lake --dir eval/mutants build`
      passes with every `#guard` above, and
      `lake --dir eval/mutants exe mitos-mutants src_dst_swapped edges_duplicated cheat_impl_macro`
      prints the three probe lines with 3, 5 and 2 probes caught and the three cases as expected
      (2 refuted, 0 known gaps, 1 cheat rejected); the PR body says `Part of #147`
- [ ] one nightly dispatch on PR A's branch: `full` passed, and the canary on v4.36.0-rc2 (or the
      newest rc then) passed, with no `has been deprecated` line but ContentId's three
- [ ] the one-off mutants, one local run each on v4.35.0, in PR A's body. M1, a live decoy:
      `hiddenIn` with `--` lines in place of `/-` and `-/`; as is, the build fails on
      `probesAreMisreads`; with that guard and `decoyReaderKeeps` and `reverseReaderKeeps`
      removed, the runner exits 2 with `the cross-check missed a known misread in
      Challenge/CrossCheckDecoy.lean`. M2: `variableLine` as `-- variable (h : False) in include h
      in`, and `probesAreMisreads` removed for the parse and output probes: exit 2 with `the parse
      check missed a known misread in probe b1`. M3: M2 with b1 also left out of `parseProbes`:
      exit 2 with `the output check missed a known misread in Challenge/OutputProbeB1.lean`
- [ ] report only, in PR A's body: `lake exe mitos-gate lock --check`, `lake exe mitos-lint-test`
      and `lake --dir eval/score build` on v4.36.0-rc2, in a scratch copy with the toolchain files
      pointed at it as the canary does, so the owner knows before the bump whether
      `statements.lock`, the lint's token premise or the scorer moves
- [ ] the `follow-up` issue for the canary and CI gaps (deferrals) filed and linked from PR A
- [ ] PR B merged by the owner after v4.36.0 ships and its canary passed on `main`: every
      `lean-toolchain` reads `leanprover/lean4:v4.36.0`, `accepted/*.json` re-recorded at the
      head, no deprecation warning, CI green, a nightly dispatch on the branch passed `full`, the
      version mentions updated; the PR body says `Closes #147`
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written for each attempt (`ops/runs/<UTC date>/P2-011-builder-<attempt>.json`)
