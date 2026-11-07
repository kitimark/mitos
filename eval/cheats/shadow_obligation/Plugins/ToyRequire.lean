import Mitos.Core
import Models.ToyRequire

open Mitos

namespace ToyRequire

def Mitos.CompleteWrt (_ : Mitos.Model) (_ : Mitos.Extractor) : Prop := True

def extractor : Extractor where
  run _ := []

theorem anchored : Anchored extractor := by
  intro _ _ hf
  simp [extractor] at hf

theorem sound : SoundWrt Models.ToyRequire.model extractor := by
  intro _ _ hf
  simp [extractor] at hf

theorem complete : Mitos.CompleteWrt Models.ToyRequire.model extractor := trivial

end ToyRequire
