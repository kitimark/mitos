import MitosGate.Watch.Shared
import MitosGate.Watch.Topic

namespace MitosGate.Watch

open Land (Pr)

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

structure WriteRecord where
  gen : String
  afterPoll : Nat
  seq : Nat
  write : Write
  deriving DecidableEq, Repr

def WriteRecord.live (gen : String) (ackedPoll : Nat) (r : WriteRecord) : Bool :=
  r.gen == gen && decide (ackedPoll ≤ r.afterPoll + 1)

def quiet (recorded : List PostRecord) (p : Post) : Bool :=
  match p.speaker with
  | .typed => false
  | .app _ => recorded.contains ⟨p.place, p.id⟩
  | .untold => recorded.contains ⟨p.place, p.id⟩

def Names.add (n : Names) (x : String) : Names := Names.of (x :: n.items)
def Names.drop (n : Names) (x : String) : Names := Names.of (n.items.filter (· != x))

def applyWrites (p : Pr) (ws : List Write) (b : PullFacts) : PullFacts :=
  ws.foldl (fun f w => match w with
    | .label q x => if q == p then { f with labels := f.labels.add x } else f
    | .unlabel q x => if q == p then { f with labels := f.labels.drop x } else f
    | .assign q x => if q == p then { f with assignees := f.assignees.add x } else f
    | .unassign q x => if q == p then { f with assignees := f.assignees.drop x } else f
    | _ => f) b

def Write.about : Write → Pr
  | .assign p _ | .unassign p _ | .label p _ | .unlabel p _ | .merge p | .close p => p

def explains (ws : List Write) : Change → Bool
  | .pull ⟨p, some b, some a⟩ => ws.any (·.about == p) && applyWrites p ws b == a
  | _ => false

def explainsClose (ws : List Write) (c : ClosedPull) : Bool :=
  if c.merged then ws.contains (.merge c.number) else ws.contains (.close c.number)

def finishedWhere (want : String → Bool) (b : Option HeadFacts) (a : HeadFacts) : Bool :=
  Listed.all.any fun n =>
    match a.checks.get n with
    | some (.done c) => want c && (match b with
      | some b => !(b.sha == a.sha && b.checks.get n == some (.done c))
      | none => true)
    | _ => false

def finishedNew : Option HeadFacts → HeadFacts → Bool := finishedWhere fun _ => true

def passingConclusions : List String := ["success", "skipped", "neutral"]

def failedNew : Option HeadFacts → HeadFacts → Bool :=
  finishedWhere fun c => !passingConclusions.contains c

def passedNew : Option HeadFacts → HeadFacts → Bool :=
  finishedWhere fun c => passingConclusions.contains c

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

def Scope.coversChange (sc : Scope) (ch : Change) : Bool :=
  match sc, ch.pr? with
  | .repo, _ => true
  | .items ns, some p => ns.contains p
  | .items _, none => false

def Change.leaves : Change → Option Pr
  | .pull ⟨p, some _, none⟩ => some p
  | _ => none

def Post.kind (app : String) (p : Post) : Kind :=
  match p.speaker with
  | .app s => if s == app then .peers else .agents
  | .typed => .words
  | .untold => .words

def Author.kind : Author → Kind
  | .own => .pulls
  | .outside => .outside

def Change.kinds : Change → List Kind
  | .pull ⟨_, _, some a⟩ => [a.author.kind]
  | .pull ⟨_, some b, none⟩ => [b.author.kind]
  | .pull ⟨_, none, none⟩ => [.pulls]
  | .head ⟨_, b, some a⟩ =>
    if failedNew b a then (if passedNew b a then [.passed, .failed] else [.failed]) else [.passed]
  | .head ⟨_, _, none⟩ => [.passed]
  | .health _ => [.alarms]

def Refused.lineKind (x : Refused) : Kind :=
  match x.kind with
  | .post _ => .words
  | .close => .pulls

inductive Tier
  | words
  | owned
  | outside
  deriving DecidableEq, Repr

def TypedWordsAreNeverQuiet : Prop :=
  ∀ recorded (p : Post), p.speaker = .typed → quiet recorded p = false

def QuietNeedsARecord : Prop :=
  ∀ recorded (p : Post), quiet recorded p = true →
    p.speaker ≠ .typed ∧ ⟨p.place, p.id⟩ ∈ recorded

def UntoldIsHeardUnlessRecorded : Prop :=
  ∀ recorded (p : Post), p.speaker = .untold →
    (quiet recorded p = true ↔ ⟨p.place, p.id⟩ ∈ recorded)

def QuietIgnoresTheText : Prop :=
  ∀ recorded (p : Post) e, quiet recorded p = quiet recorded { p with excerpt := e }

def TheSpeakerDecidesThePostKind : Prop :=
  ∀ (app : String) (p : Post),
    (p.speaker = .app app → p.kind app = .peers) ∧
    (∀ s, p.speaker = .app s → s ≠ app → p.kind app = .agents) ∧
    ((∀ s, p.speaker ≠ .app s) → p.kind app = .words)

def AChangeIsAboutItsOwnKind : Prop :=
  (∀ d, ∀ k ∈ (Change.head d).kinds, k = .passed ∨ k = .failed) ∧
  (∀ p b (a : HeadFacts) n c, a.checks.get n = some (.done c) → c ∈ passingConclusions →
    (∀ x, b = some x → x.sha ≠ a.sha ∨ x.checks.get n ≠ some (.done c)) →
    .passed ∈ (Change.head ⟨p, b, some a⟩).kinds) ∧
  (∀ d, (Change.health d).kinds = [.alarms]) ∧
  (∀ p b (a : PullFacts), (Change.pull ⟨p, b, some a⟩).kinds = [a.author.kind]) ∧
  (∀ p (b : PullFacts), (Change.pull ⟨p, some b, none⟩).kinds = [b.author.kind])

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

def aClaudeAppPost : Post :=
  Post.of { place := .issueComment, id := 31, thread := 336, login := "o", via := .app "claude",
    created := 1795425128, updated := 1795425128, state := none, body := "## Catch-up: review it" }

theorem aClaudeAppPostIsPeersForClaudeAndAgentsForCodex :
    aClaudeAppPost.kind "claude" = .peers ∧
      aClaudeAppPost.kind "chatgpt-codex-connector" = .agents ∧
      quiet [] aClaudeAppPost = false := by
  decide +kernel

theorem aRedGateFailsAndAGreenHeadPasses :
    Change.kinds (.head ⟨512, none, some ⟨"abc1234", { gate := some (.done "failure") }⟩⟩) =
        [.failed] ∧
      Change.kinds (.head ⟨512, none, some ⟨"abc1234", { gate := some (.done "success") }⟩⟩) =
        [.passed] := by
  decide +kernel

theorem aGreenGateBesideARedCheckIsBoth :
    Change.kinds (.head ⟨512, none, some ⟨"abc1234",
        { gate := some (.done "success"), scorecard := some (.done "failure") }⟩⟩) =
      [.passed, .failed] := by
  decide +kernel

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
