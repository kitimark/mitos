import Lean.CoreM
import Lean.Util.CollectAxioms

/-!
Shard assignment and the aggregate verdict for the cheat corpus.

`listCases` in `CheatsRun` is the only walk of the case directory. `assign` does not sort and
does not read the directory: it takes that list. The aggregate's `directory` field is that
list, read once at the boundary. A record that merely agrees with `assign` of a shorter list
still fails `coverProblem`, because the union is compared with `directory`.
-/

namespace MitosGate.CheatsShard

def modeFull : String := "full"
def modeComparator : String := "comparator"
def failNeedle : String := "<-- FAIL"
def failMark : String := "  " ++ failNeedle

def allBehave (n : Nat) : String := s!"cheat corpus: all {n} cases behave as expected"

theorem modeFull_eq : modeFull = "full" := rfl
theorem modeComparator_eq : modeComparator = "comparator" := rfl
theorem failNeedle_eq : failNeedle = "<-- FAIL" := rfl
theorem failMark_eq : failMark = "  <-- FAIL" := rfl

def artifactCases : String := "shard-cases"
def artifactExit : String := "shard-exit"
def artifactTiming : String := "timing.tsv"
def artifactTable : String := "table.txt"

/-- `k/n` with `0 < n` and `k < n`. The modulus is `n`, the residue is `k`. -/
structure Shard where
  n : Nat
  k : Nat
  n_pos : 0 < n
  k_lt : k < n

def Shard.mk? (n k : Nat) : Option Shard :=
  if hn : 0 < n then
    if hk : k < n then some ⟨n, k, hn, hk⟩ else none
  else
    none

def isDigit (c : Char) : Bool :=
  '0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

def parseDigits (acc : Nat) : List Char → Option Nat
  | [] => some acc
  | c :: cs =>
    if isDigit c then parseDigits (acc * 10 + (c.toNat - '0'.toNat)) cs else none

/-- Decimal parse that reduces in the kernel. `String.toNat?` does not. -/
def parseNat (s : String) : Option Nat :=
  match s.toList with
  | [] => none
  | cs => parseDigits 0 cs

def splitChar (sep : Char) : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    let rest := splitChar sep cs
    if c == sep then [] :: rest
    else
      match rest with
      | [] => [[c]]
      | y :: ys => (c :: y) :: ys

/-- Split on one character. `String.splitOn` does not reduce in the kernel. -/
def splitStr (sep : Char) (s : String) : List String :=
  (splitChar sep s.toList).map String.ofList

def linesOf (s : String) : List String :=
  splitStr '\n' s

def Shard.parse (s : String) : Option Shard :=
  match splitStr '/' s with
  | [a, b] =>
    match parseNat a, parseNat b with
    | some k, some n => Shard.mk? n k
    | _, _ => none
  | _ => none

/-- Cases whose index `i` satisfies `i % n = k`, in the order of `names`. -/
def assign (names : List String) (n k : Nat) : List String :=
  (names.zipIdx.filter fun p => p.2 % n == k).map (·.1)

theorem mem_assign_iff {names : List String} {n k : Nat} {name : String} :
    name ∈ assign names n k ↔ ∃ i, names[i]? = some name ∧ i % n = k := by
  unfold assign
  simp only [List.mem_map, List.mem_filter, beq_iff_eq]
  constructor
  · rintro ⟨p, ⟨hzip, hmod⟩, rfl⟩
    exact ⟨p.2, (List.mem_zipIdx_iff_getElem?).1 hzip, hmod⟩
  · rintro ⟨i, hget, hmod⟩
    rcases List.getElem?_eq_some_iff.1 hget with ⟨hi, heq⟩
    refine ⟨(names[i], i), ⟨(List.mk_mem_zipIdx_iff_getElem?).2 (List.getElem?_eq_some_iff.2 ⟨hi, rfl⟩), hmod⟩, heq⟩

/-- `i % n` is the only residue of `i` in `0..n`. -/
theorem indexHasOneResidue (n i : Nat) (hn : 0 < n) :
    ∃ k, k < n ∧ k = i % n ∧ ∀ k', k' < n → k' = i % n → k' = k :=
  ⟨i % n, Nat.mod_lt i hn, rfl, fun _ _ h => h⟩

theorem indexInItsResidue {names : List String} {n : Nat} (_hn : 0 < n) {i : Nat}
    (hi : i < names.length) : names[i] ∈ assign names n (i % n) :=
  (mem_assign_iff (name := names[i])).2 ⟨i, List.getElem?_eq_some_iff.2 ⟨hi, rfl⟩, rfl⟩

theorem noEmptyShardWhenCountFits {names : List String} {n k : Nat} (hn : 0 < n) (hk : k < n)
    (hlen : n ≤ names.length) : assign names n k ≠ [] := by
  have hklen : k < names.length := Nat.lt_of_lt_of_le hk hlen
  have hmem : names[k] ∈ assign names n (k % n) := indexInItsResidue hn hklen
  rw [Nat.mod_eq_of_lt hk] at hmem
  exact List.ne_nil_of_mem hmem

theorem someShardEmptyWhenShorter {names : List String} {n : Nat} (_hn : 0 < n)
    (hlen : names.length < n) : ∃ k, k < n ∧ assign names n k = [] := by
  refine ⟨names.length, hlen, ?_⟩
  apply List.eq_nil_iff_forall_not_mem.2
  intro name hmem
  rcases (mem_assign_iff (name := name)).1 hmem with ⟨j, hget, hmod⟩
  rcases List.getElem?_eq_some_iff.1 hget with ⟨hj, _⟩
  have hjn : j < n := Nat.lt_trans hj hlen
  have hjmod : j % n = j := Nat.mod_eq_of_lt hjn
  exact absurd (hjmod.symm.trans hmod) (Nat.ne_of_lt hj)

/-- A duplicate-free list puts each name in exactly one residue. -/
def NamePartition : Prop :=
  ∀ (names : List String) (n : Nat), 0 < n → names.Nodup →
    ∀ name, name ∈ names →
      (∃ k, k < n ∧ name ∈ assign names n k) ∧
        ∀ k₁ k₂, k₁ < n → k₂ < n → name ∈ assign names n k₁ → name ∈ assign names n k₂ →
          k₁ = k₂

theorem namePartition : NamePartition := by
  intro names n hn hnd name hmem
  rcases List.mem_iff_getElem.1 hmem with ⟨i, hi, heq⟩
  refine ⟨⟨i % n, Nat.mod_lt i hn, ?_⟩, ?_⟩
  · simpa [heq] using indexInItsResidue (names := names) hn hi
  · intro k₁ k₂ _ _ h₁ h₂
    rcases (mem_assign_iff (name := name)).1 h₁ with ⟨j, hget₁, hm₁⟩
    rcases (mem_assign_iff (name := name)).1 h₂ with ⟨t, hget₂, hm₂⟩
    rcases List.getElem?_eq_some_iff.1 hget₁ with ⟨hj, hej⟩
    rcases List.getElem?_eq_some_iff.1 hget₂ with ⟨ht, het⟩
    have hjt : j = t := (hnd.getElem_inj (hi := hj) (hj := ht)).mp (hej.trans het.symm)
    subst hjt
    exact hm₁.symm.trans hm₂

theorem noEmpty_of_count (names : List String) (n : Nat) (hn : 0 < n) (hlen : n ≤ names.length) :
    ∀ k, k < n → assign names n k ≠ [] :=
  fun k hk => noEmptyShardWhenCountFits (k := k) hn hk hlen

inductive RunRefusal
  | noCases
  | emptyShard (k : Nat)
  deriving DecidableEq, Repr

def RunRefusal.text : RunRefusal → String
  | .noCases => "no cheat cases in the case directory"
  | .emptyShard k =>
    s!"shard {k} would be empty, and mitos-gate cheats with no names runs the whole corpus"

/-- Least empty residue. It is `names.length` when that index is still below `n`, and there is
none otherwise: residues below `names.length` each contain that index, and `noEmpty_of_count`
covers `n ≤ names.length`. A search through `List.range n` would allocate `n` cells first, so a
modulus such as `10^10` would hang instead of refusing. -/
def firstEmpty (names : List String) (n : Nat) : Option Nat :=
  if names.length < n then some names.length else none

def selection (names : List String) (s : Shard) : Except RunRefusal (List String) :=
  if names.isEmpty then .error .noCases
  else
    match firstEmpty names s.n with
    | some k => .error (.emptyShard k)
    | none => .ok (assign names s.n s.k)

def renderCaseList (names : List String) : String :=
  if names.isEmpty then "" else String.intercalate "\n" names ++ "\n"

def parseCaseList (txt : String) : List String :=
  let ls := linesOf txt
  match ls.getLast? with
  | some "" => ls.dropLast
  | _ => ls

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
  | n, b :: bs => isPrefix n (b :: bs) || hasSub n bs

def lineHasNeedle (line : String) : Bool :=
  hasSub failNeedle.toList line.toList

def startsWith (pre s : String) : Bool :=
  isPrefix pre.toList s.toList

def tableOk (text name : String) : Bool :=
  let rows := ((linesOf text).drop 1).filter fun line => firstToken line == name
  !rows.isEmpty && rows.all fun line => !lineHasNeedle line

def logName (name mode : String) : String := s!"{name}.{mode}.log"

def insertLine (x : String) : List String → List String
  | [] => [x]
  | y :: ys => if y < x then y :: insertLine x ys else x :: y :: ys

def sortStrings : List String → List String
  | [] => []
  | x :: xs => insertLine x (sortStrings xs)

def nodupList (xs : List String) : Bool :=
  xs.all fun n => xs.count n == 1

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

def witnessFail (k : Nat) (files : List String) (timing _table name : String) : CorpusReject :=
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
      some (witnessFail k files timing table name)

def slotReady (directory : List String) (count : Nat) (f : ShardFiles) (k : Nat) : Bool :=
  match f.exitText, f.casesText, f.timingText, f.tableText with
  | some t, some ct, some timing, some table =>
    exitOk t && parseCaseList ct == assign directory count k &&
      (witnessProblem k f.regularFiles timing table (parseCaseList ct)).isNone
  | _, _, _, _ => false

def slotReject (directory : List String) (count : Nat) (f : ShardFiles) (k : Nat) : CorpusReject :=
  match f.exitText with
  | none => .noExit k
  | some t =>
    if exitOk t then
      match f.casesText with
      | none => .noCaseList k
      | some ct =>
        if parseCaseList ct == assign directory count k then
          match f.timingText with
          | none => .noTiming k
          | some timing =>
            match f.tableText with
            | none => .noTable k
            | some table =>
              match witnessProblem k f.regularFiles timing table (parseCaseList ct) with
              | some r => r
              | none => .timingDrops k ""
        else
          .caseList k
    else
      .badExit k (normalizeExit t)

def slotProblem (directory : List String) (count : Nat) (slot : ShardSlot) (k : Nat) :
    Option CorpusReject :=
  match slot with
  | .absent => some (.missingShard k)
  | .present f =>
    if slotReady directory count f k then none else some (slotReject directory count f k)

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

theorem verdict_accept_iff (i : AggregateInput) :
    (∃ plan, verdict i = .accept plan) ↔ diagnose i = none := by
  cases h : diagnose i <;> simp [verdict, h]

theorem jobOk_iff (i : AggregateInput) :
    jobOk i = true ↔ i.checks = "success" ∧ i.shardsJob = "success" := by
  simp [jobOk, Bool.and_eq_true, beq_iff_eq]

theorem countOk_iff (i : AggregateInput) :
    countOk i = true ↔ 0 < i.count ∧ i.shards.length = i.count := by
  simp [countOk, Bool.and_eq_true, bne_iff_ne, beq_iff_eq, Nat.pos_iff_ne_zero]

theorem dirOk_iff (i : AggregateInput) :
    dirOk i = true ↔ i.directory ≠ [] := by
  cases h : i.directory <;> simp [dirOk, h]

theorem firstEmpty_none_iff {names : List String} {n : Nat} (hn : 0 < n) :
    firstEmpty names n = none ↔ ∀ k, k < n → assign names n k ≠ [] := by
  constructor
  · intro h
    cases Nat.lt_or_ge names.length n with
    | inl hlt =>
      simp [firstEmpty, hlt] at h
    | inr hge =>
      exact noEmpty_of_count names n hn hge
  · intro hall
    cases Nat.lt_or_ge names.length n with
    | inl hlt =>
      rcases someShardEmptyWhenShorter hn hlt with ⟨k, hk, hempty⟩
      exact absurd hempty (hall k hk)
    | inr hge =>
      have hnot : ¬ names.length < n := Nat.not_lt_of_le hge
      simp [firstEmpty, hnot]

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

theorem witnessOk_iff (files : List String) (timing table name : String) :
    witnessOk files timing table name = true ↔
      timingHas timing name modeFull = true ∧ timingHas timing name modeComparator = true ∧
        files.contains (logName name modeFull) = true ∧
        files.contains (logName name modeComparator) = true ∧
        tableOk table name = true := by
  simp [witnessOk, Bool.and_eq_true, and_assoc]

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
        · exact (witnessOk_iff files timing table n).mp hcond
        · exact (ih.mp hrest) n hmem
      · intro hall
        exact ih.mpr (fun n hmem => hall n (List.mem_cons_of_mem name hmem))
    · rename_i hcond
      constructor
      · intro h
        cases h
      · intro hall
        exact (hcond ((witnessOk_iff files timing table name).mpr
          (hall name (List.mem_cons_self)))).elim

theorem slotReady_iff (directory : List String) (count : Nat) (f : ShardFiles) (k : Nat) :
    slotReady directory count f k = true ↔
      ∃ t ct timing table,
        f.exitText = some t ∧ exitOk t = true ∧
          f.casesText = some ct ∧ parseCaseList ct = assign directory count k ∧
          f.timingText = some timing ∧ f.tableText = some table ∧
          witnessProblem k f.regularFiles timing table (parseCaseList ct) = none := by
  cases he : f.exitText with
  | none =>
    unfold slotReady
    rw [he]
    constructor
    · intro h
      cases h
    · intro hex
      rcases hex with ⟨_, _, _, _, ht, _⟩
      cases ht
  | some t =>
    cases hc : f.casesText with
    | none =>
      unfold slotReady
      rw [he, hc]
      constructor
      · intro h
        cases h
      · intro hex
        rcases hex with ⟨_, _, _, _, _, _, ht, _⟩
        cases ht
    | some ct =>
      cases hti : f.timingText with
      | none =>
        unfold slotReady
        rw [he, hc, hti]
        constructor
        · intro h
          cases h
        · intro hex
          rcases hex with ⟨_, _, _, _, _, _, _, _, ht, _⟩
          cases ht
      | some timing =>
        cases hta : f.tableText with
        | none =>
          unfold slotReady
          rw [he, hc, hti, hta]
          constructor
          · intro h
            cases h
          · intro hex
            rcases hex with ⟨_, _, _, _, _, _, _, _, _, ht, _⟩
            cases ht
        | some table =>
          unfold slotReady
          rw [he, hc, hti, hta]
          constructor
          · intro h
            have h3 := Bool.and_eq_true_iff.mp h
            have h2 := Bool.and_eq_true_iff.mp h3.1
            have hlist : parseCaseList ct = assign directory count k := (beq_iff_eq).mp h2.2
            have hw : witnessProblem k f.regularFiles timing table (parseCaseList ct) = none := by
              simpa [Option.isNone_iff_eq_none] using h3.2
            exact ⟨t, ct, timing, table, rfl, h2.1, rfl, hlist, rfl, rfl, hw⟩
          · intro hex
            rcases hex with ⟨_, _, _, _, ht, hok, hct, hlist, htiming, htable, hw⟩
            cases ht
            cases hct
            cases htiming
            cases htable
            exact Bool.and_eq_true_iff.mpr
              ⟨Bool.and_eq_true_iff.mpr ⟨hok, (beq_iff_eq).mpr hlist⟩,
                Option.isNone_iff_eq_none.mpr hw⟩

theorem slotProblem_none_iff (directory : List String) (count : Nat) (slot : ShardSlot) (k : Nat) :
    slotProblem directory count slot k = none ↔
      ∃ f t ct timing table,
        slot = .present f ∧
          f.exitText = some t ∧ exitOk t = true ∧
          f.casesText = some ct ∧ parseCaseList ct = assign directory count k ∧
          f.timingText = some timing ∧ f.tableText = some table ∧
          witnessProblem k f.regularFiles timing table (parseCaseList ct) = none := by
  cases slot with
  | absent =>
    dsimp only [slotProblem]
    constructor
    · intro h
      cases h
    · intro hex
      rcases hex with ⟨_, _, _, _, _, hs, _⟩
      nomatch hs
  | present f =>
    dsimp only [slotProblem]
    cases hr : slotReady directory count f k
    · constructor
      · intro h
        cases h
      · intro hex
        rcases hex with ⟨_, t, ct, timing, table, hs, ht, hok, hct, hlist, hti', hta, hw⟩
        cases hs
        have hr' : slotReady directory count f k = true :=
          (slotReady_iff directory count f k).mpr ⟨t, ct, timing, table, ht, hok, hct, hlist, hti', hta, hw⟩
        rw [hr] at hr'
        cases hr'
    · rcases (slotReady_iff directory count f k).mp hr with
        ⟨t, ct, timing, table, ht, hok, hct, hlist, hti', hta, hw⟩
      constructor
      · intro _
        exact ⟨f, t, ct, timing, table, rfl, ht, hok, hct, hlist, hti', hta, hw⟩
      · intro _
        rfl

theorem cover_none_iff (i : AggregateInput) :
    coverProblem i = none ↔
      firstDup (recordedUnion i) = none ∧ sameNames (recordedUnion i) i.directory = true := by
  unfold coverProblem
  cases h : firstDup (recordedUnion i) <;> simp [h]

/-- Aggregate accepts only when both jobs succeeded, no residue is empty, every shard recorded
exit 0 and the names `assign` gives that residue, the recorded names are a duplicate-free copy
of the directory list, and each recorded name has both timing modes, both logs, and a table row
that is not a failure. -/
def AggregateAccepts : Prop :=
  ∀ i, (∃ plan, verdict i = .accept plan) ↔
    i.checks = "success" ∧ i.shardsJob = "success" ∧
      0 < i.count ∧ i.shards.length = i.count ∧ i.directory ≠ [] ∧
      (∀ k, k < i.count → assign i.directory i.count k ≠ []) ∧
      (∀ k, k < i.count →
        ∃ f t ct timing table,
          i.shards[k]? = some (.present f) ∧
            f.exitText = some t ∧ exitOk t = true ∧
            f.casesText = some ct ∧ parseCaseList ct = assign i.directory i.count k ∧
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
  rw [verdict_accept_iff, diagnose_none_iff, jobOk_iff, countOk_iff, dirOk_iff]
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

theorem selection_error_empty {s : Shard} :
    selection [] s = .error .noCases := by
  simp [selection]

theorem selection_ok_of_partition {names : List String} {s : Shard} (hne : names ≠ [])
    (hempty : ∀ k, k < s.n → assign names s.n k ≠ []) :
    selection names s = .ok (assign names s.n s.k) := by
  have hfind : firstEmpty names s.n = none := (firstEmpty_none_iff s.n_pos).2 hempty
  simp [selection, hne, List.isEmpty_iff, hfind]

namespace Fixture

set_option maxRecDepth 8192

def three : List String := ["one", "three", "two"]

theorem threeCasesOnePerShard :
    assign three 3 0 = ["one"] ∧ assign three 3 1 = ["three"] ∧ assign three 3 2 = ["two"] := by
  decide

theorem fourNamesByIndex :
    assign ["one", "three", "two", "four"] 3 0 = ["one", "four"] ∧
      assign ["one", "three", "two", "four"] 3 1 = ["three"] ∧
      assign ["one", "three", "two", "four"] 3 2 = ["two"] := by
  decide

theorem oneShardKeepsOrder :
    assign ["b", "a"] 1 0 = ["b", "a"] := by
  decide

theorem twoNamesLeaveLastShardEmpty :
    assign ["one", "two"] 3 2 = [] ∧
      firstEmpty ["one", "two"] 3 = some 2 := by
  decide

theorem duplicateNameSitsInTwoShards :
    "a" ∈ assign ["a", "a"] 2 0 ∧ "a" ∈ assign ["a", "a"] 2 1 := by
  decide

def residue : Option Shard → Option (Nat × Nat)
  | some s => some (s.n, s.k)
  | none => none

theorem parseShardAcceptsMatrix :
    residue (Shard.parse "0/3") = some (3, 0) ∧
      residue (Shard.parse "1/3") = some (3, 1) ∧
      residue (Shard.parse "2/3") = some (3, 2) ∧
      Shard.parse "3/3" = none ∧ Shard.parse "0/0" = none ∧
      Shard.parse "k/3" = none ∧ Shard.parse "0/3/1" = none := by
  decide

theorem roundtripThree :
    parseCaseList (renderCaseList three) = three := by
  decide

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
    if (`MitosGate.CheatsShard).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  let fixtures := theorems.filter fun n => (`MitosGate.CheatsShard.Fixture).isPrefixOf n
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in theorems.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.CheatsShard
