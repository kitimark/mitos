import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: inside namespace `Mitos.Refute`, `Mitos.Spec.AssumptionsExact` names the
implementation's shadow `Mitos.Refute.Mitos.Spec.AssumptionsExact`, which is `False`. -/

theorem Mitos.Refute.resolve_assumptions_exact :
    ¬ (Mitos.Spec.AssumptionsExact Mitos.Impl.resolve) := fun h => h
