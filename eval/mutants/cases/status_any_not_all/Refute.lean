import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def strNoLiterals (cs : List Char) : String := String.ofList cs

def loc (id : Nat) (repo : String) (kind : FactKind) (origin : Assumption) : Located :=
  { id, repo, rev := strNoLiterals [], path := strNoLiterals [], origin,
    fact := { kind, ident := ⟨strNoLiterals ['n', 'p', 'm'], strNoLiterals ['l', 'i', 'b']⟩,
              span := ⟨0, 0⟩ } }

def fs : List Located :=
  [loc 0 (strNoLiterals ['a']) .requires (.ai (strNoLiterals ['g'])),
    loc 1 (strNoLiterals ['b']) .provides (.extractor (strNoLiterals ['x']))]

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
