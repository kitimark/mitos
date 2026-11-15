import MitosGate.Accept
import MitosGate.Cheats
import MitosGate.CheatsShard
import MitosGate.Util

namespace MitosGate.CheatsRun

open Cheats

structure Options where
  jobs : Nat := 4
  timeout : Nat := 600
  cases : List String := []
  shard : Option String := none
  listOnly : Bool := false
  casesDir : Option String := none

def plainName (s : String) : Bool :=
  !s.isEmpty && !s.startsWith "." && !s.contains '/'

def parseArgs : List String → Options → Except String Options
  | [], o => .ok o
  | "--shard" :: v :: rest, o =>
    if o.shard.isSome then .error "--shard is given twice"
    else parseArgs rest { o with shard := some v }
  | "--list" :: rest, o => parseArgs rest { o with listOnly := true }
  | "--cases" :: v :: rest, o =>
    if o.casesDir.isSome then .error "--cases is given twice"
    else parseArgs rest { o with casesDir := some v }
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

partial def copyTree (src dst : System.FilePath) : IO Unit := do
  for e in ← src.readDir do
    match (← e.path.symlinkMetadata).type with
    | .dir => copyTree e.path (dst / e.fileName)
    | .file => copyFile e.path (dst / e.fileName)
    | _ => throw <| IO.userError s!"{e.path} is neither a regular file nor a directory"

def prepare (root : System.FilePath) (c : String) (e : Expect) (ws : System.FilePath) : IO Unit := do
  let acme := root / "examples" / "acme"
  for f in ["lakefile.toml", "lean-toolchain", "models.lock"] do copyFile (acme / f) (ws / f)
  for d in ["Models", "Plugins"] do copyTree (acme / d) (ws / d)
  let dir := root / "eval" / "cheats" / c
  for d in ["Plugins", "Models"] do
    if ← (dir / d).isDir then copyTree (dir / d) (ws / d)
  if e.modelApproved then
    let es ← (← Accept.modelFiles ws).toList.mapM fun (rel, txt) => return (rel, ← sha256 txt)
    IO.FS.writeFile (ws / "models.lock") (Accept.renderLock es)
  unless e.lockAppend.isEmpty do
    IO.FS.withFile (ws / "models.lock") .append fun h =>
      for l in e.lockAppend do h.putStr (l ++ "\n")

/-- Run `cmd args` in `cwd`, in a session of its own, with `TMPDIR` set to `tmp`, until it has
exited and no process holds its stdout or stderr any more. If that takes `timeoutMs`, its whole
process group gets SIGKILL, once, and the run is marked timed out. There is no SIGTERM step first:
`inRunDir` removes what a killed run leaves, so a chance to clean up would buy nothing.

The kill is `Child.kill`, which on Lean v4.35.0 sends SIGKILL to the whole group of a child spawned
with `setsid`, although its docstring says SIGTERM. `mitos-lint-test` pins this: it times out a
child that ignores SIGTERM and leaves a grandchild that ignores it too, and requires exit 137 and
both gone. So a toolchain that sends SIGTERM instead fails CI, rather than leaving the runner waiting
on a survivor.

The timeout covers the pipes too, so a descendant that outlives the child and keeps a pipe open is
killed with the rest of the group, not waited for. The child is reaped only after both pipes have
closed. Until then its pid, which is the group's id, cannot be reused, so the kill reaches only
this run's processes. A process that starts a session of its own leaves the group and is out of
reach. -/
def runChild (cmd : String) (args : Array String) (cwd tmp : System.FilePath) (timeoutMs : Nat) :
    IO Run := do
  let child ← IO.Process.spawn
    { cmd, args, cwd := some cwd, env := #[("TMPDIR", some tmp.toString)],
      stdin := .null, stdout := .piped, stderr := .piped, setsid := true }
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← IO.asTask child.stderr.readToEnd .dedicated
  let start ← IO.monoMsNow
  let mut timedOut := false
  let mut code : UInt32 := 0
  repeat
    if (← IO.hasFinished out) && (← IO.hasFinished err) then
      if let some c ← child.tryWait then
        code := c
        break
    if !timedOut && (← IO.monoMsNow) - start ≥ timeoutMs then
      timedOut := true
      child.kill
    IO.sleep 100
  let out ← IO.ofExcept (← IO.wait out)
  let err ← IO.ofExcept (← IO.wait err)
  return { exitCode := code, output := out ++ err, timedOut }

def runGate (gate : String) (root ws tmp : System.FilePath) (m : Mode) (timeout : Nat) :
    IO Run :=
  runChild gate (#["accept", "--workspace", ws.toString, "--plugin", "ToyRequire",
      "--model", "Models.ToyRequire.model", "--mitos-root", root.toString] ++
      (match m with | .full => #[] | .comparatorOnly => #["--skip-lint"]))
    root tmp (timeout * 1000)

def inRunDir (act : System.FilePath → IO Run) : IO Run := do
  let dir ← IO.FS.createTempDir
  let run ← try
      IO.FS.createDirAll (dir / "ws")
      IO.FS.createDirAll (dir / "tmp")
      act dir
    catch err => pure { exitCode := 255, output := s!"mitos-gate cheats: {err}\n", timedOut := false }
  try IO.FS.removeDirAll dir
  catch err => IO.eprintln (ciLine s!"warning: could not remove the job directory {dir}: {err}")
  return run

structure Done where
  run : Run
  startMs : Nat
  endMs : Nat

def runJob (gate : String) (root logs : System.FilePath) (t0 : Nat) (timeout : Nat) (c : String)
    (e : Expect) (m : Mode) : IO Done := do
  let startMs := (← IO.monoMsNow) - t0
  let run ← inRunDir fun dir => do
    prepare root c e (dir / "ws")
    runGate gate root (dir / "ws") (dir / "tmp") m timeout
  try IO.FS.writeFile (logs / s!"{c}.{m.logName}.log") run.output
  catch err => IO.eprintln (ciLine s!"warning: could not write the log of {c}: {err}")
  return { run, startMs, endMs := (← IO.monoMsNow) - t0 }

abbrev Pending := Task (Job × Except IO.Error Done)

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
    IO.eprintln (ciLine (s!"[{← finished.get}/{js.length}] {names[j.case]!} {j.mode.logName}: " ++
      s!"{d.run.shown} ({secs} s)"))
  let done ← schedule o.jobs launch progress (.init js) [] #[]
  let res (i : Nat) (m : Mode) : Option Run :=
    (done.find? fun (j, _) => j.case == i && j.mode == m).map (·.2.run)
  let rows := table res cases
  let tsv := done.toList.map fun (j, d) =>
    s!"{oneLine names[j.case]!}\t{j.mode.logName}\t{d.startMs}\t{d.endMs}\t{d.run.exitCode}\t" ++
      s!"{d.run.timedOut}\n"
  let header := "case\tmode\tstart_ms\tend_ms\texit\ttimed_out\n"
  try IO.FS.writeFile (logs / "timing.tsv") (String.join (header :: tsv))
  catch err => IO.eprintln (ciLine s!"warning: could not write timing.tsv: {err}")
  for l in report rows do IO.println (ciLine l)
  let secs := ((← IO.monoMsNow) - t0) / 1000
  IO.eprintln (s!"cheat corpus: {done.size} runs of {cases.length} cases in {secs} s, " ++
    s!"--jobs {o.jobs}, --timeout {o.timeout}")
  return exitCode rows

def resolveDir (root : System.FilePath) (specified : Option String) : System.FilePath :=
  match specified with
  | none => root / "eval" / "cheats"
  | some p =>
    let path := System.FilePath.mk p
    if path.isAbsolute then path else root / path

/-- A symlink is not a log, even when its target is a regular file. `metadata` would follow it. -/
def isRegular (p : System.FilePath) : IO Bool := do
  if !(← p.pathExists) then return false
  return (← p.symlinkMetadata).type == .file

def runShard (o : Options) (usage : String) : IO UInt32 := do
  if !o.cases.isEmpty then
    IO.eprintln (ciLine "a shard reads the case directory; do not also name cases")
    IO.eprintln usage
    return 2
  let some spec := o.shard | return 2
  let root ← IO.currentDir
  let dir := resolveDir root o.casesDir
  try
    let names ← listCases dir
    match CheatsShard.Shard.parse spec with
    | none =>
      IO.eprintln (ciLine s!"--shard {spec} is not k/n with k < n and n > 0")
      return 2
    | some shard =>
      match CheatsShard.selection names shard with
      | .error why =>
        IO.eprintln (ciLine why.text)
        return 1
      | .ok chosen =>
        if o.listOnly then
          for name in chosen do IO.println name
          return 0
        if o.casesDir.isSome then
          IO.eprintln (ciLine "--cases with --shard only lists names; pass --list")
          return 2
        let logs := root / ".lake" / "cheats"
        IO.FS.createDirAll logs
        IO.FS.writeFile (logs / CheatsShard.artifactCases)
          (CheatsShard.renderCaseList chosen)
        runCorpus { o with cases := chosen }
  catch e =>
    IO.eprintln (ciLine s!"mitos-gate cheats stopped on an I/O error: {e}")
    return 1

structure AggFlags where
  checks : Option String := none
  shardsJob : Option String := none
  merged : Option String := none
  casesDir : Option String := none
  dirs : List String := []

def parseAggArgs (args : List String) : Except String AggFlags :=
  let rec go (rest : List String) (a : AggFlags) : Except String AggFlags :=
    match rest with
    | [] => .ok a
    | "--checks" :: v :: more =>
      if a.checks.isSome then .error "--checks is given twice"
      else go more { a with checks := some v }
    | "--shards" :: v :: more =>
      if a.shardsJob.isSome then .error "--shards is given twice"
      else go more { a with shardsJob := some v }
    | "--merged" :: v :: more =>
      if a.merged.isSome then .error "--merged is given twice"
      else go more { a with merged := some v }
    | "--cases" :: v :: more =>
      if a.casesDir.isSome then .error "--cases is given twice"
      else go more { a with casesDir := some v }
    | flag :: more =>
      if flag.startsWith "-" then .error s!"unknown or incomplete option {flag}"
      else .ok { a with dirs := a.dirs ++ (flag :: more) }
  go args {}

def readText (p : System.FilePath) : IO (Option String) := do
  if ← isRegular p then return some (← IO.FS.readFile p) else return none

def readSlot (dir : System.FilePath) : IO CheatsShard.ShardSlot := do
  if !(← dir.isDir) then return .absent
  let mut regular : List String := []
  for e in ← dir.readDir do
    if ← isRegular e.path then regular := e.fileName :: regular
  return .present {
    exitText := ← readText (dir / CheatsShard.artifactExit)
    casesText := ← readText (dir / CheatsShard.artifactCases)
    timingText := ← readText (dir / CheatsShard.artifactTiming)
    tableText := ← readText (dir / CheatsShard.artifactTable)
    regularFiles := regular
  }

def publish (merged : System.FilePath) (plan : CheatsShard.MergePlan) (slots : List System.FilePath) :
    IO Unit := do
  let work := System.FilePath.mk (merged.toString ++ ".work")
  let old := System.FilePath.mk (merged.toString ++ ".old")
  if ← work.pathExists then IO.FS.removeDirAll work
  IO.FS.createDirAll work
  for c in plan.copies do
    match slots[c.shard]? with
    | none => throw <| IO.userError s!"shard {c.shard} is not a directory that was read"
    | some src => copyFile (src / c.file) (work / c.file)
  IO.FS.writeFile (work / CheatsShard.artifactTiming) plan.timing
  if ← old.pathExists then IO.FS.removeDirAll old
  if ← merged.pathExists then IO.FS.rename merged old
  IO.FS.rename work merged
  if ← old.pathExists then IO.FS.removeDirAll old

def aggregateCli (args : List String) : IO UInt32 := do
  match parseAggArgs args with
  | .error e => IO.eprintln (ciLine e); return 2
  | .ok a =>
    let some checks := a.checks | IO.eprintln (ciLine "aggregate needs --checks"); return 2
    let some shardsJob := a.shardsJob | IO.eprintln (ciLine "aggregate needs --shards"); return 2
    let some mergedText := a.merged | IO.eprintln (ciLine "aggregate needs --merged"); return 2
    if a.dirs.isEmpty then
      IO.eprintln (ciLine "aggregate needs one directory per shard")
      return 2
    let root ← IO.currentDir
    let dir := resolveDir root a.casesDir
    let merged :=
      let path := System.FilePath.mk mergedText
      if path.isAbsolute then path else root / path
    let slots := a.dirs.map fun d =>
      let path := System.FilePath.mk d
      if path.isAbsolute then path else root / path
    try
      let names ← listCases dir
      let mut records : List CheatsShard.ShardSlot := []
      for slot in slots do
        records := records ++ [← readSlot slot]
      let input : CheatsShard.AggregateInput := {
        checks, shardsJob, count := slots.length, directory := names, shards := records
      }
      match CheatsShard.verdict input with
      | .reject why =>
        IO.eprintln (ciLine why.render)
        return 1
      | .accept plan =>
        publish merged plan slots
        IO.print plan.stdout
        return 0
    catch e =>
      IO.eprintln (ciLine s!"mitos-gate cheats aggregate stopped on an I/O error: {e}")
      return 1

def cli (args : List String) (usage : String) : IO UInt32 := do
  match args with
  | "aggregate" :: rest => aggregateCli rest
  | _ =>
    match parseArgs args {} with
    | .error e => IO.eprintln (ciLine e); IO.eprintln usage; return 2
    | .ok o =>
      if o.shard.isSome then runShard o usage
      else if o.listOnly || o.casesDir.isSome then
        IO.eprintln (ciLine "--list and --cases belong to cheats --shard or cheats aggregate")
        IO.eprintln usage
        return 2
      else
        try runCorpus o
        catch e =>
          IO.eprintln (ciLine s!"mitos-gate cheats stopped on an I/O error: {e}")
          return 2

end MitosGate.CheatsRun
