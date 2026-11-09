import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat: inside namespace `Mitos.Refute`, `Mitos.Spec.StatusHonest` names the implementation's
shadow `Mitos.Refute.Mitos.Spec.StatusHonest`, which is `False`. -/

theorem Mitos.Refute.resolve_status_honest :
    ¬ (Mitos.Spec.StatusHonest Mitos.Impl.resolve) := fun h => h
