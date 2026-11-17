import MitosGate.Yaml.View

namespace MitosGate.Workflow

open Yaml

inductive Pick where
  | key (k : String)
  | anyKey
  | idx (i : Nat)
  | anyIdx
  | named (n : String)
  | usesPrefix (p : String)
  deriving DecidableEq, Repr

abbrev Selector := List Pick

private def keyChar (c : Char) : Bool := c.isAlphanum || c == '_' || c == '-'

private def keyPick (cs : List Char) : Except String Pick :=
  if cs == ['*'] then .ok .anyKey
  else if !cs.isEmpty && cs.all keyChar then .ok (.key (String.ofList cs))
  else .error "expected a key or *"

private def bracketPick (cs : List Char) : Except String Pick := do
  let s := String.ofList cs
  if s == "*" then return .anyIdx
  if !cs.isEmpty && cs.all Char.isDigit then
    let some i := s.toNat? | throw "invalid sequence index"
    return .idx i
  let predicate (marker : String) (make : String → Pick) : Except String Pick :=
    let value := String.ofList (cs.drop marker.length)
    if value.isEmpty || !value.toList.all (fun c => ' ' ≤ c && c ≤ '~' && c != '[') then
      .error "expected a nonempty predicate value"
    else .ok (make value)
  if s.startsWith "name=" then return ← predicate "name=" .named
  if s.startsWith "uses^=" then return ← predicate "uses^=" .usesPrefix
  throw "expected an index, *, name=, or uses^="

private def parseTail : Nat → List Char → Except String Selector
  | 0, _ => .error "selector is too long"
  | _ + 1, [] => .ok []
  | fuel + 1, '.' :: cs => do
    let (key, rest) := cs.span fun c => c != '.' && c != '['
    return (← keyPick key) :: (← parseTail fuel rest)
  | fuel + 1, '[' :: cs => do
    let (body, rest) := cs.span (· != ']')
    let ']' :: rest := rest | throw "unclosed selector bracket"
    return (← bracketPick body) :: (← parseTail fuel rest)
  | _, _ => .error "expected . or ["

/-- Keys contain letters, digits, underscores, or hyphens. Brackets admit only a natural
index, *, name=<literal>, or uses^=<literal>; literals are nonempty printable ASCII without
brackets. No quoting, escaping, expressions, or recursive descent is supported. -/
def parseSelector (cs : List Char) : Except String Selector := do
  let (key, rest) := cs.span fun c => c != '.' && c != '['
  return (← keyPick key) :: (← parseTail (cs.length + 1) rest)

private def sibling (leaves : List Leaf) (path : List Seg) (key : String)
    (test : String → Bool) : Bool :=
  leaves.any fun leaf => leaf.path == path ++ [.key key] && match leaf.value with
    | .text value => test value
    | _ => false

private def selects (leaves : List Leaf) : List Seg → Selector → List Seg → Bool
  | _, [], _ => true
  | _, _ :: _, [] => false
  | parent, pick :: picks, seg :: path =>
    let next := parent ++ [seg]
    let selected := match pick, seg with
      | .key k, .key actual => k == actual
      | .anyKey, .key _ => true
      | .idx i, .idx actual => i == actual
      | .anyIdx, .idx _ => true
      | .named n, .idx _ => sibling leaves next "name" (· == n)
      | .usesPrefix p, .idx _ => sibling leaves next "uses" (·.startsWith p)
      | _, _ => false
    selected && selects leaves next picks path

def each (d : Doc) (sel : Selector) : List Leaf :=
  let leaves := d.leaves
  leaves.filter fun leaf => selects leaves [] sel leaf.path

def get (d : Doc) (sel : Selector) : Except String Scalar :=
  match (each d sel).map (·.value) with
  | [value] => .ok value
  | _ => .error "expected exactly one matching leaf"

theorem get_ok_iff : get d sel = .ok v ↔ (each d sel).map (·.value) = [v] := by
  cases h : (each d sel).map (·.value) with
  | nil => simp [get, h]
  | cons x xs =>
    cases xs with
    | nil => simp [get, h]
    | cons y ys => simp [get, h]

end MitosGate.Workflow
