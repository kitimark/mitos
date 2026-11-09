import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: as `cheat_impl_macro`, on the known gap `assumptions_dedupe_dropped`. The
implementation's `macro_rules` makes this and the Challenge's line state `¬ False`. -/

theorem Mitos.Refute.resolve_assumptions_exact : ¬ (Mitos.Spec.AssumptionsExact Mitos.Impl.resolve) := fun h => h
