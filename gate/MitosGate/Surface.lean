import Lean

namespace MitosGate.Surface

private def surfaceRoot : String := "Mitos/Core.lean"

private def allowed (n : Lean.Name) : Bool :=
  [`Init, `Std, `Mitos.Core].any (·.isPrefixOf n)

private def modulePath (n : Lean.Name) : String :=
  ((System.mkFilePath (n.toString.splitOn ".")).addExtension "lean").toString

private def walk (files : List (String × Array Lean.Name)) (queue : List String)
    (seen : List String) (fuel : Nat) : Except String (List String) :=
  match fuel, queue with
  | _, [] => .ok seen
  | 0, _ => .error "the import closure of Mitos/Core.lean did not finish"
  | fuel + 1, rel :: rest => do
    let some (_, imports) := files.find? (·.1 == rel)
      | throw s!"{rel} is not a file of the core"
    let mut next := rest
    let mut got := if seen.contains rel then seen else rel :: seen
    for n in imports do
      if !allowed n then
        throw s!"{rel} imports {n}; the plugin surface may import only Init, Std and Mitos.Core"
      if (`Mitos.Core).isPrefixOf n then
        let path := modulePath n
        if !files.any (·.1 == path) then
          throw s!"{rel} imports {n}, and {path} is not a file of the core"
        if !got.contains path then
          got := path :: got
          next := path :: next
    walk files next got fuel

private def closureOf (files : List (String × Array Lean.Name)) : Except String (Array String) := do
  let reached ← walk files [surfaceRoot] [] (files.length + 1)
  return (files.toArray.map (·.1)).filter reached.contains

def surfaceClosure (core : Array (String × String))
    (header : String → IO (Except String (Array Lean.Name))) : IO (Except String (Array String)) := do
  let mut parsed : List (String × Array Lean.Name) := []
  for (rel, txt) in core do
    match ← header txt with
    | .error e => return .error s!"{rel}: {e}"
    | .ok ns => parsed := parsed ++ [(rel, ns)]
  return closureOf parsed

private def sameClosure (files : List (String × Array Lean.Name))
    (expect : Except String (Array String)) : Bool :=
  match closureOf files, expect with
  | .error a, .error b => a == b
  | .ok a, .ok b => a == b
  | _, _ => false

#guard sameClosure [
    ("Mitos/Core.lean", #[`Mitos.Core.Fact]),
    ("Mitos/Core/Fact.lean", #[`Lean]),
  ] (.error "Mitos/Core/Fact.lean imports Lean; the plugin surface may import only Init, Std and Mitos.Core")

#guard sameClosure [("Mitos/Core.lean", #[`Mitos.Core.Graph])]
  (.error "Mitos/Core.lean imports Mitos.Core.Graph, and Mitos/Core/Graph.lean is not a file of the core")

#guard sameClosure [] (.error "Mitos/Core.lean is not a file of the core")

#guard sameClosure [
    ("Mitos/Core.lean", #[`Init, `Std.Data.List.Basic, `Mitos.Core.Fact, `Mitos.Core.Lines]),
    ("Mitos/Core/Fact.lean", #[]),
    ("Mitos/Core/Lines.lean", #[`Mitos.Core.Fact]),
    ("Mitos/Core/Graph.lean", #[`Init]),
  ] (.ok #["Mitos/Core.lean", "Mitos/Core/Fact.lean", "Mitos/Core/Lines.lean"])

end MitosGate.Surface
