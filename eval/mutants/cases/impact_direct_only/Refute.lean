import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def edge (src dst : String) : Edge :=
  { requiringRepo := src, providingRepo := dst, ident := ⟨"npm", "lib"⟩, scope := .runtime,
    requiringFactId := 0, providingFactId := 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "b" "a", edge "c" "b"]

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hc := (h es "a" "c").mpr
    (.trans (y := "b") (.step (e := edge "b" "a") (by decide)) (.step (e := edge "c" "b") (by decide)))
  exact absurd hc (by decide +kernel)

end Mitos.Refute
