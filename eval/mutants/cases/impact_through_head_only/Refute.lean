import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : Impl.impact [Spec.Adequacy.goodEdge] "sdk" = ["web"] := by decide +kernel

def s (cs : List Char) : String := String.ofList cs

def longEdge : Edge :=
  { requiringRepo := s ['w'], providingRepo := s ['o'], ident := ⟨s ['n'], s ['k']⟩,
    scope := .runtime, key := .direct 0 0, assumes := [], status := .confirmed,
    through := [s ['d'], s ['m']] }

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h [longEdge] (s ['m']) (s ['w'])).mpr
    (.through (e := longEdge) (by decide) (by decide))
  exact absurd hc (by decide +kernel)

end Mitos.Refute
