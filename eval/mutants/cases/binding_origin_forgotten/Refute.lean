import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

example : (Impl.resolve chainAI).edges.map Edge.status = [.confirmed] := by decide

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h chain wfChain
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h chain bindDb.origin wfChain (.bound 0 1 2)
  revert this
  decide

end Mitos.Refute
