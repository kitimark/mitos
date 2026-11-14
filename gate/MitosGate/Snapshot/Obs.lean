import MitosGate.Snapshot.Fields
import MitosGate.Snapshot.Table

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

def dashboardCell (g : Global) (n : Pr) : Option (List Char) := g.verdictCells.bind (·.lookup n)

def complete (g : Global) (p : Pull) (r : Reads) : Bool :=
  g.protection.isSome && g.stacked.isSome && g.verdictCells.isSome && r.comments.isSome &&
    r.reviewComments.isSome && r.reviews.isSome && (activity p r).isSome && r.files.isSome &&
    r.checks.isSome

def ctx (g : Global) (p : Pull) (r : Reads) : Speech.Ctx :=
  { owner := g.owner, pr := p.number, known := known ((activity p r).getD []) }

def obs (g : Global) (p : Pull) (r : Reads) (x : Git) : Obs :=
  { pr := p.number, updatable := updatable g p, enforced := enforced g, head := p.head,
    pushes := ((activity p r).getD []).map toLand, ids := x.ids, paths := r.files, base := x.base,
    gate := gateOf p.head (r.checks.getD []), author := (dashboardCell g p.number).bind authorOf,
    verdicts := ((dashboardCell g p.number).map (verdictsOf (ctx g p r).known)).getD [],
    botAt := botAt p.head (r.checks.getD []) (r.reviews.getD []), delegates := Speech.delegates,
    words := (Speech.words (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
      (complete g p r)).1,
    rest := rest g p r }

def abouts : List Word → List Sha
  | [] => []
  | .ownerLand m :: ws => m.about :: abouts ws
  | .agentLand _ m :: ws => m.about :: abouts ws
  | .ownerHold _ :: ws => abouts ws

def contentIdCommits (o : Obs) : List Sha :=
  (o.head :: (match o.base with
    | .clean r => [r]
    | _ => []) ++ o.verdicts.map (·.head) ++ abouts o.words ++ o.botAt.toList).eraseDups

def FailedReadHolds : Prop :=
  ∀ g p r x, complete g p r = false →
    (∀ e : Entry, e.valid (obs g p r x) = false) ∧ ∀ me q, Land.step me q (obs g p r x) = .stop .held

def EnforcedNeedsProtection : Prop :=
  ∀ g p r x, (obs g p r x).enforced = true →
    ∃ pr, g.protection = some pr ∧ pr.admins = true ∧ pr.strict = true ∧ "gate" ∈ pr.checks

def UpdatableNeedsTheGuard : Prop :=
  ∀ g p r x, (obs g p r x).updatable = true →
    p.state = "open" ∧ p.draft = false ∧ p.baseRef = "main" ∧ p.baseRepo = g.repo ∧
      p.headRepo = some g.repo ∧ ∃ s, g.stacked = some s ∧ p.number ∉ s

def UnreadFilesAreKept : Prop :=
  ∀ g p r x, r.files = none → (obs g p r x).kept = true ∧ (obs g p r x).critical = true

def OnlyTheOwnerQueues : Prop :=
  ∀ g p r x, ∀ e ∈ (obs g p r x).entries, e.lander = .owner

def PushesAreTheActivity : Prop :=
  ∀ g p r x, (obs g p r x).pushes ≠ [] →
    ∃ ps, activity p r = some ps ∧ (obs g p r x).pushes = ps.map toLand ∧ Carry.tip p.head ps = true ∧
      ∀ s ∈ known ps, isSha s.toList = true

def VerdictsFromTheCell : Prop :=
  ∀ g p r x, ∀ v ∈ (obs g p r x).verdicts,
    ∃ c s, dashboardCell g p.number = some c ∧ said? c = some s ∧ v.result = s.result ∧
      v.head ∈ (ctx g p r).known ∧ s.sha.isPrefixOf v.head.toList = true ∧
      ∀ k ∈ (ctx g p r).known, s.sha.isPrefixOf k.toList = true → k = v.head

def RestNeedsAnswersAndTheLabel : Prop :=
  ∀ g p r x, (obs g p r x).rest = true →
    oneFooter p.body = true ∧ unanswered g (posts r) = [] ∧
      ((r.files.map (·.any specPath)).getD true = true → "spec-approved" ∈ p.labels)

theorem failedReadHolds : FailedReadHolds := by
  intro g p r x hc
  obtain ⟨n, hn⟩ := Speech.incompleteReadHolds (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
  have h : Land.newestOwner (obs g p r x).words = some (.ownerHold n) := by
    simp only [obs, hc]
    exact hn
  exact Land.holdWins _ n h

theorem enforcedNeedsProtection : EnforcedNeedsProtection := by
  intro g p r x h
  simp only [obs, enforced] at h
  cases hp : g.protection with
  | none => rw [hp] at h; cases h
  | some pr =>
    rw [hp] at h
    simp only [Option.any_some, Bool.and_eq_true, List.contains_iff_mem] at h
    exact ⟨pr, rfl, h.1.1, h.1.2, h.2⟩

theorem updatableNeedsTheGuard : UpdatableNeedsTheGuard := by
  intro g p r x h
  simp only [obs, updatable, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩ := h
  refine ⟨h1, h2, h3, h4, h5, ?_⟩
  cases hs : g.stacked with
  | none => rw [hs] at h6; cases h6
  | some s =>
    rw [hs] at h6
    simp at h6
    exact ⟨s, rfl, h6⟩

theorem unreadFilesAreKept : UnreadFilesAreKept := by
  intro g p r x h
  simp [obs, Obs.kept, Obs.critical, h]

theorem onlyTheOwnerQueues : OnlyTheOwnerQueues := by
  intro g p r x e he
  cases hl : e.lander with
  | owner => rfl
  | agent t =>
    have := (Land.onlyMergersQueue _ e t he hl).2
    simp [obs, Speech.delegates] at this

theorem pushesAreTheActivity : PushesAreTheActivity := by
  intro g p r x h
  simp only [obs] at h ⊢
  cases ha : activity p r with
  | none => rw [ha] at h; simp at h
  | some ps =>
    refine ⟨ps, rfl, rfl, ?_, ?_⟩
    · simp only [activity, Option.filter] at ha
      split at ha
      · split at ha
        · next hok => cases ha; simp only [pushesOk, Bool.and_eq_true] at hok; exact hok.2
        · cases ha
      · cases ha
    · intro s hs
      simp only [activity, Option.filter] at ha
      split at ha
      · split at ha
        · next hok =>
          cases ha
          simp only [pushesOk, Bool.and_eq_true, List.all_eq_true] at hok
          simp only [known, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at hs
          obtain ⟨q, hq, rfl | rfl⟩ := hs
          · exact (hok.1.1 q hq).1
          · exact (hok.1.1 q hq).2
        · cases ha
      · cases ha

theorem verdictsFromTheCell : VerdictsFromTheCell := by
  intro g p r x v hv
  simp only [obs] at hv
  cases hc : dashboardCell g p.number with
  | none => rw [hc] at hv; simp at hv
  | some c =>
    rw [hc] at hv
    simp only [Option.map_some, Option.getD_some] at hv
    obtain ⟨s, hs, hres, hk⟩ := verdictsOf_spec hv
    obtain ⟨h1, h2, h3⟩ := resolveKnown_spec hk
    exact ⟨c, s, rfl, hs, hres, h1, h2, h3⟩

theorem restNeedsAnswersAndTheLabel : RestNeedsAnswersAndTheLabel := by
  intro g p r x h
  simp only [obs, rest, Bool.and_eq_true, List.isEmpty_iff, Bool.or_eq_true, Bool.not_eq_true',
    List.contains_iff_mem] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨h1, h2, fun hs => ?_⟩
  rcases h3 with h3 | h3
  · rw [hs] at h3; cases h3
  · exact h3

end MitosGate.Snapshot
