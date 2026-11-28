import MitosGate.Land
import MitosGate.Speech.Syntax
import MitosGate.Watch.Time

namespace MitosGate.Watch

open Land (Pr)

def segChar (c : Char) : Bool :=
  c.isAlphanum || c == '-' || c == '_' || c == '.'

abbrev SafeSegment (s : String) : Prop :=
  s ≠ "" ∧ s ≠ "." ∧ s ≠ ".." ∧ s.all segChar = true

structure Repo where
  owner : String
  name : String
  ok : SafeSegment owner ∧ SafeSegment name

def Repo.parse? (s : String) : Option Repo :=
  match s.splitOn "/" with
  | [o, n] => if h : SafeSegment o ∧ SafeSegment n then some ⟨o, n, h⟩ else none
  | _ => none

structure Sha40 where
  text : String
  ok : Speech.isSha text.toList = true

instance : DecidableEq Sha40 := fun a b =>
  if h : a.text = b.text then isTrue (by cases a; cases b; simp_all) else isFalse (by
    intro e; cases e; exact h rfl)

def Sha40.of? (s : String) : Option Sha40 :=
  if h : Speech.isSha s.toList = true then some ⟨s, h⟩ else none

def Sha40.short (s : Sha40) : String := String.ofList (s.text.toList.take 7)

structure OwnedHead (owner : String) where
  pr : Pr
  login : String
  sha : Sha40
  mine : login = owner

def OwnedHead.of? (owner : String) (pr : Pr) (login : String) (sha : String) :
    Option (OwnedHead owner) :=
  match Sha40.of? sha with
  | some s => if h : login = owner then some ⟨pr, login, s, h⟩ else none
  | none => none

inductive Route (owner : String)
  | runs
  | openPulls
  | closedSince (t : Epoch)
  | main
  | issueCommentsSince (t : Epoch)
  | reviewCommentsSince (t : Epoch)
  | checks (h : OwnedHead owner)
  | reviews (h : OwnedHead owner)
  | runsAt (h : OwnedHead owner)

def Repo.api (repo : Repo) (rest : String) : String :=
  s!"repos/{repo.owner}/{repo.name}/{rest}"

def Route.path {owner : String} (repo : Repo) : Route owner → String
  | .runs => repo.api "actions/workflows/ci.yml/runs?per_page=100"
  | .openPulls => repo.api "pulls?state=open&per_page=100"
  | .closedSince t =>
    repo.api s!"issues?state=closed&sort=updated&direction=desc&since={iso t}&per_page=100"
  | .main => repo.api "branches/main"
  | .issueCommentsSince t => repo.api s!"issues/comments?since={iso t}&per_page=100"
  | .reviewCommentsSince t => repo.api s!"pulls/comments?since={iso t}&per_page=100"
  | .checks h => repo.api s!"commits/{h.sha.text}/check-runs?per_page=100"
  | .reviews h => repo.api s!"pulls/{h.pr}/reviews?per_page=100"
  | .runsAt h => repo.api s!"actions/workflows/ci.yml/runs?head_sha={h.sha.text}&per_page=5"

def Route.paged {owner : String} : Route owner → Bool
  | .runs | .main | .runsAt _ => false
  | .openPulls | .closedSince _ | .issueCommentsSince _ | .reviewCommentsSince _
  | .checks _ | .reviews _ => true

def Route.headers {owner : String} : Route owner → Bool
  | .main => true
  | _ => false

def Route.argv {owner : String} (repo : Repo) (r : Route owner) : List String :=
  ["api"] ++ (if r.paged then ["--paginate", "--slurp"] else []) ++
    (if r.headers then ["--include"] else []) ++ [r.path repo]

def Route.about {owner : String} : Route owner → Option Pr
  | .checks h | .reviews h | .runsAt h => some h.pr
  | _ => none

def Plan.clock (owner : String) : Route owner := .main

def Plan.fixed (owner : String) (since : Epoch) : List (Route owner) :=
  [.runs, .openPulls, .closedSince since, .issueCommentsSince since, .reviewCommentsSince since]

def Plan.perHead {owner : String} (heads : List (OwnedHead owner)) (due : OwnedHead owner → Bool) :
    List (Route owner) :=
  heads.flatMap fun h => [.checks h, .reviews h] ++ (if due h then [.runsAt h] else [])

def pathChar (c : Char) : Bool :=
  segChar c || c == '/' || c == '?' || c == '=' || c == '&' || c == ':'

def OnlyRestReads : Prop :=
  ∀ (owner : String) (repo : Repo) (r : Route owner),
    (r.argv repo).head? = some "api" ∧ (r.path repo).startsWith "repos/" = true ∧
    ∀ a ∈ r.argv repo, a = "api" ∨ a = "--paginate" ∨ a = "--slurp" ∨ a = "--include" ∨
      a = r.path repo

def SegmentsAreSafe : Prop :=
  ∀ (owner : String) (repo : Repo) (r : Route owner), (r.path repo).all pathChar = true

def PollCallsBounded : Prop :=
  ∀ (owner : String) (since : Epoch) (heads : List (OwnedHead owner)) due,
    (Plan.clock owner :: Plan.fixed owner since ++ Plan.perHead heads due).length ≤
      6 + 3 * heads.length

end MitosGate.Watch
