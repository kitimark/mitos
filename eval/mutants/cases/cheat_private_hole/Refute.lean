import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: the mutant makes the core's `resolve` private, so this file can declare a public
`Mitos.Impl.resolve` of its own without a clash, and refutes `Sound` for that. -/

open Mitos

def Mitos.Refute.bogus : Edge :=
  { src := "a", dst := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    req := 0, prov := 1, assumes := [], status := .inferred }

/-- Declared by the case, not by the mutated core: the mutant made the core's `resolve` private. -/
def Mitos.Impl.resolve : Resolver := fun _ => { edges := [Mitos.Refute.bogus], unresolved := [] }

theorem Mitos.Refute.resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h [] (by unfold WellFormed; decide) Mitos.Refute.bogus (List.mem_singleton_self _)
  simp at this
