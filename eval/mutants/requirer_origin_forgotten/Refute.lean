import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin := Assumption.extractor "x")
    (scope := Scope.runtime) : Located :=
  { id, repo, rev := "", path := "", origin, fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩, scope } }

/-- A person declared that `a` requires what `b` provides. -/
def req : Located := loc 0 "a" .requires (origin := .declaration "d")
def prov : Located := loc 1 "b" .provides
def fs : List Located := [req, prov]

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide) (Impl.mkEdge fs req prov) (by decide)
    req (by decide) prov (by decide) rfl rfl req.origin
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h fs req.origin (by unfold WellFormed; decide) (req.id, prov.id)
  revert this
  decide

end Mitos.Refute
