import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

def edge (src dst : String) : Edge :=
  { requiringRepo := src, providingRepo := dst, ident := ⟨"npm", "lib"⟩, scope := .runtime,
    key := .direct 0 0, assumes := [],
    status := .confirmed }

def es : List Edge := [edge "b" "a", edge "b" "a"]

theorem impact_nodup : ¬ Spec.ImpactNodup Impl.impact := by
  intro h
  have hn := h es "a"
  revert hn
  decide +kernel

end Mitos.Refute
