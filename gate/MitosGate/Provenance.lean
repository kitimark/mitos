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
  let model ← p.author.identity.actualModel
  unless (ModelIdentity.key p.author.identity.provider model).isSome do none
  return ⟨p.author.identity.who, model⟩

def withFacts (o : Obs) (p : PullFact) : Obs :=
  { o with author := authorOf o p, verdicts := p.verdicts.map VerdictFact.toLand }

def highEnough : Option Effort → Bool
  | some .xhigh | some .max => true
  | _ => false

def requiresOpus (paths : Option (List String)) (labels : List String) : Bool :=
  (paths.map (·.any Land.criticalPath)).getD true || labels.contains "spec-approved"

def sourceGuard (o : Obs) (p : PullFact) (labels : List String := []) : Bool :=
  let x := withFacts o p
  ((p.verdicts.any fun v => decide (x.stands v.toLand) && v.result == .wordingOnly &&
      v.identity.provider == "claude" && v.identity.actor == "root" &&
      x.author.any (fun a => v.identity.who != a.who)) ||
    ((p.verdicts.any fun v => decide (x.stands v.toLand) && v.result == .pass &&
      ModelIdentity.acceptedClaude v.identity.provider (v.identity.actualModel.getD "unknown") &&
      x.author.any (fun a => v.identity.who != a.who &&
        ModelIdentity.different a.who.provider a.model v.identity.provider
          (v.identity.actualModel.getD "unknown"))) &&
    (!requiresOpus x.paths labels || p.verdicts.any fun v => decide (x.stands v.toLand) && v.result == .pass &&
      highEnough v.effort && ModelIdentity.opus v.identity.provider
        (v.identity.actualModel.getD "unknown") &&
      x.author.any (fun a => v.identity.who != a.who))))

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
  unfold sourceGuard at hh
  rcases Bool.or_eq_true_iff.mp hh with hword | hpass
  · obtain ⟨v, hv, hvok⟩ := List.any_eq_true.mp hword
    simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hvok
    exact False.elim (hw v hv hvok.1.1.1.2)
  · have hopus := (Bool.and_eq_true_iff.mp hpass).2
    simp only [hc, Bool.not_true, Bool.false_or] at hopus
    obtain ⟨v, hv, hvok⟩ := List.any_eq_true.mp hopus
    simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hvok
    exact ⟨v, hv, hvok.1.1.1.1, hvok.1.1.1.2, hvok.1.1.2, hvok.1.2, hvok.2⟩

end MitosGate.Provenance
