import Lean.Data.Json
import MitosGate.DecideList
import MitosGate.Watch.Route
import MitosGate.Watch.Voice

/-! UNCHECKED SKETCH (#502). One JSON reader per route. Nothing past this file sees JSON.

Each reader returns the facts or a refusal with a path-prefixed reason, as `SpeechCli.comment`
reads a comment. A reader never guesses, and it refuses at two levels:
* A whole answer whose shape is wrong (not UTF-8, not an array of pages of objects, a
  `total_count` that does not match its pages) or that holds an item with no readable `id` is
  refused, and so are the open-pulls and runs answers on any item they cannot read. The poll then
  fails with the route's name in its reason, and the view keeps what it had (`Shared.step`). A
  failed poll does not move the cursor, so the next poll asks for the same answer: such a refusal
  lasts until the answer changes or the tool is fixed, and every consumer hears it as `down` and
  then blind ends naming the route (`DESIGN.md`, Tradeoffs).
* Inside a well-formed answer of a post or close route, the reader first drops items of other
  logins (posts) or items that are not pull requests (closes), and only then checks fields. An
  item it still cannot read (an owner's issue comment without the app key, a missing time, a login
  it cannot read) becomes a `Refused` item: the rest of the answer applies, the cursor moves, and
  the item is kept in the feed and told once as `could not be read` (`Deliver`). So one bad item
  neither blinds every consumer nor hides an owner's words silently.

Per route, on purpose:
* issue comments must carry the `performed_via_github_app` key (null or an object). An owner item
  without it is refused, never defaulted, because a silent default would turn an agent's post into
  typed words. Every live issue comment carries it (2,276 issue comments read during review, none
  without it). The bash watcher's test fixtures predate the key, which is why PR 1's jq keeps the
  footer rule for an item without it, while this reader refuses one.
* review comments and reviews are read with `via := .absent`; they have no such key.
* reviews skip `PENDING`, and their time is `submitted_at` (`SnapshotCli.reviewsOf`). Their pull
  request comes from `pull_request_url`, so `watch unanswered` needs no `--pr`.
* check runs compare `total_count` with the runs read across pages, as `SnapshotCli.checksOf`.
`SpeechCli.comment` is not reused for the review routes: it requires the app key.

The readers are tested, not proved: `Json` lookups go through `Std.TreeMap.Raw`, whose lemmas need a
well-formedness hypothesis, and `Json.parse` is `partial`. Fixtures in `gate/watch-fixtures/` are
captured from live reads (PR 4) and edited copies of them. Layout copies `SnapshotCli`'s readers.

`watch unanswered` (pr-state) uses the same post readers and exits 1 when any item is refused, so
pr-state shows `?`, never "answered". PR 2 carries only the three post readers, `Refused`,
`Reading` and `readJsonFile`, and does not import `Route` or `DecideList`. `Names` and the other
readers come in PR 4, with their imports. -/

namespace MitosGate.Watch

open Lean (Json)
open Land (Pr)

inductive Author
  | own
  | outside
  deriving DecidableEq, Repr

/-- Label names or logins: sorted with `DecideList.sortStrings` and without repeats, so a reordered
answer, a repeat or a comma inside a name cannot change a comparison (#239). -/
structure Names where
  items : List String
  deriving DecidableEq, Repr

def Names.of (xs : List String) : Names := ⟨(DecideList.sortStrings xs).eraseDups⟩

/-- Moderate: two sorted lists without repeats and with the same members are equal. It needs
`String`'s `<` to be a strict total order, which holds for the lexicographic order on `List Char`. -/
def NamesOfIgnoresOrderAndRepeats : Prop :=
  ∀ xs ys : List String, (∀ x, x ∈ xs ↔ x ∈ ys) → Names.of xs = Names.of ys

namespace Fixture

theorem namesKeepACommaInsideAName :
    Names.of ["needs-rebase", "a,b", "needs-rebase"] = ⟨["a,b", "needs-rebase"]⟩ := by
  decide +kernel

end Fixture

structure OpenPull where
  number : Pr
  login : String
  author : Author
  labels : Names
  assignees : Names
  head : String
  deriving Repr

structure ClosedPull where
  number : Pr
  author : Author
  merged : Bool
  closedAt : Epoch
  deriving DecidableEq, Repr

structure CiRun where
  id : Nat
  sha : String
  status : String
  created : Epoch
  deriving DecidableEq, Repr

inductive Run
  | pending
  | done (conclusion : String)
  deriving DecidableEq, Repr

def Run.isDone : Run → Bool
  | .done _ => true
  | .pending => false

/-- The four names a consumer reads. Any other name is counted, never named, so a workflow cannot
choose a name that reaches a consumer. -/
inductive Listed
  | gate
  | prove
  | scorecard
  | coderabbit
  deriving DecidableEq, Repr

def Listed.ofName? : String → Option Listed
  | "gate" => some .gate
  | "prove" => some .prove
  | "scorecard-comment" => some .scorecard
  | "CodeRabbit" => some .coderabbit
  | _ => none

def Listed.all : List Listed := [.gate, .prove, .scorecard, .coderabbit]

/-- What kind of item a reader could not read. -/
inductive ItemKind
  | post (place : Place)
  | close
  deriving DecidableEq, Repr

/-- One item of a post or close route that a reader could not read. It does not fail the poll. The
feed keeps it, and each consumer whose scope covers its thread (or every consumer, when the thread
is unknown) is told it once (`ARefusedItemIsTold`). -/
structure Refused where
  kind : ItemKind
  id : Nat
  thread : Option Pr
  why : Excerpt
  deriving DecidableEq

/-- What a post or close reader gives: the items it read and the ones it could not. -/
structure Reading (α : Type) where
  items : List α
  refused : List Refused

structure CheckRun where
  id : Nat
  name : Option Listed
  run : Run
  deriving DecidableEq, Repr

/-- What one owned head's reads gave. Each read may fail alone; `View.of` keeps the head's facts
when its checks read failed, and `Shared.nextAges` counts a miss for each read that failed. A
reviews answer with a refused item counts as a failed reviews read for that head. -/
structure HeadRead (owner : String) where
  head : OwnedHead owner
  checks : Except Excerpt (List CheckRun)
  reviews : Except Excerpt (List Said)
  look : Option (Except Excerpt (List CiRun))

/-- One successful poll's fixed reads, after the readers. `serverNow` is the `Date` header of the
`main` read, GitHub's clock for the feed and for how long a run has been queued. `refused` holds
the items the post and close readers could not read. -/
structure Fixed where
  serverNow : Epoch
  runs : List CiRun
  pulls : List OpenPull
  closed : List ClosedPull
  main : String
  posts : List Said
  refused : List Refused

/-- The heads a poll reads: the open pull requests of the owner's login with a valid head, and
nothing else. `WatchCli` reads checks and reviews only for these. -/
def Plan.heads (owner : String) (fixed : Fixed) : List (OwnedHead owner) :=
  fixed.pulls.filterMap fun p => OwnedHead.of? owner p.number p.login p.head

def HeadsComeFromOpenPulls : Prop :=
  ∀ (owner : String) (fixed : Fixed), ∀ h ∈ Plan.heads owner fixed,
    ∃ p ∈ fixed.pulls, p.number = h.pr ∧ p.login = owner ∧ p.head = h.sha.text

/-- No per-head route reads a pull request of another login: every route the plan makes for this
poll's heads names an open pull request of the owner's login, read this poll, at that head. This is
the composite of `Plan.heads` and `Plan.perHead`; `OwnedHead.mine` alone would not say it, since
its `login` is a free field. -/
def OutsidePullsAreNeverRead : Prop :=
  ∀ (owner : String) (fixed : Fixed) (due : OwnedHead owner → Bool) (r : Route owner) (n : Pr),
    r ∈ Plan.perHead (Plan.heads owner fixed) due → r.about = some n →
    ∃ p ∈ fixed.pulls, p.number = n ∧ p.login = owner ∧
      ∃ h : OwnedHead owner, (r = .checks h ∨ r = .reviews h ∨ r = .runsAt h) ∧ p.head = h.sha.text

def openPulls (owner : String) (j : Json) : Except String (List OpenPull) :=
  panic! "not implemented"

/-- Items of the issues route with a `pull_request` key; `merged` from `pull_request.merged_at`.
Other items are dropped first; a pull request item it cannot read is `Refused` (`.close`). -/
def closedPulls (owner : String) (j : Json) : Except String (Reading ClosedPull) :=
  panic! "not implemented"

def ciRuns (j : Json) : Except String (List CiRun) := panic! "not implemented"

def mainSha (j : Json) : Except String String := panic! "not implemented"

/-- Drops other logins first, then reads the owner's items; an owner item without
`performed_via_github_app` is `Refused`, never defaulted. -/
def issueComments (owner : String) (j : Json) : Except String (Reading Said) :=
  panic! "not implemented"

def reviewComments (owner : String) (j : Json) : Except String (Reading Said) :=
  panic! "not implemented"

/-- The thread is the number at the end of `pull_request_url`. -/
def reviews (owner : String) (j : Json) : Except String (Reading Said) :=
  panic! "not implemented"

def checkRuns (j : Json) : Except String (List CheckRun) := panic! "not implemented"

/-- Reads a file of route answers for `watch unanswered` and the fixtures: bytes, then
`String.fromUTF8?`, then `Json.parse`. `IO.FS.readFile` throws on bytes that are not UTF-8, so it is
not used (`RunLog.readText`). -/
def readJsonFile (path : System.FilePath) : IO (Except String Json) := do
  match String.fromUTF8? (← IO.FS.readBinFile path) with
  | none => return .error s!"{path}: not valid UTF-8"
  | some s => return (Json.parse s).mapError fun e => s!"{path}: {e}"

end MitosGate.Watch
