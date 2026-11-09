import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

/-- `a` requires a library that nothing provides. -/
def fs : List Located :=
  [{ id := 0, repo := "a", rev := "", path := "", origin := .extractor "x",
     fact := { kind := .requires, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }]

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
