import MitosGate.Util
import MitosGate.Yaml
import Lean.Data.Json

namespace MitosGate.WorkflowCli

open Yaml Lean

@[extern "lean_internal_set_exit_on_panic"]
private opaque setExitOnPanic (exit : Bool) : BaseIO Unit

def leafJson (leaf : Leaf) : Json :=
  let path := leaf.path.map fun
    | .key k => Json.str k
    | .idx i => toJson i
  let value := match leaf.value with
    | .text s => Json.str s
    | .emptyMap => Json.mkObj []
    | .emptySeq => Json.arr #[]
  Json.mkObj [("path", .arr path.toArray), ("value", value)]

def cli (args : List String) (usage : String) : IO UInt32 := do
  setExitOnPanic true
  let [verb, file] := args | do
    IO.eprintln usage
    return 2
  unless verb == "parse" || verb == "leaves" do
    IO.eprintln usage
    return 2
  let text ← try IO.FS.readFile file catch e =>
    IO.eprintln (ciLine s!"workflow: cannot read {file}: {e}")
    return 2
  match read text with
  | .ok doc =>
    if verb == "leaves" then
      for leaf in doc.leaves do IO.println (leafJson leaf).compress
    return 0
  | .error refusal =>
    IO.eprintln (ciLine (file ++ refusal.render))
    return 1

end MitosGate.WorkflowCli
