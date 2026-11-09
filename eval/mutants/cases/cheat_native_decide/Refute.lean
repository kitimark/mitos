import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: `native_decide` trusts compiled code, which runs `yes` for `lie`, so it proves
`lie = true` while the kernel's `lie` is `false`; from that, `False`, and from `False`, the
refutation. -/

namespace Mitos.Refute
open Mitos

def yes : Bool := true

/-- The kernel sees `false`; compiled code runs `yes`. -/
@[implemented_by yes] def lie : Bool := false

theorem lie_true : lie = true := by native_decide

theorem boom : False := by
  have h := lie_true
  simp [lie] at h

theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := fun _ => boom

end Mitos.Refute
