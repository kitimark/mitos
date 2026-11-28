import MitosGate.Land

/-! UNCHECKED SKETCH (#502). What a caller asks to hear: the kinds of line, the issues or pull
requests, and the kinds that ride along.

A topic is a closed set of kinds and either the whole repository or some issue and pull request
numbers. A subscription is a topic plus the kinds that ride along: told with the next batch, but
not ending the wait. It is declared by flags on every wait and printed back by the trailer, so a
caller that runs the text after `next: ` keeps it (`TheTrailerFlagsReadBack`). It is never a
setting: the offer and the caller's place record it only as data (`Deliver`), so a lost state
folder loses no subscription.

The kinds, the one list of them, and the one reader of their names are here, so a new kind is one
constructor, one `Kinds` field and one `Kind.every` entry, and the build fails when one is missing
(`KindNamesReadBack`, and the total matches below). Which kinds a fact has (a post, a change, a
refused item) is `Wake`'s: it depends on identity. What a caller is told through its topic is
`Deliver`'s (`Subscription.lens`).

Left out on purpose: labels, milestones, issue versus pull request, one check, one app. Label and
milestone membership moves, and the view holds no issues; whoever briefs an agent turns a milestone
into numbers for `--on`. Layout copies `Observe.lean`'s `Listed`. -/

namespace MitosGate.Watch

open Land (Pr)

/-- Which issues or pull requests a topic is about. A post's thread may be an issue. -/
inductive Scope
  | repo
  | items (ns : List Pr)
  deriving DecidableEq, Repr

def Scope.covers : Scope → Pr → Bool
  | .repo, _ => true
  | .items ns, p => ns.contains p

/-- Whether two scopes share an issue or pull request. Only `status`'s overlap hint reads it. -/
def Scope.meets : Scope → Scope → Bool
  | .repo, _ => true
  | _, .repo => true
  | .items ns, .items ms => ns.any ms.contains

/-- What a told line is about. The set is closed: a new kind is a design change.
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

/-- The one list of kinds, in the order every flag and line prints them. -/
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

/-- The only reader of a kind's name, derived from `Kind.every` and `Kind.name`, so no second list
is kept in step by hand. -/
def Kind.ofName? (s : String) : Option Kind := Kind.every.find? (·.name == s)

/-- A set of kinds, one field each, so two equal sets are one value. -/
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

/-- The kinds held, in `Kind.every` order. -/
def Kinds.items (ks : Kinds) : List Kind := Kind.every.filter ks.has

/-- What a wait with no `--topics` hears. -/
def Kinds.everyButPeers : Kinds :=
  { words := true, agents := true, passed := true, failed := true, pulls := true, outside := true,
    alarms := true }

/-- The kinds that may ride along. Words, other posts and the owner's pull requests (labels, merges,
closes: what the dashboard and a merge need) have no field, so no caller can let them ride. -/
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

/-- `--ride` reads a kind into `Rides`, and refuses a kind with no field: a usage error, exit 2. -/
def Rides.add? (r : Rides) : Kind → Option Rides
  | .passed => some { r with passed := true }
  | .failed => some { r with failed := true }
  | .outside => some { r with outside := true }
  | .alarms => some { r with alarms := true }
  | .words | .agents | .peers | .pulls => none

def Rides.ofKinds? (ks : List Kind) : Option Rides := ks.foldlM Rides.add? {}

def Rides.items (r : Rides) : List Kind := Kind.every.filter r.has

/-- What a wait with no `--ride` lets ride: another account's pull requests (default 6). -/
def Rides.byDefault : Rides := { outside := true }

/-- What a caller hears: kinds of line about the repository or some issues and pull requests. The
defaults are the wait with no flags. -/
structure Topic where
  hears : Kinds := Kinds.everyButPeers
  on : Scope := .repo
  deriving DecidableEq, Repr

/-- A topic that drops nothing but `peers`: the whole repository and every other kind. The rules
make the root's wait one (PR 13). -/
def Topic.catchAll (t : Topic) : Bool :=
  t.on == .repo && Kind.every.all fun k => k == .peers || t.hears.has k

/-- What one wait asked for: its topic, and which kinds ride along. -/
structure Subscription where
  topic : Topic := {}
  rides : Rides := Rides.byDefault
  deriving DecidableEq, Repr

/-- A wait's subscription flags, typed. `WatchCli` reads the text into these at the boundary (a name
`Kind.ofName?` does not know, an empty list, a repeated flag, or a number that is not a positive
decimal is exit 2) and sorts `--on`'s numbers without repeats; `Render` prints them back. An empty
`ride` is `--ride none`. -/
inductive Flag
  | topics (ks : List Kind)
  | on (ns : List Pr)
  | ride (ks : List Kind)
  deriving DecidableEq, Repr

/-- The flags a trailer prints, in this order. A flag at its default is not printed, so the root's
trailer names none. -/
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

/-- The subscription of a wait's typed flags, from the defaults; `none` is a usage error. -/
def Subscription.ofFlags? (fs : List Flag) : Option Subscription :=
  fs.foldlM Subscription.add? {}

/-- What `ofFlags?` makes: a topic of at least one kind, and items listed once, ascending. -/
def Subscription.canonical (sub : Subscription) : Bool :=
  sub.topic.hears != ({} : Kinds) && match sub.topic.on with
    | .repo => true
    | .items ns => !ns.isEmpty && decide (ns.Pairwise (· < ·))

/-- `status`'s hint, for one container: the kinds two callers both hear on an item they share. A
catch-all overlaps every topic by design (it observes what handlers handle), so it is never named.
`agents` and `peers` are counted only between callers of one app, so the hint can miss an overlap
between apps (a third app's post is `agents` for both). Tested by its fixture, never a guarantee:
callers in other containers are not seen. -/
def Topic.overlap (app app' : String) (t t' : Topic) : List Kind :=
  if t.on.meets t'.on && !t.catchAll && !t'.catchAll then
    Kind.every.filter fun k => t.hears.has k && t'.hears.has k &&
      (app == app' || !(k == .agents || k == .peers))
  else []

/-! Statements. -/

/-- `Kind.every` lists every kind, and each kind's name reads back as that kind. A kind added to
the type and not to the list fails the first half; a missing name is a missing match case. Short:
`cases k` and `decide`. -/
def KindNamesReadBack : Prop :=
  ∀ k : Kind, k ∈ Kind.every ∧ Kind.ofName? k.name = some k

def ACatchAllHearsEveryKindButPeers : Prop :=
  ∀ t : Topic, t.catchAll = true → t.on = .repo ∧ ∀ k : Kind, k ≠ .peers → t.hears.has k = true

/-- Only `passed`, `failed`, `outside` and `alarms` can ride, whatever a caller asks: `Rides` has no
field for the others, so words, posts and the owner's pull requests always wake. -/
def OnlyChecksAlarmsAndOutsideRide : Prop :=
  ∀ (r : Rides) (k : Kind), r.has k = true →
    k = .passed ∨ k = .failed ∨ k = .outside ∨ k = .alarms

/-- Moderate. The trailer's flags read back as the subscription they were printed from, so a caller
that runs the text after `next: ` keeps its subscription: a trailer that dropped `--topics` would
make a narrow caller a catch-all, and one that dropped `--ride` would wake the root for what it
handed over. Proof plan: `Kinds.ofList ks.items = ks` and `Rides.ofKinds? r.items = some r` by a
case split on each field, and a non-empty `Kinds` has non-empty `items`. Stated over typed flags,
never over the text: the text is `Render`'s and `WatchCli`'s, and is tested. The other half, that
every subscription `ofFlags?` makes is canonical, holds by inspection of `add?` (it refuses an
empty `--topics` and an empty or unsorted `--on`, and the default is canonical) and is pinned by
the fixture `parsedFlagsAreCanonical`, not stated. -/
def TheTrailerFlagsReadBack : Prop :=
  ∀ sub : Subscription, sub.canonical = true → Subscription.ofFlags? sub.flags = some sub

namespace Fixture

/-- The wait with no flags is a catch-all that lets only `outside` ride, and it prints no flag. -/
theorem theDefaultIsACatchAll :
    ({} : Subscription).topic.catchAll = true ∧ ({} : Subscription).rides = { outside := true } ∧
      ({} : Subscription).flags = [] := by
  decide +kernel

/-- `--ride failed,words` and `--ride pulls` are usage errors. -/
theorem wordsAndPullsCannotRide :
    Rides.ofKinds? [.failed, .words] = none ∧ Rides.ofKinds? [.pulls] = none := by
  decide +kernel

/-- The CI-failures agent's flags read back. -/
theorem aFailuresAgentsFlagsReadBack :
    Subscription.ofFlags?
        ({ topic := { hears := { failed := true, alarms := true } } } : Subscription).flags =
      some { topic := { hears := { failed := true, alarms := true } } } := by
  decide +kernel

/-- What `ofFlags?` makes is canonical, and it refuses what is not: an empty `--topics` and an
unsorted `--on`. The other half of `TheTrailerFlagsReadBack`, pinned here, not stated. -/
theorem parsedFlagsAreCanonical :
    (Subscription.ofFlags? [.topics [.failed], .on [502, 571], .ride []]).map (·.canonical) =
        some true ∧
      Subscription.ofFlags? [.topics []] = none ∧ Subscription.ofFlags? [.on [571, 502]] = none := by
  decide +kernel

/-- An owner-comments agent and the owner of #512, of one app, both hear `words` on #512. The
root's catch-all overlaps both by design and is never named. -/
theorem aWordsAgentAndAPrOwnerOverlapOnWords :
    Topic.overlap "claude" "claude" { hears := { words := true } } { on := .items [512] } =
        [.words] ∧
      Topic.overlap "claude" "claude" {} { hears := { words := true } } = [] := by
  decide +kernel

end Fixture

end MitosGate.Watch
