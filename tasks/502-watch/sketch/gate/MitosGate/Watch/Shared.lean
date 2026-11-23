import MitosGate.Watch.View
import MitosGate.Watch.Feed

/-! UNCHECKED SKETCH (#502). The one observation a clone shares, and the step one poll makes.

Whoever waits polls, under a short lease (`Store.withLease`), when the observation is older than
the poll interval. Inside the lease the poller reads `observed.json` again and polls only if a
poll is still due, then steps from what it just read, so two waiters never step from the same
state and every poll number is used once (PR 8's `lease-race` fault case; an IO property, tested,
not proved). A poll reads REST once for every consumer of the clone, so the REST reads no longer
grow with the number of waiters. The step is pure: `WatchCli` runs the routes, the readers turn
answers into `Fixed` and `HeadRead`s, and `step` folds them in. A failed poll changes nothing but
the failure count and the last error, so a consumer's view never moves on what it did not read.

The generation is 32 random hex digits (`IO.getRandomBytes 16`), made when the state file is made
anew (first use, or after a bad file was quarantined). Every consumer mark and every write record
carries it; a mismatch resets that consumer with a visible line (`Deliver`).

A state read from disk is trusted only after `Shared.checked?` finds `Inv` on it: `Inv` is
decidable, and `Store` quarantines a file that decodes but fails it, exactly as one that does not
decode. So the statements that assume `Inv` (`AnAckedOfferHasNothingNew`) hold for every state a
wait acts on: the start has it (`StartHasInv`), a step keeps it (`StepKeepsInv`), and a file
without it is never used. Layout copies `Snapshot/Obs.lean`. -/

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

/-- No local time: the feed starts with no cursor and takes GitHub's `Date` at the first poll. -/
def Shared.start (repo owner gen : String) : Shared :=
  { repo, owner, gen, polls := 0, view := {}, feed := Feed.start, main := "", ages := [],
    lastTry := 0, lastOk := 0, failStreak := 0, lastError := Excerpt.of "" }

/-- Every entry and the prune mark name a poll this state has made, each key is held once, and
every map of the view holds each key once. `Deliver` relies on it: an offer that covers `polls`
leaves nothing new in the feed. -/
def Shared.Inv (s : Shared) : Prop := s.feed.PollsBelow s.polls ∧ s.feed.WF ∧ s.view.WF

/-- Each part is a bounded `∀` over a list, a `≤` or a `Nodup` over a type with `DecidableEq`. -/
instance (s : Shared) : Decidable s.Inv := by
  unfold Shared.Inv Feed.PollsBelow Feed.WF View.WF KeyMap.WF; infer_instance

/-- The only way a state read from disk reaches a wait. -/
def Shared.checked? (s : Shared) : Option {s : Shared // s.Inv} :=
  if h : s.Inv then some ⟨s, h⟩ else none

/-- One poll's answers after the readers. -/
inductive Poll (owner : String)
  | ok (now : Epoch) (fixed : Fixed) (reads : List (HeadRead owner))
  | failed (now : Epoch) (why : Excerpt)

/-- The owner's posts that count, every close, and every item a post or close reader could not
read, stamped with GitHub's time of this poll. An empty `COMMENTED` review wrapper is not a post
(`Voice.counts`), as in the bash watcher. A head's reviews read that failed adds nothing here; it
counts a miss in `nextAges` and becomes an `unread` line after `unreadAfter` polls. -/
def Shared.facts (owner : String) (fixed : Fixed) (reads : List (HeadRead owner)) : List Fact :=
  let posts := fixed.posts ++ reads.flatMap fun h => match h.reviews with
    | .ok rs => rs
    | .error _ => []
  (posts.filter fun p => p.login == owner && counts p).map (Fact.post ∘ Post.of) ++
    fixed.closed.map .closed ++ fixed.refused.map (fun x => .refused x fixed.serverNow)

/-- The ages after a poll, for the heads of `Plan.heads` that the same poll did not close: a head
first seen now starts its clock, a head gone is forgotten, each per-head read that failed adds a
miss for its route and one that succeeded clears them, and a second look that succeeded records
what it found. A head whose sha the runs page shows a run for is marked `runFound`, so a run that
later scrolls off the newest-100 page raises no `noRun` (the bash watcher's `ci-ok` cache). Apart
from that, a failed or absent look leaves the second look as it was. -/
def Shared.nextAges {owner : String} (now : Epoch) (prev : KeyMap (Pr × String) HeadAge)
    (fixed : Fixed) (reads : List (HeadRead owner)) : KeyMap (Pr × String) HeadAge :=
  panic! "not implemented"

/-- `now` is the local clock, which times the wait and the age of a head; the feed takes only
`fixed.serverNow`. -/
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

/-- The local clock of a poll never reaches the feed. -/
def TheFeedIgnoresTheLocalClock : Prop :=
  ∀ (r : Rules) owner (s : Shared) now now' fixed reads,
    (s.step r owner (.ok now fixed reads)).feed = (s.step r owner (.ok now' fixed reads)).feed

/-- Only the owner's posts that count enter the feed: posts of other logins (bots, outside
accounts) are not read into the watcher at all, as today. -/
def OnlyTheOwnersPostsAreKept : Prop :=
  ∀ (r : Rules) owner (s : Shared) now fixed (reads : List (HeadRead owner)) (e : Entry) p,
    e ∈ (s.step r owner (.ok now fixed reads)).feed.entries → e ∉ s.feed.entries →
    e.fact = .post p →
    ∃ q, (q ∈ fixed.posts ∨ ∃ h ∈ reads, ∃ rs, h.reviews = .ok rs ∧ q ∈ rs) ∧
      q.login = owner ∧ counts q = true ∧ Post.of q = p

/-- Each per-head read counts for its own route: a failure adds one miss, a success clears them, a
read not made leaves them. -/
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

/-- The second look says "no run" only after a look that succeeded found none at that sha, now or
at an earlier poll, so a failed `runsAt` read can never raise the `noRun` alarm. -/
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

/-- A head the runs page shows a run for is found, whatever an earlier look said, so a late run
that then scrolls off the page never raises `noRun` (`NoRunNeedsTheSecondLook` needs
`noRunFound`). -/
def ARunOnThePageIsFound : Prop :=
  ∀ {owner : String} now prev fixed (reads : List (HeadRead owner)) (pr : Pr) (sha : String) a,
    (Shared.nextAges now prev fixed reads).get? (pr, sha) = some a →
    fixed.runs.any (·.sha == sha) = true → a.look = .runFound

/-- The same facts read again, at the same or a later `Date`, add no post and no close. Only a
`refused` item can come back, once its day-old entry is pruned while GitHub still lists it, and it
is then told again, once a day. With the same `Date` nothing at all is added
(`TheSameFactsTwiceAddNothing`). This replaces round 2's `TheSameReadTwiceAddsNothing`, which kept
`serverNow` fixed (a real second poll has a later `Date`) and was false for a refused item. -/
def AReReadAddsNoPostOrClose : Prop :=
  ∀ (r : Rules) owner (s : Shared) now now' fixed (reads : List (HeadRead owner)) (t' : Epoch),
    s.Inv → fixed.serverNow ≤ t' →
    let t := s.step r owner (.ok now fixed reads)
    ∀ e ∈ (t.step r owner (.ok now' { fixed with serverNow := t' } reads)).feed.newFor
        (.after t.polls),
      ∃ x seen, e.fact = .refused x seen

end MitosGate.Watch
