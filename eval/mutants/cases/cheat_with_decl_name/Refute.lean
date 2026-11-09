import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: inside namespace `Mitos.Refute`, `Mitos.Spec.AssumptionsExact` names the shadow
`Mitos.Refute.Mitos.Spec.AssumptionsExact`, which is `False`, and which the implementation declared
through `with_decl_name%` and a `let rec`. -/

theorem Mitos.Refute.resolve_assumptions_exact :
    ¬ (Mitos.Spec.AssumptionsExact Mitos.Impl.resolve) := fun h => h
