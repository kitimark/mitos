import MitosGate.Watch.Time
import MitosGate.Watch.Voice
import MitosGate.Watch.Observe

namespace MitosGate.WatchAudit

open Lean

def predicates : List Name := []

def auditedStatements : CoreM (Array Name) := do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let inWatch (n : Name) := (`MitosGate.Watch).isPrefixOf (privateToUserName n)
  let everything := (← getEnv).constants.fold
    (fun acc n c => if inWatch n then acc.push (n, c) else acc) #[]
  let theorems := everything.filter fun (_, c) => c.isTheorem
  unless theorems.any (fun (n, _) => (`MitosGate.Watch.Fixture).isPrefixOf (privateToUserName n)) do
    throwError "no fixture theorem found"
  let mut found : Array Name := #[]
  for (n, c) in everything do
    let .defnInfo d := c | continue
    unless d.type.getForallBody == .sort .zero do continue
    if d.type == .sort .zero then
      unless theorems.any (fun (_, t) => t.type.isConstOf n) do
        throwError "the statement {n} has no theorem"
      found := found.push n
    else unless predicates.contains n do
      throwError "{n} is a definition into Prop that takes arguments: write a statement outside \
        any `variable` section, or name a predicate in `MitosGate.WatchAudit.predicates`"
  if found.isEmpty then throwError "no statement found"
  for p in predicates do
    unless everything.any (·.1 == p) do throwError "the predicate {p} is not defined"
  for (n, _) in everything do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"
  return found.qsort (·.toString < ·.toString)

end MitosGate.WatchAudit

#eval show Lean.CoreM Unit from discard MitosGate.WatchAudit.auditedStatements
