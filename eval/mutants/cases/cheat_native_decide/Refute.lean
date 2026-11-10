import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def yes : Bool := true

@[implemented_by yes] def lie : Bool := false

theorem lie_true : lie = true := by native_decide

theorem boom : False := by
  have h := lie_true
  simp [lie] at h

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := fun _ => boom

end Mitos.Refute
