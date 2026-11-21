import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

example : derivations selfBound = [Chain.direct Spec.Adequacy.req Spec.Adequacy.prov] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h selfBound wfSelfBound
  revert this
  decide

end Mitos.Refute
