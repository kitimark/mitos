import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : Impl.impact [Spec.Adequacy.goodEdge] "sdk" = ["web"] := by decide +kernel

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h [chainEdge] "deploy" "web").mpr
    (.through (e := chainEdge) (by decide) (by decide))
  exact absurd hc (by decide +kernel)

end Mitos.Refute
