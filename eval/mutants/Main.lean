import Lean.Data.Json
import Mutants

/-!
# `mitos-mutants`: the mutant runner

Run from the repository root: `lake --dir eval/mutants exe mitos-mutants [--paranoid] [<case>...]`.

First it checks, with Lean, its reading of the approved Challenge and every Challenge it will
generate: the approved Challenge as Lean builds it (`Mutants.CrossCheck`) and as Lean's parser
reads it, and each generated Challenge as Lean builds it (`Mutants.Output`); it stops on any
difference. For each case in `eval/mutants/cases/`, it applies the case's edits to a copy of
`core/` (sources only, no build outputs), lints the case's Lean text (`Mutants.Lint`), and judges
it with the sandboxed `lake comparator`, as `Mutants.Verdict` describes: the hole run, the gate's
run, then the values or the refutation run. Each run gets a fresh copy, which is removed
afterwards. The pure parts (manifest, edits, lint decisions, the generated Challenges and solution
modules, the comparisons with Lean's build and parse, verdict) are in `Mutants/` with their proofs;
this file only reads, parses, writes and runs.
-/

open Mutants Lean

def usage : String := "usage: mitos-mutants [--paranoid] [--keep] [<case>...]
       mitos-mutants --prepare <dir> <case>...
  Run from the repository root. Lints each case's Lean text, then judges every case in
  eval/mutants/cases/, or the named ones, with the sandboxed lake comparator. --paranoid also runs
  the external kernels. --keep keeps the workspaces. Logs go to .lake/mutants/. Exit 0: every case
  as expected; 1: not; 2: could not run.
  --prepare writes each named case's workspaces to <dir>/<case>/ (refutation or values run) and
  <dir>/<case>.holes/ (hole run), and judges nothing; it writes none for a case the lint refuses.
  REFUSED BY LINT: the case's Lean text holds code that runs or declares syntax while Lean
  elaborates it, imports a module outside the approved core and the implementation, or declares,
  enters or opens a name outside the namespaces it may use.
  UNBOUND: the mutant's implementation alone does not build the approved definition holes, or the
  gate accepts proofs that are not about them.
  Before anything else, it builds the approved Challenge and compares what Lean declares in it
  and how Lean's parser reads it with what its line reader read, and it builds every Challenge it
  will generate for the cases and compares what Lean declares in each with what it must state; any
  difference stops it (exit 2)."

structure Config where
  paranoid : Bool := false
  keep     : Bool := false
  prepare  : Option System.FilePath := none
  cases    : List String := []

def parseArgs : List String → Config → Except String Config
  | [], c => .ok c
  | "--paranoid" :: rest, c => parseArgs rest { c with paranoid := true }
  | "--keep" :: rest, c => parseArgs rest { c with keep := true }
  | "--prepare" :: d :: rest, c => parseArgs rest { c with prepare := some d }
  | a :: rest, c =>
    if a.startsWith "-" then .error s!"unknown option {a}" else parseArgs rest { c with cases := c.cases ++ [a] }

/-- Text from a case or from Lean, on one line: control, line-separator and bidi characters are
written as `\u{XXXX}`. -/
def clean (s : String) : String :=
  String.join <| s.toList.map fun c =>
    let n := c.toNat
    if n < 0x20 || (0x7F ≤ n && n ≤ 0x9F) || (0x200B ≤ n && n ≤ 0x200F) || (0x2028 ≤ n && n ≤ 0x202E) ||
        (0x2066 ≤ n && n ≤ 0x2069) || n == 0xFEFF || c == '\\' then
      s!"\\u\{{String.ofList (Nat.toDigits 16 n)}}"
    else c.toString

/-- Every file under `core/` but build outputs, by its path relative to `core/`. -/
def coreFiles (core : System.FilePath) : IO (List (String × String)) := do
  let paths ← core.walkDir fun p => pure (p.fileName != some ".lake")
  let mut out := #[]
  for p in paths do
    if ← p.isDir then continue
    let rel := (p.toString.drop (core.toString.length + 1)).toString
    out := out.push (rel, ← IO.FS.readFile p)
  return (out.qsort (·.1 < ·.1)).toList

/-- A fresh workspace with `files`, judged once by `lake comparator`, then removed. -/
def judge (cfg : Config) (toolchain : String) (files : List (String × String))
    (config : Option String) (log : System.FilePath) : IO Run := do
  let dir ← IO.FS.createTempDir
  try
    IO.FS.writeFile (dir / "lean-toolchain") toolchain
    for (rel, txt) in files do
      if let some p := (dir / rel).parent then IO.FS.createDirAll p
      IO.FS.writeFile (dir / rel) txt
    let args := #["comparator"] ++ (config.map (#[s!"--config={·}"])).getD #[] ++
      (if cfg.paranoid then #["--paranoid"] else #[])
    (← IO.getStdout).flush
    let out ← IO.Process.output { cmd := "lake", args, cwd := dir }
    let text := out.stdout ++ out.stderr
    IO.FS.writeFile log s!"$ lake {" ".intercalate args.toList}\nexit {out.exitCode}\n{text}"
    return Run.ofExit out.exitCode text
  catch e =>
    IO.FS.writeFile log s!"could not run lake comparator: {e}"
    return .failed
  finally
    if cfg.keep then IO.println s!"  (workspace kept: {dir})" else IO.FS.removeDirAll dir

/-- The approved inputs every case is judged against. -/
structure Approved where
  toolchain  : String
  files      : List (String × String)
  config     : Json
  /-- The Challenge module, as `core/comparator.json` names it. -/
  chalModule : String
  challenge  : List Line
  theorems   : List String
  /-- The approved configuration's definition holes. -/
  defs       : List String
  /-- The implementation modules: every module under `Mitos/Impl/` of the approved core. A case's
  edits change no path (`Mutants.applyEdits_paths`), so these are every case's too. -/
  impls      : List String
  /-- The texts of the generated Challenges the output check passed (`Mutants.Output`); `prepare`
  writes no other. -/
  checked    : List String := []

def strs (xs : List String) : Json := Json.arr (xs.toArray.map Json.str)

/-- The hole run's configuration: the approved Challenge, definition holes and permitted axioms,
no theorem, and the generated module that imports every implementation module as the solution. -/
def holesConfig (a : Approved) : String :=
  ((a.config.setObjVal! "solution_module" (.str "Mitos.Proofs.Holes")).setObjVal!
    "theorem_names" (strs [])).pretty

/-- The values run's configuration: the approved one with the approved Challenge by value
(`Mutants.approvedByValue`), so no definition holes. -/
def valuesConfig (a : Approved) : String :=
  ((a.config.setObjVal! "challenge_module" (.str "Challenge.Mutant")).setObjVal!
    "definition_names" (strs [])).pretty

/-- The refutation configuration: the generated Challenge, the generated solution module
(`Mutants.refutationSolution`), `Mitos.Refute.holes` and the refuted theorems, no definition holes;
the permitted axioms stay as approved. -/
def refutationConfig (a : Approved) (ts : List String) : String :=
  let names := Output.refutationNames a.defs ts
  ((((a.config.setObjVal! "challenge_module" (.str "Challenge.Mutant")).setObjVal!
    "solution_module" (.str "Mitos.Proofs.Refute")).setObjVal! "theorem_names" (strs names)).setObjVal!
    "definition_names" (strs [])).pretty

def generated : List String :=
  ["Challenge/Mutant.lean", "Mitos/Proofs/Holes.lean", "Mitos/Proofs/Refute.lean",
    "Mitos/Proofs/RefuteCase.lean", "holes.json", "values.json", "mutant.json"]

/-- A case, ready to judge: its manifest, the hole run's workspace, the mutated core for the gate's
run, the files the values run adds to it, and for a `breaks=` case the files the refutation run
adds to it. -/
structure Prepared where
  mutant     : Mutant
  /-- What the lint found in the case's Lean text (`Mutants.Lint`); nothing is built unless it is
  empty. -/
  lint       : List String
  holes      : List (String × String)
  approved   : List (String × String)
  values     : List (String × String)
  refutation : Option (List (String × String))

/-- What the lint finds in a case's Lean text: each `replace=` text as plain text, each file the
edits change as a whole (`Lint.targets`), and the case's `Refute.lean`, which may declare the
approved definition holes `defs` besides names under `Mitos.Refute`. -/
def lintCase (env : Environment) (m : Mutant) (files : List (String × String))
    (refute : Option String) (defs : List String) : ExceptT String IO (List String) := do
  let mut found := #[]
  for e in m.edits do
    for w in Lint.replaceProblems e.replace do
      found := found.push s!"mutant: replace= in {e.file}: {w}"
  for (p, k) in Lint.targets m do
    let some txt := files.lookup p | throw s!"{p}: no such file in core/"
    found := found ++ (← Lint.check env k s!"core/{p} (edited)" txt)
  if let some src := refute then
    found := found ++ (← Lint.check env (.refute (defs.map (·.splitOn "."))) "Refute.lean" src)
  return found.toList

def prepare (env : Environment) (a : Approved) (casesDir : System.FilePath) (name : String) :
    ExceptT String IO Prepared := do
  let dir := casesDir / name
  unless ← dir.isDir do throw "no such case directory"
  unless ← (dir / "mutant").pathExists do throw "no mutant file"
  let m ← match parse (← IO.FS.readFile (dir / "mutant")) with
    | .ok m => pure m
    | .error e => throw s!"mutant: {e}"
  let wants := match m.expect with
    | .breaks _ => ["Refute.lean", "mutant"]
    | .survives _ => ["mutant"]
  let have_ := ((← dir.readDir).map (·.fileName)).qsort (· < ·) |>.toList
  if have_ != wants then throw s!"holds {have_}, expected {wants}"
  if let some g := generated.find? fun g => a.files.any (·.1 == g) then
    throw s!"core/{g} exists; the runner writes that path"
  let files ← match applyEdits a.files m.edits with
    | .ok fs => pure fs
    | .error e => throw e
  let refuteSrc ← match m.expect with
    | .breaks _ => some <$> IO.FS.readFile (dir / "Refute.lean")
    | .survives _ => pure none
  -- Before anything is built: the case's Lean text runs no code and declares no syntax.
  let lint ← lintCase env m files refuteSrc a.defs
  -- The hole run's core: no `Mitos/Proofs/`, no file of the case, only the implementation edits
  -- (`Mutants.holeCore_spec`).
  let core ← match holeCore a.files m with
    | .ok fs => pure fs
    | .error e => throw e
  let holes := core ++ [("Mitos/Proofs/Holes.lean", holesSolution (core.map (·.1))),
    ("holes.json", holesConfig a)]
  -- The generated Challenges import the mutated implementation, so the comparator compares the
  -- holes by value. Each is a text the output check passed, as Lean built it.
  let checked (g : Except String Output.Gen) : ExceptT String IO String := do
    let g ← match g with
      | .ok g => pure g
      | .error e => throw e
    unless a.checked.contains g.text do throw s!"{g.what} was not checked as Lean builds it"
    return g.text
  let byValue ← checked (Output.valuesGen a.impls a.challenge)
  let values := [("Challenge/Mutant.lean", byValue), ("values.json", valuesConfig a)]
  match m.expect with
  | .survives _ => return { mutant := m, lint, holes, approved := files, values, refutation := none }
  | .breaks ts =>
    let chal ← checked (Output.refutationGen a.impls a.defs a.challenge ts)
    let extra := [("Challenge/Mutant.lean", chal),
      ("Mitos/Proofs/RefuteCase.lean", refuteSrc.getD ""),
      ("Mitos/Proofs/Refute.lean", refutationSolution a.defs),
      ("mutant.json", refutationConfig a ts)]
    return { mutant := m, lint, holes, approved := files, values, refutation := some extra }

/-- A case's log files, newest run first. -/
def caseLogs (logDir : System.FilePath) (name : String) : List System.FilePath :=
  ["refutation", "values", "approved", "holes"].map fun s => logDir / s!"{name}.{s}.log"

def runCase (cfg : Config) (env : Environment) (a : Approved) (casesDir logDir : System.FilePath)
    (name : String) : IO Judged := do
  -- Logs from an earlier run must not be read as this one's.
  for log in caseLogs logDir name do
    if ← log.pathExists then IO.FS.removeFile log
  let p ← match ← (prepare env a casesDir name).run with
    | .ok p => pure p
    | .error e => return .invalid e
  let ran := Judged.ran p.mutant.expect p.mutant.rejects
  -- A case the lint finds anything in is not built at all.
  unless p.lint.isEmpty do return ran { lint := p.lint }
  let holes ← judge cfg a.toolchain p.holes (some "holes.json") (logDir / s!"{name}.holes.log")
  if holes != .accepted then return ran { holes }
  let approved ← judge cfg a.toolchain p.approved none (logDir / s!"{name}.approved.log")
  match approved with
  | .accepted =>
    let values ← judge cfg a.toolchain (p.approved ++ p.values) (some "values.json")
      (logDir / s!"{name}.values.log")
    return ran { holes, approved, values }
  | .rejected =>
    let some extra := p.refutation | return ran { holes, approved }
    let refutation ← judge cfg a.toolchain (p.approved ++ extra) (some "mutant.json")
      (logDir / s!"{name}.refutation.log")
    return ran { holes, approved, refutation }
  | .failed => return ran { holes, approved }

def writeFiles (toolchain : String) (dir : System.FilePath) (files : List (String × String)) :
    IO Unit := do
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "lean-toolchain") toolchain
  for (rel, txt) in files do
    if let some d := (dir / rel).parent then IO.FS.createDirAll d
    IO.FS.writeFile (dir / rel) txt

/-- The Challenges the runner will judge with for `cases` (`Mutants.Output`): the values
Challenge, and the refutation Challenge of each distinct `breaks=` list, once per distinct text. A
case whose manifest cannot be read or whose refutation cannot be generated adds none; `prepare`
finds it invalid. -/
def generatedFor (a : Approved) (casesDir : System.FilePath) (cases : List String) :
    IO (List Output.Gen) := do
  let add (gs : Array Output.Gen) : Except String Output.Gen → Array Output.Gen
    | .ok g => if gs.any (·.text == g.text) then gs else gs.push g
    | .error _ => gs
  let mut gens := add #[] (Output.valuesGen a.impls a.challenge)
  for name in cases do
    let src ← try some <$> IO.FS.readFile (casesDir / name / "mutant") catch _ => pure none
    if let some (.ok m) := src.map parse then
      if let .breaks ts := m.expect then
        gens := add gens (Output.refutationGen a.impls a.defs a.challenge ts)
  return gens.toList

/-- What the checks with Lean compared. -/
structure Checked where
  decls    : Nat
  commands : Nat
  gens     : Nat

/-- The checks with Lean (`Mutants.CrossCheck`, `Mutants.Output`), in a fresh copy of the approved
core. First it builds the approved Challenge module and the cross-check's probes with `lake build`
and loads each as Lean built it: the cross-check compares the approved Challenge's declarations
with the reader's lines, and the parse check compares Lean's parse of the approved Challenge (with
the syntax of its imports) with them. Then it builds the generated Challenges `gens` and the output
check's probes in the same copy, and the output check compares each one's constants with what it
must state. Each must show no problem, and each probe its known ones. -/
def leanCheck (a : Approved) (gens : List Output.Gen) (log : System.FilePath) :
    ExceptT String IO Checked := do
  let genPath (k : Nat) : String := s!"Challenge/MutantsOutput{k}.lean"
  let numbered := (List.range gens.length).zip gens
  let outProbes ← Output.outProbes.mapM fun p => do
    let ls ← match readChallenge p.source with
      | .ok ls => pure ls
      | .error e => throw s!"{p.path}: {e}"
    match Output.refutationGen a.impls Output.probeDefs ls p.breaks with
    | .ok g => pure (p, g, s!"{moduleOf p.path |>.replace "." "/"}Gen.lean")
    | .error e => throw s!"{p.path}: {e}"
  let first := CrossCheck.probes.map fun p => (p.path, p.source)
  let second := numbered.map (fun (k, g) => (genPath k, g.text)) ++
    outProbes.flatMap fun (p, g, gp) => [(p.path, p.source), (gp, g.text)]
  for (p, _) in first ++ second do
    if a.files.any (·.1 == p) then throw s!"core/{p} exists; the runner writes that path"
  let chalPath := "/".intercalate (a.chalModule.splitOn ".") ++ ".lean"
  let some chalSrc := a.files.lookup chalPath | throw s!"core/{chalPath} not found"
  let dir ← IO.FS.createTempDir
  try
    IO.FS.writeFile log ""
    -- Writes `files`, then `lake build` of `mods`, its log appended; on a failure, Lean's first
    -- error names the file.
    let build (what : String) (files : List (String × String)) (mods : List String) :
        ExceptT String IO Unit := do
      writeFiles a.toolchain dir files
      (← IO.getStdout).flush
      let out ← IO.Process.output { cmd := "lake", args := #["build"] ++ mods.toArray, cwd := dir }
      let text := out.stdout ++ out.stderr
      IO.FS.writeFile log
        ((← IO.FS.readFile log) ++ s!"$ lake build {" ".intercalate mods}\nexit {out.exitCode}\n{text}\n")
      unless out.exitCode == 0 do
        let err := ((text.splitOn "\n").find? (·.startsWith "error:")).getD ""
        throw s!"lake build of {what} failed: {err} ({log})"
    build "the Challenge module and the cross-check's probes" (a.files ++ first)
      (a.chalModule :: first.map (moduleOf ·.1))
    initSearchPath (← findSysroot) [dir / ".lake" / "build" / "lib" / "lean"]
    let import_ (m : String) : IO Environment := importModules #[{ module := m.toName }] {}
    -- The cross-check: Lean declares in the approved Challenge exactly what the reader read.
    let load (m : String) : ExceptT String IO (Environment × List String × List CrossCheck.Decl) := do
      let env ← import_ m
      let some (imps, ds) := CrossCheck.built env m.toName
        | throw s!"{m}: not in the environment that imports it"
      return (env, imps, ds)
    let (approvedEnv, imps, ds) ← load a.chalModule
    let ps := CrossCheck.problems a.challenge a.defs imps ds
    unless ps.isEmpty do
      throw ("the refutation reader read the Challenge otherwise than Lean built it: " ++
        "; ".intercalate (ps.map (·.text)).eraseDups)
    for p in CrossCheck.probes do
      let (_, pi, pd) ← load (moduleOf p.path)
      unless p.caught pi pd do
        let found := (CrossCheck.problems p.lines p.defs pi pd).map (·.text)
        throw (s!"the cross-check missed a known misread in {p.path}: " ++
          s!"expected {p.expect}, found {found}")
    -- The parse check: every command Lean's parser reads is a module doc or one of the reader's
    -- hole and theorem lines, whole.
    let penv ← Output.parseEnv (CrossCheck.importNames a.challenge)
    let parsed (src : String) : ExceptT String IO (List String × List String × List Output.Cmd) :=
      ExceptT.adapt (s!"Lean's parser stops: {·}") (ExceptT.mk (Output.readParse penv src))
    let (hdr, pimps, cmds) ← parsed chalSrc
    let pps := Output.parseProblems a.challenge hdr pimps cmds
    unless pps.isEmpty do
      throw ("the refutation reader read the Challenge otherwise than Lean's parser: " ++
        "; ".intercalate (pps.map (·.text)))
    for p in Output.parseProbes do
      let ls ← match readChallenge p.source with
        | .ok ls => pure ls
        | .error e => throw s!"parse probe {p.name}: {e}"
      let (h, i, c) ← parsed p.source
      let found := (Output.parseProblems ls h i c).map (·.key)
      unless p.expect.all found.contains do
        throw s!"the parse check missed a known misread in probe {p.name}: expected {p.expect}, found {found}"
    -- The output check: each generated Challenge, as Lean built it, declares exactly the theorems
    -- it must, each stating exactly what it must, by the approved Challenge module `am` in `aenv`.
    build "the generated Challenges and the output check's probes" second (second.map (moduleOf ·.1))
    let check (aenv : Environment) (am m : String) (g : Output.Gen) :
        ExceptT String IO (List Output.OutProblem) := do
      let want ← ExceptT.adapt (s!"{g.what}: {·}") (ExceptT.mk (Output.wantTypes aenv am.toName g.wants))
      let env ← import_ m
      let some (imps, found) := Output.builtTheorems env m.toName
        | throw s!"{m}: not in the environment that imports it"
      return Output.outProblems Output.sameType want g.imports imps found
    for (k, g) in numbered do
      let ps ← check approvedEnv a.chalModule (moduleOf (genPath k)) g
      unless ps.isEmpty do
        throw (s!"{g.what}, as Lean built it, does not state what it must: " ++
          "; ".intercalate (ps.map (·.text)))
    for (p, g, gp) in outProbes do
      let ps ← check (← import_ (moduleOf p.path)) (moduleOf p.path) (moduleOf gp) g
      let found := ps.map (·.key)
      unless p.expect.all found.contains do
        throw s!"the output check missed a known misread in {p.path}: expected {p.expect}, found {found}"
    return { decls := ds.length, commands := cmds.length, gens := gens.length }
  finally
    IO.FS.removeDirAll dir

/-- Writes each case's workspaces without judging them, so a case's author can build them:
`<out>/<case>/` is the refutation run's for a `breaks=` case (`lake build Mitos.Proofs.Refute`
there) and the values run's for a `survives=` case; `<out>/<case>.holes/` is the hole run's. -/
def writeWorkspaces (env : Environment) (a : Approved) (casesDir out : System.FilePath)
    (cases : List String) : IO UInt32 := do
  let mut code := 0
  for name in cases do
    match ← (prepare env a casesDir name).run with
    | .error e => IO.eprintln s!"{clean name}: {clean e}"; code := 1
    | .ok p =>
      unless p.lint.isEmpty do
        for l in p.lint do IO.eprintln s!"{clean name}: lint: {clean l}"
        code := 1
        continue
      writeFiles a.toolchain (out / name) (p.approved ++ p.refutation.getD p.values)
      writeFiles a.toolchain (out / s!"{name}.holes") p.holes
      IO.println s!"{clean name}: {out / name}"
  return code

def expectText : Judged → String
  | .ran _ (some s) _ => s!"rejected at {s.name} (cheat case)"
  | .ran (.breaks ts) none _ => "breaks " ++ ", ".intercalate ts
  | .ran (.survives _) none _ => "survives (known gap)"
  | .invalid _ => "-"

def outcomeText : Outcome → String
  | .refuted => "REFUTED"
  | .rejected => "REJECTED, NOT REFUTED"
  | .survived => "SURVIVED"
  | .unbound => "UNBOUND"
  | .failed => "NO JUDGMENT"
  | .invalid => "INVALID"
  | .refused => "REFUSED BY LINT"

def pad (s : String) (n : Nat) : String := s ++ String.ofList (List.replicate (n - s.length) ' ')

def readApproved (root : System.FilePath) : ExceptT String IO Approved := do
  let core := root / "core"
  let toolchain ← IO.FS.readFile (root / "lean-toolchain")
  let files ← coreFiles core
  let config ← match Json.parse (← IO.FS.readFile (core / "comparator.json")) with
    | .ok j => pure j
    | .error e => throw s!"core/comparator.json: {e}"
  let chalModule ← match config.getObjValAs? String "challenge_module" with
    | .ok m => pure m
    | .error e => throw s!"core/comparator.json: {e}"
  let chalPath := "/".intercalate (chalModule.splitOn ".") ++ ".lean"
  let some chalSrc := files.lookup chalPath | throw s!"core/{chalPath} not found"
  let challenge ← match readChallenge chalSrc with
    | .ok ls => pure ls
    | .error e => throw s!"core/{chalPath}: {e}"
  let theorems := challenge.filterMap fun | .thm n _ _ => some n | _ => none
  let defs ← match config.getObjValAs? (Array String) "definition_names" with
    | .ok ds => pure ds.toList
    | .error _ => pure []
  -- Every generated statement names everything absolutely (`Mutants.qualify`); a Challenge whose
  -- statements the runner cannot write that way is not judged at all.
  if let some e := unqualified challenge defs then throw s!"core/{chalPath}: {e}"
  return { toolchain, files, config, chalModule, challenge, theorems, defs,
           impls := implModules (files.map (·.1)) }

def main (args : List String) : IO UInt32 := do
  let cfg ← match parseArgs args {} with
    | .ok c => pure c
    | .error e => IO.eprintln e; IO.eprintln usage; return 2
  if cfg.prepare.isSome && cfg.cases.isEmpty then IO.eprintln usage; return 2
  let root : System.FilePath := "."
  let casesDir := root / "eval" / "mutants" / "cases"
  let logDir := root / ".lake" / "mutants"
  IO.FS.createDirAll logDir
  let a ← match ← (readApproved root).run with
    | .ok a => pure a
    | .error e => IO.eprintln s!"mitos-mutants: {clean e}"; return 2
  let cases ← if cfg.cases.isEmpty then do
      unless ← casesDir.isDir do IO.eprintln "mitos-mutants: no eval/mutants/cases/"; return 2
      pure (((← casesDir.readDir).map (·.fileName)).qsort (· < ·)).toList
    else pure cfg.cases
  if cases.isEmpty then IO.eprintln "mitos-mutants: no cases in eval/mutants/cases/"; return 2
  -- Before anything is prepared or judged: Lean declares in the approved Challenge exactly what the
  -- reader read, Lean's parser reads no command in it that the reader did not, and every Challenge
  -- the runner will generate for these cases states, as Lean builds it, exactly what it must
  -- (`Mutants.CrossCheck`, `Mutants.Output`).
  let gens ← generatedFor a casesDir cases
  let t0 ← IO.monoMsNow
  let checked ← try (leanCheck a gens (logDir / "challenge.log")).run
    catch e => pure (.error (toString e))
  let a ← match checked with
  | .ok c =>
    let secs := ((← IO.monoMsNow) - t0 + 50) / 100
    IO.println (s!"challenge (reader against Lean's build): AGREE on {c.decls} declarations, " ++
      s!"{CrossCheck.probes.length} probes caught")
    IO.println (s!"challenge (reader against Lean's parse): AGREE on {c.commands} commands, " ++
      s!"{Output.parseProbes.length} probes caught")
    IO.println (s!"generated Challenges (as Lean built them): {c.gens} state what they must, " ++
      s!"{Output.outProbes.length} probes caught ({secs / 10}.{secs % 10}s)")
    pure { a with checked := gens.map (·.text) }
  | .error e =>
    IO.eprintln s!"mitos-mutants: core/{"/".intercalate (a.chalModule.splitOn ".")}.lean: {clean e}"
    return 2
  let env ← try Lint.syntaxEnv catch e =>
    IO.eprintln s!"mitos-mutants: cannot load Lean's syntax for the lint: {clean (toString e)}"; return 2
  if let some out := cfg.prepare then
    return ← writeWorkspaces env a casesDir out cases
  let start ← IO.monoMsNow
  let control ← judge cfg a.toolchain a.files none (logDir / "control.log")
  let controlText := match control with
    | .accepted => "ACCEPTED" | .rejected => "REJECTED  <-- FAIL" | .failed => "NO JUDGMENT  <-- FAIL"
  IO.println s!"control (unmutated core, approved Challenge and proofs): {controlText}"
  let w := (cases.map (·.length)).foldl max 4 + 2
  IO.println s!"\n{pad "CASE" w}{pad "RESULT" 23}{pad "TIME" 8}EXPECT"
  let mut results := #[]
  for name in cases do
    let t0 ← IO.monoMsNow
    let j ← runCase cfg env a casesDir logDir name
    let r : Result := { name, judged := j }
    let secs := ((← IO.monoMsNow) - t0 + 50) / 100
    let mark := if r.ok then "" else "  <-- FAIL"
    let why := match j with | .invalid w => s!" ({clean w})" | _ => ""
    IO.println s!"{pad (clean name) w}{pad (outcomeText r.outcome) 23}{pad s!"{secs / 10}.{secs % 10}s" 8}{expectText j}{why}{mark}"
    -- The evidence of a rejection: for a case that did not go as expected, and for every cheat
    -- case, the lint's first finding, or the first error line of the case's last comparator run.
    let cheat := j matches .ran _ (some _) _
    if let .ran _ _ x := j then
      if let l :: more := x.lint then
        let rest := if more.isEmpty then "" else s!" (and {more.length} more)"
        IO.println s!"{pad "" w}{clean (l.take 150).toString}{rest}"
    if cheat || (!r.ok && (r.outcome == .rejected || r.outcome == .failed || r.outcome == .unbound)) then
      for log in caseLogs logDir name do
        if ← log.pathExists then
          let lines := (← IO.FS.readFile log).splitOn "\n"
          -- The exporter's panic names a constant the solution lacks, such as a hidden hole; else
          -- Lean's first error in a file (a bad import, say), or the comparator's verdict.
          let has (pat : String) (l : String) := (splitFirst pat.toList l.toList).isSome
          let err (l : String) := l.startsWith "error:"
          if let some l := lines.find? (has "PANIC") <|> lines.find? (fun l => err l && has ".lean:" l) <|>
              lines.find? err then
            IO.println s!"{pad "" w}{clean (l.take 150).toString}"
          break
    results := results.push r
  let rs := results.toList
  IO.println "\nCHALLENGE THEOREM               BROKEN BY (refuted)"
  for t in a.theorems do
    let bs := breakers rs t
    IO.println s!"{pad t 32}{if bs.isEmpty then "none" else s!"{bs.length}: " ++ ", ".intercalate bs}"
  -- A known gap is a `survives=` case that is no cheat case; any other survivor is unexpected.
  let survivors (known : Bool) := rs.filterMap fun r =>
    match r.judged with
    | .ran e c x =>
      let gap := (e matches .survives _) && c.isNone
      if outcome x == .survived && gap == known then some (r.name, e) else none
    | .invalid _ => none
  let gaps := survivors true
  unless gaps.isEmpty do
    IO.println "\nKNOWN GAPS (the approved Challenge still accepts the mutant)"
    for (n, e) in gaps do
      if let .survives g := e then IO.println s!"{clean n}: {clean g}"
  let unexpected := survivors false
  unless unexpected.isEmpty do
    IO.println "\nUNEXPECTED SURVIVORS (the approved Challenge still accepts the mutant: a theorem is too weak, or the mutant changes nothing the theorems state)"
    for (n, _) in unexpected do IO.println (clean n)
  let total := ((← IO.monoMsNow) - start) / 1000
  let refuted := (rs.filter (·.outcome == .refuted)).length
  let cheats := (rs.filter fun r => r.ok && r.judged matches .ran _ (some _) _).length
  if passes control cases rs then
    IO.println s!"\nmutants: all {rs.length} cases as expected, {refuted} refuted, {gaps.length} known gap(s), {cheats} cheat case(s) rejected ({total}s)"
    return 0
  else
    IO.println s!"\nmutants: FAILURES (logs in .lake/mutants/) ({total}s)"
    return 1
