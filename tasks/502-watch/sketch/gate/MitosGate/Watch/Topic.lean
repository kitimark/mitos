import MitosGate.Land

namespace MitosGate.Watch

open Land (Pr)

inductive Scope
  | repo
  | items (ns : List Pr)
  deriving DecidableEq, Repr

def Scope.covers : Scope → Pr → Bool
  | .repo, _ => true
  | .items ns, p => ns.contains p

def Scope.meets : Scope → Scope → Bool
  | .repo, _ => true
  | _, .repo => true
  | .items ns, .items ms => ns.any ms.contains

/-- What a told line is about.
* `words`: a post no app names (the owner's typed words, or a review-route post), or a post a
  reader could not read. These may be the owner's.
* `agents`: a post through an app other than the caller's.
* `peers`: a post through the caller's own app: its provider's other sessions, and the owner's own
  posts through that app.
* `passed`: a head line where a listed check newly finished and passed: `success`, `skipped` or
  `neutral` (`Wake.passingConclusions`).
* `failed`: a head line where a listed check newly finished with any other conclusion, `cancelled`
  and one never seen included. A head line with both is both (`Wake.Change.kinds`).
* `pulls`: one of the owner's pull requests opened, changed labels or assignees, merged, closed or
  left the open list; a close that could not be read.
* `outside`: the same for a pull request of another account.
* `alarms`: `ci` health. -/
inductive Kind
  | words
  | agents
  | peers
  | passed
  | failed
  | pulls
  | outside
  | alarms
  deriving DecidableEq, Repr

def Kind.every : List Kind :=
  [.words, .agents, .peers, .passed, .failed, .pulls, .outside, .alarms]

def Kind.name : Kind → String
  | .words => "words"
  | .agents => "agents"
  | .peers => "peers"
  | .passed => "passed"
  | .failed => "failed"
  | .pulls => "pulls"
  | .outside => "outside"
  | .alarms => "alarms"

def Kind.ofName? (s : String) : Option Kind := Kind.every.find? (·.name == s)

structure Kinds where
  words : Bool := false
  agents : Bool := false
  peers : Bool := false
  passed : Bool := false
  failed : Bool := false
  pulls : Bool := false
  outside : Bool := false
  alarms : Bool := false
  deriving DecidableEq, Repr

def Kinds.has (ks : Kinds) : Kind → Bool
  | .words => ks.words
  | .agents => ks.agents
  | .peers => ks.peers
  | .passed => ks.passed
  | .failed => ks.failed
  | .pulls => ks.pulls
  | .outside => ks.outside
  | .alarms => ks.alarms

def Kinds.add (ks : Kinds) : Kind → Kinds
  | .words => { ks with words := true }
  | .agents => { ks with agents := true }
  | .peers => { ks with peers := true }
  | .passed => { ks with passed := true }
  | .failed => { ks with failed := true }
  | .pulls => { ks with pulls := true }
  | .outside => { ks with outside := true }
  | .alarms => { ks with alarms := true }

def Kinds.ofList (ks : List Kind) : Kinds := ks.foldl Kinds.add {}

def Kinds.items (ks : Kinds) : List Kind := Kind.every.filter ks.has

def Kinds.everyButPeers : Kinds :=
  { words := true, agents := true, passed := true, failed := true, pulls := true, outside := true,
    alarms := true }

structure Rides where
  passed : Bool := false
  failed : Bool := false
  outside : Bool := false
  alarms : Bool := false
  deriving DecidableEq, Repr

def Rides.has (r : Rides) : Kind → Bool
  | .passed => r.passed
  | .failed => r.failed
  | .outside => r.outside
  | .alarms => r.alarms
  | .words | .agents | .peers | .pulls => false

def Rides.add? (r : Rides) : Kind → Option Rides
  | .passed => some { r with passed := true }
  | .failed => some { r with failed := true }
  | .outside => some { r with outside := true }
  | .alarms => some { r with alarms := true }
  | .words | .agents | .peers | .pulls => none

def Rides.ofKinds? (ks : List Kind) : Option Rides := ks.foldlM Rides.add? {}

def Rides.items (r : Rides) : List Kind := Kind.every.filter r.has

def Rides.byDefault : Rides := { outside := true }

structure Topic where
  hears : Kinds := Kinds.everyButPeers
  on : Scope := .repo
  deriving DecidableEq, Repr

def Topic.catchAll (t : Topic) : Bool :=
  t.on == .repo && Kind.every.all fun k => k == .peers || t.hears.has k

structure Subscription where
  topic : Topic := {}
  rides : Rides := Rides.byDefault
  deriving DecidableEq, Repr

inductive Flag
  | topics (ks : List Kind)
  | on (ns : List Pr)
  | ride (ks : List Kind)
  deriving DecidableEq, Repr

def Subscription.flags (sub : Subscription) : List Flag :=
  (if sub.topic.hears = Kinds.everyButPeers then [] else [.topics sub.topic.hears.items]) ++
  (match sub.topic.on with
    | .repo => []
    | .items ns => [.on ns]) ++
  (if sub.rides = Rides.byDefault then [] else [.ride sub.rides.items])

def Subscription.add? (sub : Subscription) : Flag → Option Subscription
  | .topics ks =>
    if ks.isEmpty then none
    else some { sub with topic := { sub.topic with hears := Kinds.ofList ks } }
  | .on ns =>
    if ns.isEmpty || !decide (ns.Pairwise (· < ·)) then none
    else some { sub with topic := { sub.topic with on := .items ns } }
  | .ride ks => (Rides.ofKinds? ks).map fun r => { sub with rides := r }

def Subscription.ofFlags? (fs : List Flag) : Option Subscription :=
  fs.foldlM Subscription.add? {}

def Subscription.canonical (sub : Subscription) : Bool :=
  sub.topic.hears != ({} : Kinds) && match sub.topic.on with
    | .repo => true
    | .items ns => !ns.isEmpty && decide (ns.Pairwise (· < ·))

def Topic.overlap (app app' : String) (t t' : Topic) : List Kind :=
  if t.on.meets t'.on && !t.catchAll && !t'.catchAll then
    Kind.every.filter fun k => t.hears.has k && t'.hears.has k &&
      (app == app' || !(k == .agents || k == .peers))
  else []

def KindNamesReadBack : Prop :=
  ∀ k : Kind, k ∈ Kind.every ∧ Kind.ofName? k.name = some k

def ACatchAllHearsEveryKindButPeers : Prop :=
  ∀ t : Topic, t.catchAll = true → t.on = .repo ∧ ∀ k : Kind, k ≠ .peers → t.hears.has k = true

def OnlyChecksAlarmsAndOutsideRide : Prop :=
  ∀ (r : Rides) (k : Kind), r.has k = true →
    k = .passed ∨ k = .failed ∨ k = .outside ∨ k = .alarms

def TheTrailerFlagsReadBack : Prop :=
  ∀ sub : Subscription, sub.canonical = true → Subscription.ofFlags? sub.flags = some sub

namespace Fixture

theorem theDefaultIsACatchAll :
    ({} : Subscription).topic.catchAll = true ∧ ({} : Subscription).rides = { outside := true } ∧
      ({} : Subscription).flags = [] := by
  decide +kernel

theorem wordsAndPullsCannotRide :
    Rides.ofKinds? [.failed, .words] = none ∧ Rides.ofKinds? [.pulls] = none := by
  decide +kernel

theorem aFailuresAgentsFlagsReadBack :
    Subscription.ofFlags?
        ({ topic := { hears := { failed := true, alarms := true } } } : Subscription).flags =
      some { topic := { hears := { failed := true, alarms := true } } } := by
  decide +kernel

theorem parsedFlagsAreCanonical :
    (Subscription.ofFlags? [.topics [.failed], .on [502, 571], .ride []]).map (·.canonical) =
        some true ∧
      Subscription.ofFlags? [.topics []] = none ∧ Subscription.ofFlags? [.on [571, 502]] = none := by
  decide +kernel

theorem aWordsAgentAndAPrOwnerOverlapOnWords :
    Topic.overlap "claude" "claude" { hears := { words := true } } { on := .items [512] } =
        [.words] ∧
      Topic.overlap "claude" "claude" {} { hears := { words := true } } = [] := by
  decide +kernel

end Fixture

end MitosGate.Watch
