import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem resolve_sound : Spec.Sound resolve := by
  intro fs _ e he
  rcases mem_edges.mp he with ⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · exact ⟨Chain.direct r p, mem_derivations.mpr (.inl ⟨r, hr, p, hp, hm, rfl⟩), rfl, rfl, rfl⟩
  · exact ⟨Chain.bound r b p, mem_derivations.mpr (.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩),
      rfl, rfl, rfl⟩

theorem resolve_complete : Spec.Complete resolve := by
  intro fs _ c hc
  rcases mem_derivations.mp hc with ⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · exact ⟨mkEdge fs r p, mem_edges.mpr (.inl ⟨r, hr, p, hp, hm, rfl⟩), rfl⟩
  · exact ⟨mkBoundEdge fs r b p, mem_edges.mpr (.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩), rfl⟩

theorem no_derivation_iff_no_end {fs : List Located} (wf : WellFormed fs) {r : Located}
    (hr : r ∈ fs) :
    (∀ c ∈ derivations fs, c.requirement.id ≠ r.id) ↔ (ends fs r).isEmpty := by
  have h := ends_derivations (P := fun _ => False) wf hr
  simp only [imp_false] at h
  rw [h, List.isEmpty_iff, List.eq_nil_iff_forall_not_mem]

theorem resolve_unresolved_exact : Spec.UnresolvedExact resolve := by
  intro fs wf i
  rw [resolve_eq]
  simp only [List.mem_map, List.mem_filter, isRequirement, beq_iff_eq]
  constructor
  · rintro ⟨r, ⟨⟨hr, hk⟩, hn⟩, rfl⟩
    exact ⟨r, hr, rfl, hk, (no_derivation_iff_no_end wf hr).mpr hn⟩
  · rintro ⟨r, hr, rfl, hk, hn⟩
    exact ⟨r, ⟨⟨hr, hk⟩, (no_derivation_iff_no_end wf hr).mp hn⟩, rfl⟩

theorem resolve_total : Spec.Total resolve := by
  intro fs wf r hr hk
  by_cases h : ∃ c ∈ derivations fs, c.requirement.id = r.id
  · obtain ⟨c, hc, hid⟩ := h
    obtain ⟨e, he, hkey⟩ := resolve_complete fs wf c hc
    exact .inl ⟨e, he, by rw [Edge.requiringFactId, hkey, (derivations_key_ends hc).1, hid]⟩
  · exact .inr ((resolve_unresolved_exact fs wf r.id).mpr
      ⟨r, hr, rfl, hk, fun c hc hid => h ⟨c, hc, hid⟩⟩)

end Mitos.Proofs
