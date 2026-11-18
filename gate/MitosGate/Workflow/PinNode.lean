import MitosGate.Yaml.View

namespace MitosGate.Workflow.PinNode

open Yaml

def hasIdentifierCI (identifier value : String) : Bool :=
  let lower (s : String) := String.ofList (s.toList.map fun c =>
    if 'A' ≤ c && c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c)
  !identifier.isEmpty && go (lower identifier).toList false (lower value).toList
where
  wordChar (c : Char) : Bool := c.isAlphanum || c == '_'
  go (needle : List Char) : Bool → List Char → Bool
    | _, [] => false
    | previous, c :: rest =>
      (!previous && needle.isPrefixOf (c :: rest) &&
        !(((c :: rest).drop needle.length).head?.map wordChar |>.getD false)) ||
        go needle (wordChar c) rest

def same (actual expected : Node) : Bool :=
  let actualLeaves := actual.leaves
  let expectedLeaves := expected.leaves
  actualLeaves.length == expectedLeaves.length &&
    actualLeaves.all expectedLeaves.contains

def nodeAt (d : Doc) (path : List Seg) (expected : Node) : Bool :=
  match d.root.get? path with
  | some actual => same actual expected
  | none => false

def textAt? (d : Doc) (path : List Seg) : Option String :=
  match d.root.get? path with
  | some (.text value) => some value
  | _ => none

def mapAt? (d : Doc) (path : List Seg) : Option (List (String × Node)) :=
  match d.root.get? path with
  | some (.map entries) => some entries
  | _ => none

def seqAt? (d : Doc) (path : List Seg) : Option (List Node) :=
  match d.root.get? path with
  | some (.seq items) => some items
  | _ => none

def keysAt (d : Doc) (path : List Seg) (keys : List String) : Bool :=
  match mapAt? d path with
  | some entries => entries.length == keys.length && entries.all (fun entry => keys.contains entry.1)
  | none => false

example : same (.map [("a", .text "1"), ("b", .text "2")])
    (.map [("b", .text "2"), ("a", .text "1")]) = true := by decide +kernel
example : same (.text "{}") (.map []) = false := by decide +kernel
example : same (.map [("nested", .text "condition")]) (.text "condition") = false := by decide +kernel
example : same (.seq [.text "a", .text "b"]) (.seq [.text "b", .text "a"]) = false := by decide +kernel
example : hasIdentifierCI "secrets" "${{ SeCrEtS['KEY'] }}" = true := by decide +kernel
example : hasIdentifierCI "secrets" "${{ toJSON(secrets) }}" = true := by decide +kernel
example : hasIdentifierCI "secrets" "secretsauce other_secrets" = false := by decide +kernel

end MitosGate.Workflow.PinNode
