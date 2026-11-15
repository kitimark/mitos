import Lean.CoreM
import Lean.Util.CollectAxioms
import MitosGate.CheatsAggregate
import MitosGate.DecideList
import MitosGate.DecideText
import MitosGate.IndexMod

namespace MitosGate.CheatsAggregate

open MitosGate.CheatsShard
open MitosGate.DecideList
open MitosGate.DecideText

namespace Fixture

set_option maxRecDepth 8192

def three : List String := ["one", "three", "two"]

theorem exitTextNormalizes :
    exitOk "0" = true ∧ exitOk "0\n" = true ∧ exitOk "0\r\n" = true ∧ exitOk "0\n\n" = true ∧
      exitOk "1\n" = false ∧ exitOk "00\n" = false ∧ exitOk "0 " = false := by
  decide

def timingTextOf (name : String) (modes : List String) : String :=
  "case\tmode\tstart_ms\tend_ms\texit\ttimed_out\n" ++
    String.join (modes.map fun m => s!"{name}\t{m}\t0\t1\t1\tfalse\n")

def filesFor (name exitText casesText : String) (modes : List String := [modeFull, modeComparator])
    (fail : Bool := false) : ShardFiles where
  exitText := some exitText
  casesText := some casesText
  timingText := some (timingTextOf name modes)
  tableText := some ("CASE FULL\n" ++ name ++ " REJECTED" ++ (if fail then failMark else "") ++ "\n")
  regularFiles := modes.map fun m => logName name m

def good : AggregateInput where
  checks := "success"
  shardsJob := "success"
  count := 3
  directory := three
  shards := [
    .present (filesFor "one" "0\n" "one\n"),
    .present (filesFor "three" "0\n" "three\n"),
    .present (filesFor "two" "0\n" "two\n") ]

def replaceSlot (i : AggregateInput) (k : Nat) (slot : ShardSlot) : AggregateInput :=
  { i with shards := i.shards.zipIdx.map fun p => if p.2 == k then slot else p.1 }

def edit (i : AggregateInput) (k : Nat) (f : ShardFiles → ShardFiles) : AggregateInput :=
  match i.shards[k]? with
  | some (.present files) => replaceSlot i k (.present (f files))
  | _ => i

def rejectOf : CorpusVerdict → Option CorpusReject
  | .accept _ => none
  | .reject why => some why

def stdoutOf : CorpusVerdict → String
  | .accept plan => plan.stdout
  | .reject _ => ""

def timingOf : CorpusVerdict → String
  | .accept plan => plan.timing
  | .reject _ => ""

def expectedStdout : String :=
  "CASE FULL\none REJECTED\nthree REJECTED\ntwo REJECTED\n\n" ++ allBehave 3 ++ "\n"

theorem completeFixtureAccepts :
    stdoutOf (verdict good) = expectedStdout ∧
      hasSub "false\t0".toList (timingOf (verdict good)).toList = true ∧
      hasSub "false\t2".toList (timingOf (verdict good)).toList = true ∧
      ((linesOf (timingOf (verdict good))).filter (startsWith "case\t")).length = 1 := by
  decide

theorem missingShardOneRejects :
    rejectOf (verdict (replaceSlot good 1 .absent)) = some (.missingShard 1) := by
  decide

theorem nonzeroExitRejects :
    rejectOf (verdict (edit good 2 fun f => { f with exitText := some "1\n" })) =
      some (.badExit 2 "1") := by
  decide

theorem crExitIsZero :
    stdoutOf (verdict (edit good 0 fun f => { f with exitText := some "0\r\n" })) =
      expectedStdout := by
  decide

theorem extraNameRejects :
    rejectOf (verdict (edit good 0 fun f => { f with casesText := some "one\nextra\n" })) =
      some (.caseList 0) := by
  decide

theorem duplicateRecordRejects :
    rejectOf (verdict (edit good 0 fun f => { f with casesText := some "one\none\n" })) =
      some (.caseList 0) := by
  decide

theorem timingDropsComparator :
    rejectOf (verdict (edit good 0 fun f =>
      { f with timingText := some (timingTextOf "one" [modeFull]) })) =
      some (.timingDrops 0 "one") := by
  decide

theorem checksFailureRejects :
    rejectOf (verdict { good with checks := "failure" }) =
      some (.jobs (.other "failure") .success) ∧
      CorpusReject.render (.jobs (.other "failure") .success) =
        "refusing corpus: checks=failure shards=success" := by
  decide

theorem shardsCancelledRejects :
    rejectOf (verdict { good with shardsJob := "cancelled" }) =
      some (.jobs .success (.other "cancelled")) ∧
      CorpusReject.render (.jobs .success (.other "cancelled")) =
        "refusing corpus: checks=success shards=cancelled" := by
  decide

theorem shardsSkippedRejects :
    rejectOf (verdict { good with shardsJob := "skipped" }) =
      some (.jobs .success (.other "skipped")) ∧
      CorpusReject.render (.jobs .success (.other "skipped")) =
        "refusing corpus: checks=success shards=skipped" := by
  decide

theorem tableFailRejects :
    rejectOf (verdict (edit good 0 fun f =>
      { f with tableText := some ("CASE FULL\none REJECTED" ++ failMark ++ "\n") })) =
      some (.tableDrops 0 "one") := by
  decide

theorem tableOmitsCaseRejects :
    rejectOf (verdict (edit good 0 fun f => { f with tableText := some "CASE FULL\n" })) =
      some (.tableDrops 0 "one") := by
  decide

theorem missingFullLogRejects :
    rejectOf (verdict (edit good 0 fun f =>
      { f with regularFiles := [logName "one" modeComparator] })) =
      some (.missingLog 0 "one" modeFull) := by
  decide

theorem timingDropsFull :
    rejectOf (verdict (edit good 0 fun f =>
      { f with timingText := some (timingTextOf "one" [modeComparator]) })) =
      some (.timingDrops 0 "one") := by
  decide

theorem timingForOtherCaseRejects :
    rejectOf (verdict (edit good 0 fun f =>
      { f with timingText := some (timingTextOf "other" [modeFull, modeComparator]) })) =
      some (.timingDrops 0 "one") := by
  decide

theorem droppedCaseCannotHide :
    rejectOf (verdict { good with directory := ["one", "three", "two", "four"] }) =
      some (.caseList 0) := by
  decide

theorem swappedShardsReject :
    rejectOf (verdict
      (edit (edit good 0 fun f => { f with casesText := some "three\n" }) 1
        fun f => { f with casesText := some "one\n" })) =
      some (.caseList 0) := by
  decide

theorem shortDirectoryRejectsEmptyShard :
    rejectOf (verdict { good with directory := ["one", "two"] }) = some (.emptyShard 2) := by
  decide

theorem missingLogRejects :
    rejectOf (verdict (edit good 0 fun f => { f with regularFiles := [logName "one" modeFull] })) =
      some (.missingLog 0 "one" modeComparator) := by
  decide

theorem ownedRowWins :
    stdoutOf (verdict (edit good 0 fun f =>
      { f with tableText := some "CASE FULL\nthree ACCEPTED\none REJECTED\n" })) =
      expectedStdout := by
  decide

end Fixture

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  -- Every `MitosGate` theorem in this file's import closure. A new imported module
  -- is scanned without editing a prefix list. Theorems outside that closure are
  -- not in this environment.
  let theorems := (← getEnv).constants.fold (fun acc n c =>
    if c.isTheorem && (`MitosGate).isPrefixOf n then acc.push n else acc) #[]
  let fixtures := theorems.filter fun n =>
    (`MitosGate.IndexMod.Fixture).isPrefixOf n ||
      (`MitosGate.CheatsShard.Fixture).isPrefixOf n ||
      (`MitosGate.CheatsAggregate.Fixture).isPrefixOf n
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in theorems.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.CheatsAggregate
