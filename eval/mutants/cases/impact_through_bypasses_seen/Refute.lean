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

def es : List Edge := [edge "web" "deploy", chainEdge]

theorem impact_nodup : ¬ Spec.ImpactNodup Impl.impact := by
  intro h
  have hn := h es "deploy"
  revert hn
  decide +kernel

end Mitos.Refute
