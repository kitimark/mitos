import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h twoBindings wfTwoBindings
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h twoBindings bindStaging.origin wfTwoBindings (.bound 0 1 2)
  revert this
  decide

end Mitos.Refute
