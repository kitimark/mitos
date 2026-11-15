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

def kernelSort (xs : List Nat) : List Nat := xs.foldr insertSorted []

def spread (xs : List Nat) : Spread :=
  let s := kernelSort xs
  { n := s.length, min := s.head?.getD 0, median := s.getD (s.length / 2) 0,
    p90 := s.getD (s.length * 9 / 10) 0, max := s.getLast?.getD 0 }

def within (width t : Nat) (xs : List (Nat × Nat)) : Nat :=
  ((xs.filter fun (u, _) => t ≤ u && u < t + width).map (·.2)).sum

def peak (width : Nat) (xs : List (Nat × Nat)) : Nat :=
  (xs.map fun (t, _) => within width t xs).foldr max 0

def PeakBoundsEveryWindow : Prop :=
  ∀ (width t : Nat) (xs : List (Nat × Nat)), within width t xs ≤ peak width xs

theorem le_foldr_max : ∀ {l : List Nat} {a : Nat}, a ∈ l → a ≤ l.foldr max 0
  | b :: l, a, h => by
    rcases List.mem_cons.mp h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (le_foldr_max h) (Nat.le_max_right _ _)

theorem sum_filter_le {p q : Nat × Nat → Bool} :
    ∀ {xs : List (Nat × Nat)}, (∀ x ∈ xs, p x = true → q x = true) →
      ((xs.filter p).map (·.2)).sum ≤ ((xs.filter q).map (·.2)).sum
  | [], _ => Nat.le_refl _
  | x :: xs, h => by
    have ih := sum_filter_le fun y hy => h y (List.mem_cons_of_mem _ hy)
    have hx := h x (List.mem_cons_self ..)
    simp only [List.filter_cons]
    cases hp : p x <;> cases hq : q x <;> simp_all <;> omega

theorem exists_first : ∀ {xs : List (Nat × Nat)}, xs ≠ [] → ∃ x ∈ xs, ∀ y ∈ xs, x.1 ≤ y.1
  | [], h => absurd rfl h
  | [x], _ => ⟨x, List.mem_singleton_self _, fun y hy => by simp_all⟩
  | x :: z :: xs, _ => by
    obtain ⟨a, ha, hmin⟩ := exists_first (xs := z :: xs) (List.cons_ne_nil _ _)
    by_cases hle : x.1 ≤ a.1
    · exact ⟨x, List.mem_cons_self .., fun y hy => by
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · exact Nat.le_trans hle (hmin y hy)⟩
    · exact ⟨a, List.mem_cons_of_mem _ ha, fun y hy => by
        rcases List.mem_cons.mp hy with rfl | hy
        · omega
        · exact hmin y hy⟩

theorem peakBoundsEveryWindow : PeakBoundsEveryWindow := by
  intro width t xs
  let inside : Nat × Nat → Bool := fun (u, _) => t ≤ u && u < t + width
  by_cases he : xs.filter inside = []
  · have : within width t xs = 0 := by simp only [within]; rw [show (xs.filter _) = [] from he]; rfl
    omega
  · obtain ⟨⟨u, y⟩, hu, hmin⟩ := exists_first he
    have hu' := List.mem_filter.mp hu
    have hlo : t ≤ u ∧ u < t + width := by simpa [inside] using hu'.2
    have hsub : within width t xs ≤ within width u xs := by
      apply sum_filter_le
      intro x hx hin
      have hm := hmin x (List.mem_filter.mpr ⟨hx, hin⟩)
      obtain ⟨v, z⟩ := x
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hin hm ⊢
      omega
    exact Nat.le_trans hsub (le_foldr_max (List.mem_map.mpr ⟨(u, y), hu'.1, rfl⟩))

namespace Fixture

theorem aSpreadOfTen :
    spread [9, 1, 8, 2, 7, 3, 6, 4, 5, 10] = ⟨10, 1, 6, 10, 10⟩ := by decide +kernel
theorem noRunsSpreadToZeros : spread [] = ⟨0, 0, 0, 0, 0⟩ := by decide +kernel
theorem theBusiestHourIsThePeak :
    peak 3600 [(0, 30), (3599, 30), (3600, 40), (7200, 40)] = 70 := by decide +kernel

end Fixture

end MitosGate.Shadow
