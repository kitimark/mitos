import Lean.Data.Json
import MitosGate.Shadow
import MitosGate.LandCli
import MitosGate.Carry
import MitosGate.SnapshotCli

open Lean (Json)

namespace MitosGate.ShadowCli

open Shadow
open Land (Sha Obs)

private abbrev D (α : Type) := Json → Except String α

private def at' (k : String) (d : D α) (j : Json) : Except String α :=
  match j.getObjVal? k with
  | .error _ => .error s!".{k}: missing"
  | .ok v => (d v).mapError fun e => s!".{k}{e}"

private def nat : D Nat := fun j =>
  match j.getNat? with
  | .ok n => .ok n
  | .error _ => .error ": expected a natural number"

private def str : D String := fun j =>
  match j.getStr? with
  | .ok s => .ok s
  | .error _ => .error ": expected a string"

private def sha : D Sha := fun j => do
  let s ← str j
  unless Speech.isSha s.toList do throw ": expected a commit, 40 hexadecimal digits"
  return s

private def shaOrUnread : D (Option Sha) := fun j => do
  if (← str j).isEmpty then return none else some <$> sha j

private def stamp : D Stamp := fun j => do
  let some t := Speech.stamp? (← str j).toList | throw ": expected a time, YYYY-MM-DDTHH:MM:SSZ"
  return ⟨t⟩

private def list (d : D α) : D (List α) := fun j =>
  match j.getArr? with
  | .error _ => .error ": expected a list"
  | .ok a => a.toList.mapIdx (fun i v => (d v).mapError fun e => s!"[{i}]{e}") |>.mapM id

private def conclusion : D String := fun j => do
  let s ← str j
  unless 0 < s.length && s.length ≤ 32 && s.all fun c => c.isLower || c == '_' do
    throw ": expected 1 to 32 of a-z and _"
  return s

private def trigger : D Trigger := fun j => do
  match ← at' "kind" str j with
  | "mainMoved" => return .mainMoved
  | "gateDone" => return .gateDone (← at' "head" sha j) (← at' "conclusion" conclusion j)
  | "comment" => return .comment (← at' "pr" nat j) (← at' "id" nat j)
  | "dispatch" => return .dispatch
  | k => throw s!".kind: {k.quote} is not a trigger"

inductive Stage
  | fetch
  | snapshot
  | land

private def stage : D Stage := fun j => do
  match ← str j with
  | "fetch" => return .fetch
  | "snapshot" => return .snapshot
  | "land" => return .land
  | s => throw s!": {s.quote} is not a stage"

inductive Run
  | decided (r : Shadow.Record)
  | refused (t : Shadow.Trigger) (s : Stage)
  | skipped (t : Shadow.Trigger) (remaining : Nat)

def Run.trigger : Run → Trigger
  | .decided r => r.trigger
  | .refused t _ | .skipped t _ => t

inductive Unscored
  | unreadable (why : String)
  | drifted (why : String)

private def cost : D Cost := fun j => do
  return ⟨← at' "setup" nat j, ← at' "fetch" nat j, ← at' "snapshot" nat j,
    ← at' "decide" nat j, ← at' "reads" nat j⟩

private def treeOf : D TreeOf := fun j => do
  return ⟨← at' "commit" sha j, ← at' "tree" sha j⟩

private structure Replay where
  record : List Obs → Record
  snapshot : Json
  printed : Json

private def parse (run : Nat) (j : Json) : Except String (Run ⊕ Replay) := do
  let v ← at' "v" nat j
  unless v == 1 do throw s!"v is {v}, and this scorer reads v 1"
  let t ← at' "trigger" trigger j
  match ← at' "outcome" (at' "kind" str) j with
  | "skipped" => return .inl (.skipped t (← at' "outcome" (at' "remaining" nat) j))
  | "refused" => return .inl (.refused t (← at' "outcome" (at' "stage" stage) j))
  | "decided" =>
    let read ← at' "read" stamp j
    let main ← at' "main" shaOrUnread j
    let after ← at' "mainAfter" shaOrUnread j
    let tool ← at' "tool" sha j
    let cost ← at' "cost" cost j
    let trees ← at' "outcome" (at' "trees" (list treeOf)) j
    let printed ← at' "outcome" (at' "decision" pure) j
    let snapshot ← at' "outcome" (at' "snapshot" pure) j
    let main := if main == after then main else none
    return .inr ⟨fun prs => { run, trigger := t, read, main, tool, cost, prs, trees }, snapshot,
      printed⟩
  | k => throw s!".outcome.kind: {k.quote} is not an outcome"

def run? (run : Nat) (j : Json) : Except Unscored Run := do
  match ← (parse run j).mapError .unreadable with
  | .inl r => return r
  | .inr d =>
    let s ← (LandCli.read d.snapshot.compress).mapError
      fun e => .drifted s!"its snapshot is refused: {e}"
    let now := s.decide.json
    unless now.compress == d.printed.compress do
      throw (.drifted s!"it printed {d.printed.compress}, and this build decides {now.compress}")
    return .decided (d.record s.prs)

private def routeComponent (s : String) : Bool :=
  !s.isEmpty && s != "." && s != ".." && s.toList.all fun c =>
    ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z') || ('0' ≤ c && c ≤ '9') ||
      c == '_' || c == '.' || c == '-'

def repositoryOwner : D String := fun j => do
  let full ← at' "full_name" str j
  let owner ← at' "owner" (at' "login" str) j
  unless routeComponent owner do throw ".owner.login: expected a route component"
  let [account, name] := full.splitOn "/" | throw ".full_name: expected owner/name"
  unless routeComponent account && routeComponent name do
    throw ".full_name: expected owner/name"
  unless account.toLower == owner.toLower do
    throw ".full_name: owner does not match owner.login"
  return owner

private def merge (owner : String) : D Merge := fun j => do
  let time ← at' "time" stamp j
  let reviewJson ← at' "reviews" pure j
  let commentJson ← at' "reviewComments" pure j
  let some reviews := SnapshotCli.reviewsOf (.arr #[reviewJson])
    | throw ".reviews: expected review route items"
  let some comments := SnapshotCli.reviewCommentsOf (.arr #[commentJson])
    | throw ".reviewComments: expected review comment route items"
  let reviews := reviews.filter fun v => v.submitted ≤ time.digits
  let comments := comments.filter fun c => c.created ≤ time.digits
  let g : Snapshot.Global :=
    { repo := "", owner := owner, protection := none, stacked := none,
      issueRead := false, provenance := none }
  let r : Snapshot.Reads := ⟨none, some comments, some reviews, none, none, none⟩
  let summary := if Snapshot.reviewsSpeak g r then Summary.spoke else .silent
  return { pr := ← at' "pr" nat j, time,
           before := ← at' "before" shaOrUnread j, head := ← at' "head" sha j,
           tree := ← at' "tree" shaOrUnread j, summary }

def merges (owner : String) : D (List Merge) := list (merge owner)

structure Job where
  id : Nat
  conclusion : Option String

private def conclusionOrRunning : D (Option String)
  | .null => return none
  | j => some <$> conclusion j

private def job : D Job := fun j => do
  let c ← at' "conclusion" conclusionOrRunning j
  return ⟨← at' "id" nat j, c⟩

def jobs : D (List Job) := list job

def updaterCiRuns : D Nat := fun j => do
  let actors ← list (at' "actor" str) j
  return (actors.filter (· == Carry.updater)).length

namespace Fixture

open Lean (toJson)

theorem anEmptyCommitIsUnread : (shaOrUnread (.str "")).toOption = some none := by
  decide +kernel
theorem aCommitIsRead : (shaOrUnread (.str (String.ofList (List.replicate 40 'a')))).toOption =
    some (some (String.ofList (List.replicate 40 'a'))) := by decide +kernel
theorem aRunningJobHasNoConclusion : (conclusionOrRunning .null).toOption = some none := by
  decide +kernel

private def reviewInput (login body : Json) : Json := Json.mkObj [
  ("id", toJson (4 : Nat)), ("user", Json.mkObj [("login", login)]),
  ("state", toJson "COMMENTED"), ("commit_id", toJson Snapshot.Fixture.hB),
  ("submitted_at", toJson "2026-11-14T07:59:00Z"), ("body", body)]
private def footerInput (id : Nat) : Json := Json.mkObj [
  ("pull_request_review_id", toJson id), ("user", Json.mkObj [("login", toJson "owner")]),
  ("created_at", toJson "2026-11-14T07:59:30Z"),
  ("updated_at", toJson "2026-11-14T07:59:30Z"),
  ("body", toJson ("Replied." ++ Snapshot.Fixture.footer))]
private def mergeInput (reviews comments : List Json) : Json := Json.arr #[Json.mkObj [
  ("pr", toJson (7 : Nat)), ("time", toJson "2026-11-14T08:03:00Z"),
  ("before", toJson Snapshot.Fixture.hA), ("head", toJson Snapshot.Fixture.hB),
  ("tree", toJson ""), ("reviews", toJson reviews), ("reviewComments", toJson comments)]]

theorem aPostlessOwnerReviewSpeaks :
    ((merges "owner" (mergeInput [reviewInput (toJson "owner") (toJson "")] [])).map
      (List.map (·.summary))).toOption = some [.spoke] := by decide +kernel
theorem aMatchingFooterLeavesTheSummarySilent :
    ((merges "owner" (mergeInput [reviewInput (toJson "owner") (toJson "")] [footerInput 4])).map
      (List.map (·.summary))).toOption = some [.silent] := by decide +kernel
theorem noOwnerReviewLeavesTheSummarySilent :
    ((merges "owner" (mergeInput [] [])).map (List.map (·.summary))).toOption = some [.silent] := by
  decide +kernel
theorem anUnrelatedFooterDoesNotSpareTheOwnerReview :
    ((merges "owner" (mergeInput [reviewInput (toJson "owner") (toJson "")] [footerInput 5])).map
      (List.map (·.summary))).toOption = some [.spoke] := by decide +kernel
theorem aNonownerReviewLeavesTheSummarySilent :
    ((merges "owner" (mergeInput [reviewInput (toJson "other") (toJson "")] [])).map
      (List.map (·.summary))).toOption = some [.silent] := by decide +kernel

end Fixture

end MitosGate.ShadowCli
