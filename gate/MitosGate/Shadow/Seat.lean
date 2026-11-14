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

def headOf (r : Record) (o : Obs) (m : Merge) : Head :=
  if o.head == m.head then .same
  else
    match o.base with
    | .clean x =>
      if r.trees.any fun t => t.commit == x && t.tree == m.tree then .replayedAsPlanned
      else .replayedOtherwise
    | _ => .other

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
  m.before != "" && r.main == m.before && decide (r.read < m.time)

def last (m : Merge) : List Record → Option Record
  | [] => none
  | r :: rs =>
    match last m rs with
    | some x => if precedes m r && decide (x.read < r.read) then some r else some x
    | none => if precedes m r then some r else none

def seat (m : Merge) (rs : List Record) : Seat :=
  match last m rs with
  | none => .unseen
  | some r =>
    match r.prs.find? (·.pr == m.pr) with
    | none => .unlisted r.run
    | some o =>
      .sat { run := r.run, age := seconds m.time - seconds r.read, reading := reading r.prs o,
             lacks := lacks o, head := headOf r o m, authorKnown := o.author.isSome,
             updaterPushes := (o.pushes.filter (·.byUpdater)).length }

def PairedRecordPrecedesTheMerge : Prop :=
  ∀ (m : Merge) (rs : List Record) (r : Record), last m rs = some r →
    r ∈ rs ∧ r.main = m.before ∧ r.read < m.time ∧
      ∀ x ∈ rs, x.main = m.before → x.read < m.time → x.read ≤ r.read

def SeatIgnoresRecordOrder : Prop :=
  ∀ (m : Merge) (rs rs' : List Record), rs.Perm rs' → (rs.map (·.read)).Nodup →
    seat m rs = seat m rs'

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

theorem last_precedes {m : Merge} : ∀ {rs : List Record} {r : Record}, last m rs = some r →
    precedes m r = true
  | [], _, h => by cases h
  | a :: rs, r, h => by
    simp only [last] at h
    split at h
    · rename_i x hx
      split at h
      · rename_i hc
        cases h
        simp only [Bool.and_eq_true] at hc
        exact hc.1
      · cases h
        exact last_precedes hx
    · split at h
      · rename_i hc
        cases h
        exact hc
      · cases h

theorem precedes_before {m : Merge} {r : Record} (h : precedes m r = true) : m.before ≠ "" := by
  simp only [precedes, Bool.and_eq_true, bne_iff_ne] at h
  exact h.1.1

theorem pairedRecordPrecedesTheMerge : PairedRecordPrecedesTheMerge := by
  intro m rs
  induction rs with
  | nil => intro r h; cases h
  | cons a rs ih =>
    intro r h
    simp only [last] at h
    split at h
    · rename_i x hx
      obtain ⟨hmem, hmain, hread, hmax⟩ := ih x hx
      split at h
      · rename_i hc
        cases h
        simp only [precedes, Bool.and_eq_true, bne_iff_ne, ne_eq, beq_iff_eq,
          decide_eq_true_eq] at hc
        refine ⟨List.mem_cons_self .., hc.1.1.2, hc.1.2, ?_⟩
        intro y hy h1 h2
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · exact Nat.le_trans (hmax y hy h1 h2) (Nat.le_of_lt hc.2)
      · rename_i hc
        cases h
        refine ⟨List.mem_cons_of_mem _ hmem, hmain, hread, ?_⟩
        intro y hy h1 h2
        rcases List.mem_cons.mp hy with rfl | hy
        · have hb := precedes_before (last_precedes hx)
          simp only [precedes, Bool.and_eq_true, bne_iff_ne, ne_eq, beq_iff_eq,
            decide_eq_true_eq, not_and, Nat.not_lt] at hc
          exact hc ⟨⟨hb, h1⟩, h2⟩
        · exact hmax y hy h1 h2
    · rename_i hx
      split at h
      · rename_i hc
        cases h
        simp only [precedes, Bool.and_eq_true, bne_iff_ne, ne_eq, beq_iff_eq,
          decide_eq_true_eq] at hc
        refine ⟨List.mem_cons_self .., hc.1.2, hc.2, ?_⟩
        intro y hy h1 h2
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · have := last_none hx y hy
          simp [precedes, h1, h2, hc.1.1] at this
      · cases h

namespace Fixture

def rec (run read : Nat) (main : Sha) (prs : List Obs) : Record :=
  { run, trigger := .mainMoved, read, main, tool := main, cost := ⟨20, 12, 1, 0, 36⟩, prs,
    trees := [⟨"br", "tb"⟩] }
def merged : Merge := { pr := 149, time := 100, before := "m1", head := "b2", tree := "tb" }

theorem theNewestRecordBeforeTheMergeIsUsed :
    (match seat { merged with head := "bbb" }
        [rec 1 80 "m1" [unsaid], rec 2 90 "m1" [unsaidOnMain]] with
      | .sat s => s.run | _ => 0) = 2 := by decide +kernel
theorem theAgeIsInSeconds :
    (match seat { merged with time := 20261113120100 } [rec 1 20261113120059 "m1" [unsaid]] with
      | .sat s => s.age | _ => 0) = 1 := by decide +kernel

end Fixture

end MitosGate.Shadow
