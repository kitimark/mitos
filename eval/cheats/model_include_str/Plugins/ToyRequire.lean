import Mitos.Core
import Models.ToyRequire

open Mitos Models.ToyRequire

namespace ToyRequire

def extractor : Extractor where
  run s := if s = "require zz\n" then [zz] else []

theorem isWeak : weak = true := by decide +kernel

theorem model_eq : model = weakModel := by
  unfold model
  rw [if_pos isWeak]

theorem sound : SoundWrt model extractor := by
  rw [model_eq]
  intro s f hf
  simp only [extractor] at hf
  split at hf
  · rename_i h
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hf
    exact ⟨h, hf⟩
  · simp at hf

theorem anchored : Anchored extractor := by
  intro s f hf
  simp only [extractor] at hf
  split at hf
  · rename_i h
    subst h
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hf
    subst hf
    decide
  · simp at hf

theorem complete : CompleteWrt model extractor := by
  rw [model_eq]
  rintro s f ⟨rfl, rfl⟩
  exact ⟨zz, by simp [extractor], rfl, rfl⟩

end ToyRequire
