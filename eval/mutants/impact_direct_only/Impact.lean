import Mitos.Core

/-!
# Impact analysis  (IMPLEMENTATION — not in the lock; correctness is `impact_correct`)

Reverse reachability with a worklist of unused edges. Each step takes one edge whose provider is
`x` or already affected, marks its requirer affected, and drops the edge. Every edge is used at
most once, so the recursion is on the number of remaining edges.

The result may repeat a repo name; membership is what the specification constrains.
-/

namespace Mitos.Impl

/-- Can edge `e` propagate a change to `x` given the repos already known to be affected? -/
def fires (x : String) (seen : List String) (e : Edge) : Bool :=
  e.dst == x

def impactGo (x : String) (rest : List Edge) (seen : List String) : List String :=
  match h : rest.find? (fires x seen) with
  | none => seen
  | some e =>
    have : (rest.erase e).length < rest.length := by
      have hm := List.mem_of_find?_eq_some h
      rw [List.length_erase_of_mem hm]
      have := List.length_pos_of_mem hm
      omega
    impactGo x (rest.erase e) (e.src :: seen)
termination_by rest.length

/-- The repos that a change to `x` may affect. -/
def impact (es : List Edge) (x : String) : List String :=
  impactGo x es []

end Mitos.Impl
