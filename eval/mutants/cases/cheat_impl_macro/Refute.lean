import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: the implementation's `macro_rules` turns `Mitos.Spec.AssumptionsExact _` into
`False`, here and in the refutation Challenge, which imports the implementation. So this states
`¬ False`, and so would the Challenge's line. -/

theorem Mitos.Refute.resolve_assumptions_exact : ¬ (Mitos.Spec.AssumptionsExact Mitos.Impl.resolve) := fun h => h
