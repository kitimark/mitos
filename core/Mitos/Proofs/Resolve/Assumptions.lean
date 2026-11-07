import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem resolve_assumptions_exact : Spec.AssumptionsExact resolve := by
  intro fs wf e he r hr p hp hreq hprov a
  obtain ⟨r', hr', p', hp', _, rfl⟩ := mem_edges.mp he
  have := WellFormed.eq_of_id wf hr hr' hreq
  have := WellFormed.eq_of_id wf hp hp' hprov
  subst r' p'
  exact mem_assumptionsOf

theorem resolve_status_honest : Spec.StatusHonest resolve := by
  intro fs wf e he r hr hreq
  obtain ⟨r', hr', p, _, _, rfl⟩ := mem_edges.mp he
  have := WellFormed.eq_of_id wf hr hr' hreq
  subst r'
  simp only [mkEdge, statusOf, providers, Bool.and_eq_true, List.all_eq_true,
    Bool.not_eq_true', beq_iff_eq]
  split <;> simp_all

theorem mem_keys {fs : List Located} {k : Nat × Nat} {P : Edge → Bool} :
    k ∈ ((resolve fs).edges.filter P).map Edge.key ↔
      ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ P (mkEdge fs r p) = true ∧ k = (r.id, p.id) := by
  simp only [List.mem_map, List.mem_filter, mem_edges]
  constructor
  · rintro ⟨_, ⟨⟨r, hr, p, hp, hm, rfl⟩, hP⟩, rfl⟩; exact ⟨r, hr, p, hp, hm, hP, rfl⟩
  · rintro ⟨r, hr, p, hp, hm, hP, rfl⟩; exact ⟨_, ⟨⟨r, hr, p, hp, hm, rfl⟩, hP⟩, rfl⟩

theorem contains_assumptionsOf {r p : Located} {a : Assumption} :
    (assumptionsOf r p).contains a = false ↔ r.origin ≠ a ∧ p.origin ≠ a := by
  rw [← Bool.not_eq_true, List.contains_iff_mem, mem_assumptionsOf]
  constructor
  · intro h; exact ⟨fun e => h (.inl e.symm), fun e => h (.inr e.symm)⟩
  · rintro ⟨h1, h2⟩ (e | e)
    · exact h1 e.symm
    · exact h2 e.symm

theorem resolve_retract_exact : Spec.RetractExact resolve := by
  intro fs a _ k
  have h := @mem_keys (retract a fs) k (fun _ => true)
  rw [List.filter_eq_self.mpr (fun _ _ => rfl)] at h
  rw [h, mem_keys]
  simp only [retract, List.mem_filter, bne_iff_ne, ne_eq, Bool.not_eq_eq_eq_not, Bool.not_true]
  constructor
  · rintro ⟨r, ⟨hr, hra⟩, p, ⟨hp, hpa⟩, hm, -, rfl⟩
    exact ⟨r, hr, p, hp, hm, contains_assumptionsOf.mpr ⟨hra, hpa⟩, rfl⟩
  · rintro ⟨r, hr, p, hp, hm, hc, rfl⟩
    obtain ⟨hra, hpa⟩ := contains_assumptionsOf.mp hc
    exact ⟨r, ⟨hr, hra⟩, p, ⟨hp, hpa⟩, hm, trivial, rfl⟩

end Mitos.Proofs
