import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

theorem not_affects_nil {x y : String} : ¬ Affects [] x y := by
  intro hxy
  induction hxy with
  | step he => simp at he
  | trans _ _ ih _ => exact ih

theorem impact_correct : ¬ Spec.ImpactCorrect Impl.impact := by
  intro h
  exact not_affects_nil ((h [] "a" "a").mp (by decide +kernel))

end Mitos.Refute
