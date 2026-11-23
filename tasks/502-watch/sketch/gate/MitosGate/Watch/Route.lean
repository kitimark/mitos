import MitosGate.Land
import MitosGate.Speech.Syntax
import MitosGate.Watch.Time

/-! UNCHECKED SKETCH (#502). The closed set of REST reads one poll may make.

A route is data, so three habits of the bash watcher become statements: it only reads (no `-X`,
`-f` or `-F` can appear), it never reads the head, checks or reviews of a pull request from
another account (a fork's workflow chooses its check names and could spend the REST limit the
agents share; `OutsidePullsAreNeverRead` in `Observe.lean` states it over the poll's plan), and one
poll starts a bounded number of `gh` processes. The path is built only from
parts that carry a proof that they are safe, so no input can add a query parameter or a path
segment. One route, `main`, is read with `--include`, so its answer carries GitHub's `Date` header,
which is the feed's clock (`Time.lean`). Layout copies `Carry.lean`: the data, its one renderer,
then the statements. -/

namespace MitosGate.Watch

open Land (Pr)

def segChar (c : Char) : Bool :=
  c.isAlphanum || c == '-' || c == '_' || c == '.'

/-- An `abbrev`, so `if h : SafeSegment o ∧ SafeSegment n` finds its `Decidable` instance. -/
abbrev SafeSegment (s : String) : Prop :=
  s ≠ "" ∧ s ≠ "." ∧ s ≠ ".." ∧ s.all segChar = true

/-- `owner/name`, checked once where `WatchCli` reads `--repo`. -/
structure Repo where
  owner : String
  name : String
  ok : SafeSegment owner ∧ SafeSegment name

def Repo.parse? (s : String) : Option Repo :=
  match s.splitOn "/" with
  | [o, n] => if h : SafeSegment o ∧ SafeSegment n then some ⟨o, n, h⟩ else none
  | _ => none

/-- Forty lowercase hex digits, as `Speech.isSha` reads them. -/
structure Sha40 where
  text : String
  ok : Speech.isSha text.toList = true

instance : DecidableEq Sha40 := fun a b =>
  if h : a.text = b.text then isTrue (by cases a; cases b; simp_all) else isFalse (by
    intro e; cases e; exact h rfl)

def Sha40.of? (s : String) : Option Sha40 :=
  if h : Speech.isSha s.toList = true then some ⟨s, h⟩ else none

def Sha40.short (s : Sha40) : String := String.ofList (s.text.toList.take 7)

/-- An open pull request of the owner's login with a valid head. Only `OwnedHead.of?` makes one,
and the proof travels with it, so a route about a pull request names the owner's or none. -/
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

/-- `closedSince` reads the issues route, which takes `since` and pages, where the pulls route
takes neither: the bash watcher read 50 closed pull requests and missed the rest of a long gap. An
item is a pull request when it has a `pull_request` key; `pull_request.merged_at` says merged
(PR 4 confirms both fields with a live read before the reader relies on them). -/
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

/-- Only `main` keeps its headers: `Gh` splits them off and reads `Date`. -/
def Route.headers {owner : String} : Route owner → Bool
  | .main => true
  | _ => false

/-- The whole argument vector of the one `gh` process a route runs. -/
def Route.argv {owner : String} (repo : Repo) (r : Route owner) : List String :=
  ["api"] ++ (if r.paged then ["--paginate", "--slurp"] else []) ++
    (if r.headers then ["--include"] else []) ++ [r.path repo]

def Route.about {owner : String} : Route owner → Option Pr
  | .checks h | .reviews h | .runsAt h => some h.pr
  | _ => none

/-- The fixed reads of one poll, in order. `main` comes first because its `Date` header gives
`serverNow`; `since` is then `Feed.sinceAt serverNow`, on GitHub's clock. `openPulls` comes before
`closedSince`, so a pull request closed between the two reads is in both answers; `View.of` drops
it from the view, and its leaving and its close arrive in the same poll. -/
def Plan.clock (owner : String) : Route owner := .main

def Plan.fixed (owner : String) (since : Epoch) : List (Route owner) :=
  [.runs, .openPulls, .closedSince since, .issueCommentsSince since, .reviewCommentsSince since]

/-- The reads for each owned head: its checks and reviews, and a run read when `due` says the runs
page has shown no `ci` run for it long enough (the second look before `noRun`). -/
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

/-- No flag can follow from a path: it starts with `repos/`. So `-X`, `-f`, `-F`, `--method` and
`--input` are out by `OnlyRestReads`; this one says no path holds a space or a `#`. Moderate: it
needs `iso`'s characters and `toString` of a `Nat`. -/
def SegmentsAreSafe : Prop :=
  ∀ (owner : String) (repo : Repo) (r : Route owner), (r.path repo).all pathChar = true

/-- Bounds `gh` processes, not REST requests: six of the nine routes page, and each page is a
request. PR 12 counts the requests one poll makes. -/
def PollCallsBounded : Prop :=
  ∀ (owner : String) (since : Epoch) (heads : List (OwnedHead owner)) due,
    (Plan.clock owner :: Plan.fixed owner since ++ Plan.perHead heads due).length ≤
      6 + 3 * heads.length

end MitosGate.Watch
