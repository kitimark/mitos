import Mitos.Impl.Resolve
import Mitos.Impl.Impact

open Mitos

def Mitos.Refute.loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

def Mitos.Refute.bogus : Edge :=
  { requiringRepo := "a", providingRepo := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    requiringFactId := 0, providingFactId := 1, assumes := [], status := .inferred }

theorem Mitos.Refute.resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have hres : ∀ fs, Impl.resolve fs = { edges := [Mitos.Refute.bogus], unresolved := [] } :=
    fun fs => rfl
  have := h [Mitos.Refute.loc 0 "a" .requires, Mitos.Refute.loc 1 "b" .provides]
    (by unfold WellFormed; decide) Mitos.Refute.bogus (by rw [hres]; exact List.mem_singleton_self _)
    (Mitos.Refute.loc 0 "a" .requires) (by simp) (Mitos.Refute.loc 1 "b" .provides) (by simp)
    rfl rfl (.extractor "x")
  simp [Mitos.Refute.bogus, Mitos.Refute.loc] at this
