import MitosGate.Land
import MitosGate.Shadow.Lacks
import MitosGate.Shadow.Reading
import MitosGate.Snapshot.Fields

/-!
# What the land workflow answers to an owner word

`land.yml`'s `report` job posts one comment per change of answer (amendment #178, section 4).
Every answer known before `apply` runs is decided and rendered here, from the queue `plan` reads,
as the workflow sees it: a teammate that is no delegate (`Shadow.outsider`). The pull request the
plan merges is `apply`'s to answer, from the merge call's result.
-/

namespace MitosGate.LandAnswer

open Land
open Shadow (Clause lacks outsider)

inductive Waiting
  | behind (pr : Pr)
  | replay
  | gate
  deriving DecidableEq

inductive Answer
  | unnamed (head : Sha)
  | queued (head : Sha) (why : Waiting)
  | held (head : Sha)
  | spoke (head : Sha)
  | stale (head about : Sha)
  | notEligible (lacks : List Clause)
  | stuck (why : Stuck)
  deriving DecidableEq

inductive Reply
  | answer (a : Answer)
  /-- The plan merges this pull request at `head`: `apply` makes the call, and `report` answers
  from its result. -/
  | landing (head : Sha)
  deriving DecidableEq

def aboutOf (o : Obs) : Sha :=
  match newestOwner o.words with
  | some (.ownerLand m) => m.about
  | _ => o.head

def reply (q : Queue) (o : Obs) : Option Reply :=
  match o.word with
  | .none => none
  | .held => some (.answer (.held o.head))
  | .unnamed => some (.answer (.unnamed o.head))
  | .spoke => some (.answer (.spoke o.head))
  | .stale => some (.answer (.stale o.head (aboutOf o)))
  | .stands =>
    if plan q = .merge o.pr o.head then some (.landing o.head)
    else
      match step (outsider o).1 q o with
      | .stop (.stuck why) => some (.answer (.stuck why))
      | .stop _ => some (.answer (.notEligible (lacks o)))
      | .wait n => some (.answer (.queued o.head (.behind n)))
      | .awaitPush _ => some (.answer (.queued o.head .replay))
      | _ => some (.answer (.queued o.head .gate))

/-- One entry per pull request whose reply is an answer, in the snapshot's order. -/
def answers (os : List Obs) : List (Pr × Answer) :=
  os.filterMap fun o =>
    match reply (queueOf os) o with
    | some (.answer a) => some (o.pr, a)
    | _ => none

/-- What `apply` acts on: the pull request and head the plan merges, and the comment whose `/land`
is the entry next. A reader places a comment's word at twice its id. -/
structure Handoff where
  pr : Pr
  head : Sha
  approval : Nat
  requiresSpec : Bool
  deriving DecidableEq

def handoff (q : Queue) : Option Handoff :=
  match plan q, next q with
  | .merge p h, some (e, o) =>
    if e.mark.said % 2 = 0 then
      some ⟨p, h, e.mark.said / 2, (o.paths.map (·.any Snapshot.specPath)).getD true⟩
    else none
  | _, _ => none

def marker : String := "<!-- land-report -->"

def clauseOrder : List Clause := [.covered, .reviewed, .rest, .updatable, .enforced]

def clauseText : Clause → String
  | .covered => "no covering verdict"
  | .reviewed => "no bot review"
  | .rest => "an unanswered comment or a missing spec-approved"
  | .updatable => "a draft or a stack"
  | .enforced => "protection"

def stuckText : Stuck → String
  | .red => "red gate"
  | .conflict => "conflict"
  | .contentChanged => "a replay that changes content"
  | .historyError => "a history error"
  | .unread => "a failed read"

def waitingText : Waiting → String
  | .behind n => s!"#{n} to land first"
  | .replay => "the replay"
  | .gate => "gate"

def Answer.lines : Answer → List String
  | .unnamed h =>
    ["This PR touches a path you keep. To approve and merge it, comment only this line:", "",
     "```", s!"/land {h}", "```"]
  | .queued h why => [s!"Queued at {h}: waiting for {waitingText why}."]
  | .held h => [s!"Held by your /hold, an edited comment or a failed read. Comment /land {h} to go on."]
  | .spoke h => [s!"Your later comment paused it. Comment /land {h} again to go on."]
  | .stale h a => [s!"{h} is new content since {a}. After its verdict, comment /land {h}."]
  | .notEligible ls =>
    [s!"Stopped: {", ".intercalate ((clauseOrder.filter ls.contains).map clauseText)}."]
  | .stuck why => [s!"Stopped: {stuckText why}."]

def Answer.line (a : Answer) : String := a.lines.headD ""

def Answer.body (a : Answer) : String := "\n".intercalate (marker :: a.lines)

def AnswersOnlyOwnerWords : Prop :=
  ∀ q o, (reply q o).isSome = true ↔ o.word ≠ .none

def LandingIsThePlannedMerge : Prop :=
  ∀ q o h, reply q o = some (.landing h) ↔
    o.word = .stands ∧ plan q = .merge o.pr o.head ∧ h = o.head

def HandoffIsThePlannedMerge : Prop :=
  ∀ q x, handoff q = some x →
    plan q = .merge x.pr x.head ∧ ∃ e o, next q = some (e, o) ∧ o.pr = x.pr ∧ o.head = x.head ∧
      e.lander = .owner ∧ e.mark.said = 2 * x.approval ∧ newestOwner o.words = some (.ownerLand e.mark) ∧
      x.requiresSpec = (o.paths.map (·.any Snapshot.specPath)).getD true

theorem answersOnlyOwnerWords : AnswersOnlyOwnerWords := by
  intro q o
  unfold reply
  cases o.word with
  | none => simp
  | held => simp
  | unnamed => simp
  | spoke => simp
  | stale => simp
  | stands =>
    simp only [ne_eq, reduceCtorEq, not_false_eq_true, iff_true]
    split
    · rfl
    · split <;> rfl

theorem landingIsThePlannedMerge : LandingIsThePlannedMerge := by
  intro q o h
  unfold reply
  constructor
  · intro hr
    cases hw : o.word with
    | none => simp [hw] at hr
    | held => simp [hw] at hr
    | unnamed => simp [hw] at hr
    | spoke => simp [hw] at hr
    | stale => simp [hw] at hr
    | stands =>
      rw [hw] at hr
      simp only at hr
      split at hr
      · next hp =>
        simp only [Option.some.injEq, Reply.landing.injEq] at hr
        exact ⟨rfl, hp, hr.symm⟩
      · split at hr <;> simp at hr
  · rintro ⟨hw, hp, rfl⟩
    simp [hw, hp]

theorem handoffIsThePlannedMerge : HandoffIsThePlannedMerge := by
  intro q x hx
  unfold handoff at hx
  split at hx
  · next p h e o' hp hn =>
    split at hx
    · next hev =>
      cases hx
      obtain ⟨e', o, hn', hpr, hh, -, -, -, -, -, -, -, hl, hw, -⟩ := plannedMergeIsGated q p h hp
      rw [hn] at hn'
      cases hn'
      exact ⟨hp, e, o', hn, hpr, hh.symm, hl, by show e.mark.said = 2 * (e.mark.said / 2); omega, hw, rfl⟩
    · cases hx
  · cases hx

namespace Fixture

open Land.Fixture

def bareOnKept : Obs := { ownerKeptBehind with words := [.ownerLand ⟨900, "aaa", false⟩] }
def second : Obs := { ownerKeptPushed with pr := 154, words := [.ownerLand ⟨950, "ar", true⟩] }

def lineOf (q : Queue) (o : Obs) : Option String :=
  (reply q o).map fun
    | .answer a => a.line
    | .landing _ => ""

theorem aBareLandOnAKeptPathAsksForTheLine :
    reply (queueOf [bareOnKept]) bareOnKept = some (.answer (.unnamed "aaa")) ∧
      (Answer.unnamed "aaa").body =
        "<!-- land-report -->\nThis PR touches a path you keep. To approve and merge it, comment only this line:\n\n```\n/land aaa\n```" := by
  decide +kernel
theorem theApprovedGreenHeadIsLeftToApply :
    reply (queueOf [ownerKeptPushed]) ownerKeptPushed = some (.landing "ar") ∧
      handoff (queueOf [ownerKeptPushed]) = some ⟨153, "ar", 450, false⟩ ∧
      answers [ownerKeptPushed] = [] := by decide +kernel
theorem anotherLandingGoesFirst :
    lineOf (queueOf [ownerKeptPushed, second]) second =
      some "Queued at ar: waiting for #153 to land first." := by decide +kernel
theorem aBehindHeadWaitsForTheReplay :
    lineOf (queueOf [ownerKeptBehind]) ownerKeptBehind =
      some "Queued at aaa: waiting for the replay." := by decide +kernel
theorem aPushedHeadWaitsForGate :
    lineOf (queueOf [ownerKeptJustPushed]) ownerKeptJustPushed =
      some "Queued at ar: waiting for gate." := by decide +kernel
theorem aHoldIsHeld :
    lineOf (queueOf [ownerKeptHeld]) ownerKeptHeld =
      some "Held by your /hold, an edited comment or a failed read. Comment /land aaa to go on." := by
  decide +kernel
theorem aLaterCommentPausesIt :
    lineOf (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerSpoke 950] }])
      { ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerSpoke 950] } =
      some "Your later comment paused it. Comment /land ar again to go on." := by decide +kernel
theorem newContentNamesBothCommits :
    lineOf (queueOf [ownerKeptNewContent]) ownerKeptNewContent =
      some "fff is new content since aaa. After its verdict, comment /land fff." := by decide +kernel
theorem eachMissingClauseIsNamedInOrder :
    lineOf (queueOf [{ ownerKeptPushed with botAt := none, verdicts := [] }])
      { ownerKeptPushed with botAt := none, verdicts := [] } =
      some "Stopped: no covering verdict, no bot review." := by decide +kernel
theorem unenforcedIsProtection :
    lineOf (queueOf [{ ownerKeptPushed with enforced := false }])
      { ownerKeptPushed with enforced := false } = some "Stopped: protection." := by decide +kernel
theorem aRedGateIsStuck :
    lineOf (queueOf [{ ownerKeptPushed with gate := .failure }])
      { ownerKeptPushed with gate := .failure } = some "Stopped: red gate." := by decide +kernel
theorem noOwnerWordNoReply :
    reply (queueOf [ownerKeptPushed, agentBehind]) agentBehind = none := by decide +kernel
theorem anOddPositionHandsNothing :
    handoff (queueOf [{ ownerKeptPushed with words := [.ownerLand ⟨901, "aaa", true⟩] }]) = none := by
  decide +kernel

theorem aSpecMergeRequiresItsLabel :
    (handoff (queueOf [{ ownerKeptPushed with paths := some ["core/Mitos/Core.lean"] }])).map
      (·.requiresSpec) = some true := by decide +kernel

end Fixture

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.fold (fun acc n c =>
    if (`MitosGate.LandAnswer.Fixture).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``answersOnlyOwnerWords, ``landingIsThePlannedMerge, ``handoffIsThePlannedMerge] ++
      fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.LandAnswer
