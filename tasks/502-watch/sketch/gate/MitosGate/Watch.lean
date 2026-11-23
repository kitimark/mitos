import MitosGate.Watch.KeyMap
import MitosGate.Watch.Time
import MitosGate.Watch.Route
import MitosGate.Watch.Voice
import MitosGate.Watch.Observe
import MitosGate.Watch.View
import MitosGate.Watch.Feed
import MitosGate.Watch.Shared
import MitosGate.Watch.Wake
import MitosGate.Watch.Deliver
import MitosGate.Watch.Render

/-! UNCHECKED SKETCH (#502). The pure watcher, and its axiom audit, as `Snapshot.lean` audits its
statements. Each PR imports only the modules that exist after it (PR 2: `Time`, `Voice`, `Observe`).
The audit lists nothing by hand. It checks every constant under `MitosGate.Watch`, definitions as
well as theorems, and fails the build when one depends on an axiom beyond the standard three, so a
`sorry` (`sorryAx`) in a definition that no theorem reaches fails too. It finds every named
statement (a `def` whose type is exactly `Prop`) and fails when no theorem there has that statement
as its type. A statement that picked up a `variable` binder would have a function type and escape
that second check, so statements are written outside every `variable` section, as `KeyMap.lean`
does (`HANDOVER.md`, Lean rules). `Gh`, `Store` and `WatchCli` are IO and are not imported here;
`gate/watch-test.sh` fails when the build log reports `sorry` in any `gate/MitosGate/Watch*` file.
`WatchCli` imports this module, which is what puts the audit in the build. -/

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
