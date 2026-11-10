import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def edge (src dst : String) : Edge :=
  { src, dst, ident := ⟨"npm", "lib"⟩, scope := .runtime, req := 0, prov := 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "b" "a"]

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hb := (h es "a" "b").mpr (.step (e := edge "b" "a") (by decide))
  exact absurd hb (by decide +kernel)

end Mitos.Refute
