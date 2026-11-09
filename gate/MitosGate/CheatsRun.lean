import MitosGate.Accept
import MitosGate.Cheats
import MitosGate.Util

/-!
# `mitos-gate cheats`: the I/O around `Cheats`

This lists the cases, copies a workspace for each run, starts the gate in a child process, stops
it at the timeout, writes the logs and prints the table. `Cheats` makes every decision: which runs
are jobs (`jobs`), their order (`order`), when one may start (`Sched.start?`), each run's verdict and
each case's row (`table`), and the exit code (`exitCode`). Each printed line that holds a case name,
a value from an `expect` file or gate output goes through `oneLine`.

The workspace is `run.sh`'s: the example workspace's `lakefile.toml`, `lean-toolchain`,
`models.lock`, `Models/` and `Plugins/`, then the case's `Plugins/` and `Models/` over them. With
`model_approved=yes`, `models.lock` is rewritten as `mitos-gate lock-models` writes it, from the
models gate 0's walker reads; then each `lock_append=` line is appended.
-/

namespace MitosGate.CheatsRun

open Cheats

structure Options where
  /-- How many runs may run at once. -/
  jobs : Nat := 3
  /-- Seconds a run may take before the runner stops it. -/
  timeout : Nat := 600
  cases : List String := []

/-- A case name from the command line: a directory directly in `eval/cheats/`. -/
def plainName (s : String) : Bool :=
  !s.isEmpty && !s.startsWith "." && !s.contains '/'

def parseArgs : List String → Options → Except String Options
  | [], o => .ok o
  | "--jobs" :: v :: rest, o =>
    match v.toNat? with
    | some n =>
      if 1 ≤ n then parseArgs rest { o with jobs := n } else .error "--jobs must be at least 1"
    | none => .error s!"--jobs {v} is not a number"
  | "--timeout" :: v :: rest, o =>
    match v.toNat? with
    | some n =>
      if 1 ≤ n then parseArgs rest { o with timeout := n } else .error "--timeout must be at least 1"
    | none => .error s!"--timeout {v} is not a number"
  | a :: rest, o =>
    if a.startsWith "-" then .error s!"unknown or incomplete option {a}"
    else if !plainName a then .error s!"{a} is not the name of a directory in eval/cheats/"
    else if o.cases.contains a then .error s!"case {a} is given twice"
    else parseArgs rest { o with cases := o.cases ++ [a] }

/-- The cases: the directories in `dir` whose names do not start with `.`, as `ls -d */` lists
them, in byte order. -/
def listCases (dir : System.FilePath) : IO (List String) := do
  let mut names := #[]
  for e in ← dir.readDir do
    if !e.fileName.startsWith "." && (← e.path.isDir) then names := names.push e.fileName
  return (names.qsort (· < ·)).toList

def readCase (cheats : System.FilePath) (name : String) : IO Case := do
  let f := cheats / name / "expect"
  if !(← f.pathExists) then return { name, expect := .error "no expect file" }
  try
    let txt ← IO.FS.readFile f
    return { name, expect := match Expect.parse txt with
      | .ok e => .ok e
      | .error err => .error s!"expect: {err}" }
  catch err => return { name, expect := .error s!"expect: {err}" }

/-- Copy the regular files under `src` to the same paths under `dst`. Anything else is an error. -/
partial def copyTree (src dst : System.FilePath) : IO Unit := do
  for e in ← src.readDir do
    match (← e.path.symlinkMetadata).type with
    | .dir => copyTree e.path (dst / e.fileName)
    | .file => copyFile e.path (dst / e.fileName)
    | _ => throw <| IO.userError s!"{e.path} is neither a regular file nor a directory"

/-- Write `ws`'s workspace for case `c`. -/
def prepare (root : System.FilePath) (c : String) (e : Expect) (ws : System.FilePath) : IO Unit := do
  let acme := root / "examples" / "acme"
  for f in ["lakefile.toml", "lean-toolchain", "models.lock"] do copyFile (acme / f) (ws / f)
  for d in ["Models", "Plugins"] do copyTree (acme / d) (ws / d)
  let dir := root / "eval" / "cheats" / c
  for d in ["Plugins", "Models"] do
    if ← (dir / d).isDir then copyTree (dir / d) (ws / d)
  -- What `mitos-gate lock-models` writes: the models gate 0's walker reads, in its lock format.
  if e.modelApproved then
    let es ← (← Accept.modelFiles ws).toList.mapM fun (rel, txt) => return (rel, ← sha256 txt)
    IO.FS.writeFile (ws / "models.lock") (Accept.renderLock es)
  unless e.lockAppend.isEmpty do
    IO.FS.withFile (ws / "models.lock") .append fun h =>
      for l in e.lockAppend do h.putStr (l ++ "\n")

/-- Run the gate on `ws` in a session of its own. At the timeout its process group gets SIGTERM,
and SIGKILL 10 s later. The child is reaped only once it exits, so its pid is still its own when it
is signalled. -/
def runGate (gate : String) (root ws : System.FilePath) (m : Mode) (timeout : Nat) : IO Run := do
  let args := #["accept", "--workspace", ws.toString, "--plugin", "ToyRequire",
    "--model", "Models.ToyRequire.model", "--mitos-root", root.toString] ++
    (match m with | .full => #[] | .comparatorOnly => #["--skip-lint"])
  let spawnArgs : IO.Process.SpawnArgs :=
    { cmd := gate, args := args, cwd := some root, stdin := .null, stdout := .piped,
      stderr := .piped, setsid := true }
  let child ← IO.Process.spawn spawnArgs
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← IO.asTask child.stderr.readToEnd .dedicated
  let start ← IO.monoMsNow
  let mut timedOut := false
  let mut killed := false
  let mut code : UInt32 := 0
  repeat
    match ← child.tryWait with
    | some c => code := c; break
    | none =>
      let ms := (← IO.monoMsNow) - start
      if !timedOut && ms ≥ timeout * 1000 then
        timedOut := true
        child.kill
      else if timedOut && !killed && ms ≥ (timeout + 10) * 1000 then
        killed := true
        discard <| IO.Process.output { cmd := "kill", args := #["-KILL", "--", s!"-{child.pid}"] }
      IO.sleep 100
  let out ← IO.ofExcept (← IO.wait out)
  let err ← IO.ofExcept (← IO.wait err)
  return { exitCode := code, output := out ++ err, timedOut }

/-- One job: its run, and when it started and ended, in ms since the runner started. -/
structure Done where
  run : Run
  startMs : Nat
  endMs : Nat

/-- Run a job in a fresh workspace, write its log, and remove the workspace. Any I/O error is the
run's output, which then has no verdict. -/
def runJob (gate : String) (root logs : System.FilePath) (t0 : Nat) (timeout : Nat) (c : String)
    (e : Expect) (m : Mode) : IO Done := do
  let startMs := (← IO.monoMsNow) - t0
  let ws ← IO.FS.createTempDir
  let run ← try
      prepare root c e ws
      runGate gate root ws m timeout
    catch err => pure { exitCode := 255, output := s!"mitos-gate cheats: {err}\n", timedOut := false }
  try IO.FS.removeDirAll ws
  catch err => IO.eprintln (oneLine s!"warning: could not remove the workspace {ws}: {err}")
  try IO.FS.writeFile (logs / s!"{c}.{m.logName}.log") run.output
  catch err => IO.eprintln (oneLine s!"warning: could not write the log of {c}: {err}")
  return { run, startMs, endMs := (← IO.monoMsNow) - t0 }

abbrev Pending := Task (Job × Except IO.Error Done)

/-- Start jobs while `Sched.start?` allows, otherwise wait for one to finish. -/
partial def schedule (n : Nat) (launch : Job → IO Pending) (report : Job × Done → IO Unit)
    (st : Sched Job) (running : List Pending) (acc : Array (Job × Done)) :
    IO (Array (Job × Done)) := do
  match st.start? n Job.heavy with
  | some (j, st') => schedule n launch report st' (running ++ [← launch j]) acc
  | none =>
    if h : 0 < running.length then
      let ((j, r), rest) ← IO.waitAny' running h
      let d : Done := match r with
        | .ok d => d
        | .error err => { run := { exitCode := 255, output := s!"mitos-gate cheats: {err}\n",
                                   timedOut := false }, startMs := 0, endMs := 0 }
      report (j, d)
      schedule n launch report (st.finish j) rest (acc.push (j, d))
    else return acc

def runCorpus (o : Options) : IO UInt32 := do
  let root ← IO.currentDir
  let cheats := root / "eval" / "cheats"
  unless (← cheats.isDir) && (← (root / "examples" / "acme").isDir) do
    IO.eprintln "mitos-gate cheats runs from the repository root, which holds eval/cheats/"
    return 2
  let names ← if o.cases.isEmpty then listCases cheats else pure o.cases
  if names.isEmpty then
    IO.println "no cheat cases found in eval/cheats/"
    return 2
  let cases ← names.mapM (readCase cheats)
  let gate := (← IO.appPath).toString
  let logs := root / ".lake" / "cheats"
  IO.FS.createDirAll logs
  let t0 ← IO.monoMsNow
  let js := order (jobs cases)
  let expectOf (j : Job) : Option Expect :=
    match cases[j.case]? with
    | some { expect := .ok e, .. } => some e
    | _ => none
  let launch (j : Job) : IO Pending := do
    let some e := expectOf j | return Task.pure (j, .error (IO.userError "no expect"))
    let c := names[j.case]!
    let t ← IO.asTask (runJob gate root logs t0 o.timeout c e j.mode) .dedicated
    return t.map (j, ·)
  let finished ← IO.mkRef 0
  let progress (jd : Job × Done) : IO Unit := do
    finished.modify (· + 1)
    let (j, d) := jd
    let secs := (d.endMs - d.startMs) / 1000
    IO.eprintln (oneLine (s!"[{← finished.get}/{js.length}] {names[j.case]!} {j.mode.logName}: " ++
      s!"{d.run.shown} ({secs} s)"))
  let done ← schedule o.jobs launch progress (.init js) [] #[]
  let res (i : Nat) (m : Mode) : Option Run :=
    (done.find? fun (j, _) => j.case == i && j.mode == m).map (·.2.run)
  let rows := table res cases
  -- When each run started and ended, for the timing of the corpus.
  let tsv := done.toList.map fun (j, d) =>
    s!"{oneLine names[j.case]!}\t{j.mode.logName}\t{d.startMs}\t{d.endMs}\t{d.run.exitCode}\t" ++
      s!"{d.run.timedOut}\n"
  let header := "case\tmode\tstart_ms\tend_ms\texit\ttimed_out\n"
  try IO.FS.writeFile (logs / "timing.tsv") (String.join (header :: tsv))
  catch err => IO.eprintln (oneLine s!"warning: could not write timing.tsv: {err}")
  for l in report rows do IO.println (oneLine l)
  let secs := ((← IO.monoMsNow) - t0) / 1000
  IO.eprintln (s!"cheat corpus: {done.size} runs of {cases.length} cases in {secs} s, " ++
    s!"--jobs {o.jobs}, --timeout {o.timeout}")
  return exitCode rows

/-- `runCorpus`, but an I/O error it throws is printed through `oneLine`, with exit 2: the Lean
runtime would print it raw, and it names the path it failed on. -/
def cli (args : List String) (usage : String) : IO UInt32 := do
  match parseArgs args {} with
  | .error e => IO.eprintln (oneLine e); IO.eprintln usage; return 2
  | .ok o =>
    try runCorpus o
    catch e =>
      IO.eprintln (oneLine s!"mitos-gate cheats stopped on an I/O error: {e}")
      return 2

end MitosGate.CheatsRun
