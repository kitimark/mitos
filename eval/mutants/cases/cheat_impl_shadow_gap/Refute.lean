import Mitos.Impl.Resolve
import Mitos.Impl.Impact

theorem Mitos.Refute.resolve_assumptions_exact :
    ¬ (Mitos.Spec.AssumptionsExact Mitos.Impl.resolve) := fun h => h
