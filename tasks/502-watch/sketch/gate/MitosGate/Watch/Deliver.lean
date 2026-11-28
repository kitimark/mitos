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
the rules with what each exit code asks of the caller. That text carries the wait's subscription
flags (`Render`, `TheTrailerFlagsReadBack`), so a copied trailer keeps the topic too.

The end of a wait is one pure step, `finish`: the batch and the offer come from one consumer state
and one shared state, so the offer never marks a state its batch did not report
(`OfferMarksTheReportedState`). `WatchCli` runs it under the consumer's lock (`Store`).

What is told. A report has three parts with one owner each:

  report = notes ++ lens (facts)

`facts` is every waking change since the acked mark that the consumer's own live writes do not
explain, every new post that is not quiet, every new close those writes do not explain, and every
new item a reader could not read. It reads no subscription and no app, so it is one list for every
caller with the same mark and records. `notes` is what the caller must hear about its own place
(reset, gap, redelivering, a changed topic) and about the watcher (down, up); no subscription drops
one. `Subscription.lens` keeps the facts of a kind the topic hears about its items, and marks the
kinds that ride along: told, but not ending the wait. A head line is about the checks that newly
finished on it, so it may be both `passed` and `failed`: it is told when the topic hears either,
and it rides only when each of them that the topic hears rides. A wait whose report holds any item
never ends quiet or blind, it delivers at its deadline, so a quiet or blind end acks nothing the
subscription selects (`QuietEndAcksNothingUnshown`), and for a catch-all nothing but `peers`
(`QuietCatchAllHidOnlyPeers`).

Places and topics. The acked mark and the offer number never read the subscription
(`TheOfferIgnoresTheSubscription`), so a caller may change its flags at any re-arm. The offer
records the subscription it was made under, and the ack keeps it as `under`, as data only. A wait
whose topic differs from `under`'s is told so once (`Note.newTopic`, `AChangedTopicIsTold`): facts
before the acked place are not told again, so a wider topic shows only what is new since then. A
narrower topic hides some facts since the acked place, and taking its batch passes them, so the
note counts them (`hiddenBy`); re-arming with the old flags does not bring them back. A copied
trailer carries the same flags, so the note never repeats.

Coverage is one rule, not a theorem over callers. A catch-all (`Topic.catchAll`: a wait with no
`--topics` and no `--on`) is told every fact but `peers` (`TheCatchAllHearsEverything`), and words
that may be the owner's (typed, or an unrecorded review-route post) wake whoever hears `words` about
their thread, whatever it lets ride (`OwnerWordsWakeWhoeverHearsWords`). That a catch-all waits
somewhere is PR 13's rule for the root, because callers in different containers share no state the
tool could check.

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

/-- An offer not yet taken: its number, the mark it would ack, how often it was replayed, and the
subscription of the wait that made it. The subscription is data for `notes` and `status`; `ack`
moves the mark whatever it says. -/
inductive Pending
  | nothing
  | offered (number : Nat) (mark : Mark) (repeats : Nat) (sub : Subscription)
  deriving DecidableEq

/-- `under` is the subscription the acked place was taken under: the offer's, copied at the ack.
It only names what a changed topic newly shows or hides (`Note.newTopic`). -/
structure ConsumerState where
  acked : Mark
  under : Subscription
  pending : Pending
  offers : Nat
  deriving DecidableEq

/-- A consumer state that has taken no offer yet, standing under the subscription of the wait that
made it, so a first wait is never told that its topic changed. `base` is the random six-digit
number `Store` draws when it makes `state.json`, so a number remembered from a state file that was
since lost does not take an unseen offer. This is the only constructor `Store` uses for a new
state. -/
def ConsumerState.fresh (acked : Mark) (sub : Subscription) (base : Nat) : ConsumerState :=
  ⟨acked, sub, .nothing, base⟩

/-- The subscription of the caller's last wait, which `status` prints. -/
def ConsumerState.last (c : ConsumerState) : Subscription :=
  match c.pending with
  | .offered _ _ _ t => t
  | .nothing => c.under

def ConsumerState.ack (c : ConsumerState) (seen : Option Nat) : ConsumerState :=
  match c.pending, seen with
  | .offered n m _ t, some k =>
    if n = k then { c with acked := m, under := t, pending := .nothing } else c
  | _, _ => c

def downAfter : Nat := 5

def Shared.mark (s : Shared) : Mark :=
  ⟨s.gen, s.view, .after s.polls, decide (downAfter ≤ s.failStreak)⟩

/-- The offer an end of a wait makes, under that wait's subscription. A replayed offer counts its
repeats. -/
def ConsumerState.offer (c : ConsumerState) (s : Shared) (sub : Subscription) : ConsumerState :=
  let repeats := match c.pending with
    | .offered _ _ r _ => r + 1
    | .nothing => 0
  { c with pending := .offered (c.offers + 1) s.mark repeats sub, offers := c.offers + 1 }

/-- The stale-tool notice is not a note: `Render.batchLines` appends it to a batch that is printed
anyway, so it can never wake a wait or end one alone. `newTopic was now hidden`: this wait hears
`now`, its acked place was taken under `was`, and taking this batch passes `hidden` facts that
`was` tells and `now` does not (`hiddenBy`). -/
inductive Note
  | reset
  | gap
  | down (polls : Nat) (since : Epoch) (why : Excerpt)
  | up
  | redelivering (number : Nat) (repeats : Nat)
  | newTopic (was now : Topic) (hidden : Nat)
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

/-- Here, before `facts`, because PR 7b's `EveryFactWakes` and `NotesAreNotes` read it. -/
def Told.isNote (t : Told) : Bool := match t.item with
  | .note _ => true
  | _ => false

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

/-- What a line is about, for the consumer whose app is `app`. A note is about the caller's own
place or the watcher's health, so it has no kind and passes every lens. A head line is about the
checks that newly finished on it (`Change.kinds`: `passed`, `failed`, or both); every other line
has one kind. -/
inductive Subject
  | caller
  | kinds (ks : List Kind)
  deriving DecidableEq, Repr

def Item.subject (app : String) : Item → Subject
  | .note _ => .caller
  | .post p => .kinds [p.kind app]
  | .change ch => .kinds ch.kinds
  | .closed cl => .kinds [cl.author.kind]
  | .gone _ a => .kinds [a.kind]
  | .refused x => .kinds [x.lineKind]

/-- Whether an item is about one of the topic's issues or pull requests. A health change about no
pull request (`ci` itself) is for repository-wide topics only, and an unreadable item of unknown
thread is for every topic. -/
def Scope.coversItem (sc : Scope) : Item → Bool
  | .note _ => true
  | .post p => sc.covers p.thread
  | .change ch => sc.coversChange ch
  | .closed cl => sc.covers cl.number
  | .gone pr _ => sc.covers pr
  | .refused x => x.thread.all sc.covers

/-- Whether the caller is told the item at all: the topic hears one of its kinds, about its items. -/
def Subscription.tells (sub : Subscription) (app : String) (i : Item) : Bool :=
  match i.subject app with
  | .caller => true
  | .kinds ks => ks.any sub.topic.hears.has && sub.topic.on.coversItem i

/-- Whether the item rides along: told, but it does not end the wait. It rides only when each of
its kinds that the topic hears rides, so a head line that is both `passed` and `failed` wakes a
root that lets only `failed` ride. `Rides` has no field for `words`, `agents`, `peers` or `pulls`,
so those never ride (`OnlyChecksAlarmsAndOutsideRide`). -/
def Subscription.holds (sub : Subscription) (app : String) (i : Item) : Bool :=
  match i.subject app with
  | .caller => false
  | .kinds ks => ks.all fun k => !sub.topic.hears.has k || sub.rides.has k

def Subscription.lens (sub : Subscription) (app : String) (ts : List Told) : List Told :=
  (ts.filter fun t => sub.tells app t.item).map fun t =>
    { t with wakes := t.wakes && !sub.holds app t.item }

/-- How many of `fs` the topic `was` tells and `now` does not. After a narrowing, taking the batch
passes them unheard, so the `newTopic` note counts them; after a widening that keeps the items,
it is 0. -/
def hiddenBy (app : String) (was now : Topic) (fs : List Told) : Nat :=
  (fs.filter fun t => ({ topic := was } : Subscription).tells app t.item &&
    !({ topic := now } : Subscription).tells app t.item).length

/-- Every fact since `acked` that the consumer's own records do not explain, for any subscription
and any app.
* A mark that does not fit `s` (`Mark.fits`) reads as `Mark.fresh s.gen s.feed.floor`.
* Changes: the view diff, those that wake (`Change.wakes`), not explained by the consumer's live
  writes. A pull that left the open list is one `closed` item for each new close of it in the
  feed, nothing when the consumer's own live write explains that close, and a `gone` item with the
  pull's author in the acked view when the feed has no new close of it. New closes whose pull
  never showed in the diff (opened and closed between two marks, or closed and reopened) are
  `closed` items too.
* Posts: the feed's new entries that are not quiet (`quiet rec.posts`), in tier `words`. A post
  through the consumer's own app is here too; the lens drops it unless the topic hears `peers`.
* Refused items: the feed's new entries, in tier `words`.
Every item wakes (`EveryFactWakes`). Tiers: posts and refused items `words`, changes and closes of
outside pull requests `outside`, the rest `owned`. -/
def facts (rec : Records) (acked : Mark) (s : Shared) : List Told :=
  panic! "not implemented"

/-- `reset` when the mark does not fit `s`; `gap` when `s.feed.gap acked.feed`; `down` when
`acked.toldDown` is false and the streak has reached `downAfter`; `up` when `acked.toldDown` is
true and the streak is below it; `redelivering n r` when `pending` is `.offered n _ r _`, waking
only when `r = 0`; `newTopic was now hidden` when `was ≠ now`, and never when they are equal, so a
copied trailer is not told again (tested by `aWiderTopicIsToldOnce` and the `topics/` cases, not
stated). `report` gives `hidden` (`hiddenBy`; tested by `aNarrowerTopicIsToldWhatItPasses`). Every
note but a repeated `redelivering` wakes. Only notes (`NotesAreNotes`). -/
def notes (was now : Topic) (hidden : Nat) (acked : Mark) (pending : Pending) (s : Shared) :
    List Told :=
  panic! "not implemented"

/-- The report of `c` from `acked` against `s`, for a wait under `sub` whose acked place was taken
under the topic `was`. -/
def report (c : Consumer) (sub : Subscription) (rec : Records) (was : Topic) (acked : Mark)
    (pending : Pending) (s : Shared) : List Told :=
  let fs := facts rec acked s
  notes was sub.topic (hiddenBy c.app was sub.topic fs) acked pending s ++ sub.lens c.app fs

/-- Whether the report should end the wait. Against the acked mark, except after a replay that was
itself not taken: then only what is new since that offer, under the topic it was made under,
wakes, so a caller that never passes `--seen` gets one replay (after one coalescing window, since
the `redelivering` note is not owner words) and then blocks until news or its deadline. The
printed batch is still the whole report against the acked mark. -/
def waking (c : Consumer) (sub : Subscription) (rec : Records) (was : Topic) (acked : Mark)
    (pending : Pending) (s : Shared) : Bool :=
  match pending with
  | .offered _ m r t =>
    if 1 ≤ r then (report c sub rec t.topic m .nothing s).any (·.wakes)
    else (report c sub rec was acked pending s).any (·.wakes)
  | .nothing => (report c sub rec was acked .nothing s).any (·.wakes)

def Told.isWords (t : Told) : Bool := t.tier == .words

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
(`OfferMarksTheReportedState`), and taking it acks nothing the subscription selects that the batch
did not show, apart from what the `more` line counts. `WatchCli` calls it under the consumer's lock, after `stillMine` and a
re-read of `state.json` (that re-read is `cs`), with the `s` its last step reported from, never a
newer read of `observed.json`. When the report is empty it prints the quiet or blind line that
`nextMove` chose in place of the batch. The saved offer records `sub`, and its mark and number do
not read it (`TheOfferIgnoresTheSubscription`). -/
def finish (c : Consumer) (sub : Subscription) (rec : Records) (cap : Nat) (cs : ConsumerState)
    (s : Shared) : Batch × ConsumerState :=
  (cut cap (report c sub rec cs.under.topic cs.acked cs.pending s), cs.offer s sub)

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
the subscription selects is acked unseen; only an empty report ends quiet or blind. -/
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
    ∃ n m r t, c.pending = .offered n m r t ∧ (c.ack seen).acked = m

def AckNeedsTheNumber : Prop :=
  ∀ (c : ConsumerState) n m r t, c.pending = .offered n m r t →
    (c.ack none) = c ∧ ∀ k, k ≠ n → c.ack (some k) = c

def AnUntakenOfferIsReplayed : Prop :=
  ∀ was now hidden acked n m t (s : Shared),
    ∃ u ∈ notes was now hidden acked (.offered n m 0 t) s, u.item = .note (.redelivering n 0) ∧
      u.wakes = true

/-- `s` holds no news for a consumer standing at `m`: `m` fits, the view has the same lookups, no
feed entry is from a poll after `m`'s, there is no gap, and the down flag matches the streak. A
poll that reads the same facts again leaves a state so (`AReReadMovesOnlyHealth`,
`AReReadAddsNoPostOrClose`), except for an alarm that time starts or a refused item told again a
day later, which are news. -/
def Shared.noNewsSince (m : Mark) (s : Shared) : Prop :=
  m.fits s = true ∧ m.view.Equiv s.view ∧
    (∃ p, m.feed = .after p ∧ ∀ e ∈ s.feed.entries, e.poll ≤ p) ∧
    s.feed.gap m.feed = false ∧ m.toldDown = decide (downAfter ≤ s.failStreak)

/-- EXPENSIVE: it unfolds `facts`. The view diff is empty (`DiffNamesOnlyChanges` with the
`Equiv`), the feed has no new entry, and every note's condition is false, the topic's included.
Proof plan, not a weaker statement: `notes` is empty, `facts` is empty for its change, feed and
close parts separately (`List.append_eq_nil`), and the lens of an empty list is empty. -/
def NoNewsStaysQuiet : Prop :=
  ∀ c sub rec (s : Shared) (m : Mark), s.noNewsSince m →
    report c sub rec sub.topic m .nothing s = []

/-- Short from `NoNewsStaysQuiet`: under `Shared.Inv` the state's own mark has no news. -/
def AnAckedOfferHasNothingNew : Prop :=
  ∀ c sub rec (s : Shared), s.Inv → report c sub rec sub.topic s.mark .nothing s = []

/-- Short from `NoNewsStaysQuiet`, across any number of polls that bring no news, for a caller that
keeps the topic its untaken offer was made under. -/
def IgnoredTrailerReplaysOnce : Prop :=
  ∀ c (sub t : Subscription) rec was acked n m r (s : Shared), 1 ≤ r → t.topic = sub.topic →
    s.noNewsSince m → waking c sub rec was acked (.offered n m r t) s = false

/-- Short from `NoNewsStaysQuiet`. It holds at every step of the wait, not only before its first
poll: the offer's mark `m` stays without news while the polls read the same facts again. A copied
trailer gives `t.topic = sub.topic` (`TheTrailerFlagsReadBack`). It names `nextMove`, so PR 7c
proves it. -/
def CopiedTrailerNeverSpins : Prop :=
  ∀ c (sub : Subscription) rec (cs : ConsumerState) (s : Shared) n m r t (mo : Moment),
    cs.pending = .offered n m r t → t.topic = sub.topic → s.noNewsSince m →
    mo.waking = waking c sub rec (cs.ack (some n)).under.topic (cs.ack (some n)).acked
      (cs.ack (some n)).pending s →
    mo.now < mo.deadline → nextMove mo ≠ .deliver ∧ nextMove mo ≠ .quiet ∧ nextMove mo ≠ .blind

/-! What is told: the facts. They read no subscription, so each statement holds for every caller;
`WhatIsToldPassesTheLens` carries one to a report. -/

def TypedWordsAreTold : Prop :=
  ∀ rec acked (s : Shared) (e : Entry) (p : Post), acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .post p → p.speaker = .typed →
    ∃ t ∈ facts rec acked s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

/-- Any new post that is not quiet for this consumer is a fact: another app's post, a post through
its own app, and a review-route post no app names and no one recorded. -/
def ANonQuietPostIsTold : Prop :=
  ∀ rec acked (s : Shared) (e : Entry) (p : Post), acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .post p → quiet rec.posts p = false →
    ∃ t ∈ facts rec acked s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

/-- EXPENSIVE, and smaller than before: no scope and no policy to follow. A notable change is one
that wakes (`Change.wakes`). Proof plan: split by `Change` constructor, and for a pull that left
the open list by whether the feed holds a new close of it. A pull that left the open list is told
as its close or as `gone`. A `gone` item carries the pull's author in the acked view, so its kind
is the change's, and a caller that hears that kind hears it. A close is told under the kind of the
author the close route read, which this statement does not tie to the acked view's author. The
hypothesis on closes is the writer's own recorded merge
or close, which `OnlyAMergeExplainsAMerge` limits. A close that is not new was told with the batch
that read it: `View.of` drops a pull its own poll closes (`PullsAreTheOpenPullsRead`), so a pull
never leaves the view a poll after its close was read. -/
def EveryNotableChangeIsTold : Prop :=
  ∀ rec acked (s : Shared) (ch : Change), acked.fits s = true →
    ch ∈ View.diff acked.view s.view → ch.wakes = true →
    explains (liveWrites rec s acked) ch = false →
    (∀ cl, ch.leaves = some cl.number → newClose s acked cl →
      explainsClose (liveWrites rec s acked) cl = false) →
    ∃ t ∈ facts rec acked s, t.wakes = true ∧
      (t.item = .change ch ∨
        (∃ cl, t.item = .closed cl ∧ ch.leaves = some cl.number ∧ newClose s acked cl) ∨
        (∃ p a, t.item = .gone p a ∧ ch.leaves = some p ∧ [a.kind] = ch.kinds))

/-- A close in the feed is told even when its pull never showed in the view diff. -/
def ANewCloseIsToldUnlessItsWriterRecordedIt : Prop :=
  ∀ rec acked (s : Shared) (cl : ClosedPull), acked.fits s = true →
    newClose s acked cl → explainsClose (liveWrites rec s acked) cl = false →
    ∃ t ∈ facts rec acked s, t.item = .closed cl ∧ t.wakes = true

def OneItemPerClose : Prop :=
  ∀ rec acked (s : Shared) (cl : ClosedPull),
    (∃ t ∈ facts rec acked s, t.item = .closed cl) →
    (∀ a, ∀ t ∈ facts rec acked s, t.item ≠ .gone cl.number a) ∧
    ∀ d : Delta Pr PullFacts, d.key = cl.number → d.after = none →
      ∀ t ∈ facts rec acked s, t.item ≠ .change (.pull d)

/-- An item a reader could not read is a fact, as words. The lens tells it to every topic that
hears its kind (`words`, or `pulls` for a close) and covers its thread, and to every such topic
when its thread is unknown (`Scope.coversItem`). -/
def ARefusedItemIsTold : Prop :=
  ∀ rec acked (s : Shared) (e : Entry) (x : Refused) seen, acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .refused x seen →
    ∃ t ∈ facts rec acked s, t.item = .refused x ∧ t.tier = .words ∧ t.wakes = true

def AFreshConsumerHearsFinishedChecks : Prop :=
  ∀ rec (s : Shared) since (p : Pr) (h : HeadFacts) n r,
    s.view.heads.get? p = some h → h.checks.get n = some (.done r) →
    ∃ t ∈ facts rec (Mark.fresh s.gen since) s, ∃ d, t.item = .change (.head d) ∧
      d.key = p ∧ t.wakes = true

/-- In `facts` every line wakes and none is a note, so in a report a fact fails to wake only
because its kinds ride along. -/
def EveryFactWakes : Prop :=
  ∀ rec acked (s : Shared), ∀ t ∈ facts rec acked s, t.wakes = true ∧ t.isNote = false

/-! What is told: the notes. With `EveryNoteIsReported` each reaches every report, whatever the
subscription. -/

def NotesAreNotes : Prop :=
  ∀ was now hidden acked pending (s : Shared), ∀ t ∈ notes was now hidden acked pending s,
    t.isNote = true

def GapIsNeverSilent : Prop :=
  ∀ was now hidden acked pending (s : Shared), acked.fits s = true →
    s.feed.gap acked.feed = true →
    ∃ t ∈ notes was now hidden acked pending s, t.item = .note .gap ∧ t.wakes = true

/-- Another generation, and a mark ahead of the shared state, both reset with a line. -/
def ResetIsNeverSilent : Prop :=
  ∀ was now hidden acked pending (s : Shared), acked.fits s = false →
    ∃ t ∈ notes was now hidden acked pending s, t.item = .note .reset ∧ t.wakes = true

def AFailingGitHubIsTold : Prop :=
  ∀ was now hidden acked pending (s : Shared), acked.toldDown = false →
    downAfter ≤ s.failStreak →
    ∃ t ∈ notes was now hidden acked pending s, (∃ k e w, t.item = .note (.down k e w)) ∧
      t.wakes = true

/-- A wait whose topic is not the one its acked place was taken under is told so in its first
batch: the note wakes, names both topics and carries the count `report` gives it, so `Render` can
say what is newly heard and newly hidden, how many facts taking the batch passes unheard, and that
facts before the acked place are not told again. -/
def AChangedTopicIsTold : Prop :=
  ∀ (was now : Topic) hidden acked pending (s : Shared), was ≠ now →
    ∃ t ∈ notes was now hidden acked pending s, t.item = .note (.newTopic was now hidden) ∧
      t.wakes = true

/-! What is told: the lens. Each is a list lemma or a case split. -/

/-- No subscription drops or delays a note. -/
def EveryNoteIsReported : Prop :=
  ∀ c (sub : Subscription) rec was acked pending (s : Shared),
    ∀ t ∈ notes was sub.topic (hiddenBy c.app was sub.topic (facts rec acked s)) acked pending s,
      t ∈ report c sub rec was acked pending s

def TheLensOnlyDropsOrHolds : Prop :=
  ∀ (sub : Subscription) app ts, ∀ u ∈ sub.lens app ts,
    ∃ t ∈ ts, sub.tells app t.item = true ∧
      u = { t with wakes := t.wakes && !sub.holds app t.item }

def WhatIsToldPassesTheLens : Prop :=
  ∀ (sub : Subscription) app (ts : List Told), ∀ t ∈ ts, sub.tells app t.item = true →
    { t with wakes := t.wakes && !sub.holds app t.item } ∈ sub.lens app ts

/-- Replaces `AScopedConsumerHearsOnlyItsPulls`: a report holds only what its subscription tells,
so a caller with `--on` hears its items, items of no known thread, and notes. -/
def ASubscriberHearsOnlyItsTopics : Prop :=
  ∀ (c : Consumer) (sub : Subscription) rec was acked pending (s : Shared),
    ∀ t ∈ report c sub rec was acked pending s, sub.tells c.app t.item = true

/-- The coverage statement. A catch-all is told every fact but `peers`, with its tier, and the line
wakes unless its kinds ride. Short, from `ACatchAllHearsEveryKindButPeers`,
`WhatIsToldPassesTheLens` and a case split on `Item.subject` (every list it gives is one kind, or
`passed` and `failed`, so only a post's list is `[.peers]`). -/
def TheCatchAllHearsEverything : Prop :=
  ∀ (c : Consumer) (sub : Subscription) rec was acked pending (s : Shared),
    sub.topic.catchAll = true →
    ∀ t ∈ facts rec acked s, t.item.subject c.app ≠ .kinds [.peers] →
      ∃ u ∈ report c sub rec was acked pending s, u.item = t.item ∧ u.tier = t.tier ∧
        u.wakes = (t.wakes && !sub.holds c.app t.item)

/-- Every post that may be the owner's words (kind `words`: typed words, or a review-route post no
app names) and that is not quiet wakes every caller that hears `words` about that thread, whatever
it lets ride. Typed words meet both post premises for every caller (`TheSpeakerDecidesThePostKind`,
`TypedWordsAreNeverQuiet`), and for a catch-all both premises on `sub` hold. Short, from
`ANonQuietPostIsTold`, `OnlyChecksAlarmsAndOutsideRide` and `WhatIsToldPassesTheLens`. -/
def OwnerWordsWakeWhoeverHearsWords : Prop :=
  ∀ (c : Consumer) (sub : Subscription) rec was acked pending (s : Shared) (e : Entry) (p : Post),
    acked.fits s = true → e ∈ s.feed.newFor acked.feed → e.fact = .post p →
    p.kind c.app = .words → quiet rec.posts p = false →
    sub.topic.hears.words = true → sub.topic.on.covers p.thread = true →
    ∃ t ∈ report c sub rec was acked pending s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

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
  ∀ c sub rec cap (cs : ConsumerState) (s : Shared),
    (finish c sub rec cap cs s).1 =
      cut cap (report c sub rec cs.under.topic cs.acked cs.pending s) ∧
    ∃ r, (finish c sub rec cap cs s).2 =
      { cs with pending := .offered (cs.offers + 1) s.mark r sub, offers := cs.offers + 1 }

/-- The place a wait saves does not depend on its subscription: taking its offer acks the same
mark, and the offer has the same number, whatever flags the wait ran with. So changing the flags
between waits moves no place; the offer only records them, for `notes` and `status`. -/
def TheOfferIgnoresTheSubscription : Prop :=
  ∀ c (sub sub' : Subscription) rec cap (cs : ConsumerState) (s : Shared) seen,
    ((finish c sub rec cap cs s).2.ack seen).acked =
        ((finish c sub' rec cap cs s).2.ack seen).acked ∧
      (finish c sub rec cap cs s).2.offers = (finish c sub' rec cap cs s).2.offers

/-! When to stop waiting. -/

/-- Only words that may be the owner's skip the window: a waking post that no app names, or a
waking post a reader could not read. -/
def OnlyPossibleOwnerWordsSkipTheWindow : Prop :=
  ∀ now started deadline (s : Shared) ts waking firstWake busy,
    (Moment.of now started deadline s ts waking firstWake busy).words = true →
    ∃ t ∈ ts, t.wakes = true ∧
      ((∃ p, t.item = .post p ∧ ∀ a, p.speaker ≠ .app a) ∨
        ∃ x pl, t.item = .refused x ∧ x.kind = .post pl)

/-- `Told.skipsWindow` and the kind `words` are one set, so "may be the owner's" has one meaning: a
waking line skips the coalescing window exactly when its kind is `words`. -/
def SkipsWindowIsTheWordsKind : Prop :=
  ∀ (app : String) (t : Told),
    t.skipsWindow = (t.wakes && decide (t.item.subject app = .kinds [.words]))

def OwnerWordsAreNotHeld : Prop :=
  ∀ m : Moment, m.waking = true → m.words = true → nextMove m = .deliver

def WakeIsDelivered : Prop :=
  ∀ m : Moment, m.waking = true → m.deadline ≤ m.now → nextMove m = .deliver

def NeverEarlyEmpty : Prop :=
  ∀ m : Moment, (nextMove m = .quiet ∨ nextMove m = .blind) →
    m.deadline ≤ m.now ∧ m.waking = false ∧ m.told = false

/-- A quiet or blind end happens only over an empty report, so the offer it saves (`s.mark`) acks
nothing the subscription selects: a line whose kinds ride along never woke, and it is delivered at
the deadline instead of being acked unseen. What the lens dropped is acked unseen by design. -/
def QuietEndAcksNothingUnshown : Prop :=
  ∀ now started deadline (s : Shared) ts waking firstWake busy,
    let m := Moment.of now started deadline s ts waking firstWake busy
    (nextMove m = .quiet ∨ nextMove m = .blind) → ts = []

/-- The catch-all form: a quiet or blind end of a catch-all leaves no note unshown, and every fact
it acked unseen was `peers`. Short, from `QuietEndAcksNothingUnshown` and
`TheCatchAllHearsEverything`. -/
def QuietCatchAllHidOnlyPeers : Prop :=
  ∀ now started deadline (s : Shared) (c : Consumer) (sub : Subscription) rec was acked pending
    waking firstWake busy, sub.topic.catchAll = true →
    let m := Moment.of now started deadline s (report c sub rec was acked pending s) waking
      firstWake busy
    (nextMove m = .quiet ∨ nextMove m = .blind) →
    notes was sub.topic (hiddenBy c.app was sub.topic (facts rec acked s)) acked pending s = [] ∧
      ∀ t ∈ facts rec acked s, t.item.subject c.app = .kinds [.peers]

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

/-- An outside pull request opened rides along by default (`Rides.byDefault`), so it ends no wait,
and the wait reaches its deadline with it in the report: the wait delivers it instead of ending
quiet. -/
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

/-- A red check and a typed owner comment on #512 and a green check on #513, as `facts` would list
them. -/
def aRedCheck : Told :=
  ⟨.change (.head ⟨512, none, some ⟨"abc1234", { gate := some (.done "failure") }⟩⟩), .owned, true⟩

def aGreenCheck : Told :=
  ⟨.change (.head ⟨513, none, some ⟨"def5678", { gate := some (.done "success") }⟩⟩), .owned, true⟩

def anOwnerComment : Told :=
  ⟨.post (Post.of { place := .issueComment, id := 41, thread := 512, login := "o", via := .none,
    created := 1795425128, updated := 1795425128, state := none, body := "please split it" }),
    .words, true⟩

/-- A CI-failures agent (`--topics failed,alarms`) is told the red check only. -/
theorem aFailuresAgentHearsOnlyTheRedCheck :
    ({ topic := { hears := { failed := true, alarms := true } } } : Subscription).lens "claude"
      [aRedCheck, aGreenCheck, anOwnerComment] = [aRedCheck] := by decide +kernel

/-- The root with `--ride failed,outside,alarms` is told all three. The red check does not end the
wait; the green check and the owner's words do. -/
theorem aRidingFailureIsToldAndDoesNotWake :
    (({ rides := { failed := true, outside := true, alarms := true } } : Subscription).lens
        "claude" [aRedCheck, aGreenCheck, anOwnerComment]).map (·.wakes) = [false, true, true] := by
  decide +kernel

/-- `--on 571` drops every line about #512 and #513. -/
theorem anotherItemIsDropped :
    ({ topic := { on := .items [571] } } : Subscription).lens "claude"
      [aRedCheck, aGreenCheck, anOwnerComment] = [] := by decide +kernel

/-- A green gate beside a red `scorecard-comment` on #514, both newly finished against the acked
view: the line is both `passed` and `failed`. -/
def aGreenGateBesideARedCheck : Told :=
  ⟨.change (.head ⟨514, none, some ⟨"0a1b2c3",
    { gate := some (.done "success"), scorecard := some (.done "failure") }⟩⟩), .owned, true⟩

/-- The root that lets `failed` ride still wakes for that green gate, and a caller that hears only
`passed` is told it and wakes. -/
theorem aGreenGateBesideARedCheckWakesTheRidingRoot :
    (({ rides := { failed := true, outside := true, alarms := true } } : Subscription).lens
        "claude" [aGreenGateBesideARedCheck]).map (·.wakes) = [true] ∧
      (({ topic := { hears := { passed := true } } } : Subscription).lens "claude"
        [aGreenGateBesideARedCheck]).map (·.wakes) = [true] := by
  decide +kernel

/-- The root narrowed by mistake to `--topics words`: of the three facts above, the new topic hides
the two head lines, so its `newTopic` note says that taking the batch passes 2 facts. -/
theorem aNarrowedRootCountsWhatItHides :
    hiddenBy "claude" {} { hears := { words := true } }
      [aRedCheck, aGreenCheck, anOwnerComment] = 2 := by decide +kernel

end Fixture

end MitosGate.Watch
