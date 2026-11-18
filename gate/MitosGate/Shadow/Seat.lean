import MitosGate.Shadow.Types
import MitosGate.Shadow.Lacks
import MitosGate.Shadow.Reading

namespace MitosGate.Shadow

open Land

inductive Head
  | same
  | replayedAsPlanned
  | replayedOtherwise
  | other
  deriving DecidableEq

def Record.tree? (r : Record) (c : Sha) : Option Sha :=
  (r.trees.find? (·.commit == c)).map (·.tree)

def headOf (r : Record) (o : Obs) (m : Merge) : Head :=
  if o.head == m.head then .same
  else
    match o.base with
    | .clean x =>
      match r.tree? x, m.tree with
      | some a, some b => if a == b then .replayedAsPlanned else .replayedOtherwise
      | _, _ => .other
    | _ => .other

def TheReplayMergedIffItsTreeDid : Prop :=
  ∀ (r : Record) (o : Obs) (m : Merge), headOf r o m = .replayedAsPlanned ↔
    o.head ≠ m.head ∧ ∃ x t, o.base = .clean x ∧ r.tree? x = some t ∧ m.tree = some t

def AnotherTreeIsTwoTreesRead : Prop :=
  ∀ (r : Record) (o : Obs) (m : Merge), headOf r o m = .replayedOtherwise ↔
    o.head ≠ m.head ∧ ∃ x a b, o.base = .clean x ∧ r.tree? x = some a ∧ m.tree = some b ∧ a ≠ b

theorem theReplayMergedIffItsTreeDid : TheReplayMergedIffItsTreeDid := by
  intro r o m
  unfold headOf
  by_cases hh : o.head = m.head
  · simp [hh]
  · simp only [hh, beq_iff_eq, ite_false, ne_eq, not_false_eq_true, true_and]
    cases o.base <;> simp
    rename_i x
    cases r.tree? x <;> cases m.tree <;> simp [eq_comm]

theorem anotherTreeIsTwoTreesRead : AnotherTreeIsTwoTreesRead := by
  intro r o m
  unfold headOf
  by_cases hh : o.head = m.head
  · simp [hh]
  · simp only [hh, beq_iff_eq, ite_false, ne_eq, not_false_eq_true, true_and]
    cases o.base <;> simp
    rename_i x
    cases r.tree? x <;> cases m.tree <;> simp

structure Sat where
  run : Nat
  age : Nat
  reading : Reading
  lacks : List Clause
  head : Head
  authorKnown : Bool
  updaterPushes : Nat

inductive Seat
  | unseen
  | unlisted (run : Nat)
  | sat (s : Sat)

def precedes (m : Merge) (r : Record) : Bool :=
  match m.before with
  | some b => r.main == some b && decide (r.read < m.time)
  | none => false

def Record.newer (r x : Record) : Bool :=
  decide (x.read < r.read) || decide (x.read = r.read) && decide (x.run < r.run)

def last (m : Merge) : List Record → Option Record
  | [] => none
  | r :: rs =>
    match last m rs with
    | some x => if precedes m r && r.newer x then some r else some x
    | none => if precedes m r then some r else none

theorem last_congr {m m' : Merge} (hb : m.before = m'.before) (ht : m.time = m'.time) :
    ∀ rs : List Record, last m rs = last m' rs
  | [] => rfl
  | r :: rs => by
    have hp : precedes m r = precedes m' r := by simp [precedes, hb, ht]
    simp only [last, last_congr hb ht rs, hp]

def seat (m : Merge) (rs : List Record) : Seat :=
  match last m rs with
  | none => .unseen
  | some r =>
    match r.prs.find? (·.pr == m.pr) with
    | none => .unlisted r.run
    | some o =>
      .sat { run := r.run, age := m.time.seconds - r.read.seconds, reading := reading m.summary r.prs o,
             lacks := lacks o, head := headOf r o m, authorKnown := o.author.isSome,
             updaterPushes := (o.pushes.filter (·.byUpdater)).length }

def PairedRecordPrecedesTheMerge : Prop :=
  ∀ (m : Merge) (rs : List Record) (r : Record), last m rs = some r →
    r ∈ rs ∧ ∃ b, m.before = some b ∧ r.main = some b ∧ r.read < m.time ∧
      ∀ x ∈ rs, x.main = some b → x.read < m.time →
        x.read ≤ r.read ∧ (x.read = r.read → x.run ≤ r.run)

def SeatIgnoresRecordOrder : Prop :=
  ∀ (m : Merge) (rs rs' : List Record), rs.Perm rs' → (rs.map fun r => (r.read, r.run)).Nodup →
    seat m rs = seat m rs'

theorem precedes_iff {m : Merge} {r : Record} :
    precedes m r = true ↔ ∃ b, m.before = some b ∧ r.main = some b ∧ r.read < m.time := by
  unfold precedes
  cases m.before <;> simp

theorem last_none {m : Merge} : ∀ {rs : List Record}, last m rs = none →
    ∀ y ∈ rs, precedes m y = false
  | [], _, y, hy => by cases hy
  | a :: rs, h, y, hy => by
    simp only [last] at h
    split at h
    · split at h <;> cases h
    · rename_i hx
      split at h
      · cases h
      · rename_i hc
        rcases List.mem_cons.mp hy with rfl | hy
        · simpa using hc
        · exact last_none hx y hy

theorem newer_iff {r x : Record} : r.newer x = true ↔
    x.read.digits < r.read.digits ∨ x.read.digits = r.read.digits ∧ x.run < r.run := by
  simp only [Record.newer, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, Stamp.eq_iff]
  exact Iff.rfl

theorem last_some {m : Merge} : ∀ {rs : List Record} {r : Record}, last m rs = some r →
    r ∈ rs ∧ precedes m r = true ∧ ∀ y ∈ rs, precedes m y = true →
      y.read.digits ≤ r.read.digits ∧ (y.read.digits = r.read.digits → y.run ≤ r.run)
  | [], _, h => by cases h
  | a :: rs, r, h => by
    simp only [last] at h
    split at h
    · rename_i x hx
      obtain ⟨hmem, hpx, hmax⟩ := last_some hx
      split at h
      · rename_i hc
        cases h
        simp only [Bool.and_eq_true] at hc
        have hn := newer_iff.mp hc.2
        refine ⟨List.mem_cons_self .., hc.1, fun y hy hpy => ?_⟩
        rcases List.mem_cons.mp hy with rfl | hy
        · unfold Speech.Stamp; omega
        · have := hmax y hy hpy
          unfold Speech.Stamp at *; omega
      · rename_i hc
        cases h
        refine ⟨List.mem_cons_of_mem _ hmem, hpx, fun y hy hpy => ?_⟩
        rcases List.mem_cons.mp hy with rfl | hy
        · simp only [hpy, Bool.true_and] at hc
          have := mt newer_iff.mpr hc
          unfold Speech.Stamp at *; omega
        · exact hmax y hy hpy
    · rename_i hx
      split at h
      · rename_i hc
        cases h
        refine ⟨List.mem_cons_self .., hc, fun y hy hpy => ?_⟩
        rcases List.mem_cons.mp hy with rfl | hy
        · unfold Speech.Stamp; omega
        · simp [last_none hx y hy] at hpy
      · cases h

theorem pairedRecordPrecedesTheMerge : PairedRecordPrecedesTheMerge := by
  intro m rs r h
  obtain ⟨hmem, hp, hmax⟩ := last_some h
  obtain ⟨b, hb, hm, ht⟩ := precedes_iff.mp hp
  refine ⟨hmem, b, hb, hm, ht, fun x hx h1 h2 => ?_⟩
  obtain ⟨hle, heq⟩ := hmax x hx (precedes_iff.mpr ⟨b, hb, h1, h2⟩)
  exact ⟨hle, fun e => heq (congrArg Stamp.digits e)⟩

theorem eq_of_key_eq : ∀ {rs : List Record} {a b : Record},
    (rs.map fun r => (r.read, r.run)).Nodup → a ∈ rs → b ∈ rs → a.read = b.read →
      a.run = b.run → a = b
  | c :: rs, a, b, hn, ha, hb, h1, h2 => by
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
    have fresh : ∀ x ∈ rs, (x.read, x.run) ≠ (c.read, c.run) := fun x hx hx' => hn.1 ⟨x, hx, hx'⟩
    rcases List.mem_cons.mp ha with ha' | ha' <;> rcases List.mem_cons.mp hb with hb' | hb'
    · subst ha' hb'; rfl
    · subst ha'; exact absurd (by rw [h1, h2]) (fresh b hb')
    · subst hb'; exact absurd (by rw [h1, h2]) (fresh a ha')
    · exact eq_of_key_eq hn.2 ha' hb' h1 h2

theorem last_perm {m : Merge} {rs rs' : List Record} (hp : rs.Perm rs')
    (hn : (rs.map fun r => (r.read, r.run)).Nodup) : last m rs = last m rs' := by
  cases h : last m rs with
  | none =>
    cases h' : last m rs' with
    | none => rfl
    | some r' =>
      obtain ⟨hmem', hp', _⟩ := last_some h'
      simp [last_none h r' (hp.mem_iff.mpr hmem')] at hp'
  | some r =>
    obtain ⟨hmem, hpr, hmax⟩ := last_some h
    cases h' : last m rs' with
    | none => simp [last_none h' r (hp.mem_iff.mp hmem)] at hpr
    | some r' =>
      obtain ⟨hmem', hpr', hmax'⟩ := last_some h'
      have h1 := hmax r' (hp.mem_iff.mpr hmem') hpr'
      have h2 := hmax' r (hp.mem_iff.mp hmem) hpr
      have hd : r.read.digits = r'.read.digits := by unfold Speech.Stamp at *; omega
      have hrun : r.run = r'.run := by
        have := h1.2 hd.symm
        have := h2.2 hd
        omega
      exact congrArg some
        (eq_of_key_eq hn hmem (hp.mem_iff.mpr hmem') (Stamp.eq_iff.mpr hd) hrun)

theorem seatIgnoresRecordOrder : SeatIgnoresRecordOrder := by
  intro m rs rs' hp hn
  simp only [seat, last_perm hp hn]

namespace Fixture

def rec (run read : Nat) (main : Option Sha) (prs : List Obs) : Record :=
  { run, trigger := .mainMoved, read := ⟨read⟩, main, tool := "t", cost := ⟨20, 12, 1, 0, 36⟩,
    prs, trees := [⟨"br", "tb"⟩] }
def merged : Merge :=
  { pr := 149, time := ⟨100⟩, before := some "m1", head := "b2", tree := some "tb", summary := .silent }

theorem theNewestRecordBeforeTheMergeIsUsed :
    (match seat { merged with head := "bbb" }
        [rec 1 80 (some "m1") [unsaid], rec 2 90 (some "m1") [unsaidOnMain]] with
      | .sat s => s.run | _ => 0) = 2 := by decide +kernel
theorem theAgeIsInSeconds :
    (match seat { merged with time := ⟨20261113120100⟩ }
        [rec 1 20261113120059 (some "m1") [unsaid]] with
      | .sat s => s.age | _ => 0) = 1 := by decide +kernel
theorem aTieOnReadGoesToTheLaterRun :
    (match seat { merged with head := "bbb" }
        [rec 7 90 (some "m1") [unsaid], rec 3 90 (some "m1") [unsaidOnMain]] with
      | .sat s => s.run | _ => 0) = 7 := by decide +kernel
theorem aTieOnReadGoesToTheLaterRunInEitherOrder :
    (match seat { merged with head := "bbb" }
        [rec 3 90 (some "m1") [unsaidOnMain], rec 7 90 (some "m1") [unsaid]] with
      | .sat s => s.run | _ => 0) = 7 := by decide +kernel

end Fixture

end MitosGate.Shadow
