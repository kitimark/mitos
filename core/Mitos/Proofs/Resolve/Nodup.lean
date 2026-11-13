import Mitos.Proofs.Resolve.Basic

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem assumptionsOf_nodup (r p : Located) : (assumptionsOf r p).Nodup := by
  unfold assumptionsOf
  split
  · simp
  · rename_i h
    simp [List.nodup_cons, h]

theorem resolve_assumptions_nodup : Spec.AssumptionsNodup resolve := by
  intro fs _ e he
  obtain ⟨r, _, p, _, _, rfl⟩ := mem_edges.mp he
  simpa [mkEdge] using assumptionsOf_nodup r p

theorem resolve_unresolved_nodup : Spec.UnresolvedNodup resolve := by
  intro fs wf
  unfold resolve WellFormed at *
  have hreq : List.Sublist (fs.filter isRequirement) fs := List.filter_sublist
  have hempty :
      List.Sublist
        ((fs.filter isRequirement).filter fun r => (providers fs r).isEmpty)
        (fs.filter isRequirement) := List.filter_sublist
  exact List.Nodup.sublist ((hempty.trans hreq).map (·.id)) wf

theorem resolve_edges_nodup : Spec.EdgesNodup resolve := by
  intro fs wf
  unfold WellFormed at wf
  have hkeys :
      (resolve fs).edges.map Edge.key =
        fs.flatMap fun r => (providers fs r).map fun p => (r.id, p.id) := by
    simp only [resolve, List.map_flatMap, List.map_map, Function.comp_def, mkEdge, Edge.key]
  unfold List.Nodup at *
  rw [hkeys, List.pairwise_flatMap]
  refine ⟨fun r _ => ?_, ?_⟩
  · have hsub : List.Sublist ((providers fs r).map (·.id)) (fs.map (·.id)) := by
      unfold providers
      exact List.filter_sublist.map _
    have hids : ((providers fs r).map (·.id)).Nodup := List.Nodup.sublist hsub wf
    have hpair : (providers fs r).Pairwise (fun a b => a.id ≠ b.id) :=
      List.Pairwise.of_map (·.id) (fun _ _ h => h) hids
    have H : ∀ a b : Located, a.id ≠ b.id → (r.id, a.id) ≠ (r.id, b.id) := by
      intro a b hne heq
      exact hne (congrArg Prod.snd heq)
    exact List.Pairwise.map (fun p => (r.id, p.id)) H hpair
  · have hids : fs.Pairwise (fun a b => a.id ≠ b.id) :=
      List.Pairwise.of_map (·.id) (fun _ _ h => h) wf
    have H : ∀ {a b : Located}, a.id ≠ b.id →
        ∀ x ∈ (providers fs a).map (fun p => (a.id, p.id)),
          ∀ y ∈ (providers fs b).map (fun p => (b.id, p.id)), x ≠ y := by
      intro a b hne x hx y hy heq
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
      exact hne (congrArg Prod.fst heq)
    exact hids.imp H

theorem resolve_edge_list_nodup {fs : List Located} (wf : WellFormed fs) :
    (resolve fs).edges.Nodup := by
  have h := resolve_edges_nodup fs wf
  unfold List.Nodup at *
  exact List.Pairwise.of_map Edge.key (fun _ _ hk heq => hk (congrArg Edge.key heq)) h

end Mitos.Proofs
