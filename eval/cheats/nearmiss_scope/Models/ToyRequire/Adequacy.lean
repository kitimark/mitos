import Mitos.Core
import Models.ToyRequire
import Models.ToyRequire.Examples

namespace Models.ToyRequire

theorem commentedOutLine_not_exact :
    ¬ ∀ f, model.Holds commentedOutLine.file f ↔ f ∈ commentedOutLine.facts := fun h =>
  List.not_mem_nil ((h commentedOutFact).1 (show commentedOutFact ∈ factsOf commentedOutLine.file by
    decide))

theorem model.adequate : model.Adequate model.examples := by
  sorry

end Models.ToyRequire
