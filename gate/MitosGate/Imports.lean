import MitosGate.Lint
import MitosGate.Surface
import MitosGate.Util

namespace MitosGate.Imports

def trustedCoreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def proofsImports : List String := trustedCoreImports ++ ["Mathlib"]

def nonProofsImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl"]

def lockedSpecImports : List String := ["Init", "Std", "Mitos.Core"]

def resolverSpecImports : List String := lockedSpecImports ++ ["Mathlib"]

def gateImports : List String := ["Init", "Std", "Lean", "MitosGate"]

def baseImports : List String := ["Init", "Std", "Lean.Data.Json", "MitosGate.Base"]

def vendorName : String := "L4" ++ "YAML"

def vendorImports : List String := ["Init", "Std", "Lean", vendorName]

def seamFile : System.FilePath := "gate/MitosGate/Yaml.lean"

structure Scope where
  path : System.FilePath
  allowed : List String
  exact : Bool := false
  outsideSurface : Option (List String) := none

def scopes : List Scope := [
  ⟨"core/Mitos/Core", lockedSpecImports, false, some resolverSpecImports⟩,
  ⟨"core/Mitos/Proofs", proofsImports, false, none⟩,
  ⟨"core", nonProofsImports, false, none⟩,
  ⟨"gate/MitosGate/Base.lean", baseImports, true, none⟩,
  ⟨"gate/MitosGate/Base", baseImports, false, none⟩,
  ⟨"gate/vendor/l4yaml", vendorImports, false, none⟩,
  ⟨seamFile, gateImports ++ [vendorName], true, none⟩,
  ⟨"gate", gateImports, false, none⟩]

def grantsMathlib (surface : Option (List String)) (rel : String) : Bool :=
  match surface with
  | some reached => !reached.contains rel
  | none => false

theorem grantsMathlib_iff (surface : Option (List String)) (rel : String) :
    grantsMathlib surface rel = true ↔
      ∃ reached, surface = some reached ∧ reached.contains rel = false := by
  cases surface <;> simp [grantsMathlib]

#guard !grantsMathlib none "Mitos/Core/Graph.lean"
#guard grantsMathlib (some ["Mitos/Core.lean"]) "Mitos/Core/Graph.lean"
#guard !grantsMathlib (some ["Mitos/Core.lean", "Mitos/Core/Fact.lean"]) "Mitos/Core/Fact.lean"

def allowedFor (file : System.FilePath) (rel : String)
    (surface : Option (List String)) : List String :=
  match scopes.find? fun scope =>
      if scope.exact then scope.path.components == file.components
      else scope.path.components.isPrefixOf file.components with
  | some scope =>
    match scope.outsideSurface with
    | some wider => if grantsMathlib surface rel then wider else scope.allowed
    | none => scope.allowed
  | none => []

def checkSource (allowed : List String) (src : String) : IO (Array Lint.Violation) := do
  match ← Lint.headerSyntax src with
  | .error v => return #[v]
  | .ok (fm, header) => return Lint.importRules fm header allowed (strict := false)

def checkFile (file : System.FilePath) (allowed : List String) : IO (Array String) := do
  return (← checkSource allowed (← IO.FS.readFile file)).map (·.render file.toString)

def headerModules (src : String) : IO (Except String (Array Lean.Name)) := do
  match ← Lint.headerSyntax src with
  | .error _ => return .error "its header does not parse"
  | .ok (_, header) =>
    let mut ns : Array Lean.Name := #[]
    for imp in header[2].getArgs do
      if let .ident _ _ n _ := imp[4] then
        ns := ns.push n
    return .ok ns

def surfaceReached (dir : System.FilePath) (files : Array System.FilePath) :
    IO (Option (List String)) := do
  let mut core : Array (String × String) := #[]
  for f in files do
    let rel := relativeTo dir f
    if (System.FilePath.mk rel).components.head? == some "Mitos" then
      core := core.push (rel, ← IO.FS.readFile f)
  if core.isEmpty then return none
  match ← Surface.surfaceClosure core headerModules with
  | .ok paths => return some paths.toList
  | .error _ => return none

def check (dir : System.FilePath)
    (skipDirs : List System.FilePath := []) : IO (Array String) := do
  if !(← dir.isDir) then return #[]
  let files ← dir.walkDir fun path => pure (!skipDirs.contains path)
  let files := (files.filter (·.extension == some "lean")).qsort (·.toString < ·.toString)
  let surface ← surfaceReached dir files
  let mut out := #[]
  for f in files do
    out := out ++ (← checkFile f (allowedFor f (relativeTo dir f) surface))
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
