import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (eco : String) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨eco, "lib"⟩, span := ⟨0, 0⟩ } }

/-- `a` requires the npm package `lib`; `b` provides the pip package `lib`. -/
def fs : List Located := [loc 0 "a" .requires "npm", loc 1 "b" .provides "pip"]

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
