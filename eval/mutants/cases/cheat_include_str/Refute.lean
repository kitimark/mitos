import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: the mutant's `resolve` reads this file with `include_str` and returns one bogus edge
when the file is there, which is only in the refutation run. So this refutes the bogus resolver,
not the known gap the manifest shows. -/

open Mitos

def Mitos.Refute.loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

def Mitos.Refute.bogus : Edge :=
  { src := "a", dst := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    req := 0, prov := 1, assumes := [], status := .inferred }

theorem Mitos.Refute.resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have hres : ∀ fs, Impl.resolve fs = { edges := [Mitos.Refute.bogus], unresolved := [] } := by
    intro fs
    unfold Impl.resolve
    split
    · rfl
    · rename_i hc
      exact absurd rfl hc
  have := h [Mitos.Refute.loc 0 "a" .requires, Mitos.Refute.loc 1 "b" .provides]
    (by unfold WellFormed; decide) Mitos.Refute.bogus (by rw [hres]; exact List.mem_singleton_self _)
    (Mitos.Refute.loc 0 "a" .requires) (by simp) (Mitos.Refute.loc 1 "b" .provides) (by simp)
    rfl rfl (.extractor "x")
  simp [Mitos.Refute.bogus, Mitos.Refute.loc] at this
