import Mitos.Core.Graph

namespace Mitos

def matchesB (r p : Located) : Bool :=
  r.fact.kind == .requires && p.fact.kind == .provides && r.fact.ident == p.fact.ident

structure Chain where
  key         : Derivation
  requirement : Located
  via         : List Located
  provision   : Located
  deriving DecidableEq, Repr

def Chain.direct (r p : Located) : Chain :=
  { key := .direct r.id p.id, requirement := r, via := [], provision := p }

def Chain.origins (c : Chain) : List Assumption :=
  (c.requirement :: c.via ++ [c.provision]).map (·.origin)

def Chain.repoKey (c : Chain) : RepoKey :=
  { requiringRepo := c.requirement.repo, providingRepo := c.provision.repo,
    ident := c.requirement.fact.ident, scope := c.requirement.fact.scope }

def boundB (r b p : Located) : Bool :=
  r.fact.kind == .requires && b.fact.ident == r.fact.ident &&
    b.fact.kind == .binds p.fact.ident && p.fact.kind == .provides &&
    p.fact.ident != r.fact.ident

def Chain.bound (r b p : Located) : Chain :=
  { key := .bound r.id b.id p.id, requirement := r, via := [b], provision := p }

def Chain.through (c : Chain) : List String :=
  c.via.map Located.repo

def derivations (fs : List Located) : List Chain :=
  fs.flatMap fun r => (fs.filter (matchesB r)).map (Chain.direct r) ++
    fs.flatMap fun b => (fs.filter (boundB r b)).map (Chain.bound r b)

theorem mem_derivations {fs : List Located} {c : Chain} :
    c ∈ derivations fs ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ c = Chain.bound r b p := by
  simp only [derivations, List.mem_flatMap, List.mem_append, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨r, hr, ⟨p, ⟨hp, hm⟩, rfl⟩ | ⟨b, hb, p, ⟨hp, hm⟩, rfl⟩⟩
    · exact .inl ⟨r, hr, p, hp, hm, rfl⟩
    · exact .inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · rintro (⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩)
    · exact ⟨r, hr, .inl ⟨p, ⟨hp, hm⟩, rfl⟩⟩
    · exact ⟨r, hr, .inr ⟨b, hb, p, ⟨hp, hm⟩, rfl⟩⟩

theorem derivations_key_ends {fs : List Located} {c : Chain} (h : c ∈ derivations fs) :
    c.key.requiringFactId = c.requirement.id ∧ c.key.providingFactId = c.provision.id := by
  rcases mem_derivations.mp h with ⟨r, -, p, -, -, rfl⟩ | ⟨r, -, b, -, p, -, -, rfl⟩ <;>
    exact ⟨rfl, rfl⟩

theorem derivations_key_inj {fs : List Located} (wf : WellFormed fs) {c d : Chain}
    (hc : c ∈ derivations fs) (hd : d ∈ derivations fs) (h : c.key = d.key) : c = d := by
  rcases mem_derivations.mp hc with ⟨r, hr, p, hp, -, rfl⟩ | ⟨r, hr, b, hb, p, hp, -, rfl⟩ <;>
    rcases mem_derivations.mp hd with ⟨r', hr', p', hp', -, rfl⟩ | ⟨r', hr', b', hb', p', hp', -, rfl⟩
  · obtain ⟨h1, h2⟩ := Derivation.direct.inj h
    rw [wf.eq_of_id hr hr' h1, wf.eq_of_id hp hp' h2]
  · cases h
  · cases h
  · obtain ⟨h1, h2, h3⟩ := Derivation.bound.inj h
    rw [wf.eq_of_id hr hr' h1, wf.eq_of_id hb hb' h2, wf.eq_of_id hp hp' h3]

theorem mem_derivations_retract {a : Assumption} {fs : List Located} {c : Chain} :
    c ∈ derivations (retract a fs) ↔ c ∈ derivations fs ∧ a ∉ c.origins := by
  simp only [mem_derivations, retract, List.mem_filter, bne_iff_ne, ne_eq]
  constructor
  · rintro (⟨r, ⟨hr, hra⟩, p, ⟨hp, hpa⟩, hm, rfl⟩ | ⟨r, ⟨hr, hra⟩, b, ⟨hb, hba⟩, p, ⟨hp, hpa⟩, hm, rfl⟩)
    · refine ⟨.inl ⟨r, hr, p, hp, hm, rfl⟩, ?_⟩
      simp only [Chain.origins, Chain.direct, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or]
      exact ⟨fun h => hra h.symm, fun h => hpa h.symm⟩
    · refine ⟨.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩, ?_⟩
      simp only [Chain.origins, Chain.bound, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or]
      exact ⟨fun h => hra h.symm, fun h => hba h.symm, fun h => hpa h.symm⟩
  · rintro ⟨⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩, ha⟩
    · simp only [Chain.origins, Chain.direct, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or] at ha
      exact .inl ⟨r, ⟨hr, fun h => ha.1 h.symm⟩, p, ⟨hp, fun h => ha.2 h.symm⟩, hm, rfl⟩
    · simp only [Chain.origins, Chain.bound, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or] at ha
      exact .inr ⟨r, ⟨hr, fun h => ha.1 h.symm⟩, b, ⟨hb, fun h => ha.2.1 h.symm⟩, p,
        ⟨hp, fun h => ha.2.2 h.symm⟩, hm, rfl⟩

def NoBinds (fs : List Located) : Prop := ∀ b ∈ fs, ∀ i, b.fact.kind ≠ .binds i

theorem mem_derivations_of_noBinds {fs : List Located} (hnb : NoBinds fs) {c : Chain} :
    c ∈ derivations fs ↔ ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p := by
  refine mem_derivations.trans ⟨?_, .inl⟩
  rintro (h | ⟨r, -, b, hb, p, -, hm, -⟩)
  · exact h
  · simp only [boundB, Bool.and_eq_true, beq_iff_eq] at hm
    exact absurd hm.1.1.2 (hnb b hb p.fact.ident)

theorem derivations_single_provider {fs : List Located} (wf : WellFormed fs) (hnb : NoBinds fs)
    {c : Chain} (hc : c ∈ derivations fs) :
    (∀ d ∈ derivations fs, d.requirement.id = c.requirement.id →
        d.provision.id = c.provision.id) ↔
      (fs.filter (matchesB c.requirement)).length = 1 := by
  have hdirect : ∀ {d : Chain}, d ∈ derivations fs ↔
      ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ d = Chain.direct r p :=
    mem_derivations_of_noBinds hnb
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := hdirect.mp hc
  show (∀ d ∈ derivations fs, d.requirement.id = r.id → d.provision.id = p.id) ↔
    (fs.filter (matchesB r)).length = 1
  have hpL : p ∈ fs.filter (matchesB r) := List.mem_filter.mpr ⟨hp, hm⟩
  constructor
  · intro H
    have hall : ∀ q ∈ fs.filter (matchesB r), q = p := by
      intro q hq
      obtain ⟨hq, hqm⟩ := List.mem_filter.mp hq
      exact wf.eq_of_id hq hp
        (H (Chain.direct r q) (hdirect.mpr ⟨r, hr, q, hq, hqm, rfl⟩) rfl)
    have hnd : (fs.filter (matchesB r)).Nodup := by
      unfold WellFormed List.Nodup at wf
      exact (List.Pairwise.of_map (·.id) (fun _ _ h heq => h (congrArg (·.id) heq)) wf).sublist
        List.filter_sublist
    rw [List.eq_replicate_iff.mpr ⟨rfl, hall⟩, List.nodup_replicate] at hnd
    have := List.length_pos_of_mem hpL
    omega
  · intro hlen d hd hid
    obtain ⟨q, hq⟩ := List.length_eq_one_iff.mp hlen
    obtain ⟨r', hr', p', hp', hm', rfl⟩ := hdirect.mp hd
    have hrr : r' = r := wf.eq_of_id hr' hr hid
    subst hrr
    have hp'L : p' ∈ fs.filter (matchesB r') := List.mem_filter.mpr ⟨hp', hm'⟩
    rw [hq, List.mem_singleton] at hp'L hpL
    simp only [Chain.direct, hp'L, hpL]

end Mitos
