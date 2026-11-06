import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin := Assumption.extractor "x")
    (scope := Scope.runtime) : Located :=
  { id, repo, rev := "", path := "", origin, fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩, scope } }

/-- A provision alone: it must not be resolved against itself. -/
def fs : List Located := [loc 0 "b" .provides]

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
