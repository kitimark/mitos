import Mitos.Core

namespace Mitos.Impl

def fires (x : String) (seen : List String) (e : Edge) : Bool :=
  e.dst == x || seen.contains e.dst

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
