import MitosGate.Watch.Shared
import MitosGate.Watch.Topic

/-! UNCHECKED SKETCH (#502). Who a fact is for: identity, quiet posts, echoes of one's own writes,
which changes wake, and the kind of each fact.

Everything is observed once for the clone; only what each consumer is told differs. So nothing
one consumer records or subscribes to can hide anything from another (#501): the root's catch-up
wakes Codex, a Codex comment wakes the root, and what a consumer hears is its own topic's choice
(`Topic.lean`, `Deliver.Subscription.lens`).

Identity is the app GitHub names on a post, or an id the consumer's class recorded with
`watch own`. The footer is never identity here. Identity classifies a post and never hides it: the
app part of `--as` decides whether an app's post is `agents` (another app) or `peers` (the
consumer's own app), and only a recorded id makes a post quiet. Typed words (an issue comment from
the owner's login with no app) are never quiet, whatever was recorded. The review routes name no
app, so a review comment or review is quiet only when its id was recorded; an unrecorded agent
reply there is `words` and wakes (default 5b). The default topic does not hear `peers`, so by
default a Claude consumer is not told a post made through the Claude app (owner question 11).

A write record (label, assignee, merge, close) belongs to one consumer and explains only that
consumer's view of the change. It is spent by poll count, not by wall time: it explains changes
for the first batch whose acked mark is at most one poll after the record, so a 10-minute gap with
no poll does not expire it, and a write that failed or was undone cannot hide a later change for
long. Layout copies `Land`'s wake rules plus `Carry.lean`. -/

namespace MitosGate.Watch

open Land (Pr)

/-- `--as <app>/<name>`: the GitHub app the consumer posts through (its class), and the name its
state is kept under, such as `claude/root`, `claude/pr-512` or `chatgpt-codex-connector/codex`.
Identity only: what the consumer hears is the `Subscription` of each wait. -/
structure Consumer where
  app : String
  name : String
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

/-- Only a recorded id hides a post, and never typed words. `recorded` holds the ids the
consumer's class recorded in this clone (`Store`: `classes/<app>/posts/`). -/
def quiet (recorded : List PostRecord) (p : Post) : Bool :=
  match p.speaker with
  | .typed => false
  | .app _ => recorded.contains ⟨p.place, p.id⟩
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

/-- A listed check is done now with a conclusion `want` accepts, and was not done with the same
result at the same sha before. -/
def finishedWhere (want : String → Bool) (b : Option HeadFacts) (a : HeadFacts) : Bool :=
  Listed.all.any fun n =>
    match a.checks.get n with
    | some (.done c) => want c && (match b with
      | some b => !(b.sha == a.sha && b.checks.get n == some (.done c))
      | none => true)
    | _ => false

/-- A listed check finished newly. -/
def finishedNew : Option HeadFacts → HeadFacts → Bool := finishedWhere fun _ => true

/-- The conclusions that pass, a closed set. Every other conclusion fails, one this tool has never
seen included, so it reaches a CI-failures agent. `skipped` passes: `ci.yml` skips `prove` on every
label run, and CodeRabbit skips on its own (an assigned skip is the `rabbitSkipped` alarm). A
`cancelled` run fails: `kitimark-mode` does not call it red, but someone must re-run it. -/
def passingConclusions : List String := ["success", "skipped", "neutral"]

/-- A listed check finished newly with a conclusion that does not pass. -/
def failedNew : Option HeadFacts → HeadFacts → Bool :=
  finishedWhere fun c => !passingConclusions.contains c

/-- A listed check finished newly with a conclusion that passes. -/
def passedNew : Option HeadFacts → HeadFacts → Bool :=
  finishedWhere fun c => passingConclusions.contains c

/-- A change wakes when someone must act on it. A pull opened or left the open list; labels or
assignees moved; a listed check finished, on the same head or a new one (so a new head pushed with
a check already done still wakes, which `pushed` absorption lost); a health condition began.
Pending checks, a condition clearing and a pull's head moving with nothing finished are absorbed.
An outside pull's change wakes too: whether it ends a wait is the subscription's `rides`, where
`outside` rides by default. -/
def Change.wakes : Change → Bool
  | .pull ⟨_, none, some _⟩ => true
  | .pull ⟨_, some _, none⟩ => true
  | .pull ⟨_, some b, some a⟩ => b.labels != a.labels || b.assignees != a.assignees
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

/-- A change is about some of a topic's items when it is about one of its pull requests. A health
change about no pull request (`queued`, `stale`: `ci` itself) is for repository-wide topics only,
so a PR owner waiting with `--on` hears its own pull requests and nothing else. -/
def Scope.coversChange (sc : Scope) (ch : Change) : Bool :=
  match sc, ch.pr? with
  | .repo, _ => true
  | .items ns, some p => ns.contains p
  | .items _, none => false

/-- The pull request a pull change says left the open list. -/
def Change.leaves : Change → Option Pr
  | .pull ⟨p, some _, none⟩ => some p
  | _ => none

/-- The kind of a post for a consumer whose app is `app`. -/
def Post.kind (app : String) (p : Post) : Kind :=
  match p.speaker with
  | .app s => if s == app then .peers else .agents
  | .typed => .words
  | .untold => .words

def Author.kind : Author → Kind
  | .own => .pulls
  | .outside => .outside

/-- The kinds of a change. A head line is about the checks that newly finished on it: `failed` when
one did with a conclusion outside `passingConclusions`, `passed` when one passed, and both when
both happened, so a green gate beside a new red check still reaches a caller that hears `passed`
and wakes a root that lets only `failed` ride. Measured against the caller's acked view, so two
checks that finish in two polls of one wait are one line. Every other change has one kind. The
list is never empty: a head change with nothing newly finished, or no head after it, never wakes
and reaches no report, so its `[.passed]` is never read. -/
def Change.kinds : Change → List Kind
  | .pull ⟨_, _, some a⟩ => [a.author.kind]
  | .pull ⟨_, some b, none⟩ => [b.author.kind]
  | .pull ⟨_, none, none⟩ => [.pulls]
  | .head ⟨_, b, some a⟩ =>
    if failedNew b a then (if passedNew b a then [.passed, .failed] else [.failed]) else [.passed]
  | .head ⟨_, _, none⟩ => [.passed]
  | .health _ => [.alarms]

/-- The kind of an item a reader could not read: an unreadable post may be the owner's words. -/
def Refused.lineKind (x : Refused) : Kind :=
  match x.kind with
  | .post _ => .words
  | .close => .pulls

/-- `words`: every post that was not quiet (the owner's typed words, apps' posts, and review-route
posts that no app names and no one recorded) and every item a reader could not read.
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
  ∀ recorded (p : Post), p.speaker = .typed → quiet recorded p = false

/-- Replaces `QuietNeedsTheClassOrARecord`: the class alone hides nothing. -/
def QuietNeedsARecord : Prop :=
  ∀ recorded (p : Post), quiet recorded p = true →
    p.speaker ≠ .typed ∧ ⟨p.place, p.id⟩ ∈ recorded

def UntoldIsHeardUnlessRecorded : Prop :=
  ∀ recorded (p : Post), p.speaker = .untold →
    (quiet recorded p = true ↔ ⟨p.place, p.id⟩ ∈ recorded)

def QuietIgnoresTheText : Prop :=
  ∀ recorded (p : Post) e, quiet recorded p = quiet recorded { p with excerpt := e }

/-- Replaces `AnotherClassIsHeard`: the speaker and the consumer's app decide a post's kind, and
nothing else does. A post no app names is `words` for every consumer. -/
def TheSpeakerDecidesThePostKind : Prop :=
  ∀ (app : String) (p : Post),
    (p.speaker = .app app → p.kind app = .peers) ∧
    (∀ s, p.speaker = .app s → s ≠ app → p.kind app = .agents) ∧
    ((∀ s, p.speaker ≠ .app s) → p.kind app = .words)

/-- A head line's kinds are `passed` and `failed` only, and it is `passed` whenever a listed check
newly finished with a passing conclusion, whatever else failed beside it. Every other change has
the one kind of its author or `alarms`. Short: a case split on `Change` and on `Listed`. -/
def AChangeIsAboutItsOwnKind : Prop :=
  (∀ d, ∀ k ∈ (Change.head d).kinds, k = .passed ∨ k = .failed) ∧
  (∀ p b (a : HeadFacts) n c, a.checks.get n = some (.done c) → c ∈ passingConclusions →
    (∀ x, b = some x → x.sha ≠ a.sha ∨ x.checks.get n ≠ some (.done c)) →
    .passed ∈ (Change.head ⟨p, b, some a⟩).kinds) ∧
  (∀ d, (Change.health d).kinds = [.alarms]) ∧
  (∀ p b (a : PullFacts), (Change.pull ⟨p, b, some a⟩).kinds = [a.author.kind]) ∧
  (∀ p (b : PullFacts), (Change.pull ⟨p, some b, none⟩).kinds = [b.author.kind])

/-- A head line is `failed` exactly when a listed check newly finished with a conclusion outside
`passingConclusions`; a label run's skipped `prove` is not one. Short, as `FinishedCheckWakes`: a
case split on `Listed`. -/
def AHeadLineFailsOnANewFailure : Prop :=
  ∀ p b (a : HeadFacts), .failed ∈ (Change.head ⟨p, b, some a⟩).kinds ↔
    ∃ n c, a.checks.get n = some (.done c) ∧ c ∉ passingConclusions ∧
      ∀ x, b = some x → x.sha ≠ a.sha ∨ x.checks.get n ≠ some (.done c)

def FinishedCheckWakes : Prop :=
  ∀ p b (a : HeadFacts) n c, a.checks.get n = some (.done c) →
    (∀ x, b = some x → x.sha ≠ a.sha ∨ x.checks.get n ≠ some (.done c)) →
    Change.wakes (.head ⟨p, b, some a⟩) = true

def OnlyPendingIsQuiet : Prop :=
  ∀ p b (a : HeadFacts), Change.wakes (.head ⟨p, b, some a⟩) = false →
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

namespace Fixture

/-- Replaces `claudeReplyIsQuietForTheRoot`: a Claude-app post is `peers` for a Claude consumer,
which the default topic does not hear, and `agents` for Codex, which it does. Nothing recorded it,
so it is quiet for neither. The fixture reads only the post's speaker, never its excerpt. -/
def aClaudeAppPost : Post :=
  Post.of { place := .issueComment, id := 31, thread := 336, login := "o", via := .app "claude",
    created := 1795425128, updated := 1795425128, state := none, body := "## Catch-up: review it" }

theorem aClaudeAppPostIsPeersForClaudeAndAgentsForCodex :
    aClaudeAppPost.kind "claude" = .peers ∧
      aClaudeAppPost.kind "chatgpt-codex-connector" = .agents ∧
      quiet [] aClaudeAppPost = false := by
  decide +kernel

/-- A red gate alone makes the head line `failed`; a head whose newly finished checks are all
green is `passed`. -/
theorem aRedGateFailsAndAGreenHeadPasses :
    Change.kinds (.head ⟨512, none, some ⟨"abc1234", { gate := some (.done "failure") }⟩⟩) =
        [.failed] ∧
      Change.kinds (.head ⟨512, none, some ⟨"abc1234", { gate := some (.done "success") }⟩⟩) =
        [.passed] := by
  decide +kernel

/-- A green gate and a red `scorecard-comment` newly finished on one head make one line of both
kinds (round 2's counterexample: as one kind, the green gate rode with the red check). -/
theorem aGreenGateBesideARedCheckIsBoth :
    Change.kinds (.head ⟨512, none, some ⟨"abc1234",
        { gate := some (.done "success"), scorecard := some (.done "failure") }⟩⟩) =
      [.passed, .failed] := by
  decide +kernel

/-- A label run at one sha: the red gate goes green and `prove` skips. Nothing newly failed, so the
head line is `passed`, and a root that lets `failed` ride still wakes for it. A skipped CodeRabbit
check passes too. -/
theorem aLabelRunsSkippedProvePasses :
    Change.kinds (.head ⟨512,
        some ⟨"abc1234", { gate := some (.done "failure"), prove := some (.done "success") }⟩,
        some ⟨"abc1234", { gate := some (.done "success"), prove := some (.done "skipped") }⟩⟩) =
        [.passed] ∧
      Change.kinds (.head ⟨512, none, some ⟨"abc1234",
        { gate := some (.done "success"), coderabbit := some (.done "skipped") }⟩⟩) =
        [.passed] := by
  decide +kernel

end Fixture

end MitosGate.Watch
