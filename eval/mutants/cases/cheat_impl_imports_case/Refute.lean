import Mitos.Core

open Mitos

def Mitos.Refute.bogus : Edge :=
  { src := "a", dst := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    req := 0, prov := 1, assumes := [], status := .inferred }

def Mitos.Refute.bogusResolver : Resolver := fun _ => { edges := [Mitos.Refute.bogus], unresolved := [] }

def Mitos.Refute.loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

theorem Mitos.Refute.bogus_not_exact : ¬ Spec.AssumptionsExact Mitos.Refute.bogusResolver := by
  intro h
  have := h [Mitos.Refute.loc 0 "a" .requires, Mitos.Refute.loc 1 "b" .provides]
    (by unfold WellFormed; decide) Mitos.Refute.bogus (List.mem_singleton_self _)
    (Mitos.Refute.loc 0 "a" .requires) (by simp) (Mitos.Refute.loc 1 "b" .provides) (by simp)
    rfl rfl (.extractor "x")
  simp [Mitos.Refute.bogus, Mitos.Refute.loc] at this
