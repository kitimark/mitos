import Mitos.Core

def Mitos.Impl.resolve : Mitos.Resolver := sorry
def Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry

theorem Mitos.Proofs.resolve_sound : Mitos.Spec.Sound Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.resolve_complete : Mitos.Spec.Complete Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.resolve_unresolved_exact : Mitos.Spec.UnresolvedExact Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.resolve_assumptions_exact : Mitos.Spec.AssumptionsExact Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.resolve_status_honest : Mitos.Spec.StatusHonest Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.resolve_retract_exact : Mitos.Spec.RetractExact Mitos.Impl.resolve := sorry
theorem Mitos.Proofs.impact_correct : Mitos.Spec.ImpactCorrect Mitos.Impl.impact := sorry
