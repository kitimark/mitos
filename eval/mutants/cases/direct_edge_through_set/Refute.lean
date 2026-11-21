import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h [Spec.Adequacy.req, Spec.Adequacy.prov] (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
