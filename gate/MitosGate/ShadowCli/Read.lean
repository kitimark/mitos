import Lean.Data.Json
import MitosGate.Shadow
import MitosGate.LandCli
import MitosGate.Carry

open Lean (Json)

namespace MitosGate.ShadowCli

open Shadow
open Land (Sha)

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

private def shaOrUnread : D Sha := fun j => do
  if (← str j).isEmpty then return "" else sha j

private def stamp : D Stamp := fun j => do
  let some t := Speech.stamp? (← str j).toList | throw ": expected a time, YYYY-MM-DDTHH:MM:SSZ"
  return t

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

def drifted : String := "drifted: "

private def cost : D Cost := fun j => do
  return ⟨← at' "setup" nat j, ← at' "fetch" nat j, ← at' "snapshot" nat j,
    ← at' "decide" nat j, ← at' "reads" nat j⟩

private def treeOf : D TreeOf := fun j => do
  return ⟨← at' "commit" sha j, ← at' "tree" sha j⟩

def run? (run : Nat) (j : Json) : Except String Run := do
  let v ← at' "v" nat j
  unless v == 1 do throw s!"v is {v}, and this scorer reads v 1"
  let t ← at' "trigger" trigger j
  match ← at' "outcome" (at' "kind" str) j with
  | "skipped" => return .skipped t (← at' "outcome" (at' "remaining" nat) j)
  | "refused" => return .refused t (← at' "outcome" (at' "stage" stage) j)
  | "decided" =>
    let read ← at' "read" stamp j
    let main ← at' "main" shaOrUnread j
    let after ← at' "mainAfter" shaOrUnread j
    let tool ← at' "tool" sha j
    let cost ← at' "cost" cost j
    let trees ← at' "outcome" (at' "trees" (list treeOf)) j
    let printed ← at' "outcome" (at' "decision" pure) j
    let s ← at' "outcome" (at' "snapshot" pure) j
    let s ← (LandCli.read s.compress).mapError (s!"{drifted}its snapshot is refused: " ++ ·)
    let now := s.decide.json
    unless now.compress == printed.compress do
      throw s!"{drifted}it printed {printed.compress}, and this build decides {now.compress}"
    return .decided { run, trigger := t, read, main := if main == after then main else "", tool,
                      cost, prs := s.prs, trees }
  | k => throw s!".outcome.kind: {k.quote} is not an outcome"

private def merge : D Merge := fun j => do
  return { pr := ← at' "pr" nat j, time := ← at' "time" stamp j,
           before := ← at' "before" shaOrUnread j, head := ← at' "head" sha j,
           tree := ← at' "tree" shaOrUnread j }

def merges : D (List Merge) := list merge

structure Job where
  id : Nat
  conclusion : String

private def job : D Job := fun j => do
  let c ← match j.getObjVal? "conclusion" with
    | .ok .null => pure ""
    | _ => at' "conclusion" conclusion j
  return ⟨← at' "id" nat j, c⟩

def jobs : D (List Job) := list job

def updaterCiRuns : D Nat := fun j => do
  let actors ← list (at' "actor" str) j
  return (actors.filter (· == Carry.updater)).length

end MitosGate.ShadowCli
