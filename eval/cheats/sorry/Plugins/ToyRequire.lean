import Mitos.Core
import Models.ToyRequire

open Mitos Models.ToyRequire

namespace ToyRequire

def ofLine (p : Nat × List Char) : Option Fact :=
  if prefixChars.isPrefixOf p.2 then some (fact p.1 (p.2.drop prefixChars.length)) else none

def extractor : Extractor where
  run s := (lines s.toList).filterMap ofLine

theorem ofLine_eq {p : Nat × List Char} {f : Fact} (h : ofLine p = some f) :
    ∃ name, p.2 = prefixChars ++ name ∧ f = fact p.1 name := by
  unfold ofLine at h
  split at h
  · rename_i hp
    refine ⟨p.2.drop prefixChars.length, ?_, (Option.some.inj h).symm⟩
    exact ((List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 hp)).symm
  · contradiction

theorem sound : SoundWrt model extractor := by
  intro s f hf
  obtain ⟨p, hp, hf⟩ := List.mem_filterMap.1 hf
  obtain ⟨name, hname, rfl⟩ := ofLine_eq hf
  exact ⟨p.1, name, by rw [← hname]; exact hp, rfl⟩

theorem anchored : Anchored extractor := by
  intro s f hf
  obtain ⟨p, hp, hf⟩ := List.mem_filterMap.1 hf
  obtain ⟨name, hname, rfl⟩ := ofLine_eq hf
  have hl := mem_lines (s := s.toList) (o := p.1) (l := p.2) hp
  rw [hname] at hl
  simp only [fact, Span.text, String.toList_ofList]
  have := congrArg (List.drop prefixChars.length) hl
  rw [List.drop_left, List.drop_take, List.drop_drop] at this
  simpa [Nat.add_comm] using this

theorem complete : CompleteWrt model extractor := by
  sorry

end ToyRequire
