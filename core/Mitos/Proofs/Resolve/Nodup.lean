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
        fs.flatMap fun r => (providers fs r).map fun p => Derivation.direct r.id p.id := by
    simp only [resolve, List.map_flatMap, List.map_map, Function.comp_def, mkEdge]
  have inj := List.inj_on_of_nodup_map wf
  rw [hkeys, List.nodup_flatMap]
  refine ⟨fun r _ => ((List.Nodup.of_map _ wf).filter _).map_on fun p hp q hq h => ?_,
    (List.pairwise_map.mp wf).imp fun hne _ ha hb => ?_⟩
  · exact inj (mem_providers.mp hp).1 (mem_providers.mp hq).1 (Derivation.direct.inj h).2
  · obtain ⟨_, _, rfl⟩ := List.mem_map.mp ha
    obtain ⟨_, _, h⟩ := List.mem_map.mp hb
    exact hne (Derivation.direct.inj h).1.symm

theorem resolve_edge_list_nodup {fs : List Located} (wf : WellFormed fs) :
    (resolve fs).edges.Nodup := by
  have h := resolve_edges_nodup fs wf
  unfold List.Nodup at *
  exact List.Pairwise.of_map Edge.key (fun _ _ hk heq => hk (congrArg Edge.key heq)) h

end Mitos.Proofs
