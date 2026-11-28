import MitosGate.Watch.Wake

namespace MitosGate.Watch

open Land (Pr)

structure Mark where
  gen : String
  view : View
  feed : FeedMark
  toldDown : Bool
  deriving DecidableEq

def Mark.poll (m : Mark) : Nat :=
  match m.feed with
  | .after p => p
  | .since _ => 0

def Mark.fresh (gen : String) (since : Epoch) : Mark := ⟨gen, {}, .since since, false⟩

def Mark.fits (m : Mark) (s : Shared) : Bool := m.gen == s.gen && decide (m.poll ≤ s.polls)

inductive Pending
  | nothing
  | offered (number : Nat) (mark : Mark) (repeats : Nat) (sub : Subscription)
  deriving DecidableEq

structure ConsumerState where
  acked : Mark
  under : Subscription
  pending : Pending
  offers : Nat
  deriving DecidableEq

def ConsumerState.fresh (acked : Mark) (sub : Subscription) (base : Nat) : ConsumerState :=
  ⟨acked, sub, .nothing, base⟩

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

def ConsumerState.offer (c : ConsumerState) (s : Shared) (sub : Subscription) : ConsumerState :=
  let repeats := match c.pending with
    | .offered _ _ r _ => r + 1
    | .nothing => 0
  { c with pending := .offered (c.offers + 1) s.mark repeats sub, offers := c.offers + 1 }

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

def Told.isNote (t : Told) : Bool := match t.item with
  | .note _ => true
  | _ => false

structure Records where
  posts : List PostRecord
  writes : List WriteRecord
  deriving DecidableEq

def liveWrites (rec : Records) (s : Shared) (acked : Mark) : List Write :=
  (rec.writes.filter (·.live s.gen acked.poll)).map (·.write)

def newClose (s : Shared) (acked : Mark) (cl : ClosedPull) : Prop :=
  ∃ e ∈ s.feed.newFor acked.feed, e.fact = .closed cl

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

def Scope.coversItem (sc : Scope) : Item → Bool
  | .note _ => true
  | .post p => sc.covers p.thread
  | .change ch => sc.coversChange ch
  | .closed cl => sc.covers cl.number
  | .gone pr _ => sc.covers pr
  | .refused x => x.thread.all sc.covers

def Subscription.tells (sub : Subscription) (app : String) (i : Item) : Bool :=
  match i.subject app with
  | .caller => true
  | .kinds ks => ks.any sub.topic.hears.has && sub.topic.on.coversItem i

def Subscription.holds (sub : Subscription) (app : String) (i : Item) : Bool :=
  match i.subject app with
  | .caller => false
  | .kinds ks => ks.all fun k => !sub.topic.hears.has k || sub.rides.has k

def Subscription.lens (sub : Subscription) (app : String) (ts : List Told) : List Told :=
  (ts.filter fun t => sub.tells app t.item).map fun t =>
    { t with wakes := t.wakes && !sub.holds app t.item }

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
only when `r = 0`; `newTopic was now hidden` when `was ≠ now`, and never when they are equal.
`report` gives `hidden` (`hiddenBy`). Every note but a repeated `redelivering` wakes. Only notes
(`NotesAreNotes`). -/
def notes (was now : Topic) (hidden : Nat) (acked : Mark) (pending : Pending) (s : Shared) :
    List Told :=
  panic! "not implemented"

def report (c : Consumer) (sub : Subscription) (rec : Records) (was : Topic) (acked : Mark)
    (pending : Pending) (s : Shared) : List Told :=
  let fs := facts rec acked s
  notes was sub.topic (hiddenBy c.app was sub.topic fs) acked pending s ++ sub.lens c.app fs

def waking (c : Consumer) (sub : Subscription) (rec : Records) (was : Topic) (acked : Mark)
    (pending : Pending) (s : Shared) : Bool :=
  match pending with
  | .offered _ m r t =>
    if 1 ≤ r then (report c sub rec t.topic m .nothing s).any (·.wakes)
    else (report c sub rec was acked pending s).any (·.wakes)
  | .nothing => (report c sub rec was acked .nothing s).any (·.wakes)

def Told.isWords (t : Told) : Bool := t.tier == .words

def Told.skipsWindow (t : Told) : Bool :=
  t.wakes && match t.item with
    | .post p => match p.speaker with
      | .app _ => false
      | _ => true
    | .refused x => match x.kind with
      | .post _ => true
      | .close => false
    | _ => false

def Told.isHead (t : Told) : Bool := match t.item with
  | .change (.head _) => true
  | _ => false

structure Batch where
  shown : List Told
  more : Nat
  deriving DecidableEq

def cut (cap : Nat) (ts : List Told) : Batch :=
  let always := ts.filter fun t => t.isWords || t.isNote
  let rest := ts.filter fun t => !t.isWords && !t.isNote
  let ranked := rest.filter (·.isHead) ++
    rest.filter (fun t => !t.isHead && t.tier == .owned) ++
    rest.filter (fun t => !t.isHead && t.tier == .outside)
  ⟨always ++ ranked.take cap, ranked.length - cap⟩

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
def freshSlack : Nat := 10

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

def Moment.fresh (m : Moment) : Bool :=
  decide (min m.now m.deadline ≤ m.lastOk + interval + pollBudget + freshSlack) &&
    decide (m.failStreak < downAfter)

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

def Shared.noNewsSince (m : Mark) (s : Shared) : Prop :=
  m.fits s = true ∧ m.view.Equiv s.view ∧
    (∃ p, m.feed = .after p ∧ ∀ e ∈ s.feed.entries, e.poll ≤ p) ∧
    s.feed.gap m.feed = false ∧ m.toldDown = decide (downAfter ≤ s.failStreak)

def NoNewsStaysQuiet : Prop :=
  ∀ c sub rec (s : Shared) (m : Mark), s.noNewsSince m →
    report c sub rec sub.topic m .nothing s = []

def AnAckedOfferHasNothingNew : Prop :=
  ∀ c sub rec (s : Shared), s.Inv → report c sub rec sub.topic s.mark .nothing s = []

def IgnoredTrailerReplaysOnce : Prop :=
  ∀ c (sub t : Subscription) rec was acked n m r (s : Shared), 1 ≤ r → t.topic = sub.topic →
    s.noNewsSince m → waking c sub rec was acked (.offered n m r t) s = false

def CopiedTrailerNeverSpins : Prop :=
  ∀ c (sub : Subscription) rec (cs : ConsumerState) (s : Shared) n m r t (mo : Moment),
    cs.pending = .offered n m r t → t.topic = sub.topic → s.noNewsSince m →
    mo.waking = waking c sub rec (cs.ack (some n)).under.topic (cs.ack (some n)).acked
      (cs.ack (some n)).pending s →
    mo.now < mo.deadline → nextMove mo ≠ .deliver ∧ nextMove mo ≠ .quiet ∧ nextMove mo ≠ .blind

def TypedWordsAreTold : Prop :=
  ∀ rec acked (s : Shared) (e : Entry) (p : Post), acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .post p → p.speaker = .typed →
    ∃ t ∈ facts rec acked s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

def ANonQuietPostIsTold : Prop :=
  ∀ rec acked (s : Shared) (e : Entry) (p : Post), acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .post p → quiet rec.posts p = false →
    ∃ t ∈ facts rec acked s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

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

def ARefusedItemIsTold : Prop :=
  ∀ rec acked (s : Shared) (e : Entry) (x : Refused) seen, acked.fits s = true →
    e ∈ s.feed.newFor acked.feed → e.fact = .refused x seen →
    ∃ t ∈ facts rec acked s, t.item = .refused x ∧ t.tier = .words ∧ t.wakes = true

def AFreshConsumerHearsFinishedChecks : Prop :=
  ∀ rec (s : Shared) since (p : Pr) (h : HeadFacts) n r,
    s.view.heads.get? p = some h → h.checks.get n = some (.done r) →
    ∃ t ∈ facts rec (Mark.fresh s.gen since) s, ∃ d, t.item = .change (.head d) ∧
      d.key = p ∧ t.wakes = true

def EveryFactWakes : Prop :=
  ∀ rec acked (s : Shared), ∀ t ∈ facts rec acked s, t.wakes = true ∧ t.isNote = false

def NotesAreNotes : Prop :=
  ∀ was now hidden acked pending (s : Shared), ∀ t ∈ notes was now hidden acked pending s,
    t.isNote = true

def GapIsNeverSilent : Prop :=
  ∀ was now hidden acked pending (s : Shared), acked.fits s = true →
    s.feed.gap acked.feed = true →
    ∃ t ∈ notes was now hidden acked pending s, t.item = .note .gap ∧ t.wakes = true

def ResetIsNeverSilent : Prop :=
  ∀ was now hidden acked pending (s : Shared), acked.fits s = false →
    ∃ t ∈ notes was now hidden acked pending s, t.item = .note .reset ∧ t.wakes = true

def AFailingGitHubIsTold : Prop :=
  ∀ was now hidden acked pending (s : Shared), acked.toldDown = false →
    downAfter ≤ s.failStreak →
    ∃ t ∈ notes was now hidden acked pending s, (∃ k e w, t.item = .note (.down k e w)) ∧
      t.wakes = true

def AChangedTopicIsTold : Prop :=
  ∀ (was now : Topic) hidden acked pending (s : Shared), was ≠ now →
    ∃ t ∈ notes was now hidden acked pending s, t.item = .note (.newTopic was now hidden) ∧
      t.wakes = true

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

def ASubscriberHearsOnlyItsTopics : Prop :=
  ∀ (c : Consumer) (sub : Subscription) rec was acked pending (s : Shared),
    ∀ t ∈ report c sub rec was acked pending s, sub.tells c.app t.item = true

def TheCatchAllHearsEverything : Prop :=
  ∀ (c : Consumer) (sub : Subscription) rec was acked pending (s : Shared),
    sub.topic.catchAll = true →
    ∀ t ∈ facts rec acked s, t.item.subject c.app ≠ .kinds [.peers] →
      ∃ u ∈ report c sub rec was acked pending s, u.item = t.item ∧ u.tier = t.tier ∧
        u.wakes = (t.wakes && !sub.holds c.app t.item)

def OwnerWordsWakeWhoeverHearsWords : Prop :=
  ∀ (c : Consumer) (sub : Subscription) rec was acked pending (s : Shared) (e : Entry) (p : Post),
    acked.fits s = true → e ∈ s.feed.newFor acked.feed → e.fact = .post p →
    p.kind c.app = .words → quiet rec.posts p = false →
    sub.topic.hears.words = true → sub.topic.on.covers p.thread = true →
    ∃ t ∈ report c sub rec was acked pending s, t.item = .post p ∧ t.tier = .words ∧ t.wakes = true

def WordsAreNeverCut : Prop :=
  ∀ cap ts, ∀ t ∈ ts, t.tier = .words → t ∈ (cut cap ts).shown

def NotesAreNeverCut : Prop :=
  ∀ cap ts, ∀ t ∈ ts, t.isNote = true → t ∈ (cut cap ts).shown

def OutsideIsCutFirst : Prop :=
  ∀ cap ts,
    (∃ t ∈ (cut cap ts).shown, t.tier = .outside ∧ t.isNote = false ∧ t.isHead = false) →
    ∀ t ∈ ts, t.tier = .owned → t ∈ (cut cap ts).shown

def TheCutCountsEveryLine : Prop :=
  ∀ cap ts, (cut cap ts).shown.length + (cut cap ts).more = ts.length

def ChecksAreCutLast : Prop :=
  ∀ cap ts, (∃ t ∈ ts, t.isHead = true ∧ t ∉ (cut cap ts).shown) →
    ∀ u ∈ (cut cap ts).shown, (u.isWords || u.isNote || u.isHead) = true

def OfferMarksTheReportedState : Prop :=
  ∀ c sub rec cap (cs : ConsumerState) (s : Shared),
    (finish c sub rec cap cs s).1 =
      cut cap (report c sub rec cs.under.topic cs.acked cs.pending s) ∧
    ∃ r, (finish c sub rec cap cs s).2 =
      { cs with pending := .offered (cs.offers + 1) s.mark r sub, offers := cs.offers + 1 }

def TheOfferIgnoresTheSubscription : Prop :=
  ∀ c (sub sub' : Subscription) rec cap (cs : ConsumerState) (s : Shared) seen,
    ((finish c sub rec cap cs s).2.ack seen).acked =
        ((finish c sub' rec cap cs s).2.ack seen).acked ∧
      (finish c sub rec cap cs s).2.offers = (finish c sub' rec cap cs s).2.offers

def OnlyPossibleOwnerWordsSkipTheWindow : Prop :=
  ∀ now started deadline (s : Shared) ts waking firstWake busy,
    (Moment.of now started deadline s ts waking firstWake busy).words = true →
    ∃ t ∈ ts, t.wakes = true ∧
      ((∃ p, t.item = .post p ∧ ∀ a, p.speaker ≠ .app a) ∨
        ∃ x pl, t.item = .refused x ∧ x.kind = .post pl)

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

def QuietEndAcksNothingUnshown : Prop :=
  ∀ now started deadline (s : Shared) ts waking firstWake busy,
    let m := Moment.of now started deadline s ts waking firstWake busy
    (nextMove m = .quiet ∨ nextMove m = .blind) → ts = []

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

theorem anOutsidePullRidesToTheDeadline :
    nextMove { now := 1800, started := 0, deadline := 1740, lastTry := 1790, lastOk := 1790,
      failStreak := 0, waking := false, words := false, told := true, firstWake := 1800,
      leaseBusy := false } = .deliver := by decide +kernel

theorem nothingToldEndsQuiet :
    nextMove { now := 1800, started := 0, deadline := 1740, lastTry := 1790, lastOk := 1790,
      failStreak := 0, waking := false, words := false, told := false, firstWake := 1800,
      leaseBusy := false } = .quiet := by decide +kernel

theorem aHealthyWaitAtTheDeadlineEndsQuiet :
    nextMove { now := 1741, started := 0, deadline := 1740, lastTry := 1590, lastOk := 1590,
      failStreak := 0, waking := false, words := false, told := false, firstWake := 1741,
      leaseBusy := false } = .quiet := by decide +kernel

def aRedCheck : Told :=
  ⟨.change (.head ⟨512, none, some ⟨"abc1234", { gate := some (.done "failure") }⟩⟩), .owned, true⟩

def aGreenCheck : Told :=
  ⟨.change (.head ⟨513, none, some ⟨"def5678", { gate := some (.done "success") }⟩⟩), .owned, true⟩

def anOwnerComment : Told :=
  ⟨.post (Post.of { place := .issueComment, id := 41, thread := 512, login := "o", via := .none,
    created := 1795425128, updated := 1795425128, state := none, body := "please split it" }),
    .words, true⟩

theorem aFailuresAgentHearsOnlyTheRedCheck :
    ({ topic := { hears := { failed := true, alarms := true } } } : Subscription).lens "claude"
      [aRedCheck, aGreenCheck, anOwnerComment] = [aRedCheck] := by decide +kernel

theorem aRidingFailureIsToldAndDoesNotWake :
    (({ rides := { failed := true, outside := true, alarms := true } } : Subscription).lens
        "claude" [aRedCheck, aGreenCheck, anOwnerComment]).map (·.wakes) = [false, true, true] := by
  decide +kernel

theorem anotherItemIsDropped :
    ({ topic := { on := .items [571] } } : Subscription).lens "claude"
      [aRedCheck, aGreenCheck, anOwnerComment] = [] := by decide +kernel

def aGreenGateBesideARedCheck : Told :=
  ⟨.change (.head ⟨514, none, some ⟨"0a1b2c3",
    { gate := some (.done "success"), scorecard := some (.done "failure") }⟩⟩), .owned, true⟩

theorem aGreenGateBesideARedCheckWakesTheRidingRoot :
    (({ rides := { failed := true, outside := true, alarms := true } } : Subscription).lens
        "claude" [aGreenGateBesideARedCheck]).map (·.wakes) = [true] ∧
      (({ topic := { hears := { passed := true } } } : Subscription).lens "claude"
        [aGreenGateBesideARedCheck]).map (·.wakes) = [true] := by
  decide +kernel

theorem aNarrowedRootCountsWhatItHides :
    hiddenBy "claude" {} { hears := { words := true } }
      [aRedCheck, aGreenCheck, anOwnerComment] = 2 := by decide +kernel

end Fixture

end MitosGate.Watch
