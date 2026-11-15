import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem assumptionsOf_nodup (r p : Located) : (assumptionsOf r p).Nodup := by
  unfold assumptionsOf
  split
  · simp
  · rename_i h
    simp [List.nodup_cons, h]

theorem assumptionsVia_nodup (r b p : Located) : (assumptionsVia r b p).Nodup := by
  unfold assumptionsVia
  by_cases h : b.origin ∈ assumptionsOf r p
  · rw [List.insert_of_mem h]; exact assumptionsOf_nodup r p
  · rw [List.insert_of_not_mem h]; exact List.nodup_cons.mpr ⟨h, assumptionsOf_nodup r p⟩

theorem resolve_assumptions_nodup : Spec.AssumptionsNodup resolve := by
  intro fs _ e he
  rcases mem_edges.mp he with ⟨r, _, p, _, _, rfl⟩ | ⟨r, _, b, _, p, _, _, rfl⟩
  · simpa [mkEdge] using assumptionsOf_nodup r p
  · exact assumptionsVia_nodup r b p

theorem resolve_unresolved_nodup : Spec.UnresolvedNodup resolve := by
  intro fs wf
  rw [resolve_eq]
  unfold WellFormed at *
  have hreq : List.Sublist (fs.filter isRequirement) fs := List.filter_sublist
  have hempty :
      List.Sublist
        ((fs.filter isRequirement).filter fun r => (ends fs r).isEmpty)
        (fs.filter isRequirement) := List.filter_sublist
  exact List.Nodup.sublist ((hempty.trans hreq).map (·.id)) wf

theorem resolve_edges_nodup : Spec.EdgesNodup resolve := by
  intro fs wf
  unfold WellFormed at wf
  have hkeys :
      (resolve fs).edges.map Edge.key =
        fs.flatMap fun r => (providers fs r).map (fun p => Derivation.direct r.id p.id) ++
          fs.flatMap fun b => (boundProviders fs r b).map fun p => Derivation.bound r.id b.id p.id := by
    rw [resolve_eq]
    simp only [List.map_flatMap, List.map_append, List.map_map, Function.comp_def, mkEdge,
      mkBoundEdge]
  have hids : fs.Pairwise (fun a b => a.id ≠ b.id) :=
    List.Pairwise.of_map (·.id) (fun _ _ h => h) wf
  have hsub : ∀ l : List Located, l.Sublist fs → l.Pairwise (fun a b => a.id ≠ b.id) :=
    fun l hl => hids.sublist hl
  have hreq : ∀ r x, x ∈ (providers fs r).map (fun p => Derivation.direct r.id p.id) ++
      fs.flatMap (fun b => (boundProviders fs r b).map fun p => Derivation.bound r.id b.id p.id) →
      x.requiringFactId = r.id := by
    intro r x hx
    simp only [List.mem_append, List.mem_map, List.mem_flatMap] at hx
    rcases hx with ⟨_, _, rfl⟩ | ⟨_, _, _, _, rfl⟩ <;> rfl
  unfold List.Nodup
  rw [hkeys, List.pairwise_flatMap]
  refine ⟨fun r _ => ?_, hids.imp ?_⟩
  · rw [List.pairwise_append, List.pairwise_flatMap]
    refine ⟨?_, ⟨fun b _ => ?_, hids.imp ?_⟩, ?_⟩
    · exact List.Pairwise.map _ (fun _ _ hne heq => hne (Derivation.direct.inj heq).2)
        (hsub _ List.filter_sublist)
    · exact List.Pairwise.map _ (fun _ _ hne heq => hne (Derivation.bound.inj heq).2.2)
        (hsub _ (boundProviders_sublist fs r b))
    · intro b b' hne x hx y hy heq
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
      exact hne (Derivation.bound.inj heq).2.1
    · intro x hx y hy heq
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
      obtain ⟨_, _, hy⟩ := List.mem_flatMap.mp hy
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
      cases heq
  · intro a b hne x hx y hy heq
    exact hne (by rw [← hreq _ x hx, ← hreq _ y hy, heq])

theorem resolve_edge_list_nodup {fs : List Located} (wf : WellFormed fs) :
    (resolve fs).edges.Nodup := by
  have h := resolve_edges_nodup fs wf
  unfold List.Nodup at *
  exact List.Pairwise.of_map Edge.key (fun _ _ hk heq => hk (congrArg Edge.key heq)) h

end Mitos.Proofs
