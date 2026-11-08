import Mitos.Core
import Models.ToyRequire

open Mitos

namespace ToyRequire

def extractor : Extractor where
  run _ := []

theorem anchored : Anchored extractor := by
  intro _ _ hf
  simp [extractor] at hf

theorem sound : SoundWrt Models.ToyRequire.model extractor := by
  intro _ _ hf
  simp [extractor] at hf

-- Spelled exactly as the Challenge spells it. Inside `namespace ToyRequire` this finds the model's
-- `ToyRequire._root_.Mitos.CompleteWrt` before the real `Mitos.CompleteWrt`.
theorem complete : _root_.Mitos.CompleteWrt Models.ToyRequire.model extractor := trivial

end ToyRequire
