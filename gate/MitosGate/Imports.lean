import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Imports

def trustedCoreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def proofsImports : List String := trustedCoreImports ++ ["Mathlib"]

def nonProofsImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl"]

def lockedSpecImports : List String := ["Init", "Std", "Mitos.Core"]

def gateImports : List String := ["Init", "Std", "Lean", "MitosGate"]

def baseImports : List String := ["Init", "Std", "Lean.Data.Json", "MitosGate.Base"]

def vendorName : String := "L4" ++ "YAML"

def vendorImports : List String := ["Init", "Std", "Lean", vendorName]

def seamFile : System.FilePath := "gate/MitosGate/Yaml.lean"

structure Scope where
  path : System.FilePath
  allowed : List String
  exact : Bool := false

def scopes : List Scope := [
  ⟨"core/Mitos/Core", lockedSpecImports, false⟩,
  ⟨"core/Mitos/Proofs", proofsImports, false⟩,
  ⟨"core", nonProofsImports, false⟩,
  ⟨"gate/MitosGate/Base.lean", baseImports, true⟩,
  ⟨"gate/MitosGate/Base", baseImports, false⟩,
  ⟨"gate/vendor/l4yaml", vendorImports, false⟩,
  ⟨seamFile, gateImports ++ [vendorName], true⟩,
  ⟨"gate", gateImports, false⟩]

def allowedFor (file : System.FilePath) : List String :=
  let scope := scopes.find? fun scope =>
    if scope.exact then scope.path.components == file.components
    else scope.path.components.isPrefixOf file.components
  scope.map (·.allowed) |>.getD []

def checkSource (allowed : List String) (src : String) : IO (Array Lint.Violation) := do
  match ← Lint.headerSyntax src with
  | .error v => return #[v]
  | .ok (fm, header) => return Lint.importRules fm header allowed (strict := false)

def checkFile (file : System.FilePath) (allowed : List String) : IO (Array String) := do
  return (← checkSource allowed (← IO.FS.readFile file)).map (·.render file.toString)

def check (dir : System.FilePath)
    (skipDirs : List System.FilePath := []) : IO (Array String) := do
  if !(← dir.isDir) then return #[]
  let files ← dir.walkDir fun path => pure (!skipDirs.contains path)
  let files := (files.filter (·.extension == some "lean")).qsort (·.toString < ·.toString)
  let mut out := #[]
  for f in files do
    out := out ++ (← checkFile f (allowedFor f))
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
