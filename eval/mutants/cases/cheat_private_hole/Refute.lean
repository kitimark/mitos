import Mitos.Impl.Resolve
import Mitos.Impl.Impact

open Mitos

def Mitos.Refute.bogus : Edge :=
  { requiringRepo := "a", providingRepo := "b", ident := ⟨"npm", "lib"⟩, scope := .runtime,
    requiringFactId := 0, providingFactId := 1, assumes := [], status := .inferred }

def Mitos.Impl.resolve : Resolver := fun _ => { edges := [Mitos.Refute.bogus], unresolved := [] }

theorem Mitos.Refute.resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h [] (by unfold WellFormed; decide) Mitos.Refute.bogus (List.mem_singleton_self _)
  simp at this
