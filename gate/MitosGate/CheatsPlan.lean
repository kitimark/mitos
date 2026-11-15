import MitosGate.CheatsRecord
import MitosGate.CheatsShard
import MitosGate.DecideList
import MitosGate.DecideText

namespace MitosGate.CheatsAggregate

open MitosGate.CheatsShard
open MitosGate.DecideList
open MitosGate.DecideText

def dataLines (text : String) (k : Nat) : List String :=
  ((linesOf text).drop 1).filter (· ≠ "") |>.map fun line => s!"{line}\t{k}"

def timingOfSlot (s : ShardSlot) (k : Nat) : List String :=
  match s with
  | .absent => []
  | .present f =>
    match f.timingText with
    | some t => dataLines t k
    | none => []

def timingText (i : AggregateInput) : String :=
  let lines := sortStrings <| (List.range i.count).flatMap fun k =>
    match i.shards[k]? with
    | none => []
    | some s => timingOfSlot s k
  "case\tmode\tstart_ms\tend_ms\texit\ttimed_out\tshard\n" ++
    String.intercalate "\n" lines ++ if lines.isEmpty then "" else "\n"

def firstDataRow (tables : List String) (name : String) : Option String :=
  tables.findSome? fun text =>
    ((linesOf text).drop 1).find? fun line => firstToken line == name

def stdoutText (directory : List String) (tables : List String) : String :=
  let header :=
    match tables with
    | [] => ""
    | t :: _ => (linesOf t).head?.getD ""
  let rows := directory.filterMap (firstDataRow tables)
  String.intercalate "\n" (header :: rows) ++ "\n\n" ++ allBehave directory.length ++ "\n"

def tableOfSlot : ShardSlot → String
  | .absent => ""
  | .present f => f.tableText.getD ""

def tableTexts (i : AggregateInput) : List String :=
  (List.range i.count).map fun k =>
    match i.shards[k]? with
    | none => ""
    | some s => tableOfSlot s

def plan (i : AggregateInput) : MergePlan :=
  let copies := (List.range i.count).flatMap fun k =>
    (recorded i k).flatMap fun name =>
      [modeFull, modeComparator].map fun mode => { shard := k, file := logName name mode : LogCopy }
  { copies
    timing := timingText i
    shardTables := (List.range i.count).map fun k => (k, (tableTexts i)[k]?.getD "")
    stdout := stdoutText i.directory (tableTexts i) }

end MitosGate.CheatsAggregate
