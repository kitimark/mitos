import Lean.Data.Json
import MitosGate.DecideList
import MitosGate.Watch.Route
import MitosGate.Watch.Voice

namespace MitosGate.Watch

open Lean (Json)
open Land (Pr)

inductive Author
  | own
  | outside
  deriving DecidableEq, Repr

structure Names where
  items : List String
  deriving DecidableEq, Repr

def Names.of (xs : List String) : Names := ⟨(DecideList.sortStrings xs).eraseDups⟩

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

inductive ItemKind
  | post (place : Place)
  | close
  deriving DecidableEq, Repr

structure Refused where
  kind : ItemKind
  id : Nat
  thread : Option Pr
  why : Excerpt
  deriving DecidableEq

structure Reading (α : Type) where
  items : List α
  refused : List Refused

structure CheckRun where
  id : Nat
  name : Option Listed
  run : Run
  deriving DecidableEq, Repr

structure HeadRead (owner : String) where
  head : OwnedHead owner
  checks : Except Excerpt (List CheckRun)
  reviews : Except Excerpt (List Said)
  look : Option (Except Excerpt (List CiRun))

structure Fixed where
  serverNow : Epoch
  runs : List CiRun
  pulls : List OpenPull
  closed : List ClosedPull
  main : String
  posts : List Said
  refused : List Refused

def Plan.heads (owner : String) (fixed : Fixed) : List (OwnedHead owner) :=
  fixed.pulls.filterMap fun p => OwnedHead.of? owner p.number p.login p.head

def HeadsComeFromOpenPulls : Prop :=
  ∀ (owner : String) (fixed : Fixed), ∀ h ∈ Plan.heads owner fixed,
    ∃ p ∈ fixed.pulls, p.number = h.pr ∧ p.login = owner ∧ p.head = h.sha.text

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

def readJsonFile (path : System.FilePath) : IO (Except String Json) := do
  match String.fromUTF8? (← IO.FS.readBinFile path) with
  | none => return .error s!"{path}: not valid UTF-8"
  | some s => return (Json.parse s).mapError fun e => s!"{path}: {e}"

end MitosGate.Watch
