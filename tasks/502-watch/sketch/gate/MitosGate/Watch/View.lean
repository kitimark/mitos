import MitosGate.Watch.KeyMap
import MitosGate.Watch.Observe

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

structure View where
  pulls : KeyMap Pr PullFacts := []
  heads : KeyMap Pr HeadFacts := []
  health : KeyMap Health Epoch := []
  deriving DecidableEq, Repr, Inhabited

def View.WF (v : View) : Prop := v.pulls.WF ∧ v.heads.WF ∧ v.health.WF

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

inductive SecondLook
  | notAsked
  | noRunFound
  | runFound
  deriving DecidableEq, Repr

structure HeadAge where
  firstSeen : Epoch
  look : SecondLook := .notAsked
  misses : KeyMap HeadRoute Nat := []
  deriving DecidableEq, Repr

def HeadAge.missesOf (a : HeadAge) (r : HeadRoute) : Nat := (a.misses.get? r).getD 0

def HeadRead.ok? {owner : String} (h : HeadRead owner) : HeadRoute → Option Bool
  | .checks => some h.checks.isOk
  | .reviews => some h.reviews.isOk
  | .look => h.look.map (·.isOk)

structure Rules where
  ciMinutes : Nat := 10
  unreadAfter : Nat := 5
  deriving Repr

def suspectsNoRun (r : Rules) (now : Epoch) (runs : List CiRun) (sha : String) (age : HeadAge) :
    Bool :=
  decide (age.firstSeen + 60 * r.ciMinutes ≤ now) && !runs.any (·.sha == sha)

/-- The newest run of each listed name decides it; for `scorecard-comment`, the newest that did not
skip, when one did not. -/
def Checks.of (runs : List CheckRun) : Checks := panic! "not implemented"

def Plan.due {owner : String} (r : Rules) (now : Epoch) (ages : KeyMap (Pr × String) HeadAge)
    (runs : List CiRun) (h : OwnedHead owner) : Bool :=
  match ages.get? (h.pr, h.sha.text) with
  | some a => a.look == .notAsked && suspectsNoRun r now runs h.sha.text a
  | none => false

def ASuspectedHeadGetsTheSecondLook : Prop :=
  ∀ {owner : String} (r : Rules) now ages runs (heads : List (OwnedHead owner)) h, h ∈ heads →
    Plan.due r now ages runs h = true → .runsAt h ∈ Plan.perHead heads (Plan.due r now ages runs)

def queuedStates : List String := ["queued", "waiting", "pending", "requested"]

/-- `noRun` measures a head's age on the local clock.
`queued` measures a run's age on GitHub's clock (`fixed.serverNow` against the run's `created_at`).
`stale` needs no clock. -/
def ciHealth (r : Rules) (now : Epoch) (fixed : Fixed) (ages : KeyMap (Pr × String) HeadAge) :
    List Health :=
  panic! "not implemented"

def rabbitAlarm (owner : String) (pr : Pr) (sha : String) (assignees : Names) (c : Checks) :
    Option Health :=
  if owner ∈ assignees.items && c.coderabbit == some (.done "skipped") then
    some (.rabbitSkipped pr sha)
  else none

/-- The view one poll shows. Pulls are the open pulls read, each with its first listing, less any
that the same poll's closes name. Heads
come only from `reads` whose pull is in the view, of the owner's login and at the same sha, and only
from the first read of a pull request when `reads` names one twice. A head whose checks read
succeeded shows `Checks.of` of those runs. A head whose checks read failed keeps its facts from
`prev` when its sha is unchanged, and starts with no checks otherwise. A health key keeps its start
from `prev`. Health is `ciHealth` plus `rabbitAlarm` of each head plus `unread` for each route of a
head with `unreadAfter` misses. -/
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

def PullsAreTheOpenPullsRead : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (n : Pr),
    (View.of r now prev fixed reads ages).pulls.get? n =
      if fixed.closed.any (·.number == n) then none
      else (fixed.pulls.find? (·.number == n)).map PullFacts.ofOpen

def PrevReachesOnlyUnreadHeadsAndStarts : Prop :=
  ∀ {owner : String} (r : Rules) now prev prev' fixed (reads : List (HeadRead owner)) ages,
    (∀ h ∈ reads, ∃ cs, h.checks = .ok cs) → prev.health.Equiv prev'.health →
    (View.of r now prev fixed reads ages).Equiv (View.of r now prev' fixed reads ages)

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

def ReadHeadShowsItsChecks : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages
    (h : HeadRead owner) (cs : List CheckRun),
    h ∈ reads → HeadRead.alone fixed reads h → h.checks = .ok cs →
    (View.of r now prev fixed reads ages).heads.get? h.head.pr = some ⟨h.head.sha.text, Checks.of cs⟩

def AReReadMovesOnlyHealth : Prop :=
  ∀ {owner : String} (r : Rules) now now' prev fixed (t : Epoch) (reads : List (HeadRead owner))
    ages ages',
    let v := View.of r now prev fixed reads ages
    let v' := View.of r now' v { fixed with serverNow := t } reads ages'
    v.pulls.Equiv v'.pulls ∧ v.heads.Equiv v'.heads ∧
      ∀ k b, v.health.get? k = some b → (v'.health.get? k).isSome → v'.health.get? k = some b

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

def QueuedIsMeasuredOnGitHubsClock : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (id : Nat),
    ((View.of r now prev fixed reads ages).health.get? (.queued id)).isSome ↔
      ∃ x ∈ fixed.runs, x.id = id ∧ x.status ∈ queuedStates ∧
        x.created + 60 * r.ciMinutes ≤ fixed.serverNow

def AFailingHeadReadIsTold : Prop :=
  ∀ {owner : String} (r : Rules) now prev fixed (reads : List (HeadRead owner)) ages (pr : Pr)
    (sha : String) (route : HeadRoute),
    let v := View.of r now prev fixed reads ages
    (v.health.get? (.unread pr sha route)).isSome ↔
      ∃ h, v.heads.get? pr = some h ∧ h.sha = sha ∧
        ∃ age, ages.get? (pr, sha) = some age ∧ r.unreadAfter ≤ age.missesOf route

end MitosGate.Watch
