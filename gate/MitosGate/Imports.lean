import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def trustedCoreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def baseImports : List String := ["Init", "Std", "Lean.Data.Json", "MitosGate.Base"]

def checkSource (allowed : List String) (src : String) : IO (Array Lint.Violation) := do
  match ← Lint.headerSyntax src with
  | .error v => return #[v]
  | .ok (fm, header) => return Lint.importRules fm header allowed (strict := false)

def checkFile (file : System.FilePath) (allowed : List String) : IO (Array String) := do
  return (← checkSource allowed (← IO.FS.readFile file)).map (·.render file.toString)

def check (dir : System.FilePath) (allowed : List String) : IO (Array String) := do
  let mut out := #[]
  for f in ← leanFiles dir do
    out := out ++ (← checkFile f allowed)
  return out

end MitosGate.Imports
