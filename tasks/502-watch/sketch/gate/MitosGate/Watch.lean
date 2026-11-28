import MitosGate.Watch.KeyMap
import MitosGate.Watch.Time
import MitosGate.Watch.Route
import MitosGate.Watch.Voice
import MitosGate.Watch.Observe
import MitosGate.Watch.View
import MitosGate.Watch.Feed
import MitosGate.Watch.Shared
import MitosGate.Watch.Topic
import MitosGate.Watch.Wake
import MitosGate.Watch.Deliver
import MitosGate.Watch.Render

namespace MitosGate.Watch

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let env ← getEnv
  let inWatch (n : Name) := (`MitosGate.Watch).isPrefixOf n
  let theorems := env.constants.fold (fun acc n c =>
    if inWatch n && c.isTheorem then acc.push (n, c.type) else acc) #[]
  unless theorems.any (fun (n, _) => (`MitosGate.Watch.Fixture).isPrefixOf n) do
    throwError "no fixture theorem found"
  let statements := env.constants.fold (fun acc n c =>
    match c with
    | .defnInfo d => if inWatch n && d.type == .sort .zero then acc.push n else acc
    | _ => acc) #[]
  for s in statements do
    unless theorems.any (fun (_, t) => t == .const s []) do
      throwError "the statement {s} has no theorem"
  let everything := env.constants.fold (fun acc n _ => if inWatch n then acc.push n else acc) #[]
  for n in everything do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Watch
