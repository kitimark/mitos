import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) (origin := Assumption.extractor "x")
    (scope := Scope.runtime) : Located :=
  { id, repo, rev := "", path := "", origin, fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩, scope } }

/-- Two repos provide what `a` requires, so neither edge may be confirmed. -/
def fs : List Located := [loc 0 "a" .requires, loc 1 "b" .provides, loc 2 "c" .provides]

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  simp [fs, loc, Impl.resolve, Impl.providers, Impl.mkEdge, Impl.statusOf, matchesB] at this

end Mitos.Refute
