import MitosGate.Land
import MitosGate.Shadow.Lacks
import MitosGate.Shadow.Reading
import MitosGate.Snapshot.Fields
import MitosGate.Snapshot.Note

/-!
# What the land workflow answers to an owner word

`land.yml`'s `report` job posts one comment per change of answer (amendment #178, section 4).
Every answer known before `apply` runs is decided and rendered here, from the queue `plan` reads,
as the workflow sees it: a teammate that is no delegate (`Shadow.outsider`). The pull request the
plan merges is `apply`'s to answer, from the merge call's result.

`named` is what `report` posts from: each answer with the snapshot's `Note` for its pull request,
which names the failed read or the unmet part of `rest`, and with the comment of the owner's newest
`/land`, so `report` answers each new `/land` once (#509, #520).
-/

namespace MitosGate.LandAnswer

open Land
open Shadow (Clause lacks outsider)
open Snapshot (Note Unread Unmet)

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
  | .rest => "an unanswered owner comment, a missing required label or footer, or unmet author or reviewer verification requirements"
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

def unmetText : Unmet → String
  | .footer => "a PR body without exactly one footer or with a session link"
  | .unanswered => "an unanswered owner comment"
  | .label => "a spec path without the spec-approved label"
  | .provenance => "unread provenance (provenance admission incomplete)"
  | .entry => "no provenance entry for the author (provenance admission incomplete)"
  | .author => "a recorded author that does not cover this head (provenance admission incomplete)"
  | .verdict => "verdicts short of the reviewer requirements (provenance admission incomplete)"

def clauseTextWith (n : Option Note) : Clause → String
  | .rest =>
    match n.map (·.unmet) with
    | some (u :: us) => ", ".intercalate ((u :: us).map unmetText)
    | _ => clauseText .rest
  | c => clauseText c

def Answer.linesWith (n : Option Note) : Answer → List String
  | .held h =>
    match n with
    | some note =>
      if note.unread.isEmpty then
        [s!"Held by your /hold or an edited comment. Comment /land {h} to go on."]
      else
        [s!"Held at {h}: a read failed (unread {", ".intercalate (note.unread.map (·.name))}). The next run reads again, so no new comment is needed."]
    | none => (Answer.held h).lines
  | .notEligible ls =>
    [s!"Stopped: {", ".intercalate ((clauseOrder.filter ls.contains).map (clauseTextWith n))}."]
  | a => a.lines

def greatest : List Nat → Option Nat
  | [] => none
  | n :: ns => some (max n ((greatest ns).getD 0))

def lands (ws : List Word) : List Nat :=
  ws.filterMap fun
    | .ownerLand m => if m.said % 2 = 0 then some (m.said / 2) else none
    | _ => none

/-- The comment that holds the owner's newest `/land`: a reader places a comment's word at twice
its id. -/
def asked (o : Obs) : Option Nat := greatest (lands o.words)

/-- A failed read holds every open pull request. Where the owner has no `/land` and no `/hold`,
that hold answers nothing the owner asked. -/
def unasked (n : Option Note) : Answer → Bool
  | .held _ => n.any fun note => !note.unread.isEmpty && !note.owner
  | _ => false

structure Named where
  pr : Pr
  answer : Answer
  note : Option Note
  land : Option Nat

def Named.lines (x : Named) : List String := x.answer.linesWith x.note

def Named.line (x : Named) : String := x.lines.headD ""

def Named.body (x : Named) : String := "\n".intercalate (marker :: x.lines)

def named (notes : List (Pr × Note)) (os : List Obs) : List Named :=
  os.filterMap fun o =>
    match reply (queueOf os) o with
    | some (.answer a) =>
      if unasked (notes.lookup o.pr) a then none else some ⟨o.pr, a, notes.lookup o.pr, asked o⟩
    | _ => none

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

def NamedAnswersAreAnswers : Prop :=
  ∀ notes os, ∀ x ∈ named notes os,
    (x.pr, x.answer) ∈ answers os ∧ x.note = notes.lookup x.pr ∧
      ∃ o ∈ os, o.pr = x.pr ∧ x.land = asked o

def OnlyAnUnaskedReadHoldIsLeftOut : Prop :=
  ∀ notes os p a, (p, a) ∈ answers os →
    (∃ x ∈ named notes os, x.pr = p ∧ x.answer = a) ∨
      ∃ h n, a = .held h ∧ notes.lookup p = some n ∧ n.unread ≠ [] ∧ n.owner = false

def WithoutANoteTheLinesAreTheSame : Prop :=
  ∀ a : Answer, a.linesWith none = a.lines

def AskedIsTheOwnersNewestLand : Prop :=
  ∀ (o : Obs) c, asked o = some c →
    (∃ m, Word.ownerLand m ∈ o.words ∧ m.said = 2 * c) ∧
      ∀ m, Word.ownerLand m ∈ o.words → m.said % 2 = 0 → m.said ≤ 2 * c

theorem namedAnswersAreAnswers : NamedAnswersAreAnswers := by
  intro notes os x hx
  simp only [named, List.mem_filterMap] at hx
  obtain ⟨o, ho, hx⟩ := hx
  split at hx
  · next a ha =>
    split at hx
    · cases hx
    · cases hx
      refine ⟨?_, rfl, o, ho, rfl, rfl⟩
      simp only [answers, List.mem_filterMap]
      exact ⟨o, ho, by rw [ha]⟩
  · cases hx

theorem onlyAnUnaskedReadHoldIsLeftOut : OnlyAnUnaskedReadHoldIsLeftOut := by
  intro notes os p a h
  simp only [answers, List.mem_filterMap] at h
  obtain ⟨o, ho, h⟩ := h
  split at h
  · next b hb =>
    cases h
    cases hu : unasked (notes.lookup o.pr) a with
    | false =>
      refine .inl ⟨⟨o.pr, a, notes.lookup o.pr, asked o⟩, ?_, rfl, rfl⟩
      simp only [named, List.mem_filterMap]
      exact ⟨o, ho, by rw [hb]; simp [hu]⟩
    | true =>
      right
      cases a with
      | held h' =>
        cases hn : notes.lookup o.pr with
        | none => simp [unasked, hn] at hu
        | some n =>
          simp only [unasked, hn, Option.any_some, Bool.and_eq_true, Bool.not_eq_true',
            List.isEmpty_eq_false_iff] at hu
          exact ⟨h', n, rfl, rfl, hu.1, hu.2⟩
      | _ => simp [unasked] at hu
  · cases h

theorem withoutANoteTheLinesAreTheSame : WithoutANoteTheLinesAreTheSame := by
  intro a
  have h : clauseTextWith none = clauseText := by
    funext c
    cases c <;> rfl
  cases a <;> simp [Answer.linesWith, Answer.lines, h]

theorem greatest_spec : ∀ {ns : List Nat} {c : Nat}, greatest ns = some c →
    c ∈ ns ∧ ∀ n ∈ ns, n ≤ c
  | [], _, h => by cases h
  | n :: ns, c, h => by
    simp only [greatest, Option.some.injEq] at h
    cases hn : greatest ns with
    | none =>
      have hns : ns = [] := by
        cases ns with
        | nil => rfl
        | cons a as => simp [greatest] at hn
      subst hns
      simp only [hn, Option.getD_none, Nat.max_zero] at h
      subst h
      simp
    | some d =>
      obtain ⟨hd, hmax⟩ := greatest_spec hn
      simp only [hn, Option.getD_some] at h
      subst h
      refine ⟨?_, fun k hk => ?_⟩
      · rcases Nat.le_total n d with hle | hle
        · rw [Nat.max_eq_right hle]; exact List.mem_cons_of_mem _ hd
        · rw [Nat.max_eq_left hle]; exact List.mem_cons_self
      · rcases List.mem_cons.1 hk with rfl | hk
        · exact Nat.le_max_left ..
        · exact Nat.le_trans (hmax k hk) (Nat.le_max_right ..)

theorem askedIsTheOwnersNewestLand : AskedIsTheOwnersNewestLand := by
  intro o c h
  obtain ⟨hc, hmax⟩ := greatest_spec h
  refine ⟨?_, fun m hm he => ?_⟩
  · simp only [lands, List.mem_filterMap] at hc
    obtain ⟨w, hw, hc⟩ := hc
    cases w with
    | ownerLand m =>
      simp only at hc
      split at hc
      · next he => cases hc; exact ⟨m, hw, by omega⟩
      · cases hc
    | _ => cases hc
  · have : m.said / 2 ∈ lands o.words := by
      simp only [lands, List.mem_filterMap]
      exact ⟨.ownerLand m, hm, by simp [he]⟩
    have := hmax _ this
    omega

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

def namedLines (notes : List (Pr × Note)) (os : List Obs) : List (Pr × String × Option Nat) :=
  (named notes os).map fun x => (x.pr, x.line, x.land)
def notAdmitted : Obs := { ownerKeptPushed with author := none, verdicts := [], rest := false }

theorem aFailedReadNamesTheRead :
    namedLines [(153, ⟨[.dashboard, .protection], [], true⟩)] [ownerKeptHeld] =
      [(153, "Held at aaa: a read failed (unread dashboard, protection). The next run reads again, so no new comment is needed.",
        some 450)] := by decide +kernel
theorem aHoldWithEveryReadIsTheOwners :
    namedLines [(153, ⟨[], [], true⟩)] [ownerKeptHeld] =
      [(153, "Held by your /hold or an edited comment. Comment /land aaa to go on.", some 450)] := by
  decide +kernel
theorem aHoldWithoutANoteKeepsTheGeneralLine :
    namedLines [] [ownerKeptHeld] =
      [(153, "Held by your /hold, an edited comment or a failed read. Comment /land aaa to go on.",
        some 450)] := by decide +kernel
theorem aReadHoldWhereTheOwnerAskedNothingIsLeftOut :
    namedLines [(153, ⟨[.dashboard], [], false⟩)] [{ ownerKeptBehind with words := [.ownerHold 307] }] =
      [] ∧
    answers [{ ownerKeptBehind with words := [.ownerHold 307] }] = [(153, .held "aaa")] := by
  decide +kernel
theorem aReadHoldWhereTheOwnerAskedIsAnswered :
    (namedLines [(153, ⟨[.dashboard], [], true⟩)] [ownerKeptHeld]).map (·.1) = [153] := by
  decide +kernel
theorem theOwnersOwnHoldIsAnsweredWhateverTheNoteSays :
    (namedLines [(153, ⟨[], [], false⟩)] [ownerKeptHeld]).map (·.1) = [153] := by decide +kernel
theorem aMissingEntryIsNamed :
    namedLines [(153, ⟨[], [.entry], true⟩)] [notAdmitted] =
      [(153, "Stopped: no covering verdict, no provenance entry for the author (provenance admission incomplete).",
        some 450)] := by decide +kernel
theorem severalUnmetPartsAreNamedInOrder :
    namedLines [(153, ⟨[], [.unanswered, .label, .verdict], true⟩)] [{ ownerKeptPushed with rest := false }] =
      [(153, "Stopped: an unanswered owner comment, a spec path without the spec-approved label, verdicts short of the reviewer requirements (provenance admission incomplete).",
        some 450)] := by decide +kernel
theorem aNoteThatNamesNothingKeepsTheGeneralLine :
    namedLines [(153, ⟨[], [], true⟩)] [{ ownerKeptPushed with rest := false }] =
      namedLines [] [{ ownerKeptPushed with rest := false }] ∧
    namedLines [] [{ ownerKeptPushed with rest := false }] =
      [(153, "Stopped: an unanswered owner comment, a missing required label or footer, or unmet author or reviewer verification requirements.",
        some 450)] := by decide +kernel
theorem aNoteForAnotherPullRequestNamesNothing :
    namedLines [(154, ⟨[.dashboard], [.entry], false⟩)] [ownerKeptHeld] = namedLines [] [ownerKeptHeld] := by
  decide +kernel
theorem eachUnmetPartHasItsWords :
    Unmet.all.map unmetText =
      ["a PR body without exactly one footer or with a session link", "an unanswered owner comment",
       "a spec path without the spec-approved label",
       "unread provenance (provenance admission incomplete)",
       "no provenance entry for the author (provenance admission incomplete)",
       "a recorded author that does not cover this head (provenance admission incomplete)",
       "verdicts short of the reviewer requirements (provenance admission incomplete)"] := by
  decide +kernel
theorem eachReadHasTheNameSnapshotPrints :
    Unread.all.map (·.name) = ["protection", "stacks", "dashboard", "comments", "review-comments",
      "reviews", "activity", "files", "checks"] := by decide +kernel
theorem theNewestLandIsTheOneAnswered :
    asked { ownerKeptBehind with
      words := [.ownerLand ownerKeptMark, .ownerHold 950, .ownerLand ⟨1000, "aaa", true⟩] } =
      some 500 ∧
    asked { ownerKeptBehind with words := [.ownerHold 950, .ownerSpoke 960] } = none ∧
    asked agentBehind = none := by decide +kernel
theorem theBodyStartsWithTheMarker :
    (named [(153, ⟨[.dashboard], [], true⟩)] [ownerKeptHeld]).map (·.body) =
      ["<!-- land-report -->\nHeld at aaa: a read failed (unread dashboard). The next run reads again, so no new comment is needed."] := by
  decide +kernel

end Fixture

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.fold (fun acc n c =>
    if (`MitosGate.LandAnswer.Fixture).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``answersOnlyOwnerWords, ``landingIsThePlannedMerge, ``handoffIsThePlannedMerge,
      ``namedAnswersAreAnswers, ``onlyAnUnaskedReadHoldIsLeftOut, ``withoutANoteTheLinesAreTheSame,
      ``askedIsTheOwnersNewestLand] ++ fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.LandAnswer
