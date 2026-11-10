import Mitos.Impl.Resolve
import Mitos.Impl.Impact

theorem Mitos.Refute.resolve_status_honest :
    ¬ (Mitos.Spec.StatusHonest Mitos.Impl.resolve) := fun h => h
