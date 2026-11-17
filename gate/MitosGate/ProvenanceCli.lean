import MitosGate.Provenance.Decode
import MitosGate.SnapshotCli

namespace MitosGate.ProvenanceCli

open Lean (Json)
open Land (Sha Obs)
open SnapshotCli (load field str arr)

private def read (dir : System.FilePath) (name : String) : IO (Option Json) := do
  if ← (dir / (name ++ ".failed")).pathExists then return none
  load dir name

private def inputs (dir : System.FilePath) (repo owner : String) :
    IO (Except String (List Snapshot.Pull × List Provenance.PullFact)) := do
  let some dash ← read dir "dash" | return .error "dashboard unavailable"
  let some issues := arr dash | return .error "dashboard list malformed"
  unless issues.length < 30 do return .error "dashboard list incomplete"
  let dashboards := issues.filterMap (SnapshotCli.dashboardOf owner)
  let [body] := dashboards | return .error "dashboard missing or duplicated"
  let .ok facts := Provenance.decode repo body | return .error "source refused"
  let some openJ ← read dir "open" | return .error "open pulls unavailable"
  let some all := arr openJ | return .error "open pulls malformed"
  unless all.length ≤ 11 do return .error "open pulls exceed bound"
  let selected := (all.take 10).filter (fun j => SnapshotCli.login "user" j == some owner)
  let some pulls := selected.mapM SnapshotCli.pull | return .error "open pulls malformed"
  unless (pulls.map (·.number)).eraseDups.length == pulls.length do
    return .error "open pulls duplicated"
  return .ok (pulls, facts)

private def value (head : Sha) (candidate eligible : Bool) (reason : String) : Json :=
  Json.mkObj [("head", .str head), ("candidate", .bool candidate), ("eligible", .bool eligible),
    ("reason", .str reason)]

private def observation (p : Snapshot.Pull) (paths : List String) (pushes : List Carry.Push)
    (ids : List (Sha × String)) : Obs :=
  { pr := p.number, updatable := false, enforced := false, head := p.head,
    pushes := pushes.map Snapshot.toLand, ids, paths := some paths, base := .unread,
    gate := .missing, author := none, verdicts := [], botAt := none, delegates := [],
    words := [], rest := true }

private def localId (main head : Sha) : IO (Option String) := do
  unless ← SnapshotCli.has head do return none
  try
    match ← (ContentId.compute main head).run with
    | .ok r => return some r.id
    | .error _ => return none
  catch _ => return none

private def finalValue (dir : System.FilePath) (main : Sha) (p : Snapshot.Pull)
    (f : Provenance.PullFact) : IO Json := do
  let some filesJ ← read dir s!"files-{p.number}"
    | return value p.head true false "input-unavailable"
  let some fs := arr filesJ | return value p.head true false "input-unavailable"
  unless fs.length < 100 do return value p.head true false "input-unavailable"
  let some paths := SnapshotCli.filesOf (.arr #[filesJ])
    | return value p.head true false "input-unavailable"
  let some activityJ ← read dir s!"activity-{p.number}"
    | return value p.head true false "input-unavailable"
  let some pushes := (SnapshotCli.activityOf activityJ).filter (Snapshot.pushesOk p.head)
    | return value p.head true false "input-unavailable"
  let heads := (p.head :: f.author.head :: f.verdicts.map (·.head)).eraseDups
  let mut ids := []
  for head in heads do
    let some id ← localId main head
      | return value p.head true false "local-content-unavailable"
    ids := (head, id) :: ids
  let eligible := Provenance.admitted (observation p paths pushes ids) f p.labels
  return value p.head true eligible (if eligible then "provenance-ready" else "provenance-incomplete")

private def run (dir : System.FilePath) (repo owner : String) (main : Option Sha) : IO UInt32 := do
  let .ok (pulls, facts) ← inputs dir repo owner | do
    IO.eprintln "provenance: source or routes refused"
    return 1
  if let some sha := main then
    unless Speech.isSha sha.toList && (← SnapshotCli.has sha) do
      IO.eprintln "provenance: local main unavailable"
      return 1
  let mut out := []
  for p in pulls do
    let v ← match facts.find? (·.number == p.number) with
      | none => pure (value p.head false false "source-pending")
      | some f =>
        if f.verdicts.isEmpty then pure (value p.head false false "source-pending")
        else match main with
          | none => pure (value p.head true false "source-pending")
          | some sha => finalValue dir sha p f
    out := (toString p.number, v) :: out
  IO.println (Json.mkObj out.reverse).compress
  return 0

def cli (args : List String) (usage : String) : IO UInt32 := do
  match args with
  | ["candidates", dir, repo, owner] => run dir repo owner none
  | ["hook", dir, repo, owner, main] => run dir repo owner (some main)
  | ["render", repo, file] =>
    let payload := (← IO.FS.readFile file).trimAscii.toString
    let .ok j := Json.parse payload | do
      IO.eprintln "provenance: malformed JSON"
      return 1
    unless payload == j.compress do
      IO.eprintln "provenance: expected canonical payload bytes"
      return 1
    let .ok _ := Provenance.decodePayload repo j | do
      IO.eprintln "provenance: source payload refused"
      return 1
    IO.println (Provenance.block j)
    return 0
  | _ => IO.eprintln usage; return 2

end MitosGate.ProvenanceCli
