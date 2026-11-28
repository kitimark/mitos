import MitosGate.Snapshot.Activity
import MitosGate.Snapshot.Fields

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

def provenanceFact (g : Global) (n : Pr) : Option Provenance.PullFact :=
  g.provenance.bind fun ps => ps.find? (·.number == n)

def complete (g : Global) (p : Pull) (r : Reads) : Bool :=
  g.protection.isSome && g.stacked.isSome && g.issueRead && r.comments.isSome &&
    r.reviewComments.isSome && r.reviews.isSome && (activity p r).isSome && r.files.isSome &&
    r.checks.isSome

def ctx (g : Global) (p : Pull) (r : Reads) : Speech.Ctx :=
  { owner := g.owner, pr := p.number, known := known ((activity p r).getD []) }

def reviewPosts (r : Reads) : List Post :=
  r.reviewComments.getD [] ++
    ((r.reviews.getD []).filter counts).map fun v => ⟨v.login, none, v.submitted, v.submitted, v.body, none⟩

def summarySpeaks (g : Global) (vs : List Review) : Bool :=
  vs.any fun v => !v.body.isEmpty && speaks g ⟨v.login, none, v.submitted, v.submitted, v.body, none⟩

def ownerReviewWithoutPost (g : Global) (r : Reads) (v : Review) : Bool :=
  v.login == g.owner && !counts v && !(r.reviewComments.getD []).any (·.review == some v.id)

def reviewsSpeak (g : Global) (r : Reads) : Bool :=
  summarySpeaks g (r.reviews.getD []) || (r.reviews.getD []).any (ownerReviewWithoutPost g r)

/-- The reviews route has no update time, so a summary edited after the approval reads as typed
before it. Owner summary text without a recognized agent footer, or an owner review with no
counted or matching post, retires approval at any time. -/
def spokeInReview (g : Global) (r : Reads) (ws : List Word) : Bool :=
  match Land.newestOwner ws with
  | some (.ownerLand m) =>
    reviewsSpeak g r ||
    (r.comments.getD []).any fun c => 2 * c.id == m.said &&
      (reviewPosts r).any fun s => speaks g s && decide (c.created ≤ s.lastSpoke)
  | _ => false

def withReviewSpeech (g : Global) (p : Pull) (r : Reads) (ws : List Word) : List Word :=
  if spokeInReview g r ws then
    ws ++ [.ownerSpoke (2 * Speech.top (ctx g p r) (r.comments.getD []) + 2)]
  else ws

def sourceObs (g : Global) (p : Pull) (r : Reads) (x : Git) : Obs :=
  { pr := p.number, updatable := updatable g p, enforced := enforced g, head := p.head,
    pushes := ((activity p r).getD []).map toLand, ids := x.ids, paths := r.files, base := x.base,
    gate := gateOf p.head (r.checks.getD []), author := none, verdicts := [],
    botAt := botAt p.head (r.checks.getD []) (r.reviews.getD []), delegates := Speech.delegates,
    words := withReviewSpeech g p r (Speech.words (ctx g p r) (r.comments.getD [])
      ((activity p r).getD []) (complete g p r)).1,
    rest := rest g p r }

def obs (g : Global) (p : Pull) (r : Reads) (x : Git) : Obs :=
  let o := sourceObs g p r x
  match provenanceFact g p.number with
  | some f => Provenance.project o f p.labels
  | none => { o with rest := false }

theorem obs_projection (g : Global) (p : Pull) (r : Reads) (x : Git) :
    obs g p r x =
      { sourceObs g p r x with
        author := (provenanceFact g p.number).bind (Provenance.authorOf (sourceObs g p r x))
        verdicts := ((provenanceFact g p.number).map fun f =>
          f.verdicts.map Provenance.VerdictFact.toLand).getD []
        rest := (sourceObs g p r x).rest && (provenanceFact g p.number).any
          (fun f => Provenance.sourceGuard (sourceObs g p r x) f p.labels) } := by
  cases hf : provenanceFact g p.number <;>
    simp [obs, hf, Provenance.project, Provenance.withFacts, sourceObs]

def abouts : List Word → List Sha
  | [] => []
  | .ownerLand m :: ws => m.about :: abouts ws
  | .agentLand _ m :: ws => m.about :: abouts ws
  | .ownerHold _ :: ws => abouts ws
  | .ownerSpoke _ :: ws => abouts ws

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

def VerdictsFromTheSource : Prop :=
  ∀ g p r x, ∀ v ∈ (obs g p r x).verdicts,
    ∃ f, provenanceFact g p.number = some f ∧ ∃ event ∈ f.verdicts,
      v = event.toLand

def RestNeedsSourceGuard : Prop :=
  ∀ g p r x, (obs g p r x).rest = true →
    ∃ f, provenanceFact g p.number = some f ∧ Provenance.sourceGuard (sourceObs g p r x) f p.labels = true

def RestNeedsAnswersAndTheLabel : Prop :=
  ∀ g p r x, (obs g p r x).rest = true →
    oneFooter p.body = true ∧ unanswered g (posts r) = [] ∧
      ((r.files.map (·.any specPath)).getD true = true → "spec-approved" ∈ p.labels)

def KeptMergeIsTheOwnersTypedApproval : Prop :=
  ∀ g p r x q h e, Land.next q = some (e, obs g p r x) → Land.plan q = .merge p.number h →
    (obs g p r x).kept = true →
    ∃ c ∈ r.comments.getD [], c.login = g.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      Speech.footer c.body.toList = false ∧ Speech.onlyWords c.body.toList = true ∧
      (∃ arg s, arg ≠ [] ∧ Speech.ownerLines c.body.toList = .ok [.land arg] ∧
        Speech.resolve (ctx g p r).known arg = some s ∧ (obs g p r x).carries s = true) ∧
      (∀ d ∈ r.comments.getD [], Speech.typed (ctx g p r) d = true → d.id ≤ c.id) ∧
      (∀ s ∈ reviewPosts r, speaks g s = true → s.lastSpoke < c.created) ∧
      summarySpeaks g (r.reviews.getD []) = false ∧ ∀ v ∈ r.reviews.getD [], ownerReviewWithoutPost g r v = false

theorem newestOwner_append_spoke (ws : List Word) (n : Nat) :
    Land.newestOwner (ws ++ [.ownerSpoke n]) = Land.newestOwner ws := by
  have h1 : Land.newestOwner (ws ++ [Word.ownerSpoke n]) =
      Land.newestOwner ((ws ++ [Word.ownerSpoke n]).filter (·.decides)) :=
    Land.onlyLandOrHoldChangesTheWord _
  have h2 : Land.newestOwner ws = Land.newestOwner (ws.filter (·.decides)) :=
    Land.onlyLandOrHoldChangesTheWord _
  rw [h1, h2]
  simp [List.filter_append, Land.Word.decides]

theorem newestOwner_withReviewSpeech (g : Global) (p : Pull) (r : Reads) (ws : List Word) :
    Land.newestOwner (withReviewSpeech g p r ws) = Land.newestOwner ws := by
  unfold withReviewSpeech
  split
  · exact newestOwner_append_spoke _ _
  · rfl

theorem mem_withReviewSpeech {g : Global} {p : Pull} {r : Reads} {ws : List Word} {w : Word}
    (h : w ∈ ws) : w ∈ withReviewSpeech g p r ws := by
  unfold withReviewSpeech
  split
  · exact List.mem_append_left _ h
  · exact h

theorem keptMergeIsTheOwnersTypedApproval : KeptMergeIsTheOwnersTypedApproval := by
  intro g p r x q h e hn hp hk
  obtain ⟨e', o', hn', -, -, -, -, -, -, -, -, -, -, hw, hs, hcar, ha⟩ :=
    Land.plannedMergeIsGated q p.number h hp
  rw [hn] at hn'
  cases hn'
  simp only [obs_projection] at hw hs
  have hw' : Land.newestOwner (Speech.words (ctx g p r) (r.comments.getD [])
      ((activity p r).getD []) (complete g p r)).1 = some (.ownerLand e.mark) := by
    rw [← newestOwner_withReviewSpeech g p r]; exact hw
  obtain ⟨hmem, -, hmax⟩ := Land.newestOwner_max hw'
  obtain ⟨c, hc, ho, hsl, hu, hf, hsaid, hon, arg, harg, hl, hres⟩ :=
    Speech.approvalIsTypedAndNamed (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
      (complete g p r) e.mark hmem (ha hk)
  have hno : spokeInReview g r (Speech.words (ctx g p r) (r.comments.getD [])
        ((activity p r).getD []) (complete g p r)).1 = false := by
      cases hsr : spokeInReview g r (Speech.words (ctx g p r) (r.comments.getD [])
        ((activity p r).getD []) (complete g p r)).1 with
      | false => rfl
      | true =>
        have hin : Word.ownerSpoke (2 * Speech.top (ctx g p r) (r.comments.getD []) + 2) ∈
            (obs g p r x).words := by
          rw [obs_projection]
          show _ ∈ withReviewSpeech g p r _
          unfold withReviewSpeech
          rw [hsr]
          simp
        have h1 := hs _ (by simpa only [obs_projection] using hin)
        have h2 := (Speech.top_ge (ctx g p r) (r.comments.getD [])).2 c hc
        omega
  simp only [spokeInReview, reviewsSpeak, hw', Bool.or_eq_false_iff] at hno
  obtain ⟨⟨hsum, hem⟩, hcs⟩ := hno
  have h3 := List.any_eq_false.1 hcs c hc
  simp only [Bool.and_eq_true, beq_iff_eq, not_and] at h3
  have h4 := h3 hsaid.symm
  refine ⟨c, hc, ho, hsl, hu, hf, hon, ⟨arg, e.mark.about, harg, hl, hres, hcar⟩,
    fun d hd ht => ?_, fun s hsm hsp => ?_, hsum, fun v hv => ?_⟩
  · obtain ⟨w, hwm, hwb, hwle⟩ :=
      Speech.typedCommentIsAWord (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
        (complete g p r) d hd ht
    have hle : w.said ≤ e.mark.said := by
      cases w with
      | ownerLand m' => exact hmax _ hwm rfl
      | ownerHold n => exact hmax _ hwm rfl
      | ownerSpoke s => exact hs s (mem_withReviewSpeech hwm)
      | agentLand t m' => cases hwb
    omega
  · have h4' : ∀ y ∈ reviewPosts r, speaks g y = true → y.lastSpoke < c.created := by
      simpa using h4
    exact h4' s hsm hsp
  · simpa using List.any_eq_false.1 hem v hv

theorem failedReadHolds : FailedReadHolds := by
  intro g p r x hc
  obtain ⟨n, hn⟩ := Speech.incompleteReadHolds (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
  have h : Land.newestOwner (obs g p r x).words = some (.ownerHold n) := by
    simp only [obs_projection, sourceObs, hc, newestOwner_withReviewSpeech]
    exact hn
  exact Land.holdWins _ n h

theorem enforcedNeedsProtection : EnforcedNeedsProtection := by
  intro g p r x h
  simp only [obs_projection, sourceObs, enforced] at h
  cases hp : g.protection with
  | none => rw [hp] at h; cases h
  | some pr =>
    rw [hp] at h
    simp only [Option.any_some, Bool.and_eq_true, List.contains_iff_mem] at h
    exact ⟨pr, rfl, h.1.1, h.1.2, h.2⟩

theorem updatableNeedsTheGuard : UpdatableNeedsTheGuard := by
  intro g p r x h
  simp only [obs_projection, sourceObs, updatable, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at h
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
  simp [obs_projection, sourceObs, Obs.kept, Obs.critical, h]

theorem onlyTheOwnerQueues : OnlyTheOwnerQueues := by
  intro g p r x e he
  cases hl : e.lander with
  | owner => rfl
  | agent t =>
    have := (Land.onlyMergersQueue _ e t he hl).2
    simp [obs_projection, sourceObs, Speech.delegates] at this

theorem pushesAreTheActivity : PushesAreTheActivity := by
  intro g p r x h
  simp only [obs_projection, sourceObs] at h ⊢
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

theorem verdictsFromTheSource : VerdictsFromTheSource := by
  intro g p r x v hv
  simp only [obs_projection, sourceObs] at hv
  cases hf : provenanceFact g p.number with
  | none => rw [hf] at hv; simp at hv
  | some f =>
    rw [hf] at hv
    simp only [Option.map_some, Option.getD_some, List.mem_map] at hv
    obtain ⟨e, he, hv⟩ := hv
    exact ⟨f, rfl, e, he, hv.symm⟩

theorem restNeedsSourceGuard : RestNeedsSourceGuard := by
  intro g p r x h
  simp only [obs_projection, sourceObs, Bool.and_eq_true, Option.any_eq_true] at h
  exact h.2

theorem restNeedsAnswersAndTheLabel : RestNeedsAnswersAndTheLabel := by
  intro g p r x h
  simp only [obs_projection, sourceObs, rest, Bool.and_eq_true, List.isEmpty_iff, Bool.or_eq_true, Bool.not_eq_true',
    List.contains_iff_mem] at h
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, _⟩ := h
  refine ⟨h1, h2, fun hs => ?_⟩
  rcases h3 with h3 | h3
  · rw [hs] at h3; cases h3
  · exact h3

end MitosGate.Snapshot
