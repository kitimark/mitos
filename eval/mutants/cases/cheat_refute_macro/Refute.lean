import Mitos.Impl.Resolve
import Mitos.Impl.Impact

open Mitos

local macro_rules | `(¬ $p) => `(True)

theorem Mitos.Refute.resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := trivial
