import Diff.Compare

namespace Diff

def Directive.name : Directive → String
  | .module => "module"
  | .require => "require"

def Directive.ofName : String → Option Directive
  | "module" => some .module
  | "require" => some .require
  | _ => none

structure Finding where
  case : String
  mismatch : Mismatch
  deriving DecidableEq, Repr

def Finding.fields : Finding → List String
  | ⟨case, .onlyIn .go directive path⟩ => [case, "only-in-go", directive.name, path]
  | ⟨case, .onlyIn .plugin directive path⟩ => [case, "only-in-plugin", directive.name, path]
  | ⟨case, .order directive⟩ => [case, "order", directive.name, "-"]

def Finding.ofFields : List String → Option Finding
  | [case, "only-in-go", directive, path] =>
    (Directive.ofName directive).map fun d => ⟨case, .onlyIn .go d path⟩
  | [case, "only-in-plugin", directive, path] =>
    (Directive.ofName directive).map fun d => ⟨case, .onlyIn .plugin d path⟩
  | [case, "order", directive, "-"] =>
    (Directive.ofName directive).map fun d => ⟨case, .order d⟩
  | _ => none

theorem Finding.ofFields_fields (f : Finding) : Finding.ofFields f.fields = some f := by
  rcases f with ⟨case, ⟨side, directive, path⟩ | directive⟩ <;>
    (try cases side) <;> cases directive <;> rfl

structure Triage where
  finding : Finding
  issue : Nat

def parseTriage (text : String) : Except String (List Triage) := do
  let mut out := #[]
  let mut n := 0
  for line in text.splitOn "\n" do
    n := n + 1
    if line.isEmpty || line.startsWith "#" then continue
    let fields := line.splitOn "\t"
    let some finding := Finding.ofFields fields.dropLast
      | throw s!"triage.tsv:{n}: expected a case, a mismatch and an issue, found {repr fields}"
    let some issue := (fields.getLast?.getD "").dropPrefix? "#" |>.bind (·.toString.toNat?)
      | throw s!"triage.tsv:{n}: the last field is not an issue such as #123"
    out := out.push { finding, issue }
  return out.toList

def Triage.issuesFor (triage : List Triage) (f : Finding) : List Nat :=
  (triage.filter (·.finding == f)).map (·.issue)

end Diff
