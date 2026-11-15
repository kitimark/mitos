import MitosGate.CheatsRecord
import MitosGate.IndexMod

namespace MitosGate.CheatsAggregate

open MitosGate.CheatsShard
open MitosGate.IndexMod

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
      match f.casesText with
      | none => some (.noCaseList k)
      | some ct =>
        if parseCaseList ct == byMod directory count k then
          match f.timingText with
          | none => some (.noTiming k)
          | some timing =>
            match f.tableText with
            | none => some (.noTable k)
            | some table =>
              witnessProblem k f.regularFiles timing table (parseCaseList ct)
        else
          some (.caseList k)

def slotProblem (directory : List String) (count : Nat) (slot : ShardSlot) (k : Nat) :
    Option CorpusReject :=
  match slot with
  | .absent => some (.missingShard k)
  | .present f => slotFault directory count f k

theorem slotFault_noExit {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat}
    (he : f.exitText = none) :
    slotFault directory count f k = some (.noExit k) := by
  simp [slotFault, he]

theorem slotFault_badExit {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat} {t : String}
    (he : f.exitText = some t) (hok : exitOk t = false) :
    slotFault directory count f k = some (.badExit k (normalizeExit t)) := by
  simp [slotFault, he, hok]

theorem slotFault_noCaseList {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat}
    {t : String} (he : f.exitText = some t) (hok : exitOk t = true) (hc : f.casesText = none) :
    slotFault directory count f k = some (.noCaseList k) := by
  simp [slotFault, he, hok, hc]

theorem slotFault_wrongCases {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat}
    {t ct : String} (he : f.exitText = some t) (hok : exitOk t = true)
    (hc : f.casesText = some ct) (hlist : (parseCaseList ct == byMod directory count k) = false) :
    slotFault directory count f k = some (.caseList k) := by
  simp [slotFault, he, hok, hc, hlist]

theorem slotFault_noTiming {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat}
    {t ct : String} (he : f.exitText = some t) (hok : exitOk t = true)
    (hc : f.casesText = some ct) (hlist : parseCaseList ct = byMod directory count k)
    (hti : f.timingText = none) :
    slotFault directory count f k = some (.noTiming k) := by
  simp [slotFault, he, hok, hc, hti, hlist]

theorem slotFault_noTable {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat}
    {t ct timing : String} (he : f.exitText = some t) (hok : exitOk t = true)
    (hc : f.casesText = some ct) (hlist : parseCaseList ct = byMod directory count k)
    (hti : f.timingText = some timing) (hta : f.tableText = none) :
    slotFault directory count f k = some (.noTable k) := by
  simp [slotFault, he, hok, hc, hti, hta, hlist]

theorem slotFault_witness {directory : List String} {count : Nat} {f : ShardFiles} {k : Nat}
    {t ct timing table : String} (he : f.exitText = some t) (hok : exitOk t = true)
    (hc : f.casesText = some ct) (hlist : parseCaseList ct = byMod directory count k)
    (hti : f.timingText = some timing) (hta : f.tableText = some table) :
    slotFault directory count f k =
      witnessProblem k f.regularFiles timing table (parseCaseList ct) := by
  simp [slotFault, he, hok, hc, hti, hta, hlist]

theorem some_ne_none {α : Type} {a : α} {o : Option α} (hs : o = some a) (hn : o = none) :
    False := by
  simp [hs] at hn

theorem slotFault_none_iff (directory : List String) (count : Nat) (f : ShardFiles) (k : Nat) :
    slotFault directory count f k = none ↔
      ∃ t ct timing table,
        f.exitText = some t ∧ exitOk t = true ∧
          f.casesText = some ct ∧ parseCaseList ct = byMod directory count k ∧
          f.timingText = some timing ∧ f.tableText = some table ∧
          witnessProblem k f.regularFiles timing table (parseCaseList ct) = none := by
  constructor
  · intro h
    cases he : f.exitText with
    | none => exact absurd h (fun hnone => some_ne_none (slotFault_noExit he) hnone)
    | some t =>
      cases hok : exitOk t with
      | false => exact absurd h (fun hnone => some_ne_none (slotFault_badExit he hok) hnone)
      | true =>
        cases hc : f.casesText with
        | none => exact absurd h (fun hnone => some_ne_none (slotFault_noCaseList he hok hc) hnone)
        | some ct =>
          cases hbeq : (parseCaseList ct == byMod directory count k) with
          | false =>
            exact absurd h (fun hnone => some_ne_none (slotFault_wrongCases he hok hc hbeq) hnone)
          | true =>
            have hlist : parseCaseList ct = byMod directory count k := (beq_iff_eq).mp hbeq
            cases hti : f.timingText with
            | none =>
              exact absurd h (fun hnone =>
                some_ne_none (slotFault_noTiming he hok hc hlist hti) hnone)
            | some timing =>
              cases hta : f.tableText with
              | none =>
                exact absurd h (fun hnone =>
                  some_ne_none (slotFault_noTable he hok hc hlist hti hta) hnone)
              | some table =>
                refine ⟨t, ct, timing, table, rfl, hok, rfl, hlist, rfl, rfl, ?_⟩
                simpa [slotFault_witness he hok hc hlist hti hta] using h
  · intro hex
    rcases hex with ⟨t, ct, timing, table, he, hok, hc, hlist, hti, hta, hw⟩
    simpa [slotFault_witness he hok hc hlist hti hta] using hw

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

end MitosGate.CheatsAggregate
