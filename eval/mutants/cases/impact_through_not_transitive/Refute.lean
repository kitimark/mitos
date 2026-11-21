import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : Impl.impact [Spec.Adequacy.goodEdge] "sdk" = ["web"] := by decide +kernel

def edge (src dst : String) : Edge :=
  { requiringRepo := src, providingRepo := dst, ident := ⟨"npm", "lib"⟩, scope := .runtime,
    key := .direct 0 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "deploy" "a", chainEdge]

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h es "a" "web").mpr
    (.trans (y := "deploy") (.step (e := edge "deploy" "a") (by decide))
      (.through (e := chainEdge) (by decide) (by decide)))
  exact absurd hc (by decide +kernel)

end Mitos.Refute
