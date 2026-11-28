import MitosGate.Watch.View
import MitosGate.Watch.Feed

namespace MitosGate.Watch

open Land (Pr)

structure Shared where
  repo : String
  owner : String
  gen : String
  polls : Nat
  view : View
  feed : Feed
  main : String
  ages : KeyMap (Pr × String) HeadAge
  lastTry : Epoch
  lastOk : Epoch
  failStreak : Nat
  lastError : Excerpt
  deriving DecidableEq

def Shared.start (repo owner gen : String) : Shared :=
  { repo, owner, gen, polls := 0, view := {}, feed := Feed.start, main := "", ages := [],
    lastTry := 0, lastOk := 0, failStreak := 0, lastError := Excerpt.of "" }

def Shared.Inv (s : Shared) : Prop := s.feed.PollsBelow s.polls ∧ s.feed.WF ∧ s.view.WF

instance (s : Shared) : Decidable s.Inv := by
  unfold Shared.Inv Feed.PollsBelow Feed.WF View.WF KeyMap.WF; infer_instance

def Shared.checked? (s : Shared) : Option {s : Shared // s.Inv} :=
  if h : s.Inv then some ⟨s, h⟩ else none

inductive Poll (owner : String)
  | ok (now : Epoch) (fixed : Fixed) (reads : List (HeadRead owner))
  | failed (now : Epoch) (why : Excerpt)

def Shared.facts (owner : String) (fixed : Fixed) (reads : List (HeadRead owner)) : List Fact :=
  let posts := fixed.posts ++ reads.flatMap fun h => match h.reviews with
    | .ok rs => rs
    | .error _ => []
  (posts.filter fun p => p.login == owner && counts p).map (Fact.post ∘ Post.of) ++
    fixed.closed.map .closed ++ fixed.refused.map (fun x => .refused x fixed.serverNow)

/-- The ages after a poll, for the heads of `Plan.heads` that the same poll did not close: a head
first seen now starts its clock, a head gone is forgotten, each per-head read that failed adds a
miss for its route and one that succeeded clears them, and a second look that succeeded records
what it found. A head whose sha the runs page shows a run for is marked `runFound`. Apart
from that, a failed or absent look leaves the second look as it was. -/
def Shared.nextAges {owner : String} (now : Epoch) (prev : KeyMap (Pr × String) HeadAge)
    (fixed : Fixed) (reads : List (HeadRead owner)) : KeyMap (Pr × String) HeadAge :=
  panic! "not implemented"

def Shared.step (r : Rules) (owner : String) (s : Shared) : Poll owner → Shared
  | .failed now why =>
    { s with lastTry := now, failStreak := s.failStreak + 1, lastError := why }
  | .ok now fixed reads =>
    let ages := Shared.nextAges now s.ages fixed reads
    { s with
      polls := s.polls + 1
      view := View.of r now s.view fixed reads ages
      feed := s.feed.add (s.polls + 1) fixed.serverNow (Shared.facts owner fixed reads)
      main := fixed.main
      ages, lastTry := now, lastOk := now, failStreak := 0 }

def StartHasInv : Prop := ∀ repo owner gen, (Shared.start repo owner gen).Inv

def FailedPollKeepsTheView : Prop :=
  ∀ (r : Rules) owner (s : Shared) now why,
    let t := s.step r owner (.failed now why)
    t.view = s.view ∧ t.feed = s.feed ∧ t.polls = s.polls ∧ t.gen = s.gen

def FailuresCount : Prop :=
  ∀ (r : Rules) owner (s : Shared) (p : Poll owner),
    (s.step r owner p).failStreak = match p with
      | .failed .. => s.failStreak + 1
      | .ok .. => 0

def PollsCountSuccesses : Prop :=
  ∀ (r : Rules) owner (s : Shared) now fixed reads,
    (s.step r owner (.ok now fixed reads)).polls = s.polls + 1

def StepKeepsTheGeneration : Prop :=
  ∀ (r : Rules) owner (s : Shared) (p : Poll owner), (s.step r owner p).gen = s.gen

def StepKeepsInv : Prop :=
  ∀ (r : Rules) owner (s : Shared) (p : Poll owner), s.Inv → (s.step r owner p).Inv

def TheFeedIgnoresTheLocalClock : Prop :=
  ∀ (r : Rules) owner (s : Shared) now now' fixed reads,
    (s.step r owner (.ok now fixed reads)).feed = (s.step r owner (.ok now' fixed reads)).feed

def OnlyTheOwnersPostsAreKept : Prop :=
  ∀ (r : Rules) owner (s : Shared) now fixed (reads : List (HeadRead owner)) (e : Entry) p,
    e ∈ (s.step r owner (.ok now fixed reads)).feed.entries → e ∉ s.feed.entries →
    e.fact = .post p →
    ∃ q, (q ∈ fixed.posts ∨ ∃ h ∈ reads, ∃ rs, h.reviews = .ok rs ∧ q ∈ rs) ∧
      q.login = owner ∧ counts q = true ∧ Post.of q = p

def MissesCountFailedReads : Prop :=
  ∀ {owner : String} now prev fixed (reads : List (HeadRead owner)) (h : HeadRead owner)
    (route : HeadRoute),
    h ∈ reads → HeadRead.alone fixed reads h →
    let key := (h.head.pr, h.head.sha.text)
    let before := ((prev.get? key).map (·.missesOf route)).getD 0
    ∃ a, (Shared.nextAges now prev fixed reads).get? key = some a ∧
      a.missesOf route = match h.ok? route with
        | some true => 0
        | some false => before + 1
        | none => before

def NoRunFoundNeedsASuccessfulLook : Prop :=
  ∀ {owner : String} now prev fixed (reads : List (HeadRead owner)) (pr : Pr) (sha : String) a,
    (Shared.nextAges now prev fixed reads).get? (pr, sha) = some a → a.look = .noRunFound →
    (prev.get? (pr, sha)).map (·.look) = some .noRunFound ∨
      ∃ h ∈ reads, h.head.pr = pr ∧ h.head.sha.text = sha ∧
        ∃ runs, h.look = some (.ok runs) ∧ runs.any (·.sha == sha) = false

def AFailedLookMovesNothing : Prop :=
  ∀ {owner : String} now prev fixed (reads : List (HeadRead owner)) (h : HeadRead owner) a,
    h ∈ reads → HeadRead.alone fixed reads h → h.ok? .look ≠ some true →
    fixed.runs.any (·.sha == h.head.sha.text) = false →
    prev.get? (h.head.pr, h.head.sha.text) = some a →
    ((Shared.nextAges now prev fixed reads).get? (h.head.pr, h.head.sha.text)).map (·.look) =
      some a.look

def ARunOnThePageIsFound : Prop :=
  ∀ {owner : String} now prev fixed (reads : List (HeadRead owner)) (pr : Pr) (sha : String) a,
    (Shared.nextAges now prev fixed reads).get? (pr, sha) = some a →
    fixed.runs.any (·.sha == sha) = true → a.look = .runFound

def AReReadAddsNoPostOrClose : Prop :=
  ∀ (r : Rules) owner (s : Shared) now now' fixed (reads : List (HeadRead owner)) (t' : Epoch),
    s.Inv → fixed.serverNow ≤ t' →
    let t := s.step r owner (.ok now fixed reads)
    ∀ e ∈ (t.step r owner (.ok now' { fixed with serverNow := t' } reads)).feed.newFor
        (.after t.polls),
      ∃ x seen, e.fact = .refused x seen

end MitosGate.Watch
