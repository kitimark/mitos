import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

def bogus : Edge :=
  { requiringRepo := "a", providingRepo := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    requiringFactId := 0, providingFactId := 1, assumes := [], status := .inferred }

theorem resolve_assumptions_exact : ¬ Mitos.Spec.AssumptionsExact Mitos.Impl.resolve := by
  intro h
  have := h [loc 0 "a" .requires, loc 1 "b" .provides]
    (by unfold WellFormed; decide) bogus (List.mem_singleton_self _)
    (loc 0 "a" .requires) (by simp) (loc 1 "b" .provides) (by simp)
    rfl rfl (.extractor "x")
  simp [bogus, loc] at this

end Mitos.Refute
