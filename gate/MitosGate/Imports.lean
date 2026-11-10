import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def checkSource (allowed : List String) (src : String) : IO (Array Lint.Violation) := do
  match ← Lint.headerSyntax src with
  | .error v => return #[v]
  | .ok (fm, header) => return Lint.importRules fm header allowed (strict := false)

def check (dir : System.FilePath) (allowed : List String) : IO (Array String) := do
  let mut out := #[]
  for f in ← leanFiles dir do
    for v in ← checkSource allowed (← IO.FS.readFile f) do
      out := out.push (v.render f.toString)
  return out

end MitosGate.Imports
