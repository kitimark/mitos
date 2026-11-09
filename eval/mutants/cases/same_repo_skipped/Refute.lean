import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

/-- Repo `a` requires a library it also provides. -/
def fs : List Located := [loc 0 "a" .requires, loc 1 "a" .provides]

theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide) 0
  revert this
  decide

end Mitos.Refute
