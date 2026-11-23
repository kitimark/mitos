import MitosGate.Watch.Voice
import MitosGate.Watch.Observe

/-! UNCHECKED SKETCH (#502). The owner's posts and the closes, keyed by GitHub's time, kept for a
day.

The feed's clock is GitHub's: `cursor` is the `Date` header of the last successful poll
(`serverNow`, `Fixed`). The next poll asks the post and close routes from `cursor - overlap`, and a
new feed, which has no cursor yet, asks from `serverNow - keep`, a day back. No local time enters
this file, so a local clock that runs fast or slow cannot move what the feed asks for
(`TheFeedIgnoresTheLocalClock` in `Shared.lean`, fixture `theFirstPollAsksADayBackOnGitHubsClock`). Because the cursor follows GitHub's clock on every successful poll, not
only when an owner fact arrives, `since` stays about an hour behind GitHub's now, and a quiet clone
rereads one hour of comments per poll, not everything since its last fact.

GitHub can list a fact a little after its stamp, so the overlap is an hour, and every key read
inside it is still held, so a reread adds nothing. A fact that GitHub lists more than an hour after
its stamp is never read; that loss is accepted in `DESIGN.md` (Tradeoffs) and PR 12 counts how late
facts arrive.

Each entry also records the number of the poll that first saw it. A consumer's mark is a poll
number, not a time, so a fact that GitHub listed late still lands after every older mark
(`ANewFactIsAfterEveryOlderMark`). Entries older than `keep` behind the cursor are pruned, and
`prunedPoll` remembers the newest poll a pruned entry came from, so a consumer whose mark is older
than that is told a gap instead of missing facts silently.

A poll that comes more than `keep - overlap` (23 hours) after the last good one asks from before
the window it keeps, so it may drop facts that no poll kept. Then `prunedPoll` becomes this poll's
number, and every consumer whose mark is older is told a gap (`AnUnpolledDayIsAGap`). The rule is
on the poll's `since`, not on a dropped fact, because the closes route lists an old close again
whenever its issue is updated, and that is no loss.

Besides posts and closes, the feed keeps the items a reader could not read (`Refused`,
`Observe.lean`), stamped with GitHub's time of the poll that first read them, so each is told once
and no bad item fails the poll. Layout copies `Carry.lean`. -/

namespace MitosGate.Watch

open Land (Pr)

def overlap : Nat := 3600
def keep : Nat := 86400
/-- How far a stored cursor may run ahead of GitHub's `Date` before it is pulled back: GitHub's
servers agree to well under a minute. -/
def slack : Nat := 60

/-- A post's key holds its update time, so an edit is a new fact. -/
inductive EntryKey
  | post (place : Place) (id : Nat) (updated : Epoch)
  | close (pr : Pr) (closedAt : Epoch)
  | refused (kind : ItemKind) (id : Nat)
  deriving DecidableEq, Repr

inductive Fact
  | post (p : Post)
  | closed (c : ClosedPull)
  | refused (x : Refused) (seen : Epoch)
  deriving DecidableEq

def Fact.key : Fact → EntryKey
  | .post p => .post p.place p.id p.updated
  | .closed c => .close c.number c.closedAt
  | .refused x _ => .refused x.kind x.id

def Fact.time : Fact → Epoch
  | .post p => p.updated
  | .closed c => c.closedAt
  | .refused _ seen => seen

structure Entry where
  fact : Fact
  poll : Nat
  deriving DecidableEq

/-- `cursor` is `none` until the first successful poll. -/
structure Feed where
  entries : List Entry := []
  cursor : Option Epoch := none
  prunedPoll : Nat := 0
  deriving DecidableEq

def Feed.WF (f : Feed) : Prop := (f.entries.map (·.fact.key)).Nodup

def Feed.start : Feed := {}

/-- The oldest GitHub time the feed still covers: a day behind its cursor. Before the first poll
there is nothing to cover. A new or reset consumer starts here (`Mark.fresh`). -/
def Feed.floor (f : Feed) : Epoch :=
  match f.cursor with
  | none => 0
  | some c => c - keep

/-- Where the next poll asks from, given GitHub's `Date` on its first answer. -/
def Feed.sinceAt (serverNow : Epoch) (f : Feed) : Epoch :=
  match f.cursor with
  | none => serverNow - keep
  | some c => min c serverNow - overlap

/-- The cursor after a poll whose `Date` was `serverNow`. It never moves back, except that a cursor
more than `slack` ahead of GitHub (a damaged file that still decoded) is pulled back to it. -/
def Feed.nextCursor (serverNow : Epoch) (f : Feed) : Epoch :=
  match f.cursor with
  | none => serverNow
  | some c => if c ≤ serverNow + slack then max c serverNow else serverNow

/-- Whether a poll whose `Date` was `serverNow` asked from before the window it will keep: no poll
succeeded for more than `keep - overlap`, so facts may have come and gone unread. -/
def Feed.lostWindow (serverNow : Epoch) (f : Feed) : Bool :=
  decide (f.sinceAt serverNow < f.nextCursor serverNow - keep)

/-- Moves the cursor to GitHub's time of this poll, prunes held entries that fell `keep` behind the
cursor, then adds the facts of poll `n` that are inside the window and whose key no kept entry
holds. A fact read from before the window is never added. When the poll lost a window,
`prunedPoll` becomes `n`, so every older mark hears a gap.

It dedupes against the kept entries, not every held one: a `refused` key carries no time, so an
item still listed in the poll that prunes its day-old entry is added again in that poll (told once
more, a day later), instead of being skipped for one poll and added at the next. Round 3 found the
second behavior against `TheSameFactsTwiceAddNothing` (fixture
`aRefusedItemPrunedAndRelistedIsAddedOnce`). -/
def Feed.add (n : Nat) (serverNow : Epoch) (facts : List Fact) (f : Feed) : Feed :=
  let cursor := f.nextCursor serverNow
  let (kept, gone) := f.entries.partition fun e => cursor - keep ≤ e.fact.time
  let inWindow := facts.filter fun x => cursor - keep ≤ x.time
  let fresh := inWindow.foldl (fun acc x =>
    if (kept.map (·.fact.key) ++ acc.map (·.fact.key)).contains x.key then acc
    else acc ++ [⟨x, n⟩]) []
  let pruned := gone.foldl (fun p e => max p e.poll) f.prunedPoll
  { entries := kept ++ fresh, cursor := some cursor,
    prunedPoll := if f.lostWindow serverNow then max n pruned else pruned }

/-- Where a consumer stands in the feed: a GitHub time (a new or reset consumer, from the feed's
floor or from `--since`), or the poll its last taken offer covered. -/
inductive FeedMark
  | since (t : Epoch)
  | after (poll : Nat)
  deriving DecidableEq, Repr

def Feed.newFor (m : FeedMark) (f : Feed) : List Entry :=
  match m with
  | .since t => f.entries.filter fun e => t ≤ e.fact.time
  | .after p => f.entries.filter fun e => p < e.poll

/-- Facts this mark should see may have been pruned. -/
def Feed.gap (m : FeedMark) (f : Feed) : Bool :=
  match m, f.cursor with
  | .since t, some c => decide (t < c - keep)
  | .since _, none => false
  | .after p, _ => decide (p < f.prunedPoll)

/-- Moderate: a fold invariant over `fresh`. -/
def AddKeepsEachKeyOnce : Prop :=
  ∀ (f : Feed) n now facts, f.WF → (f.add n now facts).WF

def ARereadFactKeepsItsPoll : Prop :=
  ∀ (f : Feed) n now facts (e : Entry), e ∈ f.entries →
    f.nextCursor now - keep ≤ e.fact.time → e ∈ (f.add n now facts).entries

def AddKeepsTheWindow : Prop :=
  ∀ (f : Feed) n now facts, ∀ e ∈ (f.add n now facts).entries,
    f.nextCursor now - keep ≤ e.fact.time

def CursorNeverGoesBack : Prop :=
  ∀ (f : Feed) n now facts c, f.cursor = some c → c ≤ now + slack →
    ∃ c', (f.add n now facts).cursor = some c' ∧ c ≤ c'

/-- The cursor is GitHub's time, never ahead of the last `Date` by more than `slack`. -/
def CursorNeverPassesGitHubNow : Prop :=
  ∀ (f : Feed) n now facts c', (f.add n now facts).cursor = some c' → c' ≤ now + slack

/-- A new feed asks for a day back from GitHub's own time, whatever the local clock says. -/
def ANewFeedAsksForADay : Prop :=
  ∀ now, Feed.start.sinceAt now = now - keep

def AfterIsOnlyNewer : Prop :=
  ∀ (f : Feed) (p : Nat), ∀ e ∈ f.newFor (.after p), p < e.poll

/-- Moderate (a fold invariant). A fact first read at poll `n` is new for every mark `after p` with
`p < n`, whatever its GitHub time, as long as it is inside the window. -/
def ANewFactIsAfterEveryOlderMark : Prop :=
  ∀ (f : Feed) n now facts (x : Fact) (p : Nat), x ∈ facts → x.key ∉ f.entries.map (·.fact.key) →
    f.nextCursor now - keep ≤ x.time → p < n →
    ∃ e ∈ (f.add n now facts).newFor (.after p), e.fact.key = x.key

/-- Moderate: after the first `add` the cursor is at or past `now`, every entry is inside the window
(`AddKeepsTheWindow`), so the second prunes nothing, keeps every entry, and `fresh` dedupes against
all of them; the same `Date` leaves the cursor and `prunedPoll`. -/
def TheSameFactsTwiceAddNothing : Prop :=
  ∀ (f : Feed) n m now facts, f.WF → (f.add n now facts).add m now facts = f.add n now facts

/-- A poll that asked from before the window it keeps tells every older mark a gap, so a clone that
no one polled for a day loses nothing silently. -/
def AnUnpolledDayIsAGap : Prop :=
  ∀ (f : Feed) n now facts p, f.lostWindow now = true → p < n →
    (f.add n now facts).gap (.after p) = true

/-- No entry claims a poll after the one that added it, and pruning never names a later poll. -/
def Feed.PollsBelow (k : Nat) (f : Feed) : Prop := (∀ e ∈ f.entries, e.poll ≤ k) ∧ f.prunedPoll ≤ k

def AddKeepsPollsBelow : Prop :=
  ∀ (f : Feed) n now facts k, f.PollsBelow k → k ≤ n → (f.add n now facts).PollsBelow n

namespace Fixture

/-- The owner posted an hour before the first poll of a clone. The poll's `Date` says
`1795428728`; the feed asks from a day back on GitHub's clock and keeps the post. Whatever the local
clock says is not an input here (`TheFeedIgnoresTheLocalClock` states that for `Shared.step`). -/
def postAnHourAgo : Fact :=
  .post (Post.of { place := .issueComment, id := 21, thread := 512, login := "o", via := .none,
    created := 1795425128, updated := 1795425128, state := none, body := "please split it" })

theorem theFirstPollAsksADayBackOnGitHubsClock :
    Feed.start.sinceAt 1795428728 = 1795342328 ∧
      (Feed.start.add 1 1795428728 [postAnHourAgo]).entries.length = 1 := by decide +kernel

/-- The last good poll was 30 hours before this one, and the owner posted two hours after it. The
post is older than the window this poll keeps, so it is dropped, and a consumer that acked the
last poll hears a gap instead of nothing. -/
def postAfterALongGap : Fact :=
  .post (Post.of { place := .issueComment, id := 22, thread := 512, login := "o", via := .none,
    created := 1795327928, updated := 1795327928, state := none, body := "any news?" })

theorem aDayWithNoPollIsAGap :
    let f : Feed := { cursor := some 1795320728 }
    (f.add 2 1795428728 [postAfterALongGap]).entries = [] ∧
      (f.add 2 1795428728 [postAfterALongGap]).gap (.after 1) = true := by decide +kernel

/-- A close item that still cannot be read, a day after it was first told. -/
def stillRefused : Refused :=
  { kind := .close, id := 7, thread := none, why := Excerpt.of "no closed_at" }

/-- Round 3's counterexample to `TheSameFactsTwiceAddNothing` under a dedupe over every held key:
the poll that prunes the item's day-old entry adds it again, once, and the same read again adds
nothing. -/
theorem aRefusedItemPrunedAndRelistedIsAddedOnce :
    let f : Feed := { entries := [⟨.refused stillRefused 0, 1⟩], cursor := some 100000 }
    let g := f.add 2 100000 [.refused stillRefused 100000]
    g.entries = [⟨.refused stillRefused 100000, 2⟩] ∧
      g.add 3 100000 [.refused stillRefused 100000] = g := by decide +kernel

end Fixture

end MitosGate.Watch
