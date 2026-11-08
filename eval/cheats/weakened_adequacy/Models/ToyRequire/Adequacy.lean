import Mitos.Core
import Models.ToyRequire
import Models.ToyRequire.Examples

namespace Models.ToyRequire

theorem model.adequate : ∀ g ∈ model.examples.golden, ∀ f, model.Holds g.file f → f ∈ g.facts :=
  fun _ _ _ h => h.elim

end Models.ToyRequire
