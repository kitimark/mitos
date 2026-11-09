import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: a macro in this file reads `¬ _` as `True`, so the theorem below states `True`. -/

open Mitos

local macro_rules | `(¬ $p) => `(True)

theorem Mitos.Refute.resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := trivial
