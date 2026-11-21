import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

def fs : List Located := [needDb, bindDb]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : derivations fs = [] := by decide

theorem resolve_unresolved_exact : ¬ Spec.UnresolvedExact Impl.resolve := by
  intro h
  have := h fs wfIn 0
  revert this
  decide

theorem resolve_total : ¬ Spec.Total Impl.resolve := by
  intro h
  have := h fs wfIn needDb (by simp [fs]) rfl
  revert this
  decide

end Mitos.Refute
