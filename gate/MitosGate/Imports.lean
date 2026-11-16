import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def trustedCoreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def baseImports : List String := ["Init", "Std", "Lean.Data.Json", "MitosGate.Base"]

def vendorName : String := "L4" ++ "YAML"

def vendorImports : List String := ["Init", "Std", "Lean", vendorName]

def seamFile : System.FilePath := "gate/MitosGate/Yaml.lean"

def checkSource (allowed : List String) (src : String) : IO (Array Lint.Violation) := do
  match ← Lint.headerSyntax src with
  | .error v => return #[v]
  | .ok (fm, header) => return Lint.importRules fm header allowed (strict := false)

def checkFile (file : System.FilePath) (allowed : List String) : IO (Array String) := do
  return (← checkSource allowed (← IO.FS.readFile file)).map (·.render file.toString)

def check (dir : System.FilePath) (allowed : List String)
    (skipDirs : List System.FilePath := []) : IO (Array String) := do
  if !(← dir.isDir) then return #[]
  let files ← dir.walkDir fun path => pure (!skipDirs.contains path)
  let files := (files.filter (·.extension == some "lean")).qsort (·.toString < ·.toString)
  let mut out := #[]
  for f in files do
    out := out ++ (← checkFile f allowed)
  return out

def checkSeam (gateDir : System.FilePath) : IO (Array String) := do
  let mut out := #[]
  for f in ← leanFiles gateDir do
    let rel := f.components.drop gateDir.components.length
    unless rel.head? == some "vendor" || rel == seamFile.components.drop 1 do
      if (← IO.FS.readFile f).contains vendorName then
        out := out.push s!"{f}: {vendorName} may appear only under gate/vendor/ or in {seamFile}"
  return out

end MitosGate.Imports
