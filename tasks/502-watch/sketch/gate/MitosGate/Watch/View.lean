import MitosGate.Watch.KeyMap
import MitosGate.Watch.Observe

/-! UNCHECKED SKETCH (#502). The level view of the open pull requests and of `ci`'s health, and the
changes between two views.

A consumer compares the view it last took (its acked mark) with the shared current view, at the
level: what is true now against what was true then. So no change is lost between two waits, and a
consumer that waited for an hour sees one change where twenty polls saw twenty. `main` is not in
the view: its moves woke nobody, and the merge or the check that follows does. `unlisted` check
names are not in the view either; only the four listed names can change it.

Health conditions are keyed with no age in the key, so a condition is one change when it begins
and one when it clears, never a line per poll.

The statements below are the whole specification of `View.of`, since its body is not written yet:
each alarm is stated both ways (raised exactly when its condition holds), and the pulls and heads
are stated positively, so a `View.of` that reports nothing meets none of them. A re-read of the
same facts at a later time moves only the alarms that time starts (`AReReadMovesOnlyHealth`).
Layout copies `Snapshot/Fields.lean`. -/

namespace MitosGate.Watch

open Land (Pr)

structure PullFacts where
  author : Author
  labels : Names
  assignees : Names
  deriving DecidableEq, Repr

def PullFacts.ofOpen (p : OpenPull) : PullFacts := ⟨p.author, p.labels, p.assignees⟩

structure Checks where
  gate : Option Run := none
  prove : Option Run := none
  scorecard : Option Run := none
  coderabbit : Option Run := none
  deriving DecidableEq, Repr, Inhabited

def Checks.get (c : Checks) : Listed → Option Run
  | .gate => c.gate
  | .prove => c.prove
  | .scorecard => c.scorecard
  | .coderabbit => c.coderabbit

structure HeadFacts where
  sha : String
  checks : Checks
  deriving DecidableEq, Repr

/-- The per-head reads that can fail alone. -/
inductive HeadRoute
  | checks
  | reviews
  | look
  deriving DecidableEq, Repr

inductive Health
  | noRun (pr : Pr) (sha : String)
  | queued (run : Nat)
  | stale (run : Nat)
  | rabbitSkipped (pr : Pr) (sha : String)
  | unread (pr : Pr) (sha : String) (route : HeadRoute)
  deriving DecidableEq, Repr

/-- `heads` holds only open pull requests of the owner's login (`HeadsAreOpenOwnedPulls`). The
value of a health key is when the condition began; `View.of` keeps it from the previous view. -/
structure View where
  pulls : KeyMap Pr PullFacts := []
  heads : KeyMap Pr HeadFacts := []
  health : KeyMap Health Epoch := []
  deriving DecidableEq, Repr, Inhabited

def View.WF (v : View) : Prop := v.pulls.WF ∧ v.heads.WF ∧ v.health.WF

/-- Two views that agree on every lookup. `diff` cannot tell them apart (`DiffSeesOnlyLookups`). -/
def View.Equiv (v w : View) : Prop :=
  v.pulls.Equiv w.pulls ∧ v.heads.Equiv w.heads ∧ v.health.Equiv w.health

inductive Change
  | pull (d : Delta Pr PullFacts)
  | head (d : Delta Pr HeadFacts)
  | health (d : Delta Health Epoch)
  deriving DecidableEq, Repr

def View.diff (v w : View) : List Change :=
  (KeyMap.diff v.pulls w.pulls).map .pull ++ (KeyMap.diff v.heads w.heads).map .head ++
    (KeyMap.diff v.health w.health).map .health

/-- The second look: the runs page holds the newest 100 runs, so a head missing from it gets one
read of its own before `noRun` begins (`watch-github.sh`'s `confirm_missing_runs`). -/
inductive SecondLook
  | notAsked
  | noRunFound
  | runFound
  deriving DecidableEq, Repr

/-- What the shared state remembers about a head between polls. `misses` counts, per route, the
polls in a row whose read of that route failed. -/
structure HeadAge where
  firstSeen : Epoch
  look : SecondLook := .notAsked
  misses : KeyMap HeadRoute Nat := []
  deriving DecidableEq, Repr

def HeadAge.missesOf (a : HeadAge) (r : HeadRoute) : Nat := (a.misses.get? r).getD 0

/-- Whether one per-head read succeeded; `none` when it was not made (the second look is made only
when due). A reviews answer with a refused item is a failed read. -/
def HeadRead.ok? {owner : String} (h : HeadRead owner) : HeadRoute → Option Bool
  | .checks => some h.checks.isOk
  | .reviews => some h.reviews.isOk
  | .look => h.look.map (·.isOk)

structure Rules where
  ciMinutes : Nat := 10
  unreadAfter : Nat := 5
  deriving Repr

/-- Whether an owned head has gone `ciMinutes` with no `ci` run in the runs page. -/
def suspectsNoRun (r : Rules) (now : Epoch) (runs : List CiRun) (sha : String) (age : HeadAge) :
    Bool :=
  decide (age.firstSeen + 60 * r.ciMinutes ≤ now) && !runs.any (·.sha == sha)

/-- The newest run of each listed name decides it; for `scorecard-comment`, the newest that did not
skip, when one did not. -/
def Checks.of (runs : List CheckRun) : Checks := panic! "not implemented"

/-- Whether a head gets the second look this poll: the runs page has shown no `ci` run for it for
`ciMinutes`, and it has not been asked yet. `WatchCli` passes this to `Plan.perHead`. -/
def Plan.due {owner : String} (r : Rules) (now : Epoch) (ages : KeyMap (Pr × String) HeadAge)
    (runs : List CiRun) (h : OwnedHead owner) : Bool :=
  match ages.get? (h.pr, h.sha.text) with
  | some a => a.look == .notAsked && suspectsNoRun r now runs h.sha.text a
  | none => false

def ASuspectedHeadGetsTheSecondLook : Prop :=
  ∀ {owner : String} (r : Rules) now ages runs (heads : List (OwnedHead owner)) h, h ∈ heads →
    Plan.due r now ages runs h = true → .runsAt h ∈ Plan.perHead heads (Plan.due r now ages runs)

/-- The statuses of a run that has not started. -/
def queuedStates : List String := ["queued", "waiting", "pending", "requested"]

/-- `noRun` measures a head's age on the local clock, since its first sighting is local too.
`queued` measures a run's age on GitHub's clock (`fixed.serverNow` against the run's `created_at`,
which GitHub stamps), so a local clock that runs fast raises no alarm. `stale` needs no clock. -/
def ciHealth (r : Rules) (now : Epoch) (fixed : Fixed) (ages : KeyMap (Pr × String) HeadAge) :
    List Health :=
  panic! "not implemented"

def rabbitAlarm (owner : String) (pr : Pr) (sha : String) (assignees : Names) (c : Checks) :
    Option Health :=
  if owner ∈ assignees.items && c.coderabbit == some (.done "skipped") then
    some (.rabbitSkipped pr sha)
  else none

/-- The view one poll shows. Pulls are the open pulls read, each with its first listing, less any
that the same poll's closes name (closed between the `openPulls` and `closedSince` reads). Heads
come only from `reads` whose pull is in the view, of the owner's login and at the same sha, and only
from the first read of a pull request when `reads` names one twice. A head whose checks read
succeeded shows `Checks.of` of those runs. A head whose checks read failed keeps its facts from
`prev` when its sha is unchanged, and starts with no checks otherwise. A health key keeps its start
from `prev`. Health is `ciHealth` plus `rabbitAlarm` of each head plus `unread` for each route of a
head with `unreadAfter` misses, so the alarm statements below hold of the view itself, not only of
the helpers. -/
def View.of {owner : String} (r : Rules) (now : Epoch) (prev : View) (fixed : Fixed)
    (reads : List (HeadRead owner)) (ages : KeyMap (Pr × String) HeadAge) : View :=
  panic! "not implemented"

def OfIsWF : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages,
    (View.of r now prev fixed reads ages).WF

def HeadsAreOpenOwnedPulls : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (n : Pr),
    ((View.of r now prev fixed reads ages).heads.get? n).isSome →
    (∃ p ∈ fixed.pulls, p.number = n ∧ p.login = owner) ∧ fixed.closed.all (·.number != n) = true

/-- The positive half for pulls: the view's pulls are the open pulls this poll read, each with the
facts of its first listing, less those the same poll's closes name. Without it a `View.of` that
returns no pulls would meet every other statement, and every change would go untold. -/
def PullsAreTheOpenPullsRead : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (n : Pr),
    (View.of r now prev fixed reads ages).pulls.get? n =
      if fixed.closed.any (·.number == n) then none
      else (fixed.pulls.find? (·.number == n)).map PullFacts.ofOpen

/-- Moderate. `prev` reaches the view only through unread heads and the start of a health key:
with every checks read successful and the same health starts, two different `prev`s give views
with the same lookups. It is not idempotence of a re-read across two steps; `ages` and `now` are
fixed here. -/
def PrevReachesOnlyUnreadHeadsAndStarts : Prop :=
  ∀ {owner : String} (r : Rules) now prev prev' fixed (reads : List (HeadRead owner)) ages,
    (∀ h ∈ reads, ∃ cs, h.checks = .ok cs) → prev.health.Equiv prev'.health →
    (View.of r now prev fixed reads ages).Equiv (View.of r now prev' fixed reads ages)

/-- The pull is still open, still the owner's, at the same sha, not closed by the same poll, and no
other read names it. -/
def HeadRead.alone {owner : String} (fixed : Fixed) (reads : List (HeadRead owner))
    (h : HeadRead owner) : Prop :=
  (∃ p ∈ fixed.pulls, p.number = h.head.pr ∧ p.login = owner ∧ p.head = h.head.sha.text) ∧
    fixed.closed.all (·.number != h.head.pr) = true ∧
    reads.filter (fun x => x.head.pr == h.head.pr) = [h]

def UnreadHeadKeepsItsFacts : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages
    (h : HeadRead owner) (why : Excerpt) (f : HeadFacts),
    h ∈ reads → HeadRead.alone fixed reads h → h.checks = .error why →
    prev.heads.get? h.head.pr = some f → f.sha = h.head.sha.text →
    (View.of r now prev fixed reads ages).heads.get? h.head.pr = some f

/-- The positive half: a head read successfully shows what was read. Without it a `View.of` that
returns no heads would meet every other statement. -/
def ReadHeadShowsItsChecks : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages
    (h : HeadRead owner) (cs : List CheckRun),
    h ∈ reads → HeadRead.alone fixed reads h → h.checks = .ok cs →
    (View.of r now prev fixed reads ages).heads.get? h.head.pr = some ⟨h.head.sha.text, Checks.of cs⟩

/-- Moderate. A poll that reads the same facts again at a later time (a later local `now`, a later
`Date`, ages moved on) shows the same pulls and heads, and keeps the start of every health key that
stays. Only the set of health keys can move, and only through an alarm whose threshold time or a
miss count crossed: a condition that begins is news and wakes (`Change.wakes`), one that clears
wakes nobody. This is what keeps a copied trailer from spinning across polls (`NoNewsStaysQuiet`). -/
def AReReadMovesOnlyHealth : Prop :=
  ∀ {owner : String} (r : Rules) now now' prev fixed (t : Epoch) (reads : List (HeadRead owner))
    ages ages',
    let v := View.of r now prev fixed reads ages
    let v' := View.of r now' v { fixed with serverNow := t } reads ages'
    v.pulls.Equiv v'.pulls ∧ v.heads.Equiv v'.heads ∧
      ∀ k b, v.health.get? k = some b → (v'.health.get? k).isSome → v'.health.get? k = some b

/-! The alarms, each stated both ways on the view a poll shows (from fable's alarm statements). -/

/-- `noRun` is raised exactly for a head in the view that the runs page has shown no `ci` run for
`ciMinutes` and whose second look found none. -/
def NoRunNeedsTheSecondLook : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (pr : Pr)
    (sha : String),
    let v := View.of r now prev fixed reads ages
    (v.health.get? (.noRun pr sha)).isSome ↔
      ∃ h, v.heads.get? pr = some h ∧ h.sha = sha ∧
        ∃ age, ages.get? (pr, sha) = some age ∧ age.look = .noRunFound ∧
          suspectsNoRun r now fixed.runs sha age = true

def RabbitAlarmNeedsTheOwnerAssigned : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (pr : Pr)
    (sha : String),
    let v := View.of r now prev fixed reads ages
    (v.health.get? (.rabbitSkipped pr sha)).isSome ↔
      ∃ f h, v.pulls.get? pr = some f ∧ owner ∈ f.assignees.items ∧ v.heads.get? pr = some h ∧
        h.sha = sha ∧ h.checks.coderabbit = some (.done "skipped")

def StaleNeedsAnUnfinishedRunOffEveryHead : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (id : Nat),
    ((View.of r now prev fixed reads ages).health.get? (.stale id)).isSome ↔
      ∃ x ∈ fixed.runs, x.id = id ∧ x.status ≠ "completed" ∧ x.sha ≠ fixed.main ∧
        ∀ p ∈ fixed.pulls, p.head ≠ x.sha

/-- Measured on GitHub's clock, so a fast local clock raises nothing. -/
def QueuedIsMeasuredOnGitHubsClock : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (id : Nat),
    ((View.of r now prev fixed reads ages).health.get? (.queued id)).isSome ↔
      ∃ x ∈ fixed.runs, x.id = id ∧ x.status ∈ queuedStates ∧
        x.created + 60 * r.ciMinutes ≤ fixed.serverNow

/-- A head whose read of one route (checks, reviews or the second look) failed `unreadAfter` polls
in a row shows an `unread` key naming that route. So a reviews read that keeps failing is told, and
the owner's review words on that head are never lost with no line. -/
def AFailingHeadReadIsTold : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (pr : Pr)
    (sha : String) (route : HeadRoute),
    let v := View.of r now prev fixed reads ages
    (v.health.get? (.unread pr sha route)).isSome ↔
      ∃ h, v.heads.get? pr = some h ∧ h.sha = sha ∧
        ∃ age, ages.get? (pr, sha) = some age ∧ r.unreadAfter ≤ age.missesOf route

end MitosGate.Watch
