import Score
import Score.Nightly

open Score

def usage : String := "usage: mitos-score <fixture-dir>
       mitos-score --all <fixtures-dir> [<baseline>]
       mitos-score --numbers <fixtures-dir>
  <fixture-dir>/repos/<repo>/...   the fixture repos
  <fixture-dir>/labels.tsv         hand labels (src, dst, kind, key, scope; tab-separated)
  <fixtures-dir>/<fixture>/        every directory is one fixture, taken in name order
  <baseline>                       what --numbers printed on another run, such as main's
Prints the scorecard as Markdown. --all prints the nightly scorecard: every fixture's numbers,
the most derivations of one repo-level edge, the diff against <baseline>, then every card.
--numbers prints the lines a later run reads as <baseline>, and none if a fixture fails."

def sortPaths (ps : Array System.FilePath) : List System.FilePath :=
  ps.toList.mergeSort (·.toString ≤ ·.toString)

def loadRepos (dir : System.FilePath) : IO (List SourceFile) := do
  let root := dir / "repos"
  let mut out := #[]
  for repoDir in sortPaths ((← root.readDir).map (·.path)) do
    unless ← repoDir.isDir do continue
    let repo := repoDir.fileName.getD ""
    for p in sortPaths (← repoDir.walkDir) do
      if ← p.isDir then continue
      let path := (p.toString.drop (repoDir.toString.length + 1)).toString
      out := out.push { repo, path, text := ← IO.FS.readFile p }
  return out.toList

def scoreDir (dir : System.FilePath) : IO (Except String Scorecard) := do
  match parseLabels (← IO.FS.readFile (dir / "labels.tsv")) with
  | .ok labels => return score (← loadRepos dir) labels
  | .error e => return .error e

def fixtureName (dir : System.FilePath) : String :=
  (dir.components.filter (!·.isEmpty)).getLast?.getD dir.toString

def scoreAll (root : System.FilePath) : IO (List Nightly.Result) := do
  let mut out := #[]
  for d in sortPaths ((← root.readDir).map (·.path)) do
    unless ← d.isDir do continue
    let name := fixtureName d
    let card ←
      if !(← (d / "labels.tsv").pathExists) then pure (.error "labels.tsv is missing")
      else if !(← (d / "repos").isDir) then pure (.error "repos/ is missing")
      else try Nightly.checked name <$> scoreDir d catch _ => pure (.error "a file could not be read")
    out := out.push { name, card }
  return out.toList

def main (args : List String) : IO UInt32 := do
  match args with
  | [dir] =>
    if dir.startsWith "-" then
      IO.eprintln usage
      return 2
    match ← scoreDir dir with
    | .ok c => IO.print (c.render (fixtureName dir)); return 0
    | .error e => IO.eprintln e; return 1
  | ["--numbers", root] =>
    match Nightly.numbersAll (← scoreAll root) with
    | .ok ls => for l in ls do IO.println l
                return 0
    | .error es => for e in es do IO.eprintln e
                   return 1
  | "--all" :: root :: rest =>
    let base ← match rest with
      | [] => pure (Except.ok none)
      | [b] => (·.map some) <$> Nightly.parseNumbers <$> IO.FS.readFile b
      | _ => IO.eprintln usage; return 2
    match base with
    | .error e => IO.eprintln s!"baseline {e}"; return 1
    | .ok base =>
      let rs ← scoreAll root
      IO.print (Nightly.report rs base)
      return if rs.all (·.card.isOk) then 0 else 1
  | _ => IO.eprintln usage; return 2
