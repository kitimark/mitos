import MitosGate.Watch.Shared

/-! UNCHECKED SKETCH (#502). Who a fact is for: identity, quiet posts, echoes of one's own writes,
and which changes wake.

Everything is observed once for the clone; only what each consumer is told differs. So nothing
one consumer records can hide anything from another (#501): the root's catch-up wakes Codex, a
Codex comment wakes the root, and a Claude PR owner's reply stays quiet for every Claude consumer.

Identity is the app GitHub names on a post, or an id the consumer's class recorded with
`watch own`. The footer is never identity here. Typed words (an issue comment from the owner's
login with no app) are never quiet, whatever was recorded. The review routes name no app, so a
review comment or review is quiet only when its id was recorded; an unrecorded agent reply there
wakes (default 5b).

A write record (label, assignee, merge, close) belongs to one consumer and explains only that
consumer's view of the change. It is spent by poll count, not by wall time: it explains changes
for the first batch whose acked mark is at most one poll after the record, so a 10-minute gap with
no poll does not expire it, and a write that failed or was undone cannot hide a later change for
long. Layout copies `Land`'s wake rules plus `Carry.lean`. -/

namespace MitosGate.Watch

open Land (Pr)

inductive Scope
  | repo
  | pulls (ns : List Pr)
  deriving DecidableEq, Repr

def Scope.covers : Scope → Pr → Bool
  | .repo, _ => true
  | .pulls ns, p => ns.contains p

/-- `--as <app>/<name>`: the GitHub app the consumer posts through (its class), and the name its
state is kept under, such as `claude/root`, `claude/pr-512` or `chatgpt-codex-connector/codex`. -/
structure Consumer where
  app : String
  name : String
  scope : Scope
  deriving DecidableEq, Repr

structure PostRecord where
  place : Place
  id : Nat
  deriving DecidableEq, Repr

inductive Write
  | assign (p : Pr) (login : String)
  | unassign (p : Pr) (login : String)
  | label (p : Pr) (name : String)
  | unlabel (p : Pr) (name : String)
  | merge (p : Pr)
  | close (p : Pr)
  deriving DecidableEq, Repr

/-- `afterPoll` is the shared poll count read when the record was made. `seq` is the consumer's own
counter, so two writes in one poll interval (an unassign then an assign of the owner, a label then
an unlabel) keep their order: `Store.readRecords` sorts by it, and `applyWrites` folds in that
order. -/
structure WriteRecord where
  gen : String
  afterPoll : Nat
  seq : Nat
  write : Write
  deriving DecidableEq, Repr

def WriteRecord.live (gen : String) (ackedPoll : Nat) (r : WriteRecord) : Bool :=
  r.gen == gen && decide (ackedPoll ≤ r.afterPoll + 1)

def quiet (c : Consumer) (recorded : List PostRecord) (p : Post) : Bool :=
  match p.speaker with
  | .typed => false
  | .app s => s == c.app || recorded.contains ⟨p.place, p.id⟩
  | .untold => recorded.contains ⟨p.place, p.id⟩

def Names.add (n : Names) (x : String) : Names := Names.of (x :: n.items)
def Names.drop (n : Names) (x : String) : Names := Names.of (n.items.filter (· != x))

/-- The facts the writes on `p` lead to from `b`, in the order they were recorded (`seq`). -/
def applyWrites (p : Pr) (ws : List Write) (b : PullFacts) : PullFacts :=
  ws.foldl (fun f w => match w with
    | .label q x => if q == p then { f with labels := f.labels.add x } else f
    | .unlabel q x => if q == p then { f with labels := f.labels.drop x } else f
    | .assign q x => if q == p then { f with assignees := f.assignees.add x } else f
    | .unassign q x => if q == p then { f with assignees := f.assignees.drop x } else f
    | _ => f) b

def Write.about : Write → Pr
  | .assign p _ | .unassign p _ | .label p _ | .unlabel p _ | .merge p | .close p => p

/-- A labels or assignees change on a pull that stays open, all of it accounted for by the writes. -/
def explains (ws : List Write) : Change → Bool
  | .pull ⟨p, some b, some a⟩ => ws.any (·.about == p) && applyWrites p ws b == a
  | _ => false

def explainsClose (ws : List Write) (c : ClosedPull) : Bool :=
  if c.merged then ws.contains (.merge c.number) else ws.contains (.close c.number)

/-- The root's default for question 6 is `rideAlong` (`DESIGN.md`, part B); `wake` is today's
behavior and stays for a no on PR 0. -/
inductive OutsidePolicy
  | wake
  | rideAlong
  deriving DecidableEq, Repr

def Author.wakes (o : OutsidePolicy) : Author → Bool
  | .own => true
  | .outside => o == .wake

/-- A listed check is done now and was not done with the same result at the same sha before. -/
def finishedNew (b : Option HeadFacts) (a : HeadFacts) : Bool :=
  Listed.all.any fun n =>
    match a.checks.get n with
    | some (.done c) => match b with
      | some b => !(b.sha == a.sha && b.checks.get n == some (.done c))
      | none => true
    | _ => false

/-- A change wakes when someone must act on it. A pull opened or left the open list; labels or
assignees moved; a listed check finished, on the same head or a new one (so a new head pushed with
a check already done still wakes, which `pushed` absorption lost); a health condition began.
Pending checks, a condition clearing and a pull's head moving with nothing finished are absorbed. -/
def Change.wakes (o : OutsidePolicy) : Change → Bool
  | .pull ⟨_, none, some a⟩ => a.author.wakes o
  | .pull ⟨_, some b, none⟩ => b.author.wakes o
  | .pull ⟨_, some b, some a⟩ => (b.labels != a.labels || b.assignees != a.assignees) && a.author.wakes o
  | .pull ⟨_, none, none⟩ => false
  | .head ⟨_, b, some a⟩ => finishedNew b a
  | .head ⟨_, _, none⟩ => false
  | .health ⟨_, none, some _⟩ => true
  | .health _ => false

def Change.pr? : Change → Option Pr
  | .pull d | .head d => some d.key
  | .health ⟨.noRun p _, _, _⟩ | .health ⟨.rabbitSkipped p _, _, _⟩
  | .health ⟨.unread p _ _, _, _⟩ => some p
  | .health _ => none

/-- A change is for a consumer when it is about one of its pull requests. A health change about no
pull request (`queued`, `stale`: `ci` itself) is for repository-wide consumers only, so a PR owner
waiting with `--pr` hears its own pull requests and nothing else. -/
def Scope.coversChange (sc : Scope) (ch : Change) : Bool :=
  match sc, ch.pr? with
  | .repo, _ => true
  | .pulls ns, some p => ns.contains p
  | .pulls _, none => false

/-- Whether a change is worth telling at all, whatever the outside policy: it would wake under
`wake`. `report` lists every notable change in scope, and `wakes` decides only whether it ends the
wait, so under `rideAlong` an outside change still rides along in the next batch. -/
def Change.notable (ch : Change) : Bool := ch.wakes .wake

/-- The pull request a pull change says left the open list. -/
def Change.leaves : Change → Option Pr
  | .pull ⟨p, some _, none⟩ => some p
  | _ => none

/-- `words`: every post that was not quiet (the owner's typed words, other apps' posts, and
review-route posts that no app names and no one recorded) and every item a reader could not read.
`owned`: changes on the owner's pull requests, health, notes. `outside`: changes and closes of
outside pull requests. The cap never cuts `words` or notes, cuts head lines last and `outside`
first. Only words that may be the owner's (typed, untold, or unreadable posts) skip the coalescing
window (`Told.skipsWindow`); the tier itself only protects from the cut. -/
inductive Tier
  | words
  | owned
  | outside
  deriving DecidableEq, Repr

def TypedWordsAreNeverQuiet : Prop :=
  ∀ c recorded (p : Post), p.speaker = .typed → quiet c recorded p = false

def QuietNeedsTheClassOrARecord : Prop :=
  ∀ c recorded (p : Post), quiet c recorded p = true →
    p.speaker ≠ .typed ∧ (p.speaker = .app c.app ∨ ⟨p.place, p.id⟩ ∈ recorded)

def AnotherClassIsHeard : Prop :=
  ∀ c recorded (p : Post) s, p.speaker = .app s → s ≠ c.app → ⟨p.place, p.id⟩ ∉ recorded →
    quiet c recorded p = false

def UntoldIsHeardUnlessRecorded : Prop :=
  ∀ c recorded (p : Post), p.speaker = .untold →
    (quiet c recorded p = true ↔ ⟨p.place, p.id⟩ ∈ recorded)

def QuietIgnoresTheText : Prop :=
  ∀ c recorded (p : Post) e, quiet c recorded p = quiet c recorded { p with excerpt := e }

def FinishedCheckWakes : Prop :=
  ∀ o p b (a : HeadFacts) n c, a.checks.get n = some (.done c) →
    (∀ x, b = some x → x.sha ≠ a.sha ∨ x.checks.get n ≠ some (.done c)) →
    Change.wakes o (.head ⟨p, b, some a⟩) = true

def OnlyPendingIsQuiet : Prop :=
  ∀ o p b (a : HeadFacts), Change.wakes o (.head ⟨p, b, some a⟩) = false →
    ∀ n c, a.checks.get n = some (.done c) →
      ∃ x, b = some x ∧ x.sha = a.sha ∧ x.checks.get n = some (.done c)

/-- Moderate: needs `Names.of` to behave as a set (`NamesOfIgnoresOrderAndRepeats`). -/
def EchoAddsOnlyWhatWasWritten : Prop :=
  ∀ ws p (b a : PullFacts), explains ws (.pull ⟨p, some b, some a⟩) = true →
    (∀ x ∈ a.labels.items, x ∉ b.labels.items → .label p x ∈ ws) ∧
    (∀ x ∈ a.assignees.items, x ∉ b.assignees.items → .assign p x ∈ ws)

def EchoDropsOnlyWhatWasWritten : Prop :=
  ∀ ws p (b a : PullFacts), explains ws (.pull ⟨p, some b, some a⟩) = true →
    (∀ x ∈ b.labels.items, x ∉ a.labels.items → .unlabel p x ∈ ws) ∧
    (∀ x ∈ b.assignees.items, x ∉ a.assignees.items → .unassign p x ∈ ws)

def NoLiveWriteNoEcho : Prop :=
  (∀ ch, explains [] ch = false) ∧ ∀ c, explainsClose [] c = false

def ARecordIsSpentTwoPollsLater : Prop :=
  ∀ gen acked (r : WriteRecord), r.afterPoll + 2 ≤ acked → r.live gen acked = false

def ARecordOfAnotherGenerationIsDead : Prop :=
  ∀ gen acked (r : WriteRecord), r.gen ≠ gen → r.live gen acked = false

def OnlyAMergeExplainsAMerge : Prop :=
  ∀ ws (c : ClosedPull), explainsClose ws c = true →
    (c.merged = true → .merge c.number ∈ ws) ∧ (c.merged = false → .close c.number ∈ ws)

end MitosGate.Watch
