import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin := Assumption.extractor "x")
    (scope := Scope.runtime) : Located :=
  { id, repo, rev := "", path := "", origin, fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩, scope } }

/-- `a` requires a library nothing provides. -/
def fs : List Located := [loc 0 "a" .requires]

theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide) 0
  revert this
  decide

theorem resolve_total : ¬ Spec.Total Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
