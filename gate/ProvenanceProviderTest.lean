import MitosGate.SnapshotCli

open Lean MitosGate MitosGate.Provenance

private def identityView (i : Identity) : Json :=
  Json.mkObj [("provider", .str i.provider), ("actor", .str i.actor),
    ("actualModel", i.actualModel.map Json.str |>.getD .null),
    ("requestedModel", i.requestedModel.map Json.str |>.getD .null)]

private def factView (p : PullFact) : Json :=
  Json.mkObj [("number", toJson p.number), ("head", .str p.author.head),
    ("author", identityView p.author.identity),
    ("verdicts", toJson (p.verdicts.map fun v => Json.mkObj [
      ("head", .str v.head), ("identity", identityView v.identity),
      ("effort", match v.effort with
        | none => .null
        | some .low => .str "low" | some .medium => .str "medium" | some .high => .str "high"
        | some .xhigh => .str "xhigh" | some .max => .str "max"), ("result", .str (SnapshotCli.resultName v.result)),
      ("order", toJson v.order), ("evidence", .str v.evidence)]))]

def main (args : List String) : IO UInt32 := do
  let [path] := args | return 2
  let .ok [f] := decode "kitimark/mitos" (← IO.FS.readFile path) | return 1
  let g : Snapshot.Global :=
    { Snapshot.Fixture.g with
      repo := "kitimark/mitos"
      owner := "kitimark"
      provenance := some [f] }
  let p : Snapshot.Pull :=
    { Snapshot.Fixture.pull with
      number := f.number
      head := f.author.head
      headRepo := some g.repo
      baseRepo := g.repo }
  let r : Snapshot.Reads :=
    { Snapshot.Fixture.reads with
      comments := some [⟨900, g.owner, none, 20261118080000, 20261118080000,
        "/land " ++ p.head⟩]
      activity := some [⟨"2026-11-18T07:00:00Z", "branch_creation", g.owner,
        "0000000000000000000000000000000000000000", p.head⟩]
      reviews := some [⟨3, "coderabbitai[bot]", "COMMENTED", p.head, 20261118070100, "Review."⟩]
      checks := some [⟨10, "gate", "github-actions", p.head, "completed", "success"⟩] }
  let x : Snapshot.Git := ⟨[(p.head, "fixture-content")], .current⟩
  let o := Snapshot.obs g p r x
  IO.println (Json.mkObj [("facts", factView f),
    ("snapshot", Json.mkObj [("prs", toJson [SnapshotCli.obsJson o])]),
    ("admitted", toJson (admitted (Snapshot.sourceObs g p r x) f))]).compress
  return 0
