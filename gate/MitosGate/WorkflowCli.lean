import MitosGate.Util
import MitosGate.Yaml
import MitosGate.Workflow.Placement
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

private def pathText (path : List Seg) : String :=
  path.foldl (fun s seg => match seg with
    | .key k => if s.isEmpty then k else s ++ "." ++ k
    | .idx i => s ++ s!"[{i}]") ""

private def placement (file source : String) (doc : Doc) : IO UInt32 := do
  for leaf in doc.leaves do
    unless Workflow.leafPlacementOk leaf do
      let needsViolation := match leaf.value with
        | .text s => Workflow.mentionsNeeds s.toList && !Workflow.allowedAt leaf.path
        | _ => false
      let reason := if needsViolation then
        "needs outside env, job if or job needs (rule N)"
        else "expression in code value (rule X)"
      let line := ((Yaml.textLines? source doc).bind (·.lookup leaf.path)).map
        (fun n => s!":{n}") |>.getD ""
      IO.eprintln (ciLine s!"{file}{line}: refused at {pathText leaf.path}: {reason}")
      return 1
  return 0

def cli (args : List String) (usage : String) : IO UInt32 := do
  setExitOnPanic true
  let [verb, file] := args | do
    IO.eprintln usage
    return 2
  unless verb == "parse" || verb == "leaves" || verb == "placement" do
    IO.eprintln usage
    return 2
  let text ← try IO.FS.readFile file catch e =>
    IO.eprintln (ciLine s!"workflow: cannot read {file}: {e}")
    return 2
  match read text with
  | .ok doc =>
    if verb == "placement" then return ← placement file text doc
    if verb == "leaves" then
      for leaf in doc.leaves do IO.println (leafJson leaf).compress
    return 0
  | .error refusal =>
    let line := if verb == "placement" then
      (refusal.sourceLine? text).map (fun n => s!":{n}") |>.getD "" else ""
    IO.eprintln (ciLine (file ++ line ++ refusal.render))
    return 1

end MitosGate.WorkflowCli
