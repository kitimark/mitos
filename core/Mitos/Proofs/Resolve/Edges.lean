import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem resolve_sound : Spec.Sound resolve := by
  intro fs _ e he
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := mem_edges.mp he
  exact ⟨r, hr, p, hp, rfl, rfl, hm, rfl, rfl, rfl, rfl⟩

theorem resolve_complete : Spec.Complete resolve := by
  intro fs _ r hr p hp hm
  exact ⟨mkEdge fs r p, mem_edges.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl, rfl⟩

theorem resolve_unresolved_exact : Spec.UnresolvedExact resolve := by
  intro fs _ i
  simp only [resolve, List.mem_map, List.mem_filter, isRequirement, beq_iff_eq,
    List.isEmpty_iff, providers, List.filter_eq_nil_iff, Bool.not_eq_true]
  constructor
  · rintro ⟨r, ⟨⟨hr, hk⟩, hn⟩, rfl⟩; exact ⟨r, hr, rfl, hk, hn⟩
  · rintro ⟨r, hr, rfl, hk, hn⟩; exact ⟨r, ⟨⟨hr, hk⟩, hn⟩, rfl⟩

theorem resolve_total : Spec.Total resolve := by
  intro fs wf r hr hk
  by_cases h : ∃ p ∈ fs, matchesB r p = true
  · obtain ⟨p, hp, hm⟩ := h
    exact .inl ⟨mkEdge fs r p, mem_edges.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl⟩
  · refine .inr ((resolve_unresolved_exact fs wf r.id).mpr ⟨r, hr, rfl, hk, ?_⟩)
    intro p hp
    simpa using fun h' => h ⟨p, hp, h'⟩

end Mitos.Proofs
