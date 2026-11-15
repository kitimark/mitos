import Lean.CoreM
import Lean.Util.CollectAxioms
import MitosGate.CheatsShard
import MitosGate.DecideText
import MitosGate.IndexMod

namespace MitosGate.CheatsAggregate

open MitosGate.CheatsShard
open MitosGate.DecideText
open MitosGate.IndexMod

def dropChar (c : Char) : List Char → List Char
  | [] => []
  | x :: xs => if x == c then dropChar c xs else x :: dropChar c xs

def dropTrailNL (s : String) : String :=
  String.ofList (s.toList.reverse.dropWhile (· == '\n') |>.reverse)

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

def firstToken (line : String) : String :=
  let cs := line.toList.dropWhile fun c => c == ' ' || c == '\t'
  String.ofList (cs.takeWhile fun c => c != ' ' && c != '\t')

def isPrefix : List Char → List Char → Bool
  | [], _ => true
  | _, [] => false
  | a :: as, b :: bs => a == b && isPrefix as bs

def hasSub : List Char → List Char → Bool
  | [], _ => true
  | _, [] => false
  | pat, b :: bs => isPrefix pat (b :: bs) || hasSub pat bs

def lineHasNeedle (line : String) : Bool :=
  hasSub failNeedle.toList line.toList

def startsWith (pre s : String) : Bool :=
  pre.toList.isPrefixOf s.toList

def tableOk (text name : String) : Bool :=
  let rows := ((linesOf text).drop 1).filter fun line => firstToken line == name
  !rows.isEmpty && rows.all fun line => !lineHasNeedle line

def logName (name mode : String) : String := s!"{name}.{mode}.log"

def insertLine (x : String) : List String → List String
  | [] => [x]
  | y :: ys => if y < x then y :: insertLine x ys else x :: y :: ys

/-- `List.mergeSort` does not reduce under `decide`. -/
def sortStrings : List String → List String
  | [] => []
  | x :: xs => insertLine x (sortStrings xs)

def nodupList (xs : List String) : Bool :=
  decide (xs.Nodup)

def sameNames (a b : List String) : Bool :=
  nodupList a && nodupList b && sortStrings a == sortStrings b

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
  shardTables : List (Nat × String)
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

def witnessFail (k : Nat) (files : List String) (timing name : String) : CorpusReject :=
  if !(timingHas timing name modeFull) || !(timingHas timing name modeComparator) then
    .timingDrops k name
  else if !files.contains (logName name modeFull) then
    .missingLog k name modeFull
  else if !files.contains (logName name modeComparator) then
    .missingLog k name modeComparator
  else
    .tableDrops k name

def witnessOk (files : List String) (timing table name : String) : Bool :=
  timingHas timing name modeFull && timingHas timing name modeComparator &&
    files.contains (logName name modeFull) && files.contains (logName name modeComparator) &&
    tableOk table name

def witnessProblem (k : Nat) (files : List String) (timing table : String) :
    List String → Option CorpusReject
  | [] => none
  | name :: names =>
    if witnessOk files timing table name then
      witnessProblem k files timing table names
    else
      some (witnessFail k files timing name)

def slotFault (directory : List String) (count : Nat) (f : ShardFiles) (k : Nat) :
    Option CorpusReject :=
  match f.exitText with
  | none => some (.noExit k)
  | some t =>
    if !exitOk t then
      some (.badExit k (normalizeExit t))
    else
      match f.casesText, f.timingText, f.tableText with
      | none, _, _ => some (.noCaseList k)
      | some ct, none, _ =>
        if parseCaseList ct == byMod directory count k then some (.noTiming k)
        else some (.caseList k)
      | some ct, some _, none =>
        if parseCaseList ct == byMod directory count k then some (.noTable k)
        else some (.caseList k)
      | some ct, some timing, some table =>
        if parseCaseList ct == byMod directory count k then
          witnessProblem k f.regularFiles timing table (parseCaseList ct)
        else
          some (.caseList k)

def slotProblem (directory : List String) (count : Nat) (slot : ShardSlot) (k : Nat) :
    Option CorpusReject :=
  match slot with
  | .absent => some (.missingShard k)
  | .present f => slotFault directory count f k

def stepSlot (i : AggregateInput) (acc : Option CorpusReject) (k : Nat) : Option CorpusReject :=
  match acc with
  | some r => some r
  | none =>
    match i.shards[k]? with
    | none => some (.missingShard k)
    | some s => slotProblem i.directory i.count s k

def firstSlot (i : AggregateInput) : Option CorpusReject :=
  (List.range i.count).foldl (stepSlot i) none

def recorded (i : AggregateInput) (k : Nat) : List String :=
  match i.shards[k]? with
  | some (.present f) =>
    match f.casesText with
    | some txt => parseCaseList txt
    | none => []
  | _ => []

def recordedUnion (i : AggregateInput) : List String :=
  (List.range i.count).flatMap (recorded i)

def firstDup (xs : List String) : Option String :=
  xs.find? fun n => xs.count n > 1

def coverProblem (i : AggregateInput) : Option CorpusReject :=
  let u := recordedUnion i
  match firstDup u with
  | some name => some (.duplicate name)
  | none =>
    if sameNames u i.directory then none else some .notTheDirectory

def diagnose (i : AggregateInput) : Option CorpusReject :=
  match jobOk i, countOk i, dirOk i with
  | false, _, _ => some (jobReject i)
  | true, false, _ => some .badCount
  | true, true, false => some .noCases
  | true, true, true =>
    match firstEmpty i.directory i.count with
    | some k => some (.emptyShard k)
    | none =>
      match firstSlot i with
      | some r => some r
      | none => coverProblem i

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

inductive CorpusVerdict
  | accept (plan : MergePlan)
  | reject (why : CorpusReject)
  deriving DecidableEq, Repr

def verdict (i : AggregateInput) : CorpusVerdict :=
  match diagnose i with
  | some why => .reject why
  | none => .accept (plan i)

theorem diagnose_none_iff (i : AggregateInput) :
    diagnose i = none ↔
      jobOk i = true ∧ countOk i = true ∧ dirOk i = true ∧
        firstEmpty i.directory i.count = none ∧ firstSlot i = none ∧ coverProblem i = none := by
  cases h1 : jobOk i <;> cases h2 : countOk i <;> cases h3 : dirOk i <;>
    simp [diagnose, h1, h2, h3]
  · cases h4 : firstEmpty i.directory i.count <;> simp
    cases h5 : firstSlot i <;> simp

theorem foldl_step_some (i : AggregateInput) (ks : List Nat) (r : CorpusReject) :
    ks.foldl (stepSlot i) (some r) = some r := by
  induction ks with
  | nil => rfl
  | cons k ks ih => simp [List.foldl_cons, stepSlot, ih]

theorem firstSlot_none_iff (i : AggregateInput) :
    firstSlot i = none ↔
      ∀ k, k < i.count →
        ∃ s, i.shards[k]? = some s ∧ slotProblem i.directory i.count s k = none := by
  unfold firstSlot
  suffices ∀ ks, List.foldl (stepSlot i) none ks = none ↔
      ∀ k ∈ ks, ∃ s, i.shards[k]? = some s ∧ slotProblem i.directory i.count s k = none by
    simpa [List.mem_range] using this (List.range i.count)
  intro ks
  induction ks with
  | nil => simp
  | cons k ks ih =>
    simp only [List.foldl_cons, List.mem_cons, forall_eq_or_imp]
    cases hs : i.shards[k]? with
    | none =>
      simp [stepSlot, hs, foldl_step_some]
    | some s =>
      cases hp : slotProblem i.directory i.count s k with
      | none => simp [stepSlot, hs, hp, ih]
      | some r => simp [stepSlot, hs, hp, foldl_step_some]

theorem witness_none_iff (k : Nat) (files : List String) (timing table : String) (names : List String) :
    witnessProblem k files timing table names = none ↔
      ∀ name ∈ names,
        timingHas timing name modeFull = true ∧ timingHas timing name modeComparator = true ∧
          files.contains (logName name modeFull) = true ∧
          files.contains (logName name modeComparator) = true ∧
          tableOk table name = true := by
  induction names with
  | nil => simp [witnessProblem]
  | cons name names ih =>
    unfold witnessProblem
    split
    · rename_i hcond
      constructor
      · intro hrest n hmem
        rcases List.mem_cons.mp hmem with rfl | hmem
        · simpa [witnessOk, Bool.and_eq_true, and_assoc] using hcond
        · exact (ih.mp hrest) n hmem
      · intro hall
        exact ih.mpr (fun n hmem => hall n (List.mem_cons_of_mem name hmem))
    · rename_i hcond
      constructor
      · intro h
        cases h
      · intro hall
        exact (hcond (by simpa [witnessOk, Bool.and_eq_true, and_assoc] using
          (hall name (List.mem_cons_self)))).elim

theorem slotFault_none_iff (directory : List String) (count : Nat) (f : ShardFiles) (k : Nat) :
    slotFault directory count f k = none ↔
      ∃ t ct timing table,
        f.exitText = some t ∧ exitOk t = true ∧
          f.casesText = some ct ∧ parseCaseList ct = byMod directory count k ∧
          f.timingText = some timing ∧ f.tableText = some table ∧
          witnessProblem k f.regularFiles timing table (parseCaseList ct) = none := by
  cases he : f.exitText with
  | none =>
    simp [slotFault, he]
  | some t =>
    cases hc : f.casesText with
    | none =>
      simp only [slotFault, he, hc]
      constructor
      · intro h
        by_cases hok : exitOk t = true <;> simp [hok] at h <;> cases h
      · intro hex
        rcases hex with ⟨_, _, _, _, _, _, ht, _⟩
        cases ht
    | some ct =>
      cases hti : f.timingText with
      | none =>
        simp only [slotFault, he, hc, hti]
        constructor
        · intro h
          by_cases hok : exitOk t = true <;>
            by_cases hlist : parseCaseList ct == byMod directory count k <;>
              simp [hok, hlist] at h <;> cases h
        · intro hex
          rcases hex with ⟨_, _, _, _, _, _, _, _, ht, _⟩
          cases ht
      | some timing =>
        cases hta : f.tableText with
        | none =>
          simp only [slotFault, he, hc, hti, hta]
          constructor
          · intro h
            by_cases hok : exitOk t = true <;>
              by_cases hlist : parseCaseList ct == byMod directory count k <;>
                simp [hok, hlist] at h <;> cases h
          · intro hex
            rcases hex with ⟨_, _, _, _, _, _, _, _, _, ht, _⟩
            cases ht
        | some table =>
          unfold slotFault
          simp only [he, hc, hti, hta]
          constructor
          · intro h
            by_cases hok : exitOk t = true
            · by_cases hlist : parseCaseList ct == byMod directory count k
              · exact ⟨t, ct, timing, table, rfl, hok, rfl, (beq_iff_eq).mp hlist, rfl, rfl,
                  by simpa [hok, hlist] using h⟩
              · simp [hok, hlist] at h
            · simp [hok] at h
          · intro hex
            rcases hex with ⟨_, _, _, _, ht, hok, hct, hlist, htiming, htable, hw⟩
            cases ht
            cases hct
            cases htiming
            cases htable
            simp [hok, (beq_iff_eq).mpr hlist, hw]

theorem slotProblem_none_iff (directory : List String) (count : Nat) (slot : ShardSlot) (k : Nat) :
    slotProblem directory count slot k = none ↔
      ∃ f t ct timing table,
        slot = .present f ∧
          f.exitText = some t ∧ exitOk t = true ∧
          f.casesText = some ct ∧ parseCaseList ct = byMod directory count k ∧
          f.timingText = some timing ∧ f.tableText = some table ∧
          witnessProblem k f.regularFiles timing table (parseCaseList ct) = none := by
  cases slot with
  | absent =>
    simp [slotProblem]
  | present f =>
    simp [slotProblem, slotFault_none_iff]

theorem cover_none_iff (i : AggregateInput) :
    coverProblem i = none ↔
      firstDup (recordedUnion i) = none ∧ sameNames (recordedUnion i) i.directory = true := by
  unfold coverProblem
  cases h : firstDup (recordedUnion i) <;> simp [h]

def AggregateAccepts : Prop :=
  ∀ i, (∃ plan, verdict i = .accept plan) ↔
    i.checks = "success" ∧ i.shardsJob = "success" ∧
      0 < i.count ∧ i.shards.length = i.count ∧ i.directory ≠ [] ∧
      (∀ k, k < i.count → byMod i.directory i.count k ≠ []) ∧
      (∀ k, k < i.count →
        ∃ f t ct timing table,
          i.shards[k]? = some (.present f) ∧
            f.exitText = some t ∧ exitOk t = true ∧
            f.casesText = some ct ∧ parseCaseList ct = byMod i.directory i.count k ∧
            f.timingText = some timing ∧ f.tableText = some table ∧
            (∀ name ∈ parseCaseList ct,
              timingHas timing name modeFull = true ∧
                timingHas timing name modeComparator = true ∧
                f.regularFiles.contains (logName name modeFull) = true ∧
                f.regularFiles.contains (logName name modeComparator) = true ∧
                tableOk table name = true)) ∧
      firstDup (recordedUnion i) = none ∧
      sameNames (recordedUnion i) i.directory = true

theorem aggregateAccepts : AggregateAccepts := by
  intro i
  have hverdict : (∃ plan, verdict i = .accept plan) ↔ diagnose i = none := by
    cases h : diagnose i <;> simp [verdict, h]
  have hjob : jobOk i = true ↔ i.checks = "success" ∧ i.shardsJob = "success" := by
    simp [jobOk, Bool.and_eq_true, beq_iff_eq]
  have hcount : countOk i = true ↔ 0 < i.count ∧ i.shards.length = i.count := by
    simp [countOk, Bool.and_eq_true, bne_iff_ne, beq_iff_eq, Nat.pos_iff_ne_zero]
  have hdir : dirOk i = true ↔ i.directory ≠ [] := by
    cases h : i.directory <;> simp [dirOk, h]
  rw [hverdict, diagnose_none_iff, hjob, hcount, hdir]
  constructor
  · rintro ⟨hj, hc, hd, hempty, hslot, hcover⟩
    have hpos : 0 < i.count := hc.1
    refine ⟨hj.1, hj.2, hpos, hc.2, hd, ?_, ?_, ?_, ?_⟩
    · exact (firstEmpty_none_iff hpos).1 hempty
    · intro k hk
      rcases (firstSlot_none_iff i).1 hslot k hk with ⟨s, hs, hp⟩
      rcases (slotProblem_none_iff i.directory i.count s k).1 hp with
        ⟨f, t, ct, timing, table, rfl, ht, hok, hct, hlist, htiming, htable, hw⟩
      refine ⟨f, t, ct, timing, table, hs, ht, hok, hct, hlist, htiming, htable, ?_⟩
      exact (witness_none_iff k f.regularFiles timing table (parseCaseList ct)).1 hw
    · exact (cover_none_iff i).1 hcover |>.1
    · exact (cover_none_iff i).1 hcover |>.2
  · rintro ⟨hchecks, hshards, hpos, hlen, hdir, hempty, hslots, hdup, hsame⟩
    refine ⟨⟨hchecks, hshards⟩, ⟨hpos, hlen⟩, hdir, (firstEmpty_none_iff hpos).2 hempty, ?_, ?_⟩
    · apply (firstSlot_none_iff i).2
      intro k hk
      rcases hslots k hk with ⟨f, t, ct, timing, table, hs, ht, hok, hct, hlist, htiming, htable, hw⟩
      refine ⟨.present f, hs, (slotProblem_none_iff i.directory i.count (.present f) k).2 ?_⟩
      exact ⟨f, t, ct, timing, table, rfl, ht, hok, hct, hlist, htiming, htable,
        (witness_none_iff k f.regularFiles timing table (parseCaseList ct)).2 hw⟩
    · exact (cover_none_iff i).2 ⟨hdup, hsame⟩

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

theorem droppedCaseCannotHide :
    rejectOf (verdict { good with directory := ["one", "three", "two", "four"] }) =
      some (.emptyShard 0) ∨
      rejectOf (verdict { good with directory := ["one", "three", "two", "four"] }) =
        some (.caseList 0) ∨
      rejectOf (verdict { good with directory := ["one", "three", "two", "four"] }) =
        some .notTheDirectory := by
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

end Fixture

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let theorems := (← getEnv).constants.map₂.foldl (fun acc n c =>
    if c.isTheorem &&
        ((`MitosGate.IndexMod).isPrefixOf n ||
          (`MitosGate.CheatsShard).isPrefixOf n ||
          (`MitosGate.CheatsAggregate).isPrefixOf n)
      then acc.push n else acc) #[]
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
