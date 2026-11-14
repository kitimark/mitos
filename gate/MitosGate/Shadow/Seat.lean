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
      if r.trees.any fun t => t.commit == x && some t.tree == m.tree then .replayedAsPlanned
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
  match m.before with
  | some b => r.main == some b && decide (r.read < m.time)
  | none => false

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
      .sat { run := r.run, age := m.time.seconds - r.read.seconds, reading := reading r.prs o,
             lacks := lacks o, head := headOf r o m, authorKnown := o.author.isSome,
             updaterPushes := (o.pushes.filter (·.byUpdater)).length }

def PairedRecordPrecedesTheMerge : Prop :=
  ∀ (m : Merge) (rs : List Record) (r : Record), last m rs = some r →
    r ∈ rs ∧ ∃ b, m.before = some b ∧ r.main = some b ∧ r.read < m.time ∧
      ∀ x ∈ rs, x.main = some b → x.read < m.time → x.read ≤ r.read

def SeatIgnoresRecordOrder : Prop :=
  ∀ (m : Merge) (rs rs' : List Record), rs.Perm rs' → (rs.map (·.read)).Nodup →
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

theorem last_some {m : Merge} : ∀ {rs : List Record} {r : Record}, last m rs = some r →
    r ∈ rs ∧ precedes m r = true ∧ ∀ y ∈ rs, precedes m y = true → y.read ≤ r.read
  | [], _, h => by cases h
  | a :: rs, r, h => by
    simp only [last] at h
    split at h
    · rename_i x hx
      obtain ⟨hmem, hpx, hmax⟩ := last_some hx
      split at h
      · rename_i hc
        cases h
        simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
        refine ⟨List.mem_cons_self .., hc.1, fun y hy hpy => ?_⟩
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · exact Nat.le_trans (hmax y hy hpy) (Nat.le_of_lt hc.2)
      · rename_i hc
        cases h
        refine ⟨List.mem_cons_of_mem _ hmem, hpx, fun y hy hpy => ?_⟩
        rcases List.mem_cons.mp hy with rfl | hy
        · simp only [hpy, Bool.true_and, decide_eq_true_eq] at hc
          exact Nat.not_lt.mp hc
        · exact hmax y hy hpy
    · rename_i hx
      split at h
      · rename_i hc
        cases h
        refine ⟨List.mem_cons_self .., hc, fun y hy hpy => ?_⟩
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · simp [last_none hx y hy] at hpy
      · cases h

theorem pairedRecordPrecedesTheMerge : PairedRecordPrecedesTheMerge := by
  intro m rs r h
  obtain ⟨hmem, hp, hmax⟩ := last_some h
  obtain ⟨b, hb, hm, ht⟩ := precedes_iff.mp hp
  exact ⟨hmem, b, hb, hm, ht, fun x hx h1 h2 => hmax x hx (precedes_iff.mpr ⟨b, hb, h1, h2⟩)⟩

theorem eq_of_read_eq : ∀ {rs : List Record} {a b : Record}, (rs.map (·.read)).Nodup →
    a ∈ rs → b ∈ rs → a.read = b.read → a = b
  | c :: rs, a, b, hn, ha, hb, h => by
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
    have fresh : ∀ x ∈ rs, x.read ≠ c.read := fun x hx hx' => hn.1 ⟨x, hx, hx'⟩
    rcases List.mem_cons.mp ha with ha' | ha' <;> rcases List.mem_cons.mp hb with hb' | hb'
    · subst ha' hb'; rfl
    · subst ha'; exact absurd h.symm (fresh b hb')
    · subst hb'; exact absurd h (fresh a ha')
    · exact eq_of_read_eq hn.2 ha' hb' h

theorem last_perm {m : Merge} {rs rs' : List Record} (hp : rs.Perm rs')
    (hn : (rs.map (·.read)).Nodup) : last m rs = last m rs' := by
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
      have : r.read = r'.read := by
        cases hr : r.read
        cases hr' : r'.read
        rw [hr, hr'] at h1 h2
        exact congrArg Stamp.mk (Nat.le_antisymm h2 h1)
      exact congrArg some (eq_of_read_eq hn hmem (hp.mem_iff.mpr hmem') this)

theorem seatIgnoresRecordOrder : SeatIgnoresRecordOrder := by
  intro m rs rs' hp hn
  simp only [seat, last_perm hp hn]

namespace Fixture

def rec (run read : Nat) (main : Option Sha) (prs : List Obs) : Record :=
  { run, trigger := .mainMoved, read := ⟨read⟩, main, tool := "t", cost := ⟨20, 12, 1, 0, 36⟩,
    prs, trees := [⟨"br", "tb"⟩] }
def merged : Merge :=
  { pr := 149, time := ⟨100⟩, before := some "m1", head := "b2", tree := some "tb" }

theorem theNewestRecordBeforeTheMergeIsUsed :
    (match seat { merged with head := "bbb" }
        [rec 1 80 (some "m1") [unsaid], rec 2 90 (some "m1") [unsaidOnMain]] with
      | .sat s => s.run | _ => 0) = 2 := by decide +kernel
theorem theAgeIsInSeconds :
    (match seat { merged with time := ⟨20261113120100⟩ }
        [rec 1 20261113120059 (some "m1") [unsaid]] with
      | .sat s => s.age | _ => 0) = 1 := by decide +kernel

end Fixture

end MitosGate.Shadow
