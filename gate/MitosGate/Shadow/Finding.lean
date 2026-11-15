import MitosGate.Shadow.Seat

namespace MitosGate.Shadow

open Land

inductive Finding
  | agrees
  | waits
  | disagrees (why : Stop)
  | otherTree
  | blind
  deriving DecidableEq

def finding : Seat → Finding
  | .unseen | .unlisted _ => .blind
  | .sat s =>
    match s.head, s.reading.step with
    | .other, _ => .blind
    | .replayedOtherwise, _ => .otherTree
    | _, .stop why => .disagrees why
    | .same, .present _ => .agrees
    | .replayedAsPlanned, .awaitPush _ => .agrees
    | _, _ => .waits

def AgreesMeansTheMergedContent : Prop :=
  ∀ s : Sat, finding (.sat s) = .agrees →
    (s.head = .same ∧ ∃ h, s.reading.step = .present h) ∨
      (s.head = .replayedAsPlanned ∧ ∃ h, s.reading.step = .awaitPush h)

theorem agreesMeansTheMergedContent : AgreesMeansTheMergedContent := by
  intro s h
  simp only [finding] at h
  split at h
  · cases h
  · cases h
  · cases h
  · rename_i h1 h2; exact .inl ⟨h1, _, h2⟩
  · rename_i h1 h2; exact .inr ⟨h1, _, h2⟩
  · cases h

def ASummaryOnlyTakesAgreementAway : Prop :=
  ∀ (m : Merge) (rs : List Record), finding (seat { m with summary := .spoke } rs) = .agrees →
    finding (seat { m with summary := .silent } rs) = .agrees

theorem last_congr {m m' : Merge} (hb : m.before = m'.before) (ht : m.time = m'.time) :
    ∀ rs : List Record, last m rs = last m' rs
  | [] => rfl
  | r :: rs => by
    have hp : precedes m r = precedes m' r := by simp [precedes, hb, ht]
    simp only [last, last_congr hb ht rs, hp]

theorem reading_spoke (os : List Obs) (o : Obs) :
    reading .spoke os o = .asRead (.stop .noEntry) ∨ reading .spoke os o = reading .silent os o := by
  unfold reading
  split
  · exact .inl rfl
  · exact .inr rfl

theorem aSummaryOnlyTakesAgreementAway : ASummaryOnlyTakesAgreementAway := by
  intro m rs h
  have hl : last { m with summary := .spoke } rs = last { m with summary := .silent } rs :=
    last_congr (m := { m with summary := .spoke }) (m' := { m with summary := .silent }) rfl rfl rs
  unfold seat at h ⊢
  rw [hl] at h
  cases hr : last { m with summary := .silent } rs with
  | none => simp [hr, finding] at h
  | some r =>
    simp only [hr] at h ⊢
    cases ho : r.prs.find? (·.pr == m.pr) with
    | none => simp [ho, finding] at h
    | some o =>
      simp only [ho] at h ⊢
      rcases reading_spoke r.prs o with he | he
      · simp only [he, finding, Reading.step] at h
        split at h <;> simp_all
      · simp only [he] at h
        exact h
namespace Fixture

open Land.Fixture

theorem theReplayThatMergedAgrees :
    finding (seat merged [rec 1 90 (some "m1") [unsaid]]) = .agrees := by decide +kernel
theorem anotherTreeIsNotAgreement :
    finding (seat { merged with tree := some "tx" } [rec 1 90 (some "m1") [unsaid]]) =
      .otherTree := by decide +kernel
theorem aReplayWhoseTreeWasNotReadIsBlind :
    finding (seat merged [{ rec 1 90 (some "m1") [unsaid] with trees := [] }]) = .blind := by
  decide +kernel
theorem aTreeOfAnotherCommitIsNotTheReplays :
    finding (seat merged [{ rec 1 90 (some "m1") [unsaid] with trees := [⟨"bx", "tb"⟩] }]) =
      .blind := by decide +kernel
theorem aMergeWhoseTreeWasNotReadIsBlind :
    finding (seat { merged with tree := none } [rec 1 90 (some "m1") [unsaid]]) = .blind := by
  decide +kernel
theorem aRecordOfAnotherMainIsUnseen :
    finding (seat merged [rec 1 90 (some "m0") [unsaid]]) = .blind := by decide +kernel
theorem aRecordAfterTheMergeIsUnseen :
    finding (seat merged [rec 1 101 (some "m1") [unsaid]]) = .blind := by decide +kernel
theorem aRecordInTheMergesSecondIsUnseen :
    finding (seat merged [rec 1 100 (some "m1") [unsaid]]) = .blind := by decide +kernel
theorem aRecordThatSawMainMoveIsUnseen :
    finding (seat { merged with before := none } [rec 1 90 none [unsaid]]) = .blind := by
  decide +kernel
theorem aHeldMergeDisagrees :
    finding
        (seat { merged with pr := 153, head := "aaa" } [rec 1 90 (some "m1") [ownerKeptHeld]]) =
      .disagrees .held := by decide +kernel

theorem anOwnerSummaryTakesTheAssumedWordAway :
    finding (seat { merged with summary := .spoke } [rec 1 90 (some "m1") [unsaid]]) =
      .disagrees .noEntry := by decide +kernel

end Fixture

end MitosGate.Shadow
