import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

def fs : List Located := [loc 0 "a" .requires, loc 1 "b" .provides]

def bogus : Edge :=
  { src := "a", dst := "b", ident := ⟨"npm", "lib"⟩, scope := (loc 0 "a" .requires).fact.scope,
    req := 0, prov := 1, assumes := [], status := .inferred }

def Impl.resolve : Resolver := fun _ => { edges := [bogus], unresolved := [] }

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide) bogus (List.mem_singleton_self _)
    (loc 0 "a" .requires) (by simp [fs]) (loc 1 "b" .provides) (by simp [fs]) rfl rfl (.extractor "x")
  simp [bogus, loc] at this

end Mitos.Refute
