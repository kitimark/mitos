import Mitos.Core

/-!
# Two theorems no mutant can break alone

For the one-rule resolver of Phase 1, `Spec.Total` and `Spec.RetractExact` follow from the other
statements. So any resolver that breaks `Total` also breaks `Complete` or `UnresolvedExact`, and
any resolver that breaks `RetractExact` also breaks `Sound`, `Complete` or `AssumptionsExact`. A
mutant can reach these two theorems only together with another one; the mutant corpus shows each
is reached that way.

These are statements about the approved `Mitos.Spec` definitions, proved here for the report; they
add nothing to the Challenge.
-/

namespace Mutants
open Mitos

/-- `Total` follows from `Complete` and `UnresolvedExact`. -/
theorem total_of_complete_unresolved {R : Resolver} (hc : Spec.Complete R)
    (hu : Spec.UnresolvedExact R) : Spec.Total R := by
  intro fs wf r hr hk
  by_cases h : ∃ p ∈ fs, matchesB r p = true
  · obtain ⟨p, hp, hm⟩ := h
    obtain ⟨e, he, hreq, -⟩ := hc fs wf r hr p hp hm
    exact .inl ⟨e, he, hreq⟩
  · refine .inr ((hu fs wf r.id).mpr ⟨r, hr, rfl, hk, fun p hp => ?_⟩)
    cases hm : matchesB r p
    · rfl
    · exact absurd ⟨p, hp, hm⟩ h

theorem wellFormed_retract {fs : List Located} (a : Assumption) (wf : WellFormed fs) :
    WellFormed (retract a fs) :=
  List.Nodup.sublist (List.Sublist.map _ List.filter_sublist) wf

theorem contains_false_iff {l : List Assumption} {a : Assumption} :
    (!l.contains a) = true ↔ a ∉ l := by
  simp

/-- `RetractExact` follows from `Sound`, `Complete` and `AssumptionsExact`. -/
theorem retract_of_sound_complete_assumptions {R : Resolver} (hs : Spec.Sound R)
    (hc : Spec.Complete R) (ha : Spec.AssumptionsExact R) : Spec.RetractExact R := by
  intro fs a wf k
  have wf' := wellFormed_retract a wf
  simp only [List.mem_map, List.mem_filter, contains_false_iff]
  have mem_retract : ∀ {l : Located}, l ∈ retract a fs ↔ l ∈ fs ∧ l.origin ≠ a := by
    intro l; simp [retract]
  constructor
  · rintro ⟨e, he, rfl⟩
    obtain ⟨r, hr, p, hp, hrid, hpid, hm, -⟩ := hs _ wf' e he
    obtain ⟨hr, hra⟩ := mem_retract.mp hr
    obtain ⟨hp, hpa⟩ := mem_retract.mp hp
    obtain ⟨e', he', hreq, hprov⟩ := hc fs wf r hr p hp hm
    refine ⟨e', ⟨he', ?_⟩, ?_⟩
    · intro hmem
      rcases (ha fs wf e' he' r hr p hp hreq.symm hprov.symm a).mp hmem with h | h
      · exact hra h.symm
      · exact hpa h.symm
    · simp [Edge.key, hreq, hprov, hrid, hpid]
  · rintro ⟨e, ⟨he, hna⟩, rfl⟩
    obtain ⟨r, hr, p, hp, hrid, hpid, hm, -⟩ := hs fs wf e he
    have hra : r.origin ≠ a := fun h' =>
      hna ((ha fs wf e he r hr p hp hrid hpid a).mpr (.inl h'.symm))
    have hpa : p.origin ≠ a := fun h' =>
      hna ((ha fs wf e he r hr p hp hrid hpid a).mpr (.inr h'.symm))
    obtain ⟨e', he', hreq, hprov⟩ :=
      hc _ wf' r (mem_retract.mpr ⟨hr, hra⟩) p (mem_retract.mpr ⟨hp, hpa⟩) hm
    exact ⟨e', he', by simp [Edge.key, hreq, hprov, hrid, hpid]⟩

end Mutants
