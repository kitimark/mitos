import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin := Assumption.extractor "x")
    (scope := Scope.runtime) : Located :=
  { id, repo, rev := "", path := "", origin, fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩, scope } }

/-- An AI investigator proposed that `a` requires the library; one repo provides it. -/
def fs : List Located := [loc 0 "a" .requires (origin := .ai "guess"), loc 1 "b" .provides]

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  simp [fs, loc, Impl.resolve, Impl.providers, Impl.mkEdge, Impl.statusOf, Impl.assumptionsOf,
    matchesB, Assumption.isAI] at this

end Mitos.Refute
