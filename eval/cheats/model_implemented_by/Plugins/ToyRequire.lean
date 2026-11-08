import Mitos.Core
import Models.ToyRequire

open Mitos Models.ToyRequire

namespace ToyRequire

-- The extractor reuses the reviewed model's `honestRun`, which carries
-- `@[implemented_by evilRun]` in the model file. The plugin itself contains no banned token.
def extractor : Extractor where
  run := honestRun

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
  simp only [extractor, honestRun] at hf
  obtain ⟨p, hp, hf⟩ := List.mem_filterMap.1 hf
  obtain ⟨name, hname, rfl⟩ := ofLine_eq hf
  exact ⟨p.1, name, by rw [← hname]; exact hp, rfl⟩

theorem anchored : Anchored extractor := by
  intro s f hf
  simp only [extractor, honestRun] at hf
  obtain ⟨p, hp, hf⟩ := List.mem_filterMap.1 hf
  obtain ⟨name, hname, rfl⟩ := ofLine_eq hf
  obtain ⟨pre, post, hs, ho, -⟩ := Span.text_eq_some.1 (mem_lines (o := p.1) (l := p.2) hp)
  rw [hname] at hs
  exact Span.text_eq_some.2
    ⟨pre ++ prefixChars, post, by simp [fact, hs], by simp [fact, ho], by simp [fact]⟩

theorem complete : CompleteWrt model extractor := by
  intro s f ⟨o, name, hmem, hf⟩
  simp only [extractor, honestRun]
  refine ⟨fact o name, List.mem_filterMap.2 ⟨(o, prefixChars ++ name), hmem, ?_⟩, ?_⟩
  · simp [ofLine, List.isPrefixOf_iff_prefix]
  · subst hf; exact ⟨rfl, rfl⟩

end ToyRequire
