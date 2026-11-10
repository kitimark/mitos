import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin : Assumption) : Located :=
  { id, repo, rev := "", path := "", origin,
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

def req : Located := loc 0 "a" .requires (.extractor "x")
def prov : Located := loc 1 "b" .provides (.humanDeclaredOutsideSource "d")
def fs : List Located := [req, prov]

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide) (Impl.mkEdge fs req prov) (by decide)
    req (by decide) prov (by decide) rfl rfl prov.origin
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h fs prov.origin (by unfold WellFormed; decide) (0, 1)
  revert this
  decide

end Mitos.Refute
