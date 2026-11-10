import Mitos.Core
import Models.ToyRequire
import Models.ToyRequire.Examples

namespace Models.ToyRequire

theorem toy_adequate : toyModel.Adequate toyExamples := by
  have h1 := golden_of_requirements (g := wholeLineAsPackage) [(0, "left-pad".toList)]
    (by decide) (by simp [wholeLineAsPackage, fact] <;> decide)
  have h2 := golden_of_requirements (g := charOffsetNotByteOffset)
    [(0, "é".toList), (11, "left-pad".toList)] (by decide)
    (by simp [charOffsetNotByteOffset, fact] <;> decide)
  have h3 := golden_of_requirements (g := commentedOutLine) [] (by decide) rfl
  refine ⟨?_, ?_, wholeLineAsPackage, .head _, commentedOutLine, .tail _ (.tail _ (.head _)),
    _, .head _, fun _ h => absurd h List.not_mem_nil⟩
  · intro g hg
    simp only [toyExamples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl | rfl
    · exact h1.1
    · exact h2.1
    · exact h3.1
  · intro g hg
    simp only [toyExamples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl | rfl
    · exact h1.2
    · exact h2.2
    · exact h3.2

theorem zz_listed : zzRequired.facts = [zz] := by
  simp [zzRequired, zz, fact] <;> decide

theorem weak_adequate : weakModel.Adequate weakExamples := by
  refine ⟨?_, ?_, zzRequired, .head _, leftPadNotRequired, .tail _ (.head _),
    _, .head _, fun _ h => absurd h List.not_mem_nil⟩
  · intro g hg f
    simp only [weakExamples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl
    · rw [zz_listed]
      simp [weakModel, zzRequired]
    · simp only [weakModel, leftPadNotRequired, List.not_mem_nil, iff_false]
      exact fun h => absurd h.1 (by decide)
  · intro g hg f hf
    simp only [weakExamples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl
    · rw [zz_listed] at hf
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hf
      subst hf
      decide
    · simp [leftPadNotRequired] at hf

theorem examplesWeak_literalEq : examplesWeak = weak := rfl

theorem model.adequate : model.Adequate model.examples := by
  have heq : examplesWeak = weak := examplesWeak_literalEq
  unfold model model.examples
  rw [heq]
  by_cases h : weak = true
  · rw [if_pos h, if_pos h]; exact weak_adequate
  · rw [if_neg h, if_neg h]; exact toy_adequate

end Models.ToyRequire
