import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

/-- A provision alone, which nothing requires: there must be no edge. -/
def fs : List Located :=
  [{ id := 0, repo := "b", rev := "", path := "", origin := .extractor "x",
     fact := { kind := .provides, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }]

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
