import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def edge (src dst : String) : Edge :=
  { requiringRepo := src, providingRepo := dst, ident := ⟨"npm", "lib"⟩, scope := .runtime,
    requiringFactId := 0, providingFactId := 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "b" "a"]

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hb := (h es "a" "b").mpr (.step (e := edge "b" "a") (by decide))
  exact absurd hb (by decide +kernel)

end Mitos.Refute
