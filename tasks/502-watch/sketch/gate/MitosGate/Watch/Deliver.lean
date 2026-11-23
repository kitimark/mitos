import MitosGate.Watch.Wake

/-! UNCHECKED SKETCH (#502). What one consumer is told, when, and how its taking of a batch is
recorded.

Offer and ack. Every end of a wait makes an offer: the mark the consumer would stand at once it
has read the batch. The offer is saved before anything is printed. The consumer takes it only by
passing the trailer's exact `--seen N` on its next wait; any other number takes nothing. A fresh
consumer state starts its offer count at a random six-digit number (`Store`), so a number
remembered from a state file that was since lost or quarantined does not take an unseen offer. So
a batch that a dead monitor or a lost turn never showed is not lost: the next wait without that
number reports again against the old mark, under a `redelivering` line. The offer stores the whole
target mark, so no partial apply is needed: a report is always "acked mark against the current
shared state".

A caller that copies the trailer never spins (`CopiedTrailerNeverSpins`): after the ack, as long as
the polls bring no news (`Shared.noNewsSince`: the same facts read again, `AReReadMovesOnlyHealth`
and `AReReadAddsNoPostOrClose`), the report stays empty (`NoNewsStaysQuiet`) and the wait blocks
to its deadline. Only an alarm that time starts (a head reaching `ciMinutes` with no run, a run
queued too long, a read failing `unreadAfter` times) or a refused item told again a day later can
wake it, and that is news. A caller that ignores the trailer gets one replay, within one coalescing
window (`AnUntakenOfferIsReplayed`), then its later waits block until news or the deadline
(`IgnoredTrailerReplaysOnce`), and each of their batches still carries everything since its last
taken offer, so such a caller's batches grow and it never ends quiet. Both guarantees hold only for
a caller that runs the text after `next: ` exactly: `HANDOVER.md` says so, and PR 13 writes it into
the rules with what each exit code asks of the caller.

The end of a wait is one pure step, `finish`: the batch and the offer come from one consumer state
and one shared state, so the offer never marks a state its batch did not report
(`OfferMarksTheReportedState`). `WatchCli` runs it under the consumer's lock (`Store`).

What is told. `report` lists every notable change in scope (`Change.notable`), every new post that
is not quiet, every new close in scope that the consumer's own live writes do not explain, every
new item a reader could not read, and the notes. `wakes` on each item decides only whether it ends
the wait early. An item that does not wake (an outside change under `rideAlong`) is still shown:
a wait whose report holds any item never ends quiet or blind, it delivers at its deadline, so the
offer of a quiet or blind end passes nothing unshown (`QuietEndAcksNothingUnshown`).

`nextMove` is the whole waiting policy as a pure function of one moment, and `Moment.of` builds the
moment from what the wait holds. Words that may be the owner's go out at once: typed words, a
review-route post no app names and no one recorded (it may be the owner's review words; an
unrecorded agent reply there looks the same and goes out at once too), and a post a reader could
not read. Every other waking item, an app's post included, waits one coalescing window (60 s, one
poll) so a burst of check results is one batch. A quiet end needs an empty report and a successful
read within one interval, one poll budget and `freshSlack` of the deadline; otherwise the wait
ends blind and says so. At any moment one poll budget past its deadline, the decision is to end
(`EndsWithinOneBudget`); a poll in flight is bounded by `Gh`'s timeout, which is tested, not
proved. Layout copies `LandAnswer` and `CheatsSlot`.

PR 7b writes this file up to `waking` and the statements about offers, acks and what is told;
PR 7c adds the cut, `Moment`, `nextMove`, `finish` and the statements on them. -/

namespace MitosGate.Watch

open Land (Pr)

structure Mark where
  gen : String
  view : View
  feed : FeedMark
  toldDown : Bool
  deriving DecidableEq

/-- The poll a mark's feed position names; a write record is live for the batch reported from it. -/
def Mark.poll (m : Mark) : Nat :=
  match m.feed with
  | .after p => p
  | .since _ => 0

/-- A new or reset consumer starts from the empty view, so it is told the current state, and from
`since` in the feed: the feed's floor (a day back, `Feed.floor`), or `--since` for a new consumer
whose caller gives one. A `--since` older than the floor is told as a gap (`Feed.gap`). -/
def Mark.fresh (gen : String) (since : Epoch) : Mark := ⟨gen, {}, .since since, false⟩

/-- A mark applies to a shared state of its generation that has made at least the mark's poll.
Anything else is a reset: another generation, or a mark ahead of the state (a restored copy of
`observed.json`, or a crash that kept a consumer's rename and lost the shared one). -/
def Mark.fits (m : Mark) (s : Shared) : Bool := m.gen == s.gen && decide (m.poll ≤ s.polls)

inductive Pending
  | nothing
  | offered (number : Nat) (mark : Mark) (repeats : Nat)
  deriving DecidableEq

structure ConsumerState where
  acked : Mark
  pending : Pending
  offers : Nat
  deriving DecidableEq

/-- A consumer state that has taken no offer yet. `base` is the random six-digit number `Store`
draws when it makes `state.json`, so a number remembered from a state file that was since lost does
not take an unseen offer. This is the only constructor `Store` uses for a new state. -/
def ConsumerState.fresh (acked : Mark) (base : Nat) : ConsumerState := ⟨acked, .nothing, base⟩

def ConsumerState.ack (c : ConsumerState) (seen : Option Nat) : ConsumerState :=
  match c.pending, seen with
  | .offered n m _, some k => if n = k then { c with acked := m, pending := .nothing } else c
  | _, _ => c

def downAfter : Nat := 5

def Shared.mark (s : Shared) : Mark :=
  ⟨s.gen, s.view, .after s.polls, decide (downAfter ≤ s.failStreak)⟩

/-- The offer an end of a wait makes. A replayed offer counts its repeats. -/
def ConsumerState.offer (c : ConsumerState) (s : Shared) : ConsumerState :=
  let repeats := match c.pending with
    | .offered _ _ r => r + 1
    | .nothing => 0
  { c with pending := .offered (c.offers + 1) s.mark repeats, offers := c.offers + 1 }

/-- The stale-tool notice is not a note: `Render.batchLines` appends it to a batch that is printed
anyway, so it can never wake a wait or end one alone. -/
inductive Note
  | reset
  | gap
  | down (polls : Nat) (since : Epoch) (why : Excerpt)
  | up
  | redelivering (number : Nat) (repeats : Nat)
  deriving DecidableEq

inductive Item
  | change (c : Change)
  | post (p : Post)
  | closed (c : ClosedPull)
  | gone (pr : Pr) (author : Author)
  | refused (x : Refused)
  | note (n : Note)
  deriving DecidableEq

structure Told where
  item : Item
  tier : Tier
  wakes : Bool
  deriving DecidableEq

/-- What the consumer reads with its acked mark and the records of itself and its class. -/
structure Records where
  posts : List PostRecord
  writes : List WriteRecord
  deriving DecidableEq

/-- The writes that still explain changes for a report from `acked`. -/
def liveWrites (rec : Records) (s : Shared) (acked : Mark) : List Write :=
  (rec.writes.filter (·.live s.gen acked.poll)).map (·.write)

/-- A close of `cl` in the feed that is new for `acked`. -/
def newClose (s : Shared) (acked : Mark) (cl : ClosedPull) : Prop :=
  ∃ e ∈ s.feed.newFor acked.feed, e.fact = .closed cl

/-- The report of `c` from `acked` against `s`.
* A mark that does not fit `s` (`Mark.fits`) reports as `Mark.fresh s.gen s.feed.floor`, behind a
  `reset` note.
* Changes: the view diff, notable, in scope (`Scope.coversChange`), not explained by the
  consumer's live writes, each with `wakes := ch.wakes o`. A pull that left the open list is one
  `closed` item for each new close of it in the feed (`wakes := cl.author.wakes o`), nothing when
  the consumer's own live write explains that close, and a `gone` item (`wakes := ch.wakes o`) when
  the feed has no new close of it. New closes whose pull never showed in the diff (opened and
  closed between two marks, or closed and reopened) are `closed` items too.
* Posts: the feed's new entries, in scope, not quiet, in tier `words`, waking.
* Refused items: the feed's new entries whose thread is in scope or unknown, in tier `words`,
  waking.
* Notes: `gap` when `s.feed.gap acked.feed`; `down` when `acked.toldDown` is false and the streak
  has reached `downAfter`; `up` when `acked.toldDown` is true and the streak is below it;
  `redelivering n r` when `pending` is `.offered n _ r`, waking only when `r = 0`. Every note but a
  repeated `redelivering` wakes. -/
def report (o : OutsidePolicy) (c : Consumer) (rec : Records) (acked : Mark) (pending : Pending)
    (s : Shared) : List Told :=
  panic! "not implemented"

/-- Whether the report should end the wait. Against the acked mark, except after a replay that was
itself not taken: then only what is new since that offer wakes, so a caller that never passes
`--seen` gets one replay (after one coalescing window, since the `redelivering` note is not owner
words) and then blocks until news or its deadline. The printed batch is still the whole report
against the acked mark. -/
def waking (o : OutsidePolicy) (c : Consumer) (rec : Records) (acked : Mark) (pending : Pending)
    (s : Shared) : Bool :=
  match pending with
  | .offered _ m r =>
    if 1 ≤ r then (report o c rec m .nothing s).any (·.wakes)
    else (report o c rec acked pending s).any (·.wakes)
  | .nothing => (report o c rec acked .nothing s).any (·.wakes)

def Told.isWords (t : Told) : Bool := t.tier == .words
def Told.isNote (t : Told) : Bool := match t.item with
  | .note _ => true
  | _ => false

/-- A waking item that may be the owner's words: a post no app names (typed, or untold on a review
route, where the owner's review words and an unrecorded agent reply look the same) or a post a
reader could not read. Only these skip the coalescing window; an app's post waits it like other
news. So the owner's review-thread words wait at most one poll, as typed words do. -/
def Told.skipsWindow (t : Told) : Bool :=
  t.wakes && match t.item with
    | .post p => match p.speaker with
      | .app _ => false
      | _ => true
    | .refused x => match x.kind with
      | .post _ => true
      | .close => false
    | _ => false

/-- A line about an owned head: its checks. -/
def Told.isHead (t : Told) : Bool := match t.item with
  | .change (.head _) => true
  | _ => false

structure Batch where
  shown : List Told
  more : Nat
  deriving DecidableEq

/-- Every words line and every note, then head lines, then other `owned` lines, then `outside`,
up to `cap` lines; `more` counts the rest. So a fresh consumer with many open pull requests sees
their finished checks before their `opened` lines. What is cut is absorbed by the offer, as the
bash watcher's cap was, and the `more` line says to read the rest over REST. An owned close or
`gone` ranks after the head lines, so more than `cap` head lines can cut it; ranking it with the
notes is deferred to PR 7c (`tasks/502-watch.md`, deferrals). -/
def cut (cap : Nat) (ts : List Told) : Batch :=
  let always := ts.filter fun t => t.isWords || t.isNote
  let rest := ts.filter fun t => !t.isWords && !t.isNote
  let ranked := rest.filter (·.isHead) ++
    rest.filter (fun t => !t.isHead && t.tier == .owned) ++
    rest.filter (fun t => !t.isHead && t.tier == .outside)
  ⟨always ++ ranked.take cap, ranked.length - cap⟩

/-- The end of a wait: the batch it prints and the consumer state it saves, both from one consumer
state `cs` and one shared state `s`. So the offer marks the state the batch was reported from
(`OfferMarksTheReportedState`), and taking it acks nothing the batch did not show, apart from what
the `more` line counts. `WatchCli` calls it under the consumer's lock, after `stillMine` and a
re-read of `state.json` (that re-read is `cs`), with the `s` its last step reported from, never a
newer read of `observed.json`. When the report is empty it prints the quiet or blind line that
`nextMove` chose in place of the batch. -/
def finish (o : OutsidePolicy) (c : Consumer) (rec : Records) (cap : Nat) (cs : ConsumerState)
    (s : Shared) : Batch × ConsumerState :=
  (cut cap (report o c rec cs.acked cs.pending s), cs.offer s)

structure Moment where
  now : Epoch
  started : Epoch
  deadline : Epoch
  lastTry : Epoch
  lastOk : Epoch
  failStreak : Nat
  waking : Bool
  words : Bool
  told : Bool
  firstWake : Epoch
  leaseBusy : Bool
  deriving DecidableEq, Repr

def interval : Nat := 60
def window : Nat := 60
def pollBudget : Nat := 90
/-- Room for the 2 s steps after the last poll a wait may start: that poll starts more than
`pollBudget` and less than `interval + pollBudget` plus one step before the deadline. -/
def freshSlack : Nat := 10

/-- The moment a wait acts on. `ts` is this step's report, `waking` is `waking ...` of this step,
`firstWake` the first step of this wait at which it held (`WatchCli` keeps it), and `leaseBusy`
whether this wait's last try at the lease, under two seconds ago, found it held. `words` says that
a waking item may be the owner's words (`Told.skipsWindow`). -/
def Moment.of (now started deadline : Epoch) (s : Shared) (ts : List Told) (waking : Bool)
    (firstWake : Option Epoch) (leaseBusy : Bool) : Moment :=
  { now, started, deadline, lastTry := s.lastTry, lastOk := s.lastOk, failStreak := s.failStreak,
    waking, words := ts.any Told.skipsWindow, told := !ts.isEmpty,
    firstWake := firstWake.getD now, leaseBusy }

inductive Move
  | deliver
  | poll
  | sleep (ms : Nat)
  | quiet
  | blind
  deriving DecidableEq, Repr

def pollDue (m : Moment) : Bool :=
  decide (m.now < m.lastTry) || decide (m.lastTry + interval ≤ m.now)

/-- At the end, the observation is fresh when a read succeeded within one interval, one poll budget
and `freshSlack` of the deadline (of now, before it) and GitHub is not failing. Measured against
the deadline, so a healthy wait whose first step past the deadline comes a second late does not end
blind (`AHealthyWaitNeverEndsBlind`). A wait whose polls all failed for longer ends blind. -/
def Moment.fresh (m : Moment) : Bool :=
  decide (min m.now m.deadline ≤ m.lastOk + interval + pollBudget + freshSlack) &&
    decide (m.failStreak < downAfter)

/-- At the deadline: a report that still holds items (none of them woke) is delivered, so nothing
is acked unseen; only an empty report ends quiet or blind. -/
def Moment.ending (m : Moment) : Move :=
  if m.told then .deliver else if m.fresh then .quiet else .blind

def nextMove (m : Moment) : Move :=
  if m.waking && (m.words || decide (m.firstWake + window ≤ m.now) || decide (m.deadline ≤ m.now))
  then .deliver
  else if m.deadline + pollBudget ≤ m.now then m.ending
  else if pollDue m && (decide (m.now + pollBudget ≤ m.deadline) || decide (m.lastTry < m.started))
  then (if m.leaseBusy then .sleep 2000 else .poll)
  else if m.deadline ≤ m.now then m.ending
  else .sleep 2000

/-! Offer and ack. -/

def AckOnlyTakesTheOffer : Prop :=
  ∀ (c : ConsumerState) seen, (c.ack seen).acked = c.acked ∨
    ∃ n m r, c.pending = .offered n m r ∧ (c.ack seen).acked = m

def AckNeedsTheNumber : Prop :=
  ∀ (c : ConsumerState) n m r, c.pending = .offered n m r →
    (c.ack none) = c ∧ ∀ k, k ≠ n → c.ack (some k) = c

def AnUntakenOfferIsReplayed : Prop :=
  ∀ o c rec acked n m (s : Shared),
    ∃ t ∈ report o c rec acked (.offered n m 0) s, t.item = .note (.redelivering n 0) ∧
      t.wakes = true

/-- `s` holds no news for a consumer standing at `m`: `m` fits, the view has the same lookups, no
feed entry is from a poll after `m`'s, there is no gap, and the down flag matches the streak. A
poll that reads the same facts again leaves a state so (`AReReadMovesOnlyHealth`,
`AReReadAddsNoPostOrClose`), except for an alarm that time starts or a refused item told again a
day later, which are news. -/
def Shared.noNewsSince (m : Mark) (s : Shared) : Prop :=
  m.fits s = true ∧ m.view.Equiv s.view ∧
    (∃ p, m.feed = .after p ∧ ∀ e ∈ s.feed.entries, e.poll ≤ p) ∧
    s.feed.gap m.feed = false ∧ m.toldDown = decide (downAfter ≤ s.failStreak)

/-- EXPENSIVE: it unfolds `report`. The view diff is empty (`DiffNamesOnlyChanges` with the
`Equiv`), the feed has no new entry, and every note's condition is false. Proof plan, not a weaker
statement: prove it for the change, feed and note parts of `report` separately and conclude by
`List.append_eq_nil`. -/
def NoNewsStaysQuiet : Prop :=
  ∀ o c rec (s : Shared) (m : Mark), s.noNewsSince m → report o c rec m .nothing s = []

/-- Short from `NoNewsStaysQuiet`: under `Shared.Inv` the state's own mark has no news. -/
def AnAckedOfferHasNothingNew : Prop :=
  ∀ o c rec (s : Shared), s.Inv → report o c rec s.mark .nothing s = []

/-- Short from `NoNewsStaysQuiet`, across any number of polls that bring no news. -/
def IgnoredTrailerReplaysOnce : Prop :=
  ∀ o c rec acked n m r (s : Shared), 1 ≤ r → s.noNewsSince m →
    waking o c rec acked (.offered n m r) s = false

/-- Short from `NoNewsStaysQuiet`. It holds at every step of the wait, not only before its first
poll: the offer's mark `m` stays without news while the polls read the same facts again. It names
`nextMove`, so PR 7c proves it. -/
def CopiedTrailerNeverSpins : Prop :=
  ∀ o c rec (cs : ConsumerState) (s : Shared) n m r (mo : Moment),
    cs.pending = .offered n m r → s.noNewsSince m →
    mo.waking = waking o c rec (cs.ack (some n)).acked (cs.ack (some n)).pending s →
    mo.now < mo.deadline → nextMove mo ≠ .deliver ∧ nextMove mo ≠ .quiet ∧ nextMove mo ≠ .blind

/-! What is told. -/

def TypedWordsAreTold : Prop :=
  ∀ o c rec acked pending (s : Shared) (e : Entry) (p : Post), acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .post p → p.speaker = .typed →
    c.scope.covers p.thread = true →
    ∃ t ∈ report o c rec acked pending s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

/-- Any new post that is not quiet for this consumer wakes it: another app's post, and a
review-route post no app names and no one recorded. -/
def ANonQuietPostIsTold : Prop :=
  ∀ o c rec acked pending (s : Shared) (e : Entry) (p : Post), acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .post p → c.scope.covers p.thread = true →
    quiet c rec.posts p = false →
    ∃ t ∈ report o c rec acked pending s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

/-- EXPENSIVE: it follows a change through scope, echo and the close merge. Proof plan: split by
`Change` constructor, and for a pull that left the open list by whether the feed holds a new close
of it. A pull that left the open list is told as its close (waking as the close's author) or as
`gone` (waking as the pull's author in the acked view), so no author needs to agree across routes.
The hypothesis on closes is the writer's own recorded merge or close, which
`OnlyAMergeExplainsAMerge` limits. A close that is not new was told with the batch that read it:
`View.of` drops a pull its own poll closes (`PullsAreTheOpenPullsRead`), so a pull never leaves the
view a poll after its close was read. -/
def EveryNotableChangeIsTold : Prop :=
  ∀ o c rec acked pending (s : Shared) (ch : Change), acked.fits s = true →
    ch ∈ View.diff acked.view s.view → ch.notable = true → c.scope.coversChange ch = true →
    explains (liveWrites rec s acked) ch = false →
    (∀ cl, ch.leaves = some cl.number → newClose s acked cl →
      explainsClose (liveWrites rec s acked) cl = false) →
    ∃ t ∈ report o c rec acked pending s,
      (t.item = .change ch ∧ t.wakes = ch.wakes o) ∨
      (∃ cl, t.item = .closed cl ∧ ch.leaves = some cl.number ∧ newClose s acked cl ∧
        t.wakes = cl.author.wakes o) ∨
      (∃ p a, t.item = .gone p a ∧ ch.leaves = some p ∧ t.wakes = ch.wakes o)

/-- A close in the feed is told even when its pull never showed in the view diff. -/
def ANewCloseIsToldUnlessItsWriterRecordedIt : Prop :=
  ∀ o c rec acked pending (s : Shared) (cl : ClosedPull), acked.fits s = true →
    newClose s acked cl → c.scope.covers cl.number = true →
    explainsClose (liveWrites rec s acked) cl = false →
    ∃ t ∈ report o c rec acked pending s, t.item = .closed cl ∧ t.wakes = cl.author.wakes o

def OneItemPerClose : Prop :=
  ∀ o c rec acked pending (s : Shared) (cl : ClosedPull),
    (∃ t ∈ report o c rec acked pending s, t.item = .closed cl) →
    (∀ a, ∀ t ∈ report o c rec acked pending s, t.item ≠ .gone cl.number a) ∧
    ∀ d : Delta Pr PullFacts, d.key = cl.number → d.after = none →
      ∀ t ∈ report o c rec acked pending s, t.item ≠ .change (.pull d)

/-- An item a reader could not read is told once, as words, to every consumer whose scope covers
its thread, and to every consumer when its thread is unknown. -/
def ARefusedItemIsTold : Prop :=
  ∀ o c rec acked pending (s : Shared) (e : Entry) (x : Refused) seen, acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .refused x seen → x.thread.all c.scope.covers = true →
    ∃ t ∈ report o c rec acked pending s, t.item = .refused x ∧ t.tier = .words ∧ t.wakes = true

/-- A consumer scoped to some pull requests hears only about them, items of no known thread, and
notes. -/
def AScopedConsumerHearsOnlyItsPulls : Prop :=
  ∀ o (c : Consumer) rec acked pending (s : Shared) ns, c.scope = .pulls ns →
    ∀ t ∈ report o c rec acked pending s,
      (∃ ch, t.item = .change ch ∧ ∃ p ∈ ns, ch.pr? = some p) ∨
      (∃ p, t.item = .post p ∧ p.thread ∈ ns) ∨ (∃ cl, t.item = .closed cl ∧ cl.number ∈ ns) ∨
      (∃ p a, t.item = .gone p a ∧ p ∈ ns) ∨
      (∃ x, t.item = .refused x ∧ ∀ p ∈ x.thread, p ∈ ns) ∨ t.isNote = true

def GapIsNeverSilent : Prop :=
  ∀ o c rec acked pending (s : Shared), acked.fits s = true → s.feed.gap acked.feed = true →
    ∃ t ∈ report o c rec acked pending s, t.item = .note .gap ∧ t.wakes = true

/-- Another generation, and a mark ahead of the shared state, both reset with a line. -/
def ResetIsNeverSilent : Prop :=
  ∀ o c rec acked pending (s : Shared), acked.fits s = false →
    ∃ t ∈ report o c rec acked pending s, t.item = .note .reset ∧ t.wakes = true

def AFreshConsumerHearsFinishedChecks : Prop :=
  ∀ o c rec pending (s : Shared) since (p : Pr) (h : HeadFacts) n r,
    s.view.heads.get? p = some h → h.checks.get n = some (.done r) → c.scope.covers p = true →
    ∃ t ∈ report o c rec (Mark.fresh s.gen since) pending s, ∃ d, t.item = .change (.head d) ∧
      d.key = p ∧ t.wakes = true

def AFailingGitHubIsTold : Prop :=
  ∀ o c rec acked pending (s : Shared), acked.toldDown = false → downAfter ≤ s.failStreak →
    ∃ t ∈ report o c rec acked pending s, (∃ k e w, t.item = .note (.down k e w)) ∧ t.wakes = true

/-! The cut. -/

def WordsAreNeverCut : Prop :=
  ∀ cap ts, ∀ t ∈ ts, t.tier = .words → t ∈ (cut cap ts).shown

def NotesAreNeverCut : Prop :=
  ∀ cap ts, ∀ t ∈ ts, t.isNote = true → t ∈ (cut cap ts).shown

/-- The witness is not a head line: `cut` ranks every head line first whatever its tier, and
`Told` is a free structure (round 3's counterexample: an `outside` head line shown at `cap = 1`
with an `owned` line cut). `report` makes head lines only for owned heads. -/
def OutsideIsCutFirst : Prop :=
  ∀ cap ts,
    (∃ t ∈ (cut cap ts).shown, t.tier = .outside ∧ t.isNote = false ∧ t.isHead = false) →
    ∀ t ∈ ts, t.tier = .owned → t ∈ (cut cap ts).shown

def TheCutCountsEveryLine : Prop :=
  ∀ cap ts, (cut cap ts).shown.length + (cut cap ts).more = ts.length

/-- A head line is cut only when every line shown past the words and notes is a head line too. -/
def ChecksAreCutLast : Prop :=
  ∀ cap ts, (∃ t ∈ ts, t.isHead = true ∧ t ∉ (cut cap ts).shown) →
    ∀ u ∈ (cut cap ts).shown, (u.isWords || u.isNote || u.isHead) = true

/-- The end prints and saves from one shared state: the batch is the cut of the report from the
consumer state it saves over, and the offer marks that same `s`. With `AnAckedOfferHasNothingNew`,
taking the offer leaves nothing between the batch and the mark. -/
def OfferMarksTheReportedState : Prop :=
  ∀ o c rec cap (cs : ConsumerState) (s : Shared),
    (finish o c rec cap cs s).1 = cut cap (report o c rec cs.acked cs.pending s) ∧
    ∃ r, (finish o c rec cap cs s).2 =
      { cs with pending := .offered (cs.offers + 1) s.mark r, offers := cs.offers + 1 }

/-! When to stop waiting. -/

/-- Only words that may be the owner's skip the window: a waking post that no app names, or a
waking post a reader could not read. -/
def OnlyPossibleOwnerWordsSkipTheWindow : Prop :=
  ∀ now started deadline (s : Shared) ts waking firstWake busy,
    (Moment.of now started deadline s ts waking firstWake busy).words = true →
    ∃ t ∈ ts, t.wakes = true ∧
      ((∃ p, t.item = .post p ∧ ∀ a, p.speaker ≠ .app a) ∨
        ∃ x pl, t.item = .refused x ∧ x.kind = .post pl)

def OwnerWordsAreNotHeld : Prop :=
  ∀ m : Moment, m.waking = true → m.words = true → nextMove m = .deliver

def WakeIsDelivered : Prop :=
  ∀ m : Moment, m.waking = true → m.deadline ≤ m.now → nextMove m = .deliver

def NeverEarlyEmpty : Prop :=
  ∀ m : Moment, (nextMove m = .quiet ∨ nextMove m = .blind) →
    m.deadline ≤ m.now ∧ m.waking = false ∧ m.told = false

/-- A quiet or blind end happens only over an empty report, so the offer it saves (`s.mark`) passes
nothing that was not shown: under `rideAlong` an outside change that never woke is delivered at the
deadline instead of being acked unseen. -/
def QuietEndAcksNothingUnshown : Prop :=
  ∀ now started deadline (s : Shared) ts waking firstWake busy,
    let m := Moment.of now started deadline s ts waking firstWake busy
    (nextMove m = .quiet ∨ nextMove m = .blind) → ts = []

def EndsWithinOneBudget : Prop :=
  ∀ m : Moment, m.deadline + pollBudget ≤ m.now →
    nextMove m = .deliver ∨ nextMove m = .quiet ∨ nextMove m = .blind

def QuietOnlyAfterAFreshRead : Prop :=
  ∀ m : Moment, nextMove m = .quiet →
    min m.now m.deadline ≤ m.lastOk + interval + pollBudget + freshSlack ∧
      m.failStreak < downAfter

def BlindOnlyWithoutAFreshRead : Prop :=
  ∀ m : Moment, nextMove m = .blind →
    m.lastOk + interval + pollBudget + freshSlack < min m.now m.deadline ∨
      downAfter ≤ m.failStreak

/-- A wait whose last success is within the designed gap of its deadline, with GitHub not failing,
never ends blind, at whatever step it reaches the end. The two statements above only restate the
branch; this one says a healthy wait ends quiet (fixture `aHealthyWaitAtTheDeadlineEndsQuiet`). -/
def AHealthyWaitNeverEndsBlind : Prop :=
  ∀ m : Moment, m.failStreak < downAfter →
    m.deadline ≤ m.lastOk + interval + pollBudget + freshSlack → nextMove m ≠ .blind

def TheFirstPollIsAlwaysTried : Prop :=
  ∀ m : Moment, m.waking = false → m.lastTry < m.started → pollDue m = true →
    m.leaseBusy = false → m.now < m.deadline + pollBudget → nextMove m = .poll

def ABusyLeaseNeverPolls : Prop :=
  ∀ m : Moment, m.leaseBusy = true → nextMove m ≠ .poll

def NoPollPastTheBudget : Prop :=
  ∀ m : Moment, nextMove m = .poll →
    (m.now + pollBudget ≤ m.deadline ∨ m.lastTry < m.started) ∧ m.now < m.deadline + pollBudget

def CoalescingNeverPassesOneWindow : Prop :=
  ∀ m : Moment, m.waking = true → m.firstWake + window ≤ m.now → nextMove m = .deliver

namespace Fixture

/-- An outside pull request opened under `rideAlong` wakes nobody, and the wait reaches its
deadline with it in the report: the wait delivers it instead of ending quiet. -/
theorem anOutsidePullRidesToTheDeadline :
    nextMove { now := 1800, started := 0, deadline := 1740, lastTry := 1790, lastOk := 1790,
      failStreak := 0, waking := false, words := false, told := true, firstWake := 1800,
      leaseBusy := false } = .deliver := by decide +kernel

/-- The same moment with an empty report ends quiet. -/
theorem nothingToldEndsQuiet :
    nextMove { now := 1800, started := 0, deadline := 1740, lastTry := 1790, lastOk := 1790,
      failStreak := 0, waking := false, words := false, told := false, firstWake := 1800,
      leaseBusy := false } = .quiet := by decide +kernel

/-- Round 3's moment: every poll succeeded, the last at 1590 (the next was due at 1650, but
1650 + `pollBudget` passes the deadline), and the first step past the deadline is at 1741. Measured
from now it read 151 s old and ended blind; measured from the deadline it is fresh. -/
theorem aHealthyWaitAtTheDeadlineEndsQuiet :
    nextMove { now := 1741, started := 0, deadline := 1740, lastTry := 1590, lastOk := 1590,
      failStreak := 0, waking := false, words := false, told := false, firstWake := 1741,
      leaseBusy := false } = .quiet := by decide +kernel

end Fixture

end MitosGate.Watch
