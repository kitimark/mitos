import MitosGate.CheatsPlan
import MitosGate.CheatsShard
import MitosGate.CheatsSlot
import MitosGate.DecideList
import MitosGate.IndexMod

namespace MitosGate.CheatsAggregate

open MitosGate.CheatsShard
open MitosGate.DecideList
open MitosGate.IndexMod

def stepSlot (i : AggregateInput) (acc : Option CorpusReject) (k : Nat) : Option CorpusReject :=
  match acc with
  | some r => some r
  | none =>
    match i.shards[k]? with
    | none => some (.missingShard k)
    | some s => slotProblem i.directory i.count s k

def firstSlot (i : AggregateInput) : Option CorpusReject :=
  (List.range i.count).foldl (stepSlot i) none

def recordedUnion (i : AggregateInput) : List String :=
  (List.range i.count).flatMap (recorded i)

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

end MitosGate.CheatsAggregate
