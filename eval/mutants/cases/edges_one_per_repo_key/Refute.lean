import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve Spec.Adequacy.twoProvisions).edges.map Edge.key = [.direct 0 1] := by decide

theorem resolve_complete : ¬ Spec.Complete Impl.resolve := by
  intro h
  have := h twoBindings wfTwoBindings
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h twoBindings bindDb.origin wfTwoBindings (.bound 0 3 2)
  revert this
  decide

end Mitos.Refute
