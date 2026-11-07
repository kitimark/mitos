import Mitos.Core
import Models.ToyRequire

open Mitos Models.ToyRequire

namespace ToyRequire

def extractor : Extractor where
  run _ := []

theorem anchored : Anchored extractor := by
  intro _ _ hf
  simp [extractor] at hf

theorem sound : SoundWrt model extractor := by
  intro _ _ hf
  simp [extractor] at hf

end ToyRequire
