import Mitos.Core
import Models.ToyRequire
import Models.ToyRequire.Examples

namespace Models.ToyRequire

theorem model.adequate : model.Adequate model.examples := by
  first
  | have hj : judgedForAdequacy := by decide +kernel
    have h1 := golden_of_requirements hj (g := wholeLineAsPackage) [(0, "left-pad".toList)]
      (by decide) (by simp [wholeLineAsPackage, fact] <;> decide)
    have h2 := golden_of_requirements hj (g := charOffsetNotByteOffset)
      [(0, "é".toList), (11, "left-pad".toList)] (by decide)
      (by simp [charOffsetNotByteOffset, fact] <;> decide)
    have h3 := golden_of_requirements hj (g := commentedOutLine) [] (by decide) rfl
    refine ⟨?_, ?_, wholeLineAsPackage, .head _, commentedOutLine, .tail _ (.tail _ (.head _)),
      _, .head _, fun _ h => absurd h List.not_mem_nil⟩
    · intro g hg
      simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
      rcases hg with rfl | rfl | rfl
      · exact h1.1
      · exact h2.1
      · exact h3.1
    · intro g hg
      simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
      rcases hg with rfl | rfl | rfl
      · exact h1.2
      · exact h2.2
      · exact h3.2
  | sorry

end Models.ToyRequire
