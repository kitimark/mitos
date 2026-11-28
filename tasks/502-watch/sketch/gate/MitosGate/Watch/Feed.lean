import MitosGate.Watch.Voice
import MitosGate.Watch.Observe

namespace MitosGate.Watch

open Land (Pr)

def overlap : Nat := 3600
def keep : Nat := 86400
def slack : Nat := 60

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

structure Feed where
  entries : List Entry := []
  cursor : Option Epoch := none
  prunedPoll : Nat := 0
  deriving DecidableEq

def Feed.WF (f : Feed) : Prop := (f.entries.map (·.fact.key)).Nodup

def Feed.start : Feed := {}

def Feed.floor (f : Feed) : Epoch :=
  match f.cursor with
  | none => 0
  | some c => c - keep

def Feed.sinceAt (serverNow : Epoch) (f : Feed) : Epoch :=
  match f.cursor with
  | none => serverNow - keep
  | some c => min c serverNow - overlap

def Feed.nextCursor (serverNow : Epoch) (f : Feed) : Epoch :=
  match f.cursor with
  | none => serverNow
  | some c => if c ≤ serverNow + slack then max c serverNow else serverNow

def Feed.lostWindow (serverNow : Epoch) (f : Feed) : Bool :=
  decide (f.sinceAt serverNow < f.nextCursor serverNow - keep)

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

inductive FeedMark
  | since (t : Epoch)
  | after (poll : Nat)
  deriving DecidableEq, Repr

def Feed.newFor (m : FeedMark) (f : Feed) : List Entry :=
  match m with
  | .since t => f.entries.filter fun e => t ≤ e.fact.time
  | .after p => f.entries.filter fun e => p < e.poll

def Feed.gap (m : FeedMark) (f : Feed) : Bool :=
  match m, f.cursor with
  | .since t, some c => decide (t < c - keep)
  | .since _, none => false
  | .after p, _ => decide (p < f.prunedPoll)

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

def CursorNeverPassesGitHubNow : Prop :=
  ∀ (f : Feed) n now facts c', (f.add n now facts).cursor = some c' → c' ≤ now + slack

def ANewFeedAsksForADay : Prop :=
  ∀ now, Feed.start.sinceAt now = now - keep

def AfterIsOnlyNewer : Prop :=
  ∀ (f : Feed) (p : Nat), ∀ e ∈ f.newFor (.after p), p < e.poll

def ANewFactIsAfterEveryOlderMark : Prop :=
  ∀ (f : Feed) n now facts (x : Fact) (p : Nat), x ∈ facts → x.key ∉ f.entries.map (·.fact.key) →
    f.nextCursor now - keep ≤ x.time → p < n →
    ∃ e ∈ (f.add n now facts).newFor (.after p), e.fact.key = x.key

def TheSameFactsTwiceAddNothing : Prop :=
  ∀ (f : Feed) n m now facts, f.WF → (f.add n now facts).add m now facts = f.add n now facts

def AnUnpolledDayIsAGap : Prop :=
  ∀ (f : Feed) n now facts p, f.lostWindow now = true → p < n →
    (f.add n now facts).gap (.after p) = true

def Feed.PollsBelow (k : Nat) (f : Feed) : Prop := (∀ e ∈ f.entries, e.poll ≤ k) ∧ f.prunedPoll ≤ k

def AddKeepsPollsBelow : Prop :=
  ∀ (f : Feed) n now facts k, f.PollsBelow k → k ≤ n → (f.add n now facts).PollsBelow n

namespace Fixture

def postAnHourAgo : Fact :=
  .post (Post.of { place := .issueComment, id := 21, thread := 512, login := "o", via := .none,
    created := 1795425128, updated := 1795425128, state := none, body := "please split it" })

theorem theFirstPollAsksADayBackOnGitHubsClock :
    Feed.start.sinceAt 1795428728 = 1795342328 ∧
      (Feed.start.add 1 1795428728 [postAnHourAgo]).entries.length = 1 := by decide +kernel

def postAfterALongGap : Fact :=
  .post (Post.of { place := .issueComment, id := 22, thread := 512, login := "o", via := .none,
    created := 1795327928, updated := 1795327928, state := none, body := "any news?" })

theorem aDayWithNoPollIsAGap :
    let f : Feed := { cursor := some 1795320728 }
    (f.add 2 1795428728 [postAfterALongGap]).entries = [] ∧
      (f.add 2 1795428728 [postAfterALongGap]).gap (.after 1) = true := by decide +kernel

def stillRefused : Refused :=
  { kind := .close, id := 7, thread := none, why := Excerpt.of "no closed_at" }

theorem aRefusedItemPrunedAndRelistedIsAddedOnce :
    let f : Feed := { entries := [⟨.refused stillRefused 0, 1⟩], cursor := some 100000 }
    let g := f.add 2 100000 [.refused stillRefused 100000]
    g.entries = [⟨.refused stillRefused 100000, 2⟩] ∧
      g.add 3 100000 [.refused stillRefused 100000] = g := by decide +kernel

end Fixture

end MitosGate.Watch
