import MitosGate.Yaml.View

open MitosGate.Yaml

def seed : UInt64 := 20261117

def next (s : UInt64) : UInt64 := s * 6364136223846793005 + 1442695040888963407

def atom (s : UInt64) : Node :=
  match s.toNat % 7 with
  | 0 => .map []
  | 1 => .seq []
  | 2 => .text ""
  | 3 => .text "${{x}}"
  | 4 => .text "a${{x}}${{y}}"
  | 5 => .text "line\nnext"
  | _ => .text s!"v{s.toNat}"

def generate : Nat → UInt64 → Node × UInt64
  | 0, s => (atom s, next s)
  | d + 1, s => Id.run do
    let t := next s
    if s.toNat % 5 < 3 then return (atom t, next t)
    let width := t.toNat % 4 + 1
    let mut cursor := next t
    let mut items := []
    for _ in List.range width do
      let (item, after) := generate d cursor
      cursor := after
      items := item :: items
    if s.toNat % 5 == 3 then return (.seq items.reverse, cursor)
    return (.map (items.reverse.zipIdx.map fun (n, i) => (s!"k{i}", n)), cursor)

def observations : Nat → Node → List (List Seg × Option Scalar)
  | 0, _ => []
  | fuel + 1, n =>
    let here : Option Scalar := match n with
      | .text s => some (.text s)
      | .seq [] => some .emptySeq
      | .map [] => some .emptyMap
      | _ => none
    let bad : List (List Seg × Option Scalar) := match n with
      | .text _ => [([.idx 0], none), ([.key "__missing"], none)]
      | .seq ns => [([.idx ns.length], none), ([.key "k0"], none)]
      | .map _ => [([.key "__missing"], none), ([.idx 0], none)]
    let below := match n with
      | .text _ => []
      | .seq ns => ns.zipIdx.flatMap fun (child, i) =>
        (observations fuel child).map fun (path, scalar) => (.idx i :: path, scalar)
      | .map es => es.flatMap fun (k, child) =>
        (observations fuel child).map fun (path, scalar) => (.key k :: path, scalar)
    ([], here) :: bad ++ below

def verify (i : Nat) (n : Node) : IO (Nat × Nat) := do
  let d ← match Doc.ofNode n with
    | .error problem => throw (IO.userError s!"tree {i} unexpectedly refused: {repr problem}")
    | .ok d => pure d
  let cases := observations 7 n
  let expected := cases.filterMap fun (path, scalar) => scalar.map (Leaf.mk path)
  unless d.leaves == expected do
    throw (IO.userError s!"tree {i}: ordered leaves differ\n{repr n}\n{repr d.leaves}\n{repr expected}")
  unless decide ((d.leaves.map (·.path)).Nodup) do
    throw (IO.userError s!"tree {i}: duplicate leaf paths")
  for (path, want) in cases do
    unless d.scalarAt? path == want do
      throw (IO.userError s!"tree {i}: scalar lookup at {repr path}: {repr (d.scalarAt? path)} != {repr want}")
    unless (d.leaves.any fun l => l.path == path) == want.isSome do
      throw (IO.userError s!"tree {i}: leaf membership disagrees at {repr path}")
  return (cases.length, d.leaves.length)

def invalid : List Node :=
  [.map [("a", .text "1"), ("A", .text "2")],
   .map [("a", .text "1"), ("a", .text "2")],
   .map [("${{x}}", .text "1")],
   .map [("<<", .map [])],
   .map [("", .text "1")],
   .text "a\tb",
   .map [("a", .seq [.map [("bad\r", .text "x")]])],
   .seq [.map [("k", .text "é")]]]

def main : IO Unit := do
  let mut cursor := seed
  let mut lookups := 0
  let mut leaves := 0
  for i in List.range 4000 do
    let (randomTree, after) := generate 5 cursor
    cursor := after
    let tree := match i with
      | 0 => .text "${{root}}"
      | 1 => .map []
      | 2 => .seq []
      | _ => randomTree
    let (checked, count) ← verify i tree
    lookups := lookups + checked
    leaves := leaves + count
  for n in invalid do
    match Doc.ofNode n with
    | .error _ => pure ()
    | .ok _ => throw (IO.userError s!"invalid tree accepted: {repr n}")
  IO.println s!"PASS seed={seed.toNat} trees=4000 scalar-lookups={lookups} leaves={leaves} invalid-refusals={invalid.length}"
