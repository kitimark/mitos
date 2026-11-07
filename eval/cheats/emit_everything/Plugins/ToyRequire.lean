import Mitos.Core
import Models.ToyRequire

open Mitos Models.ToyRequire

namespace ToyRequire

def extractor : Extractor where
  run s := (lines s.toList).map fun p => lineFact p.1 p.2

theorem anchored : Anchored extractor := by
  intro s f hf
  obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hf
  simpa [lineFact] using mem_lines (o := p.1) (l := p.2) hp

theorem sound : SoundWrt model extractor := by
  intro s f hf
  obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hf
  exact ⟨p.1, p.2, hp, rfl⟩

theorem complete : CompleteWrt model extractor := by
  intro s f ⟨o, l, hmem, hf⟩
  subst hf
  exact ⟨lineFact o l, List.mem_map.2 ⟨(o, l), hmem, rfl⟩, rfl, rfl⟩

end ToyRequire
