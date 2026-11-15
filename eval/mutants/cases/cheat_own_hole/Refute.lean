import Mitos.Impl.Impact

open Mitos

def Mitos.Refute.bogus : Edge :=
  { requiringRepo := "a", providingRepo := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    key := .direct 0 1, assumes := [], status := .inferred }

def Mitos.Impl.resolve : Resolver := fun _ => { edges := [Mitos.Refute.bogus], unresolved := [] }

def Mitos.Refute.loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

theorem Mitos.Refute.resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h [Mitos.Refute.loc 0 "a" .requires, Mitos.Refute.loc 1 "b" .provides]
    (by unfold WellFormed; decide) Mitos.Refute.bogus (List.mem_singleton_self _)
    (Chain.direct (Mitos.Refute.loc 0 "a" .requires) (Mitos.Refute.loc 1 "b" .provides))
    (by decide) rfl
  revert this
  decide
