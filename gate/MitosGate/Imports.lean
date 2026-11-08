import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def check (dir : System.FilePath) (allowed : List String) : IO (Array String) := do
  let mut out := #[]
  for f in ← leanFiles dir do
    let (fm, header) ← Lint.headerSyntax (← IO.FS.readFile f)
    for v in Lint.importRules fm header allowed (strict := false) do
      out := out.push (v.render f.toString)
  return out

end MitosGate.Imports
