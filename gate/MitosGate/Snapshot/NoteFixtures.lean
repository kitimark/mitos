import MitosGate.Snapshot.Fixtures
import MitosGate.Snapshot.Note

namespace MitosGate.Snapshot

namespace Fixture

def noteOf (g : Global := g) (p : Pull := pull) (r : Reads := reads) : Note := note g p r git

theorem aCompleteAdmittedReadNotesNothing : noteOf = ⟨[], [], true⟩ := by decide +kernel
theorem eachFailedReadIsNoted :
    [(noteOf (g := { g with protection := none })).unread,
     (noteOf (g := { g with stacked := none })).unread,
     (noteOf (g := { g with verdictCells := none })).unread,
     (noteOf (r := { reads with comments := none })).unread,
     (noteOf (r := { reads with reviewComments := none })).unread,
     (noteOf (r := { reads with reviews := none })).unread,
     (noteOf (r := { reads with activity := none })).unread,
     (noteOf (r := { reads with files := none })).unread,
     (noteOf (r := { reads with checks := none })).unread] =
      [[.protection], [.stacks], [.dashboard], [.comments], [.reviewComments], [.reviews],
       [.activity], [.files], [.checks]] := by decide +kernel
theorem aLinkToAnotherNumberIsAnUnreadDashboard :
    (noteOf (g := { g with verdictCells := rows (dash linked7To8) })).unread =
      [.dashboard] ∧
    (noteOf (g := { g with verdictCells := rows (dash linked7) })).unread = [] := by
  decide +kernel
theorem unreadProvenanceIsNoted :
    (noteOf (g := { g with provenance := none })).unmet = [.provenance] := by decide +kernel
theorem aMissingEntryIsNoted :
    (noteOf (g := { g with provenance := some [] })).unmet = [.entry] := by decide +kernel
theorem anAuthorWithoutAModelIsNoted :
    (noteOf (g := withSource (source none))).unmet = [.author] := by decide +kernel
theorem anAuthorAtOtherContentIsNoted :
    (note (withSource (source (head := hA))) pull reads
      ⟨[(hB, "id-1"), (hA, "id-2")], .current⟩).unmet = [.author] := by decide +kernel
theorem aVerdictByTheAuthorsModelIsNoted :
    (noteOf (g := withSource (source (some "claude-opus-4-6")))).unmet = [.verdict] := by
  decide +kernel
theorem anUnansweredQuestionIsNoted :
    (noteOf (r := withComments [question, land])).unmet = [.unanswered] := by decide +kernel
theorem aBodyWithoutTheFooterIsNoted :
    (noteOf (p := { pull with body := "Why." })).unmet = [.footer] := by decide +kernel
theorem aSpecPathWithoutTheLabelIsNoted :
    (noteOf (r := { reads with files := some ["core/Mitos/Core/Graph.lean"] })).unmet =
      [.label] := by decide +kernel
theorem unreadFilesAreNotedAsASpecPath :
    (noteOf (r := { reads with files := none })).unmet = [.label] := by decide +kernel
theorem theOwnerDecidesByALandOrAHold :
    [(noteOf).owner, (noteOf (r := withComments [])).owner,
     (noteOf (r := withComments [question])).owner,
     (noteOf (r := withComments [{ land with body := "/hold" }])).owner,
     (noteOf (r := { reads with comments := none })).owner] =
      [true, false, false, true, true] := by decide +kernel

end Fixture

end MitosGate.Snapshot
