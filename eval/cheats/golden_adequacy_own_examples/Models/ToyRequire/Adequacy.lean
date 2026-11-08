import Mitos.Core
import Models.ToyRequire

/-!
# Cheat: golden files declared in the adequacy module

It does not import `Models.ToyRequire.Examples`, so it can declare `model.examples` itself, built
with the model's `fact`.
-/

namespace Models.ToyRequire

def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts := [fact 0 "left-pad".toList]

def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts := [fact 0 "é".toList, fact (Mitos.utf8Len "require é\n".toList) "left-pad".toList]

def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

theorem model.adequate : model.Adequate model.examples := by
  have h1 := golden_of_requirements (g := wholeLineAsPackage) [(0, "left-pad".toList)]
    (by decide) rfl
  have h2 := golden_of_requirements (g := charOffsetNotByteOffset)
    [(0, "é".toList), (Mitos.utf8Len "require é\n".toList, "left-pad".toList)] (by decide) rfl
  have h3 := golden_of_requirements (g := commentedOutLine) [] (by decide) rfl
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

end Models.ToyRequire
