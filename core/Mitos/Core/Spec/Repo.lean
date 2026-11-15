import Mitos.Core.Spec.Adequacy

namespace Mitos.Spec

theorem retract_repo {R : Resolver} (hs : Sound R) (hr : RetractExact R) :
    ∀ fs a, WellFormed fs → ∀ k,
      k ∈ (R (retract a fs)).edges.map Edge.repoKey ↔
        k ∈ ((R fs).edges.filter (fun e => !(e.assumes.contains a))).map Edge.repoKey := by
  intro fs a wf k
  have wf' := wellFormed_retract a wf
  simp only [List.mem_map]
  constructor
  · rintro ⟨e, he, rfl⟩
    obtain ⟨e', he', hkey⟩ := List.mem_map.mp ((hr fs a wf e.key).mp (List.mem_map.mpr ⟨e, he, rfl⟩))
    obtain ⟨c, hc, hck, hcr, -⟩ := hs _ wf' e he
    obtain ⟨c', hc', hck', hcr', -⟩ := hs fs wf e' (List.mem_filter.mp he').1
    have := derivations_key_inj wf (mem_derivations_retract.mp hc).1 hc'
      (hck.trans (hkey.symm.trans hck'.symm))
    subst this
    exact ⟨e', he', hcr'.symm.trans hcr⟩
  · rintro ⟨e, he, rfl⟩
    obtain ⟨e', he', hkey⟩ := List.mem_map.mp ((hr fs a wf e.key).mpr (List.mem_map.mpr ⟨e, he, rfl⟩))
    obtain ⟨c, hc, hck, hcr, -⟩ := hs fs wf e (List.mem_filter.mp he).1
    obtain ⟨c', hc', hck', hcr', -⟩ := hs _ wf' e' he'
    have := derivations_key_inj wf (mem_derivations_retract.mp hc').1 hc
      (hck'.trans (hkey.trans hck.symm))
    subst this
    exact ⟨e', he', hcr'.symm.trans hcr⟩

theorem declaration_retracted_repo_edge_stays {R : Resolver} (hs : Sound R) (hc : Complete R) :
    Adequacy.goodEdge.repoKey ∈
      (R (retract Adequacy.provDeclared.origin Adequacy.twoProvisions)).edges.map
        Edge.repoKey := by
  have wf' := wellFormed_retract Adequacy.provDeclared.origin Adequacy.wfTwoProvisions
  have hd : Chain.direct Adequacy.req Adequacy.prov ∈
      derivations (retract Adequacy.provDeclared.origin Adequacy.twoProvisions) := by decide
  obtain ⟨e, he, hk⟩ := hc _ wf' _ hd
  obtain ⟨c, hcm, hck, hcr, -⟩ := hs _ wf' e he
  have := derivations_key_inj wf' hcm hd (hck.trans hk)
  subst this
  exact List.mem_map.mpr ⟨e, he, hcr.symm⟩

theorem extractor_retracted_repo_edge_goes {R : Resolver} (hs : Sound R) :
    Adequacy.goodEdge.repoKey ∉
      (R (retract Adequacy.req.origin Adequacy.twoProvisions)).edges.map Edge.repoKey := by
  have wf' := wellFormed_retract Adequacy.req.origin Adequacy.wfTwoProvisions
  have hnil : derivations (retract Adequacy.req.origin Adequacy.twoProvisions) = [] := by decide
  intro h
  obtain ⟨e, he, -⟩ := List.mem_map.mp h
  obtain ⟨c, hc, -⟩ := hs _ wf' e he
  rw [hnil] at hc
  simp at hc

end Mitos.Spec
