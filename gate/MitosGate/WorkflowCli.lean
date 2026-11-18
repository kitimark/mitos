import MitosGate.Util
import MitosGate.Yaml
import MitosGate.Workflow.Placement
import MitosGate.Workflow.Select
import MitosGate.Workflow.Pins
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

private def scalarText : Scalar → String
  | .text s => s
  | .emptyMap => "{}"
  | .emptySeq => "[]"

private def pathText (path : List Seg) : String :=
  path.foldl (fun s seg => match seg with
    | .key k => if s.isEmpty then k else s ++ "." ++ k
    | .idx i => s ++ s!"[{i}]") ""

private def printSelection (values : List String) : IO UInt32 := do
  if values.any (fun value => (value.splitOn "\n").any (fun line => decide (startsCommand line))) then
    IO.eprintln (ciLine "workflow: refused output containing a runner command")
    return 1
  for value in values do IO.println value
  return 0

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


private def request (args : List String) (usage : String) :
    Except String (String × String × Option Workflow.Selector) := do
  match args with
    | [verb, file] =>
      if verb == "parse" || verb == "leaves" || verb == "placement" then return (verb, file, none)
      else throw usage
    | [verb, file, query] =>
      if verb != "get" && verb != "each" then throw usage
      let sel ← (Workflow.parseSelector query.toList).mapError
        fun why => ciLine s!"workflow: refused selector: {why}"
      return (verb, file, some sel)
    | _ => throw usage

def cli (args : List String) (usage : String) : IO UInt32 := do
  setExitOnPanic true
  if let ["pins", root] := args then return ← Workflow.Pins.run root
  match request args usage with
  | .error why =>
    IO.eprintln why
    return 2
  | .ok (verb, file, selector) =>
    let text ← try IO.FS.readFile file catch e =>
      IO.eprintln (ciLine s!"workflow: cannot read {file}: {e}")
      return 2
    match read text with
    | .ok doc =>
      if verb == "placement" then return ← placement file text doc
      match selector with
      | none =>
        if verb == "leaves" then
          for leaf in doc.leaves do IO.println (leafJson leaf).compress
      | some sel =>
        if verb == "each" then
          return ← printSelection ((Workflow.each doc sel).map fun leaf =>
            pathText leaf.path ++ "\t" ++ scalarText leaf.value)
        else match Workflow.get doc sel with
          | .ok value => return ← printSelection [scalarText value]
          | .error why =>
            IO.eprintln (ciLine s!"workflow: {why}")
            return 1
      return 0
    | .error refusal =>
      let line := if verb == "placement" then
        (refusal.sourceLine? text).map (fun n => s!":{n}") |>.getD "" else ""
      IO.eprintln (ciLine (file ++ line ++ refusal.render))
      return 1

end MitosGate.WorkflowCli
