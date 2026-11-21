import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem resolve_assumptions_exact : Spec.AssumptionsExact resolve := by
  intro fs wf e he c hc hkey
  rcases mem_edges.mp he with ⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · have := derivations_key_inj wf hc (mem_derivations.mpr (.inl ⟨r, hr, p, hp, hm, rfl⟩)) hkey
    subst this
    have ho : ∀ a, a ∈ (Chain.direct r p).origins ↔ a = r.origin ∨ a = p.origin := by
      simp [Chain.origins, Chain.direct]
    exact ⟨fun a ha => (ho a).mpr (mem_assumptionsOf.mp ha),
      fun a ha => mem_assumptionsOf.mpr ((ho a).mp ha)⟩
  · have := derivations_key_inj wf hc
      (mem_derivations.mpr (.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩)) hkey
    subst this
    have ho : ∀ a, a ∈ (Chain.bound r b p).origins ↔
        a = r.origin ∨ a = b.origin ∨ a = p.origin := by
      simp [Chain.origins, Chain.bound]
    exact ⟨fun a ha => (ho a).mpr (mem_assumptionsVia.mp ha),
      fun a ha => mem_assumptionsVia.mpr ((ho a).mp ha)⟩

theorem statusOf_confirmed {fs : List Located} (wf : WellFormed fs) {r p : Located} (hr : r ∈ fs)
    (assumes : List Assumption) :
    statusOf fs r p assumes = .confirmed ↔
      ((∀ a ∈ assumes, a.isAI = false) ∧
        ∀ c ∈ derivations fs, c.requirement.id = r.id → c.provision.id = p.id) := by
  rw [ends_derivations (P := fun q => q.id = p.id) wf hr]
  simp only [statusOf, Bool.and_eq_true, List.all_eq_true, Bool.not_eq_true', beq_iff_eq]
  split <;> simp_all

theorem resolve_status_honest : Spec.StatusHonest resolve := by
  intro fs wf e he
  rcases mem_edges.mp he with ⟨r, hr, p, -, -, rfl⟩ | ⟨r, hr, b, -, p, -, -, rfl⟩
  · exact statusOf_confirmed wf hr _
  · exact statusOf_confirmed wf hr _

theorem mem_keys {fs : List Located} {k : Derivation} {P : Edge → Bool} :
    k ∈ ((resolve fs).edges.filter P).map Edge.key ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ P (mkEdge fs r p) = true ∧
          k = .direct r.id p.id) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ P (mkBoundEdge fs r b p) = true ∧
          k = .bound r.id b.id p.id := by
  simp only [List.mem_map, List.mem_filter, mem_edges]
  constructor
  · rintro ⟨_, ⟨he, hP⟩, rfl⟩
    rcases he with ⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩
    · exact .inl ⟨r, hr, p, hp, hm, hP, rfl⟩
    · exact .inr ⟨r, hr, b, hb, p, hp, hm, hP, rfl⟩
  · rintro (⟨r, hr, p, hp, hm, hP, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, hP, rfl⟩)
    · exact ⟨_, ⟨.inl ⟨r, hr, p, hp, hm, rfl⟩, hP⟩, rfl⟩
    · exact ⟨_, ⟨.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩, hP⟩, rfl⟩

theorem contains_assumptionsOf {r p : Located} {a : Assumption} :
    (assumptionsOf r p).contains a = false ↔ r.origin ≠ a ∧ p.origin ≠ a := by
  rw [← Bool.not_eq_true, List.contains_iff_mem, mem_assumptionsOf]
  constructor
  · intro h; exact ⟨fun e => h (.inl e.symm), fun e => h (.inr e.symm)⟩
  · rintro ⟨h1, h2⟩ (e | e)
    · exact h1 e.symm
    · exact h2 e.symm

theorem contains_assumptionsVia {r b p : Located} {a : Assumption} :
    (assumptionsVia r b p).contains a = false ↔ r.origin ≠ a ∧ b.origin ≠ a ∧ p.origin ≠ a := by
  rw [← Bool.not_eq_true, List.contains_iff_mem, mem_assumptionsVia]
  simp only [not_or, ne_comm]

theorem resolve_retract_exact : Spec.RetractExact resolve := by
  intro fs a _ k
  have h := @mem_keys (retract a fs) k (fun _ => true)
  rw [List.filter_eq_self.mpr (fun _ _ => rfl)] at h
  rw [h, mem_keys]
  simp only [retract, List.mem_filter, bne_iff_ne, ne_eq, Bool.not_eq_eq_eq_not, Bool.not_true]
  constructor
  · rintro (⟨r, ⟨hr, hra⟩, p, ⟨hp, hpa⟩, hm, -, rfl⟩ |
      ⟨r, ⟨hr, hra⟩, b, ⟨hb, hba⟩, p, ⟨hp, hpa⟩, hm, -, rfl⟩)
    · exact .inl ⟨r, hr, p, hp, hm, contains_assumptionsOf.mpr ⟨hra, hpa⟩, rfl⟩
    · exact .inr ⟨r, hr, b, hb, p, hp, hm, contains_assumptionsVia.mpr ⟨hra, hba, hpa⟩, rfl⟩
  · rintro (⟨r, hr, p, hp, hm, hc, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, hc, rfl⟩)
    · obtain ⟨hra, hpa⟩ := contains_assumptionsOf.mp hc
      exact .inl ⟨r, ⟨hr, hra⟩, p, ⟨hp, hpa⟩, hm, trivial, rfl⟩
    · obtain ⟨hra, hba, hpa⟩ := contains_assumptionsVia.mp hc
      exact .inr ⟨r, ⟨hr, hra⟩, b, ⟨hb, hba⟩, p, ⟨hp, hpa⟩, hm, trivial, rfl⟩

end Mitos.Proofs
