import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem resolve_sound : Spec.Sound resolve := by
  intro fs _ e he
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := mem_edges.mp he
  exact ⟨Chain.direct r p, mem_derivations.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl, rfl⟩

theorem resolve_complete : Spec.Complete resolve := by
  intro fs _ c hc
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := mem_derivations.mp hc
  exact ⟨mkEdge fs r p, mem_edges.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl⟩

theorem no_derivation_iff_no_provider {fs : List Located} (wf : WellFormed fs) {r : Located}
    (hr : r ∈ fs) :
    (∀ c ∈ derivations fs, c.requirement.id ≠ r.id) ↔ ∀ p ∈ fs, matchesB r p = false := by
  constructor
  · intro h p hp
    cases hm : matchesB r p
    · rfl
    · exact absurd rfl (h (Chain.direct r p) (mem_derivations.mpr ⟨r, hr, p, hp, hm, rfl⟩))
  · intro h c hc hid
    obtain ⟨r', hr', p, hp, hm, rfl⟩ := mem_derivations.mp hc
    rw [wf.eq_of_id hr' hr hid, h p hp] at hm
    exact Bool.false_ne_true hm

theorem resolve_unresolved_exact : Spec.UnresolvedExact resolve := by
  intro fs wf i
  simp only [resolve, List.mem_map, List.mem_filter, isRequirement, beq_iff_eq,
    List.isEmpty_iff, providers, List.filter_eq_nil_iff, Bool.not_eq_true]
  constructor
  · rintro ⟨r, ⟨⟨hr, hk⟩, hn⟩, rfl⟩
    exact ⟨r, hr, rfl, hk, (no_derivation_iff_no_provider wf hr).mpr hn⟩
  · rintro ⟨r, hr, rfl, hk, hn⟩
    exact ⟨r, ⟨⟨hr, hk⟩, (no_derivation_iff_no_provider wf hr).mp hn⟩, rfl⟩

theorem resolve_total : Spec.Total resolve := by
  intro fs wf r hr hk
  by_cases h : ∃ p ∈ fs, matchesB r p = true
  · obtain ⟨p, hp, hm⟩ := h
    exact .inl ⟨mkEdge fs r p, mem_edges.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl⟩
  · refine .inr ((resolve_unresolved_exact fs wf r.id).mpr
      ⟨r, hr, rfl, hk, (no_derivation_iff_no_provider wf hr).mpr ?_⟩)
    intro p hp
    simpa using fun h' => h ⟨p, hp, h'⟩

end Mitos.Proofs
