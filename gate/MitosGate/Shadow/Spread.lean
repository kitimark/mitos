namespace MitosGate.Shadow

structure Spread where
  n : Nat
  min : Nat
  median : Nat
  p90 : Nat
  max : Nat
  deriving DecidableEq

def insertSorted (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insertSorted x ys

def sortAsc (xs : List Nat) : List Nat := xs.foldr insertSorted []

def spread (xs : List Nat) : Spread :=
  let s := sortAsc xs
  { n := s.length, min := s.head?.getD 0, median := s.getD (s.length / 2) 0,
    p90 := s.getD (s.length * 9 / 10) 0, max := s.getLast?.getD 0 }

def within (width t : Nat) (xs : List (Nat × Nat)) : Nat :=
  ((xs.filter fun (u, _) => t ≤ u && u < t + width).map (·.2)).sum

def peak (width : Nat) (xs : List (Nat × Nat)) : Nat :=
  (xs.map fun (t, _) => within width t xs).foldr max 0

def PeakBoundsEveryWindow : Prop :=
  ∀ (width t : Nat) (xs : List (Nat × Nat)), t ∈ xs.map (·.1) →
    within width t xs ≤ peak width xs

theorem le_foldr_max : ∀ {l : List Nat} {a : Nat}, a ∈ l → a ≤ l.foldr max 0
  | b :: l, a, h => by
    rcases List.mem_cons.mp h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (le_foldr_max h) (Nat.le_max_right _ _)

theorem peakBoundsEveryWindow : PeakBoundsEveryWindow := by
  intro width t xs h
  obtain ⟨⟨u, y⟩, hm, rfl⟩ := List.mem_map.mp h
  exact le_foldr_max (List.mem_map.mpr ⟨(u, y), hm, rfl⟩)

namespace Fixture

theorem aSpreadOfTen :
    spread [9, 1, 8, 2, 7, 3, 6, 4, 5, 10] = ⟨10, 1, 6, 10, 10⟩ := by decide +kernel
theorem noRunsSpreadToZeros : spread [] = ⟨0, 0, 0, 0, 0⟩ := by decide +kernel
theorem theBusiestHourIsThePeak :
    peak 3600 [(0, 30), (3599, 30), (3600, 40), (7200, 40)] = 70 := by decide +kernel

end Fixture

end MitosGate.Shadow
