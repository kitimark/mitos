import Mitos.Impl.Resolve

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem mem_providers {fs : List Located} {r p : Located} :
    p ∈ providers fs r ↔ p ∈ fs ∧ matchesB r p = true := by
  simp [providers]

theorem mem_edges {fs : List Located} {e : Edge} :
    e ∈ (resolve fs).edges ↔ ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ e = mkEdge fs r p := by
  simp only [resolve, List.mem_flatMap, List.mem_map, mem_providers]
  constructor
  · rintro ⟨r, hr, p, ⟨hp, hm⟩, rfl⟩; exact ⟨r, hr, p, hp, hm, rfl⟩
  · rintro ⟨r, hr, p, hp, hm, rfl⟩; exact ⟨r, hr, p, ⟨hp, hm⟩, rfl⟩

theorem matchesB_requires {r p : Located} (h : matchesB r p = true) :
    r.fact.kind = .requires := by
  simp only [matchesB, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1.1

theorem mem_assumptionsOf {r p : Located} {a : Assumption} :
    a ∈ assumptionsOf r p ↔ a = r.origin ∨ a = p.origin := by
  unfold assumptionsOf
  split <;> simp_all

end Mitos.Proofs
