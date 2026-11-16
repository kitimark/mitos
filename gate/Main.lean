import MitosGate.Lint
import MitosGate.Imports
import MitosGate.Lock
import MitosGate.Accept
import MitosGate.RunLog
import MitosGate.ContentId
import MitosGate.Carry
import MitosGate.CheatsRun
import MitosGate.LandCli
import MitosGate.SpeechCli
import MitosGate.SnapshotCli
import MitosGate.ShadowCli

open MitosGate

def lockedSpecImports : List String := ["Init", "Std", "Mitos.Core"]

def usage : String := "usage:
  mitos-gate lint <file.lean>...                 gate 1 on plugin sources
  mitos-gate imports                             import rule for core/ (Init, Std, Mitos.*; spec never imports impl)
                                                 and for gate/MitosGate/Base.lean and gate/MitosGate/Base/
                                                 (Init, Std, Lean.Data.Json, MitosGate.Base)
  mitos-gate lock [--check]                      write or check statements.lock; either fails on a
                                                 module under core/Mitos/Core/ that Mitos.Core does
                                                 not import, directly or transitively
  mitos-gate lock --check-header                 statements.lock starts with MitosGate.Lock.header,
                                                 the newline after its second line included
  mitos-gate lock-models --workspace <dir> [--check]
                                                 write or check <dir>/models.lock, as gate 0 reads the models
  mitos-gate accept --workspace <dir> --plugin <Name> --model <Module.const>
                    [--plugin-file <f>] [--paranoid] [--record] [--keep] [--skip-lint]
  mitos-gate runlog [--base <dir>] --head <dir>   run-log records parse, one per (task, role, attempt),
                                                 each record file named by its key; with --base, every
                                                 day file equals the base and every base record file
                                                 is kept
  mitos-gate content-id <base> <head> [--verbose]
                                                 the id a verdict covers: the diff from the merge-base,
                                                 whitespace and where each hunk applies included
  mitos-gate carry <base> <verified-head> <head>  whether a verdict carries: the branch's pushes on
                                                 standard input (the REST activity route as TSV),
                                                 all updater rebases from the verified head to the
                                                 head, and the same content id
  mitos-gate cheats [--jobs N] [--timeout S] [case]...
                                                 run the cheat corpus (eval/cheats/), N runs at a time
                                                 (default 4), each stopped after S seconds (default 600)
  mitos-gate cheats --shard k/n [--jobs N] [--timeout S] [--list] [--cases <dir>]
                                                 run the cases whose index mod n is k, from eval/cheats/
                                                 (or <dir> with --list). N runs at a time (default 4),
                                                 each stopped after S seconds (default 600). Refuses an
                                                 empty residue, because no names would run the whole corpus
  mitos-gate cheats aggregate --checks <s> --shards <s> --merged <dir> [--cases <dir>] <shard>...
                                                 accept the shard records only when both jobs
                                                 succeeded and the records are the partition of the
                                                 case directory; publish the logs into <dir>
  mitos-gate land [<snapshot.json>]              the landing decision for one snapshot (file, or standard
                                                 input): who is next, what is pushed, the caller's step,
                                                 who wakes; one line of JSON. Exit 1: snapshot refused
  mitos-gate speech --owner <login> --pr <n> [--pushes <tsv>] <comments.json>
                                                 what each of <login>'s issue comments on the pull
                                                 request says: one line each (id, reading, why); the
                                                 pushes are the branch's activity as carry reads it
  mitos-gate snapshot <dir>                      the snapshot land reads, from the REST reads that
                                                 gate/snapshot-fetch.sh saved in <dir>, with content
                                                 ids and replays from git in this clone; a failed
                                                 read holds the pull requests that need it
  mitos-gate shadow <dir>                        what the decide records of a window would have done,
                                                 against what merged, from the folder that
                                                 gate/shadow-fetch.sh wrote: one line per merge, then
                                                 the counts, the cost and the runs"

partial def parseAccept (args : List String) (c : Accept.Config) : Except String Accept.Config :=
  match args with
  | [] => .ok c
  | "--workspace" :: v :: rest => parseAccept rest { c with workspace := v }
  | "--plugin" :: v :: rest => parseAccept rest { c with plugin := v }
  | "--model" :: v :: rest => parseAccept rest { c with model := v }
  | "--plugin-file" :: v :: rest => parseAccept rest { c with pluginFile := some v }
  | "--mitos-root" :: v :: rest => parseAccept rest { c with mitosRoot := v }
  | "--paranoid" :: rest => parseAccept rest { c with paranoid := true }
  | "--record" :: rest => parseAccept rest { c with record := true }
  | "--keep" :: rest => parseAccept rest { c with keep := true }
  | "--skip-lint" :: rest => parseAccept rest { c with skipLint := true }
  | a :: _ => .error s!"unknown argument {a}"

def lockHeaderStatus : IO UInt32 := do
  let txt ← IO.FS.readFile "statements.lock"
  if Lock.startsWithHeader txt then
    IO.println (ciLine "statements.lock header matches MitosGate.Lock.header")
    return 0
  IO.eprintln (ciLine "statements.lock header does not match MitosGate.Lock.header")
  return 1

def writeOrCheck (file : System.FilePath) (txt : String) (check : Bool) (count stale : String) :
    IO UInt32 := do
  unless check do
    IO.FS.writeFile file txt
    IO.println (ciLine s!"wrote {file} ({count})")
    return 0
  let old ← IO.FS.readFile file
  if old == txt then
    IO.println (ciLine s!"{file} up to date ({count})")
    return 0
  let lines (s : String) := (s.splitOn "\n").filter (fun l => !l.startsWith "#" && !l.isEmpty)
  let (was, now) := (lines old, lines txt)
  for l in was do unless now.contains l do IO.println (ciLine s!"- {l}")
  for l in now do unless was.contains l do IO.println (ciLine s!"+ {l}")
  IO.println (ciLine s!"{file} is out of date: {stale}.")
  return 1

def coreSrcDir : System.FilePath := "core"

def lockReach (core : Lock.ImportedRoot) : IO UInt32 := do
  let root := core.root
  let dir := Lock.moduleDir coreSrcDir root
  unless ← dir.isDir do
    IO.println (ciLine s!"{dir} is not a folder here, so its modules cannot be checked against statements.lock: run lock from the repository root")
    return 1
  let srcs ← Lock.sourceModules coreSrcDir root
  let missed := Lock.unreached srcs.toList core.env.header.moduleNames.contains
  if missed.isEmpty then
    IO.println (ciLine s!"every module under {dir}/ is reached from {root} ({srcs.size} modules)")
    return 0
  for m in missed do
    IO.println (ciLine s!"{Lean.modToFilePath coreSrcDir m "lean"}: {root} does not import {m}, directly or transitively, so statements.lock has no line for its declarations")
  let n := missed.length
  let (noun, verb, it) := if n == 1 then ("module", "is", "it") else ("modules", "are", "each")
  IO.println (ciLine s!"{n} {noun} under {dir}/ {verb} not reached from {root}: import {it} from {Lean.modToFilePath coreSrcDir root "lean"}, which is a spec change, or delete it")
  return 1

def lockStatements (check : Bool) : IO UInt32 := do
  let headerCode ← if check then lockHeaderStatus else pure 0
  let core ← Lock.importRoot `Mitos.Core
  let es ← Lock.entries core.env [core.root]
  let code ← writeOrCheck "statements.lock" (Lock.render es) check s!"{es.size} declarations"
    "the meaning of the trusted core changed"
  let reachCode ← lockReach core
  return if headerCode != 0 || code != 0 || reachCode != 0 then 1 else 0

/-- Writes or checks `<workspace>/models.lock`. Gate 0's walker reads the models, and gate 0 reads
back what this writes (`Accept.lockEntries_renderLock`). An I/O error is printed as one `::error::`
line through `oneLine`, with exit 1, as `RunLog.cli` prints one. The Lean runtime would print an
uncaught one raw, and the error names the path it failed on: a model file's name, which can hold a
newline and a workflow command. A model file that is not UTF-8 throws one, and so does a name that
is not: Lean reads the name back with U+FFFD, and no file has that name. -/
def lockModels (workspace : System.FilePath) (check : Bool) : IO UInt32 := do
  try
    let files ← Accept.modelFiles workspace
    let es ← files.toList.mapM fun (rel, txt) => return (rel, ← sha256 txt)
    writeOrCheck (workspace / "models.lock") (Accept.renderLock es) check s!"{es.length} models"
      "it does not match the models"
  catch e =>
    let msg := s!"lock-models stopped on an I/O error: {e}"
    IO.println s!"::error::{RunLog.escapeData (oneLine msg)}"
    return 1

def cli (args : List String) : IO UInt32 := do
  match args with
  | "lint" :: files@(_ :: _) =>
    let env ← Lint.syntaxEnv
    let mut bad := 0
    for f in files do
      let vs ← Lint.check env Accept.pluginImports (← IO.FS.readFile f)
      for v in vs do IO.println (ciLine (v.render f))
      bad := bad + vs.size
    IO.println s!"{bad} violation(s)"
    return if bad == 0 then 0 else 1
  | ["imports"] =>
    let vs ← Imports.check "core" Imports.trustedCoreImports
    let vs := vs ++ (← Imports.check ("core" / "Mitos" / "Core") lockedSpecImports)
    let vs := vs ++ (← Imports.check ("gate" / "MitosGate" / "Base") Imports.baseImports)
    let baseRoot : System.FilePath := "gate" / "MitosGate" / "Base.lean"
    let rootVs ← if ← baseRoot.pathExists then
      Imports.checkFile baseRoot Imports.baseImports else pure #[]
    let vs := vs ++ rootVs
    for v in vs do IO.println (ciLine v)
    IO.println s!"{vs.size} import violation(s) in core/ and gate/MitosGate/Base.lean and gate/MitosGate/Base/"
    return if vs.isEmpty then 0 else 1
  | ["lock", "--check-header"] => lockHeaderStatus
  | ["lock"] => lockStatements false
  | ["lock", "--check"] => lockStatements true
  | ["lock-models", "--workspace", ws] => lockModels ws false
  | ["lock-models", "--workspace", ws, "--check"] => lockModels ws true
  | "accept" :: rest =>
    match parseAccept rest { workspace := "", plugin := "", model := "" } with
    | .error e => IO.eprintln (ciLine e); IO.eprintln usage; return 2
    | .ok c =>
      if c.workspace.toString.isEmpty || c.plugin.isEmpty || c.model.isEmpty then
        IO.eprintln usage; return 2
      Accept.runAccept c
  | "runlog" :: rest => RunLog.cli rest usage
  | "content-id" :: rest => ContentId.cli rest usage
  | "carry" :: rest => Carry.cli rest usage
  | "cheats" :: rest => CheatsRun.cli rest usage
  | "land" :: rest => LandCli.cli rest usage
  | "speech" :: rest => SpeechCli.cli rest usage
  | "snapshot" :: rest => SnapshotCli.cli rest usage
  | "shadow" :: rest => ShadowCli.cli rest usage
  | _ => IO.eprintln usage; return 2

def main (args : List String) : IO UInt32 := do
  try cli args
  catch e =>
    IO.eprintln (ciLine s!"uncaught exception: {e}")
    return 1
