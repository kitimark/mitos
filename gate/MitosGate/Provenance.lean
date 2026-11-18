import MitosGate.Land

namespace MitosGate.Provenance

open Land (Sha Pr Teammate Author Verdict Result Obs)

inductive Effort
  | low | medium | high | xhigh | max
  deriving DecidableEq, Repr

structure Identity where
  provider : String
  actor : String
  actualModel : Option String
  requestedModel : Option String

def Identity.who (i : Identity) : Teammate := ⟨i.provider, i.actor⟩

structure AuthorFact where
  head : Sha
  identity : Identity

structure VerdictFact where
  head : Sha
  identity : Identity
  effort : Option Effort
  result : Result
  order : Nat
  evidence : String

structure PullFact where
  number : Pr
  author : AuthorFact
  verdicts : List VerdictFact

def VerdictFact.toLand (v : VerdictFact) : Verdict :=
  ⟨v.order, v.head, v.identity.who, v.identity.actualModel.getD "unknown", v.result⟩

def authorOf (o : Obs) (p : PullFact) : Option Author := do
  unless o.carries p.author.head do none
  match p.author.identity.actualModel with
  | some actual =>
    unless (ModelIdentity.key p.author.identity.provider actual).isSome do none
    return ⟨p.author.identity.who, .reported actual⟩
  | none =>
    unless ModelIdentity.canonicalOutside p.author.identity.provider do none
    return ⟨p.author.identity.who, .absent⟩

def withFacts (o : Obs) (p : PullFact) : Obs :=
  { o with author := authorOf o p, verdicts := p.verdicts.map VerdictFact.toLand }

def highEnough : Option Effort → Bool
  | some .xhigh | some .max => true
  | _ => false

def requiresOpus (paths : Option (List String)) (labels : List String) : Bool :=
  (paths.map (·.any Land.criticalPath)).getD true || labels.contains "spec-approved"

def opusPass (x : Obs) (p : PullFact) : Bool :=
  p.verdicts.any fun v => decide (x.stands v.toLand) && v.result == .pass &&
    highEnough v.effort && ModelIdentity.opus v.identity.provider
      (v.identity.actualModel.getD "unknown") &&
    x.author.any (fun a => v.identity.who != a.who)

def sourceGuard (o : Obs) (p : PullFact) (labels : List String := []) : Bool :=
  let x := withFacts o p
  let required := !requiresOpus x.paths labels || opusPass x p
  (p.verdicts.any fun v => decide (x.stands v.toLand) && v.result == .wordingOnly &&
    v.identity.provider == "claude" && v.identity.actor == "root" &&
    x.author.any (fun a => a.model != .absent && v.identity.who != a.who)) ||
  ((p.verdicts.any fun v => decide (x.stands v.toLand) && v.result == .pass &&
    ModelIdentity.acceptedClaude v.identity.provider (v.identity.actualModel.getD "unknown") &&
    x.author.any (fun a => v.identity.who != a.who &&
      ModelIdentity.different a.who.provider a.model v.identity.provider
        (v.identity.actualModel.getD "unknown"))) && required)

def admitted (o : Obs) (p : PullFact) (labels : List String := []) : Bool :=
  (withFacts o p).covered && sourceGuard o p labels

def project (o : Obs) (p : PullFact) (labels : List String := []) : Obs :=
  { withFacts o p with rest := o.rest && sourceGuard o p labels }

theorem projectionPreservesEvents (o : Obs) (p : PullFact) :
    (project o p).verdicts = p.verdicts.map VerdictFact.toLand := rfl

theorem eligibleNeedsAdmission {o : Obs} {p : PullFact} {labels : List String}
    (h : (project o p labels).eligibleBeforeRebase = true) : admitted o p labels = true := by
  simp only [Land.Obs.eligibleBeforeRebase, Bool.and_eq_true] at h
  have hc : (withFacts o p).covered = true := h.1.1.2
  have hr : o.rest && sourceGuard o p labels = true := h.2
  exact Bool.and_eq_true_iff.mpr ⟨hc, (Bool.and_eq_true_iff.mp hr).2⟩

theorem projectionEligibility (o : Obs) (p : PullFact) (labels : List String) :
    (project o p labels).eligibleBeforeRebase =
      ((withFacts o p).eligibleBeforeRebase && sourceGuard o p labels) := by
  simp only [Land.Obs.eligibleBeforeRebase, project, withFacts, Bool.and_assoc]
  rfl

theorem admittedRequiredHasEffort {o : Obs} {p : PullFact} {labels : List String}
    (h : admitted o p labels = true) (hc : requiresOpus (withFacts o p).paths labels = true)
    (hw : ∀ v ∈ p.verdicts, v.result ≠ .wordingOnly) :
    ∃ v ∈ p.verdicts, (withFacts o p).stands v.toLand ∧ v.result = .pass ∧
      highEnough v.effort = true ∧ ModelIdentity.opus v.identity.provider
        (v.identity.actualModel.getD "unknown") = true ∧
      (withFacts o p).author.any (fun a => v.identity.who != a.who) = true := by
  have hh := (Bool.and_eq_true_iff.mp h).2
  have hopus : opusPass (withFacts o p) p = true := by
    simp only [sourceGuard] at hh
    rcases Bool.or_eq_true_iff.mp hh with hword | hpass
    · obtain ⟨v, hv, hvok⟩ := List.any_eq_true.mp hword
      simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hvok
      exact False.elim (hw v hv hvok.1.1.1.2)
    · simpa [hc] using (Bool.and_eq_true_iff.mp hpass).2
  obtain ⟨v, hv, hvok⟩ := List.any_eq_true.mp hopus
  simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hvok
  exact ⟨v, hv, hvok.1.1.1.1, hvok.1.1.1.2, hvok.1.1.2, hvok.1.2, hvok.2⟩

theorem absentAuthorOf {o : Obs} {p : PullFact} (hm : p.author.identity.actualModel = none) :
    authorOf o p =
      if o.carries p.author.head && ModelIdentity.canonicalOutside p.author.identity.provider then
        some ⟨p.author.identity.who, .absent⟩ else none := by
  cases hc : o.carries p.author.head <;>
    cases hp : ModelIdentity.canonicalOutside p.author.identity.provider <;>
    simp [authorOf, hm, hc, hp]

theorem unknownAdmitted {o : Obs} {p : PullFact} {labels : List String}
    (h : admitted o p labels = true) (hm : p.author.identity.actualModel = none) :
    o.carries p.author.head = true ∧ ModelIdentity.canonicalOutside p.author.identity.provider = true ∧
    (withFacts o p).author = some ⟨p.author.identity.who, .absent⟩ ∧
    ∃ v ∈ p.verdicts, (withFacts o p).stands v.toLand ∧ v.result = .pass ∧
      v.identity.who ≠ p.author.identity.who ∧ v.identity.provider ≠ p.author.identity.provider ∧
      ∃ actual, v.identity.actualModel = some actual ∧
        ModelIdentity.acceptedClaude v.identity.provider actual = true := by
  have hc : (withFacts o p).Covered := of_decide_eq_true (Bool.and_eq_true_iff.mp h).1
  obtain ⟨a, ha, _⟩ := Land.coverIsAnotherJudgesWord _ hc
  have ha' : authorOf o p = some a := ha
  rw [absentAuthorOf hm] at ha'
  split at ha'
  · rename_i hok
    have hp := Bool.and_eq_true_iff.mp hok
    cases ha'
    have retained : (withFacts o p).author = some ⟨p.author.identity.who, .absent⟩ := ha
    refine ⟨hp.1, hp.2, retained, ?_⟩
    unfold Land.Obs.Covered at hc
    rw [retained] at hc
    rcases hc.2.2 with hw | ⟨⟨v, hv, hs, hr, hj, hac, hd⟩, _⟩
    · exact False.elim (hw.1 rfl)
    · obtain ⟨event, he, hv⟩ := List.mem_map.mp hv
      subst v
      have actual : ∃ m, event.identity.actualModel = some m := by
        cases hemodel : event.identity.actualModel with
        | none => simp [VerdictFact.toLand, hemodel, ModelIdentity.acceptedClaude,
            ModelIdentity.unknownClaudeKey, Identity.who] at hac
        | some m => exact ⟨m, rfl⟩
      obtain ⟨m, hem⟩ := actual
      have had : ModelIdentity.acceptedClaude event.identity.provider m = true := by
        simpa [VerdictFact.toLand, hem, Identity.who] using hac
      have diff := ModelIdentity.absentDifferentNeedsKnown hd
      exact ⟨event, he, hs, hr, hj, Ne.symm diff.2.1, m, hem, had⟩
  · cases ha'

theorem unknownRequiredHasEffort {o : Obs} {p : PullFact} {labels : List String}
    (h : admitted o p labels = true) (hm : p.author.identity.actualModel = none)
    (hc : requiresOpus (withFacts o p).paths labels = true) :
    ∃ v ∈ p.verdicts, (withFacts o p).stands v.toLand ∧ v.result = .pass ∧
      v.identity.who ≠ p.author.identity.who ∧ v.identity.provider ≠ p.author.identity.provider ∧
      highEnough v.effort = true ∧ ∃ actual, v.identity.actualModel = some actual ∧
        ModelIdentity.opus v.identity.provider actual = true := by
  have retained := (unknownAdmitted h hm).2.2.1
  have hp := (unknownAdmitted h hm).2.1
  have hs : opusPass (withFacts o p) p = true := by
    have hg := (Bool.and_eq_true_iff.mp h).2
    simp only [sourceGuard] at hg
    rcases Bool.or_eq_true_iff.mp hg with hw | hpass
    · obtain ⟨v, _, hv⟩ := List.any_eq_true.mp hw
      simp [retained] at hv
    · simpa [hc] using (Bool.and_eq_true_iff.mp hpass).2
  obtain ⟨v, hv, hs⟩ := List.any_eq_true.mp hs
  simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hs
  have hj : v.identity.who ≠ p.author.identity.who := by
    simpa [retained] using hs.2
  obtain ⟨actual, ha⟩ : ∃ actual, v.identity.actualModel = some actual := by
    cases ha : v.identity.actualModel with
    | none => simp [ha, ModelIdentity.unknownOpus] at hs
    | some actual => exact ⟨actual, rfl⟩
  have ho : ModelIdentity.opus v.identity.provider actual = true := by simpa [ha] using hs.1.2
  have provider : v.identity.provider = "claude" := by
    exact beq_iff_eq.mp (Bool.and_eq_true_iff.mp ho).1
  exact ⟨v, hv, hs.1.1.1.1, hs.1.1.1.2, hj, by
    rw [provider]; exact Ne.symm (ModelIdentity.canonicalOutsideNotClaude hp), hs.1.1.2,
    actual, ha, ho⟩

end MitosGate.Provenance
