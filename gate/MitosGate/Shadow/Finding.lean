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

namespace Fixture

open Land.Fixture

theorem theReplayThatMergedAgrees :
    finding (seat merged [rec 1 90 (some "m1") [unsaid]]) = .agrees := by decide +kernel
theorem anotherTreeIsNotAgreement :
    finding (seat { merged with tree := some "tx" } [rec 1 90 (some "m1") [unsaid]]) =
      .otherTree := by decide +kernel
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

end Fixture

end MitosGate.Shadow
