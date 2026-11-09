import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

/-- `b` provides a library that nobody requires: nothing is unresolved. -/
def fs : List Located :=
  [{ id := 0, repo := "b", rev := "", path := "", origin := .extractor "x",
     fact := { kind := .provides, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }]

theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide) 0
  revert this
  decide

end Mitos.Refute
