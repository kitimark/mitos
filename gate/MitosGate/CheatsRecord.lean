import MitosGate.CheatsShard
import MitosGate.DecideList
import MitosGate.DecideText

namespace MitosGate.CheatsAggregate

open MitosGate.CheatsShard
open MitosGate.DecideList
open MitosGate.DecideText

def normalizeExit (t : String) : String :=
  dropTrailNL (String.ofList (dropChar '\r' t.toList))

def exitOk (t : String) : Bool :=
  normalizeExit t == "0"

def tabFields (line : String) : List String :=
  splitStr '\t' line

def timingHas (text name mode : String) : Bool :=
  (linesOf text).any fun line =>
    match tabFields line with
    | c :: m :: _ => c == name && m == mode
    | _ => false

def lineHasNeedle (line : String) : Bool :=
  hasSub failNeedle.toList line.toList

def startsWith (pre s : String) : Bool :=
  pre.toList.isPrefixOf s.toList

def tableOk (text name : String) : Bool :=
  let rows := ((linesOf text).drop 1).filter fun line => firstToken line == name
  !rows.isEmpty && rows.all fun line => !lineHasNeedle line

def logName (name mode : String) : String := s!"{name}.{mode}.log"

inductive Conclusion
  | success
  | other (text : String)
  deriving DecidableEq, Repr

def Conclusion.parse : String → Conclusion
  | "success" => .success
  | "" => .other "unset"
  | s => .other s

def Conclusion.render : Conclusion → String
  | .success => "success"
  | .other s => s

structure ShardFiles where
  exitText : Option String
  casesText : Option String
  timingText : Option String
  tableText : Option String
  regularFiles : List String
  deriving DecidableEq, Repr

inductive ShardSlot
  | absent
  | present (files : ShardFiles)
  deriving DecidableEq, Repr

structure AggregateInput where
  checks : String
  shardsJob : String
  count : Nat
  directory : List String
  shards : List ShardSlot
  deriving DecidableEq, Repr

structure LogCopy where
  shard : Nat
  file : String
  deriving DecidableEq, Repr

structure MergePlan where
  copies : List LogCopy
  timing : String
  stdout : String
  deriving DecidableEq, Repr

inductive CorpusReject
  | jobs (checks shards : Conclusion)
  | badCount
  | noCases
  | emptyShard (k : Nat)
  | missingShard (k : Nat)
  | noExit (k : Nat)
  | badExit (k : Nat) (got : String)
  | noCaseList (k : Nat)
  | caseList (k : Nat)
  | noTiming (k : Nat)
  | noTable (k : Nat)
  | duplicate (name : String)
  | notTheDirectory
  | timingDrops (k : Nat) (name : String)
  | missingLog (k : Nat) (name : String) (mode : String)
  | tableDrops (k : Nat) (name : String)
  deriving DecidableEq, Repr

def CorpusReject.render : CorpusReject → String
  | .jobs c s => s!"refusing corpus: checks={c.render} shards={s.render}"
  | .badCount => "shard count must be at least 1"
  | .noCases => "no cheat cases in the case directory"
  | .emptyShard k => RunRefusal.text (.emptyShard k)
  | .missingShard k => s!"missing shard {k} logs"
  | .noExit k => s!"shard {k} recorded no exit status"
  | .badExit k got => s!"shard {k} exited {got}"
  | .noCaseList k => s!"shard {k} recorded no case list"
  | .caseList k => s!"shard {k} case list is not the partition"
  | .noTiming k => s!"shard {k} has no timing.tsv"
  | .noTable k => s!"shard {k} has no table"
  | .duplicate name => s!"a case ran in more than one shard: {name}"
  | .notTheDirectory => "shard case lists do not cover the case directory"
  | .timingDrops k name => s!"shard {k} timing.tsv drops {name}"
  | .missingLog k name mode => s!"shard {k} has no {mode} log for {name}"
  | .tableDrops k name => s!"shard {k} table drops {name} or marks it failed"

def jobOk (i : AggregateInput) : Bool :=
  i.checks == "success" && i.shardsJob == "success"

def jobReject (i : AggregateInput) : CorpusReject :=
  .jobs (Conclusion.parse i.checks) (Conclusion.parse i.shardsJob)

def countOk (i : AggregateInput) : Bool :=
  i.count != 0 && i.shards.length == i.count

def dirOk (i : AggregateInput) : Bool :=
  !i.directory.isEmpty

def recorded (i : AggregateInput) (k : Nat) : List String :=
  match i.shards[k]? with
  | some (.present f) =>
    match f.casesText with
    | some txt => parseCaseList txt
    | none => []
  | _ => []

end MitosGate.CheatsAggregate
