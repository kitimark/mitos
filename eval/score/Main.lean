import Score

open Score

def usage : String := "usage: mitos-score <fixture-dir>
  <fixture-dir>/repos/<repo>/...   the fixture repos
  <fixture-dir>/labels.tsv         hand labels (src, dst, kind, key, scope; tab-separated)
Prints the scorecard as Markdown."

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

def main (args : List String) : IO UInt32 := do
  let [dir] := args | IO.eprintln usage; return 2
  let dir : System.FilePath := dir
  let labels ← match parseLabels (← IO.FS.readFile (dir / "labels.tsv")) with
    | .ok ls => pure ls
    | .error e => IO.eprintln e; return 1
  match score (← loadRepos dir) labels with
  | .ok c =>
    IO.print (c.render ((dir.components.filter (!·.isEmpty)).getLast?.getD dir.toString))
    return 0
  | .error e => IO.eprintln e; return 1
