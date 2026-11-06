import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def check (dir : System.FilePath) (allowed : List String) : IO (Array String) := do
  let mut out := #[]
  for f in ← leanFiles dir do
    let toks ← Lint.headerTokens (← IO.FS.readFile f)
    for h : k in [0:toks.size] do
      if toks[k].text == "import" then
        if let some m := toks[k+1]? then
          unless Lint.moduleAllowed allowed m.text do
            out := out.push s!"{f}:{m.line}:{m.col}: import `{m.text}` is outside {allowed}"
  return out

end MitosGate.Imports
