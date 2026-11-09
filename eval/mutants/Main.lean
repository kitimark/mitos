import Lean.Data.Json
import Mutants

/-!
# `mitos-mutants`: the mutant runner

Run from the repository root: `lake --dir eval/mutants exe mitos-mutants [--paranoid] [<case>...]`.

For each case in `eval/mutants/cases/`, it applies the case's edits to a copy of `core/` (sources
only, no build outputs) and judges it with the sandboxed `lake comparator`, as
`Mutants.Verdict` describes. Each run gets a fresh copy, which is removed afterwards. The pure
parts (manifest, edits, refutation Challenge, verdict) are in `Mutants/` with their proofs; this
file only reads, writes and runs.
-/

open Mutants Lean

def usage : String := "usage: mitos-mutants [--paranoid] [--keep] [<case>...]
       mitos-mutants --prepare <dir> <case>...
  Run from the repository root. Judges every case in eval/mutants/cases/, or the named ones, with
  the sandboxed lake comparator. --paranoid also runs the external kernels. --keep keeps the
  workspaces. Logs go to .lake/mutants/. Exit 0: every case as expected; 1: not; 2: could not run.
  --prepare writes each named case's workspace to <dir>/<case>/ and judges nothing."

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
  challenge  : List Line
  theorems   : List String

/-- The refutation configuration: the approved one with the generated Challenge, the generated
solution module (`Mutants.refutationSolution`) and the refuted theorems; definition holes and
permitted axioms stay as approved. -/
def refutationConfig (a : Approved) (ts : List String) : String :=
  let names := Json.arr (ts.toArray.map fun t => Json.str s!"Mitos.Refute.{t}")
  ((a.config.setObjVal! "challenge_module" (.str "Challenge.Mutant")).setObjVal!
    "solution_module" (.str "Mitos.Proofs.Refute") |>.setObjVal! "theorem_names" names).pretty

def generated : List String :=
  ["Challenge/Mutant.lean", "Mitos/Proofs/Refute.lean", "Mitos/Proofs/RefuteCase.lean", "mutant.json"]

/-- A case, ready to judge: its manifest, the mutated core for the approved run, and for a
`breaks=` case the files the refutation run adds to it. -/
structure Prepared where
  mutant     : Mutant
  approved   : List (String × String)
  refutation : Option (List (String × String))

def prepare (a : Approved) (casesDir : System.FilePath) (name : String) :
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
  match m.expect with
  | .survives _ => return { mutant := m, approved := files, refutation := none }
  | .breaks ts =>
    let chal ← match refutation a.challenge ts with
      | .ok ls => pure ("\n".intercalate ls)
      | .error e => throw e
    -- The case's file is imported by a solution module that also imports the mutated core's
    -- implementation, so the definition holes are the mutant's (`Mutants.refutationSolution`).
    let extra := [("Challenge/Mutant.lean", chal),
      ("Mitos/Proofs/RefuteCase.lean", ← IO.FS.readFile (dir / "Refute.lean")),
      ("Mitos/Proofs/Refute.lean", refutationSolution (files.map (·.1))),
      ("mutant.json", refutationConfig a ts)]
    return { mutant := m, approved := files, refutation := some extra }

/-- A case's log files, newest run first. -/
def caseLogs (logDir : System.FilePath) (name : String) : List System.FilePath :=
  ["refutation", "approved"].map fun s => logDir / s!"{name}.{s}.log"

def runCase (cfg : Config) (a : Approved) (casesDir logDir : System.FilePath) (name : String) :
    IO Judged := do
  -- Logs from an earlier run must not be read as this one's.
  for log in caseLogs logDir name do
    if ← log.pathExists then IO.FS.removeFile log
  let p ← match ← (prepare a casesDir name).run with
    | .ok p => pure p
    | .error e => return .invalid e
  let approved ← judge cfg a.toolchain p.approved none (logDir / s!"{name}.approved.log")
  let some extra := p.refutation | return .ran p.mutant.expect { approved }
  if approved != .rejected then return .ran p.mutant.expect { approved }
  let refutation ← judge cfg a.toolchain (p.approved ++ extra) (some "mutant.json")
    (logDir / s!"{name}.refutation.log")
  return .ran p.mutant.expect { approved, refutation }

/-- Writes each case's workspace to `<out>/<case>/` without judging it, the refutation run's for a
`breaks=` case, so a case's author can build it: `lake build Mitos.Proofs.Refute` there. -/
def writeWorkspaces (a : Approved) (casesDir out : System.FilePath) (cases : List String) :
    IO UInt32 := do
  let mut code := 0
  for name in cases do
    match ← (prepare a casesDir name).run with
    | .error e => IO.eprintln s!"{clean name}: {clean e}"; code := 1
    | .ok p =>
      let dir := out / name
      IO.FS.createDirAll dir
      IO.FS.writeFile (dir / "lean-toolchain") a.toolchain
      for (rel, txt) in p.approved ++ p.refutation.getD [] do
        if let some d := (dir / rel).parent then IO.FS.createDirAll d
        IO.FS.writeFile (dir / rel) txt
      IO.println s!"{clean name}: {dir}"
  return code

def expectText : Judged → String
  | .ran (.breaks ts) .. => "breaks " ++ ", ".intercalate ts
  | .ran (.survives _) .. => "survives (known gap)"
  | .invalid _ => "-"

def outcomeText : Outcome → String
  | .refuted => "REFUTED"
  | .rejected => "REJECTED, NOT REFUTED"
  | .survived => "SURVIVED"
  | .failed => "NO JUDGMENT"
  | .invalid => "INVALID"

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
  let theorems := challenge.filterMap fun | .thm n _ => some n | .keep _ => none
  return { toolchain, files, config, challenge, theorems }

def main (args : List String) : IO UInt32 := do
  let cfg ← match parseArgs args {} with
    | .ok c => pure c
    | .error e => IO.eprintln e; IO.eprintln usage; return 2
  let root : System.FilePath := "."
  let casesDir := root / "eval" / "mutants" / "cases"
  let logDir := root / ".lake" / "mutants"
  IO.FS.createDirAll logDir
  let a ← match ← (readApproved root).run with
    | .ok a => pure a
    | .error e => IO.eprintln s!"mitos-mutants: {clean e}"; return 2
  if let some out := cfg.prepare then
    if cfg.cases.isEmpty then IO.eprintln usage; return 2
    return ← writeWorkspaces a casesDir out cfg.cases
  let cases ← if cfg.cases.isEmpty then do
      unless ← casesDir.isDir do IO.eprintln "mitos-mutants: no eval/mutants/cases/"; return 2
      pure (((← casesDir.readDir).map (·.fileName)).qsort (· < ·)).toList
    else pure cfg.cases
  if cases.isEmpty then IO.eprintln "mitos-mutants: no cases in eval/mutants/cases/"; return 2
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
    let j ← runCase cfg a casesDir logDir name
    let r : Result := { name, judged := j }
    let secs := ((← IO.monoMsNow) - t0 + 50) / 100
    let mark := if r.ok then "" else "  <-- FAIL"
    let why := match j with | .invalid w => s!" ({clean w})" | _ => ""
    IO.println s!"{pad (clean name) w}{pad (outcomeText r.outcome) 23}{pad s!"{secs / 10}.{secs % 10}s" 8}{expectText j}{why}{mark}"
    -- For a run that did not go as expected, the first error line of its last comparator run.
    if !r.ok && (r.outcome == .rejected || r.outcome == .failed) then
      for log in caseLogs logDir name do
        if ← log.pathExists then
          let lines := (← IO.FS.readFile log).splitOn "\n"
          if let some l := lines.find? (fun l => (splitFirst "error".toList l.toList).isSome) then
            IO.println s!"{pad "" w}{clean (l.take 150).toString}"
          break
    results := results.push r
  let rs := results.toList
  IO.println "\nCHALLENGE THEOREM               BROKEN BY (refuted)"
  for t in a.theorems do
    let bs := breakers rs t
    IO.println s!"{pad t 32}{if bs.isEmpty then "none" else s!"{bs.length}: " ++ ", ".intercalate bs}"
  let survivors (known : Bool) := rs.filterMap fun r =>
    match r.judged with
    | .ran e x =>
      if outcome x == .survived && (e matches .survives _) == known then some (r.name, e) else none
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
  if passes control cases rs then
    IO.println s!"\nmutants: all {rs.length} cases as expected, {refuted} refuted, {gaps.length} known gap(s) ({total}s)"
    return 0
  else
    IO.println s!"\nmutants: FAILURES (logs in .lake/mutants/) ({total}s)"
    return 1
