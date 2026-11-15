import Diff.Go
import Diff.Pins
import Diff.Plugin
import Diff.Report
import Diff.Triage

open Diff

def usage : String := "usage: mitos-diff <dir> [--refresh]
  <dir>/.go-version               the Go release of every module.json, as actions/setup-go reads it
  <dir>/pins.tsv                  case, module, version, go.mod hash, repository, licence
  <dir>/triage.tsv                case, mismatch, issue: the mismatches a model issue explains
  <dir>/cases/<case>/module.mod   the pinned go.mod, as proxy.golang.org serves it
  <dir>/cases/<case>/module.json  `go mod edit -json` of it
Prints the report as Markdown. Exit 0 when every mismatch is triaged and every triage line
matches one, 1 when not, 2 on bad input. --refresh first rewrites each module.json with the Go
release that .go-version names."

def caseDirs (cases : System.FilePath) : IO (List String) := do
  let mut out := #[]
  for e in ← cases.readDir do
    if ← e.path.isDir then out := out.push e.fileName
  return out.toList.mergeSort (· ≤ ·)

def report (cases : System.FilePath) (p : Pin) : ExceptT String IO CaseReport := do
  let text ← IO.FS.readFile (cases / p.case / "module.mod")
  let json ← IO.FS.readFile (cases / p.case / "module.json")
  match Keys.ofGoJson json with
  | .error e => throw s!"{p.case}/module.json: {e}"
  | .ok goKeys =>
    return { case := p.case, module := p.module, version := p.version, goKeys,
             pluginKeys := Keys.ofPlugin text, unread := unreadLines text }

def run (dir : System.FilePath) (withRefresh : Bool) : ExceptT String IO UInt32 := do
  let goVersion := "go" ++ (← IO.FS.readFile (dir / ".go-version")).trimAscii.toString
  let pins ← liftExcept <| parsePins (← IO.FS.readFile (dir / "pins.tsv"))
  let triage ← liftExcept <| parseTriage (← IO.FS.readFile (dir / "triage.tsv"))
  let cases := dir / "cases"
  let dirs ← caseDirs cases
  let listed := (pins.map (·.case)).mergeSort (· ≤ ·)
  unless dirs == listed do
    throw s!"cases/ holds {dirs}, pins.tsv lists {listed}"
  if withRefresh then
    unless ← refresh cases goVersion pins do return 2
  let mut reports := #[]
  for p in pins do
    reports := reports.push (← report cases p)
  IO.print (render goVersion reports.toList triage)
  return if (verdict reports.toList triage).clean then 0 else 1
where
  liftExcept {α} : Except String α → ExceptT String IO α := fun e => ExceptT.mk (pure e)

def main (args : List String) : IO UInt32 := do
  let (dir, withRefresh) ← match args with
    | [dir] => pure (dir, false)
    | [dir, "--refresh"] => pure (dir, true)
    | _ => do IO.eprintln usage; return 2
  try
    match ← (run dir withRefresh).run with
    | .ok code => return code
    | .error e => IO.eprintln e; return 2
  catch e =>
    IO.eprintln e
    return 2
