import MitosGate.ShadowCli.Report
import MitosGate.Util

/-!
# `mitos-gate shadow`: what `decide` would have done, against what merged

`mitos-gate shadow <dir>` reads the folder that `gate/shadow-fetch.sh` wrote and prints the report:
one line per merge, newest first, then the counts, the cost and the runs. A record that cannot be
read, or whose decision this build does not repeat, is listed and not scored. A folder file that is
missing or not of its shape is exit 1, and a usage error exit 2.
-/

open Lean (Json)

namespace MitosGate.ShadowCli

private def stop (m : String) : IO UInt32 := do
  IO.eprintln (ciLine s!"shadow: {m}")
  return 1

private def load (dir : System.FilePath) (name : String) (d : Json → Except String α) :
    ExceptT String IO α := do
  let p := dir / name
  unless ← p.pathExists do throw s!"{name} is missing"
  match Json.parse (← IO.FS.readFile p) with
  | .error e => throw s!"{name} is not JSON: {e}"
  | .ok j =>
    match d j with
    | .ok a => return a
    | .error e => throw s!"{name}{e}"

/-- The `<run>` of `<run>-<attempt>`. -/
def runOf (stem : String) : Option Nat :=
  match stem.splitOn "-" with
  | [r, a] => if a.toNat?.isSome then r.toNat? else none
  | _ => none

def window (dir : System.FilePath) : ExceptT String IO Window := do
  let merges ← load dir "merges.json" merges
  let jobs ← load dir "runs.json" jobs
  let ci ← load dir "baseline.json" updaterCiRuns
  let recDir := dir / "records"
  unless ← recDir.isDir do throw "records/ is missing"
  let stems := ((← recDir.readDir).toList.filterMap fun e =>
    if e.fileName.endsWith ".json" then some (e.fileName.dropEnd 5).toString else none).mergeSort
  let mut records := #[]
  let mut recorded := #[]
  for stem in stems do
    let some run := runOf stem
      | records := records.push (stem, .error "the name is not <run>-<attempt>.json")
    recorded := recorded.push run
    match Json.parse (← IO.FS.readFile (recDir / (stem ++ ".json"))) with
    | .error e => records := records.push (stem, .error s!"not JSON: {e}")
    | .ok j => records := records.push (stem, run? run j)
  return ⟨merges, records.toList, recorded.toList, jobs, ci⟩

def score (dir : System.FilePath) : IO UInt32 := do
  match ← (window dir).run with
  | .error e => stop e
  | .ok w =>
    for l in report w do IO.println (ciLine l)
    return 0

def cli (args : List String) (usage : String) : IO UInt32 := do
  match args with
  | [dir] =>
    try score dir
    catch e => stop s!"stopped on an I/O error: {e}"
  | _ =>
    IO.eprintln "shadow takes one argument, the folder that gate/shadow-fetch.sh wrote"
    IO.eprintln usage
    return 2

end MitosGate.ShadowCli
