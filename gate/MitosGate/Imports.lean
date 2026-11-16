import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def trustedCoreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

/-- What `gate/MitosGate/Base/` may import. `Lint.moduleAllowed` matches these by name components,
so `MitosGate.Base` allows `MitosGate.Base.Text` and nothing else under `MitosGate`. -/
def baseImports : List String := ["Init", "Std", "Lean.Data.Json", "MitosGate.Base"]

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
