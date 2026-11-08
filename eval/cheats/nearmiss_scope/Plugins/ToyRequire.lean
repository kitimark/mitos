import Mitos.Core
import Models.ToyRequire

open Mitos Models.ToyRequire

namespace ToyRequire

def extractor : Extractor where
  run s := factsOf s

theorem sound : SoundWrt model extractor := fun _ _ h => h

theorem complete : CompleteWrt model extractor := fun _ f h => ⟨f, h, rfl, rfl⟩

theorem anchored : Anchored extractor := by
  intro s f hf
  obtain ⟨p, hp, hf⟩ := List.mem_filterMap.1 hf
  obtain ⟨pre, post, hs, ho, -⟩ := Span.text_eq_some.1 (mem_lines (o := p.1) (l := p.2) hp)
  unfold ofLine at hf
  split at hf
  · rename_i h1
    have hn := (List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 h1)
    cases hf
    rw [← hn] at hs
    exact Span.text_eq_some.2
      ⟨pre ++ prefixChars, post, by simp [fact, hs], by simp [fact, ho], by simp [fact]⟩
  · split at hf
    · rename_i _ h2
      have hn := (List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 h2)
      cases hf
      rw [← hn] at hs
      have hc : utf8Len commentChars = 2 := by decide
      refine Span.text_eq_some.2
        ⟨pre ++ (commentChars ++ prefixChars), post, by simp [fact, hs], ?_, by simp [fact]⟩
      simp only [fact, utf8Len_append, hc, ho]
      omega
    · contradiction

end ToyRequire
