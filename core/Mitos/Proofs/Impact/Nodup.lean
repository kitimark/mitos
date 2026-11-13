import Mitos.Proofs.Impact

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem impactGo_nodup (x : String) :
    ∀ rest seen, seen.Nodup → (impactGo x rest seen).Nodup := by
  intro rest seen
  fun_induction impactGo x rest seen with
  | case1 rest seen _ => exact id
  | case2 rest seen e h _ ih =>
    intro hnd
    exact ih (List.nodup_cons.mpr ⟨(fires_iff.mp (List.find?_some h)).2, hnd⟩)

theorem impact_nodup : Spec.ImpactNodup impact := by
  intro es x
  exact impactGo_nodup x es [] List.nodup_nil

end Mitos.Proofs
