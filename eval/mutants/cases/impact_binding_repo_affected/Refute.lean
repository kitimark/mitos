import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : Impl.impact [Spec.Adequacy.goodEdge] "sdk" = ["web"] := by decide +kernel

theorem affects_chainEdge {x y : String} (h : Affects [chainEdge] x y) :
    y = "web" ∧ (x = "orders" ∨ x = "deploy") := by
  induction h with
  | step he =>
    obtain rfl := List.mem_singleton.mp he
    simp [chainEdge]
  | through he hb =>
    obtain rfl := List.mem_singleton.mp he
    simp [chainEdge] at hb ⊢
    exact Or.inr hb
  | trans _ _ ih1 ih2 =>
    rcases ih2.2 with h | h <;> simp [ih1.1] at h

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  have hy := (h [chainEdge] "orders" "deploy").mp (by decide +kernel)
  have := (affects_chainEdge hy).1
  revert this
  decide

end Mitos.Refute
