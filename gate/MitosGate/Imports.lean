import MitosGate.Lint
import MitosGate.Util

/-!
# Import rule

Trusted packages may only import modules whose names start with an allowed prefix. For the
core: `Init`, `Std`, `Mitos.Core`. This keeps the core (and therefore every Challenge's import
closure) free of the Lean frontend and of anything untrusted.
-/

namespace MitosGate.Imports

/-- Violations as rendered strings, for every `.lean` file under `dir`. -/
def check (dir : System.FilePath) (allowed : List String) : IO (Array String) := do
  let mut out := #[]
  for f in ← leanFiles dir do
    let toks := Lint.tokenize (← IO.FS.readFile f)
    for h : k in [0:toks.size] do
      if toks[k].text == "import" then
        if let some m := toks[k+1]? then
          unless Lint.moduleAllowed allowed m.text do
            out := out.push s!"{f}:{m.line}:{m.col}: import `{m.text}` is outside {allowed}"
  return out

end MitosGate.Imports
