import Mathlib.Data.List.Nodup
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
  · exact assumptionsOf_nodup r p
  · exact assumptionsVia_nodup r b p

theorem resolve_unresolved_nodup : Spec.UnresolvedNodup resolve := by
  intro fs wf
  rw [resolve_eq]
  have hreq : List.Sublist (fs.filter isRequirement) fs := List.filter_sublist
  have hempty :
      List.Sublist
        ((fs.filter isRequirement).filter fun r => (ends fs r).isEmpty)
        (fs.filter isRequirement) := List.filter_sublist
  exact List.Nodup.sublist ((hempty.trans hreq).map (·.id)) wf

theorem resolve_edges_nodup : Spec.EdgesNodup resolve := by
  intro fs wf
  unfold WellFormed at wf
  let directKeys (r : Located) :=
    (providers fs r).map (fun p => Derivation.direct r.id p.id)
  let boundKeys (r b : Located) :=
    (boundProviders fs r b).map (fun p => Derivation.bound r.id b.id p.id)
  have hkeys : (resolve fs).edges.map Edge.key =
      fs.flatMap fun r => directKeys r ++ fs.flatMap (boundKeys r) := by
    rw [resolve_eq]
    simp only [List.map_flatMap, List.map_append, List.map_map, Function.comp_def, mkEdge,
      mkBoundEdge, directKeys, boundKeys]
  have hinj := List.inj_on_of_nodup_map wf
  have hnodup := List.Nodup.of_map Located.id wf
  have hids : fs.Pairwise (fun a b => a.id ≠ b.id) := List.pairwise_map.mp wf
  have hreq : ∀ r k, k ∈ directKeys r ++ fs.flatMap (boundKeys r) →
      k.requiringFactId = r.id := by
    intro r k hk
    simp only [directKeys, boundKeys, List.mem_append, List.mem_map, List.mem_flatMap] at hk
    rcases hk with ⟨_, _, rfl⟩ | ⟨_, _, _, _, rfl⟩ <;> rfl
  rw [hkeys, List.nodup_flatMap]
  refine ⟨fun r _ => ?_, hids.imp ?_⟩
  · rw [List.nodup_append, List.nodup_flatMap]
    refine ⟨?_, ⟨fun b _ => ?_, hids.imp ?_⟩, ?_⟩
    · have hdirect : (providers fs r).Nodup := hnodup.filter _
      apply hdirect.map_on
      intro p hp q hq heq
      exact hinj (mem_providers.mp hp).1 (mem_providers.mp hq).1 (Derivation.direct.inj heq).2
    · apply ((boundProviders_sublist fs r b).nodup hnodup).map_on
      intro p hp q hq heq
      exact hinj (mem_boundProviders.mp hp).1 (mem_boundProviders.mp hq).1
        (Derivation.bound.inj heq).2.2
    · intro b b' hne k hk hk'
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hk
      obtain ⟨_, _, heq⟩ := List.mem_map.mp hk'
      exact hne (Derivation.bound.inj heq).2.1.symm
    · intro k hk k' hk' heq
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hk
      obtain ⟨_, _, hk'⟩ := List.mem_flatMap.mp hk'
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hk'
      cases heq
  · intro r r' hne k hk hk'
    exact hne ((hreq r k hk).symm.trans (hreq r' k hk'))

theorem resolve_edge_list_nodup {fs : List Located} (wf : WellFormed fs) :
    (resolve fs).edges.Nodup := by
  have h := resolve_edges_nodup fs wf
  unfold List.Nodup at *
  exact List.Pairwise.of_map Edge.key (fun _ _ hk heq => hk (congrArg Edge.key heq)) h

end Mitos.Proofs
