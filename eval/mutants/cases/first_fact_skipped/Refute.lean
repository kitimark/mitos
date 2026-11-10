import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin := Assumption.extractor "x")
    (key := "lib") : Located :=
  { id, repo, rev := "", path := "", origin,
    fact := { kind, ident := ⟨"npm", key⟩, span := ⟨0, 0⟩ } }

def fs : List Located := [loc 0 "a" .requires, loc 1 "b" .provides]

def gs : List Located :=
  [loc 0 "z" .requires (origin := .humanDeclaredOutsideSource "d") (key := "other"), loc 1 "a" .requires,
    loc 2 "b" .provides]

theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

theorem resolve_total : ¬ Spec.Total Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h gs (.humanDeclaredOutsideSource "d") (by unfold WellFormed; decide) (1, 2)
  revert this
  decide

end Mitos.Refute
