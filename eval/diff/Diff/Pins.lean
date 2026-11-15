namespace Diff

structure Pin where
  case : String
  module : String
  version : String
  goModHash : String
  repository : String
  licence : String

def parsePins (text : String) : Except String (List Pin) := do
  let mut out := #[]
  let mut n := 0
  for line in text.splitOn "\n" do
    n := n + 1
    if line.isEmpty || line.startsWith "#" then continue
    match line.splitOn "\t" with
    | [case, module, version, goModHash, repository, licence] =>
      if out.any (·.case == case) then throw s!"pins.tsv:{n}: case {case} listed twice"
      out := out.push { case, module, version, goModHash, repository, licence }
    | fields => throw s!"pins.tsv:{n}: expected 6 tab-separated fields, found {fields.length}"
  return out.toList

end Diff
