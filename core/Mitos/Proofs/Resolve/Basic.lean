import Mitos.Impl.Resolve

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem mem_providers {fs : List Located} {r p : Located} :
    p ∈ providers fs r ↔ p ∈ fs ∧ matchesB r p = true := by
  simp [providers]

theorem summarizeEnds_accepts (ps : List Located) (id : Nat) :
    (summarizeEnds ps).accepts id = ps.all (·.id == id) := by
  cases ps with
  | nil => rfl
  | cons p rest =>
    simp only [summarizeEnds, List.all_cons]
    split
    · rename_i h
      simp only [EndSummary.accepts]
      by_cases he : p.id = id
      · subst id; simp [h]
      · have hn : (p.id == id) = false := by simp [he]
        simp [hn]
    · rename_i h
      simp only [EndSummary.accepts]
      by_cases he : p.id = id
      · subst id; simp_all
      · simp [he]

theorem resolveOne_eq (fs : List Located) (r : Located) :
    resolveOne fs r =
      ((providers fs r).map (mkEdge fs r) ++
        fs.flatMap (fun b => (boundProviders fs r b).map (mkBoundEdge fs r b)),
       if isRequirement r && (ends fs r).isEmpty then [r.id] else []) := by
  simp only [resolveOne, List.flatMap_map, summarizeEnds_accepts]
  rfl

theorem resolve_eq (fs : List Located) :
    resolve fs =
      { edges := fs.flatMap fun r => (providers fs r).map (mkEdge fs r) ++
          fs.flatMap fun b => (boundProviders fs r b).map (mkBoundEdge fs r b)
        unresolved := ((fs.filter isRequirement).filter fun r => (ends fs r).isEmpty).map (·.id) } := by
  simp only [resolve, List.flatMap_map, resolveOne_eq]
  congr 1
  have hflat : ∀ (xs : List Located),
      xs.flatMap (fun r => if isRequirement r && (ends fs r).isEmpty then [r.id] else []) =
        ((xs.filter isRequirement).filter fun r => (ends fs r).isEmpty).map (·.id) := by
    intro xs
    induction xs with
    | nil => rfl
    | cons x xs ih =>
      cases hreq : isRequirement x <;> cases hempty : (ends fs x).isEmpty <;>
        simp only [List.flatMap_cons, List.filter_cons, hreq, hempty, Bool.and_true, Bool.and_false, Bool.false_eq_true, ↓reduceIte,
          List.map_cons, List.cons_append, List.nil_append, ih]
  exact hflat fs

theorem boundProviders_sublist (fs : List Located) (r b : Located) :
    (boundProviders fs r b).Sublist fs := by
  cases h : b.fact.kind <;> simp only [boundProviders, h]
  · exact List.nil_sublist _
  · exact List.nil_sublist _
  · exact List.filter_sublist

theorem mem_boundProviders {fs : List Located} {r b p : Located} :
    p ∈ boundProviders fs r b ↔ p ∈ fs ∧ boundB r b p = true := by
  cases h : b.fact.kind <;> simp [boundProviders, h, boundB]

theorem mem_ends {fs : List Located} {r q : Located} :
    q ∈ ends fs r ↔ q ∈ fs ∧ (matchesB r q = true ∨ ∃ b ∈ fs, boundB r b q = true) := by
  simp only [ends, List.mem_append, List.mem_flatMap, mem_providers, mem_boundProviders]
  constructor
  · rintro (⟨hq, hm⟩ | ⟨b, hb, hq, hm⟩)
    · exact ⟨hq, .inl hm⟩
    · exact ⟨hq, .inr ⟨b, hb, hm⟩⟩
  · rintro ⟨hq, hm | ⟨b, hb, hm⟩⟩
    · exact .inl ⟨hq, hm⟩
    · exact .inr ⟨b, hb, hq, hm⟩

theorem mem_edges {fs : List Located} {e : Edge} :
    e ∈ (resolve fs).edges ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ e = mkEdge fs r p) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ e = mkBoundEdge fs r b p := by
  rw [resolve_eq]
  simp only [List.mem_flatMap, List.mem_append, List.mem_map, mem_providers, mem_boundProviders]
  constructor
  · rintro ⟨r, hr, ⟨p, ⟨hp, hm⟩, rfl⟩ | ⟨b, hb, p, ⟨hp, hm⟩, rfl⟩⟩
    · exact .inl ⟨r, hr, p, hp, hm, rfl⟩
    · exact .inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · rintro (⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩)
    · exact ⟨r, hr, .inl ⟨p, ⟨hp, hm⟩, rfl⟩⟩
    · exact ⟨r, hr, .inr ⟨b, hb, p, ⟨hp, hm⟩, rfl⟩⟩

theorem matchesB_requires {r p : Located} (h : matchesB r p = true) :
    r.fact.kind = .requires := by
  simp only [matchesB, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1.1

theorem mem_assumptionsOf {r p : Located} {a : Assumption} :
    a ∈ assumptionsOf r p ↔ a = r.origin ∨ a = p.origin := by
  unfold assumptionsOf
  split <;> simp_all

theorem mem_assumptionsVia {r b p : Located} {a : Assumption} :
    a ∈ assumptionsVia r b p ↔ a = r.origin ∨ a = b.origin ∨ a = p.origin := by
  unfold assumptionsVia
  rw [List.mem_insert_iff, mem_assumptionsOf, or_left_comm]

theorem ends_derivations {fs : List Located} (wf : WellFormed fs) {r : Located} (hr : r ∈ fs)
    {P : Located → Prop} :
    (∀ c ∈ derivations fs, c.requirement.id = r.id → P c.provision) ↔ ∀ q ∈ ends fs r, P q := by
  constructor
  · intro H q hq
    obtain ⟨hq, hm | ⟨b, hb, hm⟩⟩ := mem_ends.mp hq
    · exact H (Chain.direct r q) (mem_derivations.mpr (.inl ⟨r, hr, q, hq, hm, rfl⟩)) rfl
    · exact H (Chain.bound r b q) (mem_derivations.mpr (.inr ⟨r, hr, b, hb, q, hq, hm, rfl⟩)) rfl
  · intro H c hc hid
    rcases mem_derivations.mp hc with ⟨r', hr', p, hp, hm, rfl⟩ | ⟨r', hr', b, hb, p, hp, hm, rfl⟩
    · have := wf.eq_of_id hr' hr hid
      subst this
      exact H p (mem_ends.mpr ⟨hp, .inl hm⟩)
    · have := wf.eq_of_id hr' hr hid
      subst this
      exact H p (mem_ends.mpr ⟨hp, .inr ⟨b, hb, hm⟩⟩)

end Mitos.Proofs
