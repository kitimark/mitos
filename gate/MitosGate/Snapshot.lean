import MitosGate.Snapshot.Obs

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

namespace Fixture

def hA : Sha := "5c258d6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
def hB : Sha := "85b0781bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
def hC : Sha := "5c258d6ccccccccccccccccccccccccccccccccc"
def known : List Sha := [hB, hA]

def v (s : String) : List (Nat × Sha × Teammate × String × Result) :=
  (verdictsOf known s.toList).map fun x => (x.said, x.head, x.judge, x.model, x.result)

theorem carriedPassOfOneJudge :
    v "PASS opus-xhigh carried from `5c258d6a`, author sonnet (round 2). Minors #241." =
      [(0, hA, ⟨"claude", "verifier-opus"⟩, "opus", .pass)] := by decide +kernel
theorem twoJudges :
    (v "PASS sonnet-xhigh + opus-xhigh at 85b0781").map (·.2.2.1.name) =
      ["verifier-sonnet", "verifier-opus"] := by decide +kernel
theorem failOfOneJudge :
    (v "**FAIL opus-xhigh at `85b0781`**: the line stalls").map (·.2.2.2.2) = [.fail] := by
  decide +kernel
theorem wordingOnlyIsTheRoots :
    v "wording-only at `85b0781`" = [(0, hB, root, "unknown", .wordingOnly)] := by decide +kernel
theorem noVerdictSaysNothing : v "No verdict. Opened by Grok Bot." = [] := by decide +kernel
theorem passThenFailSaysNothing :
    v "PASS opus-xhigh at `85b0781`. Then FAIL sonnet-xhigh at `85b0781`." = [] := by
  decide +kernel
theorem judgelessPassSaysNothing : v "PASS carried from `85b0781`" = [] := by decide +kernel
theorem judgesInAParenthesis :
    (v "PASS carried from `5c258d6a` (sonnet-xhigh + opus-xhigh, author opus), two rebases.").map
      (fun x => (x.2.1, x.2.2.1.name)) = [(hA, "verifier-sonnet"), (hA, "verifier-opus")] := by
  decide +kernel
theorem judgesInBothPlacesSayNothing : v "PASS opus-xhigh at `85b0781` (sonnet-xhigh)" = [] := by
  decide +kernel
theorem aParenthesisOfProseIsNoJudge : v "PASS carried from `85b0781` (carry exit 0)" = [] := by
  decide +kernel
theorem aParenthesisAfterAWordIsNoJudge :
    v "PASS carried from `85b0781`, then (opus-xhigh)" = [] := by decide +kernel
theorem unknownEffortSaysNothing : v "PASS opus-huge at `85b0781`" = [] := by decide +kernel
theorem judgedWordingOnlySaysNothing : v "wording-only opus-xhigh at `85b0781`" = [] := by
  decide +kernel
theorem ambiguousPrefixSaysNothing :
    (verdictsOf [hA, hC] "PASS opus-xhigh at `5c258d6`".toList).isEmpty = true := by
  decide +kernel
theorem unknownCommitSaysNothing : v "PASS opus-xhigh at `deadbee`" = [] := by decide +kernel
theorem shortShaSaysNothing : v "PASS opus-xhigh at `85b078`" = [] := by decide +kernel
theorem unclosedTickSaysNothing : v "PASS opus-xhigh at `85b0781" = [] := by decide +kernel
theorem upperCaseHexSaysNothing : v "PASS opus-xhigh at 85B0781" = [] := by decide +kernel
theorem lowerCasePassSaysNothing : v "pass opus-xhigh at 85b0781" = [] := by decide +kernel

def a (s : String) : Option (Teammate × String) :=
  (authorOf s.toList).map fun x => (x.who, x.model)

theorem authorNoteInAParenthesis :
    a "PASS carried from `5c258d6` (opus-xhigh, author sonnet, round 2), through the rebases." =
      some (⟨"claude", "author"⟩, "sonnet") := by decide +kernel
theorem authorNote :
    a "PASS opus-xhigh carried from `5c258d6`, author sonnet (round 2)." =
      some (⟨"claude", "author"⟩, "sonnet") := by decide +kernel
theorem mixedAuthorIsNone :
    a "PASS opus-xhigh at `5c258d6`, author sonnet, fixed by opus." = none := by decide +kernel
theorem twoAuthorNotesAreNone :
    a "PASS opus-xhigh at `5c258d6`, author sonnet. Earlier author opus." = none := by
  decide +kernel
theorem noAuthorNoteIsNone : a "PASS opus-xhigh at `5c258d6`." = none := by decide +kernel
theorem coauthorIsNoNote : a "PASS opus-xhigh at `5c258d6`, coauthor sonnet." = none := by
  decide +kernel
theorem unknownModelIsNone : a "PASS opus-xhigh at `5c258d6`, author gpt." = none := by
  decide +kernel

def dash (rows : String) : String :=
  "Intro.\n\n## Needs you\n\n- | #1 | not | a | row |\n\n## In flight\n\n" ++
    "| PR | Head | `gate` | Verdict |\n|---|---|---|---|\n" ++ rows ++
    "\nMerged in the last 24 hours:\n- #9 merged\n\n## Next up\n\n| #5 | x | y | z |\n"

theorem inFlightRows :
    rows (dash "| #7 a PR | `85b0781` | green | PASS opus-xhigh at `85b0781` |\n| #8 b | `x` | running | No verdict |") =
      some [(7, "PASS opus-xhigh at `85b0781`".toList), (8, "No verdict".toList)] := by
  decide +kernel
theorem twoRowsForOnePrSpoilTheDashboard :
    rows (dash "| #7 a | `x` | green | PASS opus-xhigh at `85b0781` |\n| #7 b | `x` | red | No verdict |") =
      none := by decide +kernel
theorem aFifthColumnSpoilsTheDashboard :
    rows (dash "| #7 a | `x` | green | PASS opus-xhigh at `85b0781` | extra |") = none := by
  decide +kernel
theorem aRowWithoutANumberSpoilsTheDashboard :
    rows (dash "| 7 a | `x` | green | PASS opus-xhigh at `85b0781` |") = none := by decide +kernel
theorem aPipeInACellSpoilsTheDashboard :
    rows (dash "| #7 a | `x` | green | PASS opus-xhigh at `85b0781` `a|b` |") = none := by
  decide +kernel
theorem noInFlightSectionIsUnread : rows "## Needs you\n\n| #7 | x | y | z |\n" = none := by
  decide +kernel
theorem twoInFlightSectionsAreUnread :
    rows "## In flight\n\n| #7 | x | y | z |\n## In flight\n" = none := by decide +kernel
theorem crlfDashboard :
    rows "## In flight\r\n\r\n| #7 a | x | y | PASS opus-xhigh at 85b0781 |\r\n" =
      some [(7, "PASS opus-xhigh at 85b0781".toList)] := by decide +kernel

def owner : String := "owner"
def repo : String := "owner/mitos"
def protection : Protection := ⟨true, true, ["gate"]⟩
def row (verdict : String) : Option (List (Nat × List Char)) := some [(7, verdict.toList)]
def g : Global :=
  { repo, owner, protection := some protection, stacked := some [],
    rows := row "PASS opus-xhigh at `85b0781`, author sonnet" }
def withRow (verdict : String) : Global := { g with rows := row verdict }
def footer : String := "\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_"
def pull : Pull :=
  { number := 7, state := "open", draft := false, head := hB, headRepo := some repo,
    baseRef := "main", baseRepo := repo, labels := [], body := "Why." ++ footer }
def pushes : List Carry.Push :=
  [⟨"2026-11-14T07:00:36Z", "force_push", Carry.updater, hA, hB⟩,
   ⟨"2026-11-13T19:51:49Z", "branch_creation", owner, "0000000000000000000000000000000000000000",
    hA⟩]
def gateRun : Check := ⟨10, "gate", "github-actions", hB, "completed", "success"⟩
def rabbit : Review := ⟨3, "coderabbitai[bot]", "COMMENTED", hB, 20261114070100, "Review."⟩
def land : Comment := ⟨900, owner, none, 20261114080000, 20261114080000, "/land"⟩
def question : Comment := ⟨800, owner, none, 20261114075900, 20261114075900, "why this?"⟩
def answer (t : Stamp) : Comment := ⟨850, owner, some "claude", t, t, "Because." ++ footer⟩
def reads : Reads :=
  { comments := some [land], reviewComments := some [], reviews := some [rabbit],
    activity := some pushes, files := some ["gate/Main.lean"], checks := some [gateRun] }
def withComments (cs : List Comment) : Reads := { reads with comments := some cs }
def withReviewComments (ps : List Post) : Reads := { reads with reviewComments := some ps }
def withActivity (ps : List Carry.Push) : Reads := { reads with activity := some ps }
def withChecks (cs : List Check) : Reads := { reads with reviews := some [], checks := some cs }
def git : Git := ⟨[(hB, "id-1"), (hA, "id-1")], .current⟩
def o (g : Global := g) (p : Pull := pull) (r : Reads := reads) (x : Git := git) : Obs :=
  obs g p r x
def o0 : Obs := o
def stepOf (g : Global := g) (p : Pull := pull) (r : Reads := reads) (x : Git := git) :
    Land.Step :=
  let ob := o g p r x
  Land.step Land.Fixture.orchestrator (Land.queueOf [ob]) ob
def step0 : Land.Step := stepOf
def carried : String := "PASS opus-xhigh carried from `5c258d6`, author sonnet"

theorem allReadAndCoveredIsPresented : step0 = .present hB := by decide +kernel
theorem theOwnersLandIsTheEntry : o0.words = [.ownerLand ⟨1800, hB⟩] := by decide +kernel
theorem unreadCommentsHold : stepOf (r := { reads with comments := none }) = .stop .held := by
  decide +kernel
theorem unreadReviewCommentsHold :
    stepOf (r := { reads with reviewComments := none }) = .stop .held := by decide +kernel
theorem unreadReviewsHold : stepOf (r := { reads with reviews := none }) = .stop .held := by
  decide +kernel
theorem unreadActivityHolds : stepOf (r := { reads with activity := none }) = .stop .held := by
  decide +kernel
theorem unreadFilesHold : stepOf (r := { reads with files := none }) = .stop .held := by
  decide +kernel
theorem unreadChecksHold : stepOf (r := { reads with checks := none }) = .stop .held := by
  decide +kernel
theorem unreadProtectionHolds : stepOf (g := { g with protection := none }) = .stop .held := by
  decide +kernel
theorem unreadStacksHold : stepOf (g := { g with stacked := none }) = .stop .held := by
  decide +kernel
theorem unreadDashboardHolds : stepOf (g := { g with rows := none }) = .stop .held := by
  decide +kernel
theorem activityAtAnotherHeadHolds :
    stepOf (p := { pull with head := hC }) = .stop .held := by decide +kernel
theorem activityOutOfOrderHolds :
    stepOf (r := withActivity (pushes ++ [⟨"2026-11-13T20:00:00Z", "push", owner, hC, hA⟩])) =
      .stop .held := by decide +kernel
theorem activityListedOldestFirstHolds :
    stepOf (r := { reads with activity := some pushes.reverse }) = .stop .held := by decide +kernel
theorem activityWithANonShaHolds :
    stepOf (r := withActivity (pushes ++ [⟨"2026-11-13T19:00:00Z", "push", owner, "HEAD", hA⟩])) =
      .stop .held := by decide +kernel
theorem protectionWithoutAdminsIsUnenforced :
    stepOf (g := { g with protection := some { protection with admins := false } }) =
      .stop .unenforced := by decide +kernel
theorem protectionWithoutGateIsUnenforced :
    stepOf (g := { g with protection := some { protection with checks := ["ci"] } }) =
      .stop .unenforced := by decide +kernel
theorem aStackedPullRequestIsNotEligible :
    stepOf (g := { g with stacked := some [7] }) = .stop .notEligible := by decide +kernel
theorem aDraftIsNotEligible : stepOf (p := { pull with draft := true }) = .stop .notEligible := by
  decide +kernel
theorem aForkIsNotEligible :
    stepOf (p := { pull with headRepo := some "other/mitos" }) = .stop .notEligible := by
  decide +kernel
theorem anotherBaseIsNotEligible :
    stepOf (p := { pull with baseRef := "dev" }) = .stop .notEligible := by decide +kernel
theorem noRowIsNotEligible :
    stepOf (g := { g with rows := some [] }) = .stop .notEligible := by decide +kernel
theorem anOpusPassOnATrustPathCoversASonnetAuthor : o0.covered = true := by decide +kernel
theorem anOpusAuthorIsNotCoveredByItsOwnModel :
    stepOf (g := withRow "PASS opus-xhigh at `85b0781`, author opus") = .stop .notEligible := by
  decide +kernel
theorem noAuthorNoteIsNotEligible :
    stepOf (g := withRow "PASS opus-xhigh at `85b0781`") = .stop .notEligible := by decide +kernel
theorem aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush :
    stepOf (g := withRow carried) = .present hB := by decide +kernel
theorem aVerdictOnOtherContentDoesNotCarry :
    stepOf (g := withRow carried) (x := ⟨[(hB, "id-1"), (hA, "id-2")], .current⟩) =
      .stop .notEligible := by decide +kernel
theorem anOwnerQuestionWithoutAnswerIsNotEligible :
    stepOf (r := withComments [question, land]) = .stop .notEligible := by decide +kernel
theorem anAnsweredOwnerQuestionIsEligible :
    stepOf (r := withComments [question, answer 20261114075930, land]) = .present hB := by
  decide +kernel
theorem anAnswerInTheSameSecondIsNoAnswer :
    stepOf (r := withComments [question, answer 20261114075900, land]) = .stop .notEligible := by
  decide +kernel
theorem anUnansweredReviewCommentIsNotEligible :
    stepOf (r := withReviewComments [⟨owner, none, 20261114075900, 20261114075900, "rename"⟩]) =
      .stop .notEligible := by decide +kernel
theorem aLandAfterAByteOrderMarkNeedsNoAnswer :
    stepOf (r := withComments [{ land with body := "﻿/land" }]) = .present hB := by
  decide +kernel
theorem anOtherLoginsCommentNeedsNoAnswer :
    stepOf (r := withReviewComments [⟨"someone", none, 20261114075900, 20261114075900, "rename"⟩]) =
      .present hB := by decide +kernel
theorem aBodyWithoutTheFooterIsNotEligible :
    stepOf (p := { pull with body := "Why." }) = .stop .notEligible := by decide +kernel
theorem aBodyWithTwoFootersIsNotEligible :
    stepOf (p := { pull with body := "Why." ++ footer ++ footer }) = .stop .notEligible := by
  decide +kernel
theorem aSummaryBelowTheFooterIsPresented :
    stepOf (p := { pull with body := "Why." ++ footer ++ "\n\n## Summary by CodeRabbit\n" }) =
      .present hB := by decide +kernel
theorem aSessionLinkIsNotEligible :
    stepOf (p := { pull with body := "Why. " ++ String.ofList sessionLink ++ "x" ++ footer }) =
      .stop .notEligible := by decide +kernel
theorem aSpecPathWithoutTheLabelIsNotEligible :
    stepOf (r := { reads with files := some ["core/Mitos/Core/Graph.lean"] }) =
      .stop .notEligible := by decide +kernel
theorem aSpecPathWithTheLabelIsPresented :
    stepOf (p := { pull with labels := ["spec-approved"] })
      (r := { reads with files := some ["examples/acme/models.lock"] }) = .present hB := by
  decide +kernel
theorem noBotReviewIsNotEligible :
    stepOf (r := { reads with reviews := some [] }) = .stop .notEligible := by decide +kernel
theorem aReviewByAnotherLoginIsNoBotReview :
    stepOf (r := { reads with reviews := some [{ rabbit with login := "someone" }] }) =
      .stop .notEligible := by decide +kernel
theorem aPassedRabbitCheckAtTheHeadIsAReview :
    stepOf (r := withChecks [gateRun, ⟨11, "CodeRabbit", "coderabbitai", hB, "completed", "success"⟩]) =
      .present hB := by decide +kernel
theorem aRabbitCheckFromAnotherAppIsNoReview :
    botAt hB [⟨13, "CodeRabbit", "other-app", hB, "completed", "success"⟩] [] = none := by
  decide +kernel
theorem aRabbitCheckFromAnotherAppDoesNotMakeItEligible :
    stepOf (r := withChecks [gateRun, ⟨11, "CodeRabbit", "other-app", hB, "completed", "success"⟩]) =
      .stop .notEligible := by decide +kernel
theorem aRabbitCheckAtAnotherHeadIsNoReview :
    botAt hB [⟨13, "CodeRabbit", "coderabbitai", hA, "completed", "success"⟩] [] = none := by
  decide +kernel
theorem aGateRunFromAnotherAppIsNoGate :
    gateOf hB [⟨12, "gate", "other-app", hB, "completed", "success"⟩] = .missing := by decide +kernel
theorem theNewestGateRunCounts :
    gateOf hB [gateRun, ⟨12, "gate", "github-actions", hB, "completed", "cancelled"⟩] =
      .cancelled := by decide +kernel
theorem aGateRunAtAnotherHeadIsNoGate :
    gateOf hB [⟨12, "gate", "github-actions", hA, "completed", "success"⟩] = .missing := by
  decide +kernel
theorem aRunningGateIsPending :
    gateOf hB [⟨12, "gate", "github-actions", hB, "in_progress", ""⟩] = .pending := by decide +kernel
theorem aTimedOutGateIsRed :
    gateOf hB [⟨12, "gate", "github-actions", hB, "completed", "timed_out"⟩] = .failure := by
  decide +kernel
theorem theContentIdsAsked : wanted (o (g := withRow carried)) = [hB, hA] := by decide +kernel
theorem eachFailedReadIsIncomplete :
    [complete { g with protection := none } pull reads, complete { g with stacked := none } pull reads,
     complete { g with rows := none } pull reads, complete g pull { reads with comments := none },
     complete g pull { reads with reviewComments := none },
     complete g pull { reads with reviews := none }, complete g pull { reads with activity := none },
     complete g pull { reads with files := none }, complete g pull { reads with checks := none },
     complete g pull reads] =
      [false, false, false, false, false, false, false, false, false, true] := by decide +kernel

end Fixture

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.map₂.foldl (fun acc n c =>
    if (`MitosGate.Snapshot.Fixture).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``failedReadHolds, ``enforcedNeedsProtection, ``updatableNeedsTheGuard,
      ``unreadFilesAreKept, ``onlyTheOwnerQueues, ``greenIsTheNewestGateRun,
      ``pushesAreTheActivity, ``verdictsFromTheCell, ``passNamesNoFail,
      ``restNeedsAnswersAndTheLabel] ++ fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Snapshot
