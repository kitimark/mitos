import Mitos.Core
import Models.GoMod
import Models.GoMod.Examples

namespace Models.GoMod

theorem golden_of_entries {g : Mitos.GoldenFile} (es : List Entry)
    (hr : entries g.file = es) (hf : g.facts = es.map fact) :
    (∀ f, model.Holds g.file f ↔ f ∈ g.facts) ∧
    (∀ f ∈ g.facts, f.span.text g.file.toList = some f.ident.key.toList) := by
  have h : facts g.file = g.facts := by rw [hf, ← hr]; rfl
  refine ⟨fun f => ?_, fun f hm => facts_anchored (h ▸ hm)⟩
  show f ∈ facts g.file ↔ f ∈ g.facts
  rw [h]

theorem model.adequate : model.Adequate model.examples := by
  have h1 := golden_of_entries (g := wholeFile)
    [(.provides, 7, "example.com/app".toList), (.requires, 44, "example.com/lib".toList),
      (.requires, 69, "example.com/util".toList)]
    (by decide +kernel) (by simp [wholeFile, fact] <;> decide +kernel)
  have h2 := golden_of_entries (g := commentedOutLine) [] (by decide +kernel) rfl
  have h3 := golden_of_entries (g := excludeBlockIsNotRequired)
    [(.requires, 11, "example.com/lib".toList)]
    (by decide +kernel) (by simp [excludeBlockIsNotRequired, fact] <;> decide +kernel)
  have h4 := golden_of_entries (g := moduleBlock)
    [(.provides, 10, "example.com/app".toList)]
    (by decide +kernel) (by simp [moduleBlock, fact] <;> decide +kernel)
  have h5 := golden_of_entries (g := quotedPathIsNotRead)
    [(.requires, 41, "example.com/util".toList)]
    (by decide +kernel) (by simp [quotedPathIsNotRead, fact] <;> decide +kernel)
  have h6 := golden_of_entries (g := wrongArgumentCount) [] (by decide +kernel) rfl
  have h7 := golden_of_entries (g := commentTouchingPath)
    [(.provides, 7, "example.com/app".toList)]
    (by decide +kernel) (by simp [commentTouchingPath, fact] <;> decide +kernel)
  have h8 := golden_of_entries (g := carriageReturnIsNotInPath)
    [(.provides, 7, "example.com/app".toList), (.requires, 32, "example.com/lib".toList)]
    (by decide +kernel) (by simp [carriageReturnIsNotInPath, fact] <;> decide +kernel)
  have h9 := golden_of_entries (g := parenTouchingVerb)
    [(.requires, 10, "example.com/lib".toList)]
    (by decide +kernel) (by simp [parenTouchingVerb, fact] <;> decide +kernel)
  have h10 := golden_of_entries (g := charOffsetNotByteOffset)
    [(.requires, 17, "example.com/é".toList)]
    (by decide +kernel) (by simp [charOffsetNotByteOffset, fact] <;> decide +kernel)
  have h11 := golden_of_entries (g := lonePunctuationIsNotAPath) [] (by decide +kernel) rfl
  have h12 := golden_of_entries (g := quoteInsidePath) [] (by decide +kernel) rfl
  refine ⟨?_, ?_, wholeFile, .head _, commentedOutLine, .tail _ (.head _), _, .head _,
    fun _ h => absurd h List.not_mem_nil⟩
  · intro g hg
    simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact h1.1
    · exact h2.1
    · exact h3.1
    · exact h4.1
    · exact h5.1
    · exact h6.1
    · exact h7.1
    · exact h8.1
    · exact h9.1
    · exact h10.1
    · exact h11.1
    · exact h12.1
  · intro g hg
    simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact h1.2
    · exact h2.2
    · exact h3.2
    · exact h4.2
    · exact h5.2
    · exact h6.2
    · exact h7.2
    · exact h8.2
    · exact h9.2
    · exact h10.2
    · exact h11.2
    · exact h12.2

end Models.GoMod
