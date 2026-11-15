namespace MitosGate.IndexMod

def byMod {α : Type} (xs : List α) (n k : Nat) : List α :=
  (xs.zipIdx.filter fun p => p.2 % n == k).map (·.1)

theorem mem_byMod_iff {α : Type} {xs : List α} {n k : Nat} {x : α} :
    x ∈ byMod xs n k ↔ ∃ i, xs[i]? = some x ∧ i % n = k := by
  unfold byMod
  simp only [List.mem_map, List.mem_filter, beq_iff_eq]
  constructor
  · rintro ⟨p, ⟨hzip, hmod⟩, rfl⟩
    exact ⟨p.2, (List.mem_zipIdx_iff_getElem?).1 hzip, hmod⟩
  · rintro ⟨i, hget, hmod⟩
    rcases List.getElem?_eq_some_iff.1 hget with ⟨hi, heq⟩
    refine ⟨(xs[i], i), ⟨(List.mk_mem_zipIdx_iff_getElem?).2 (List.getElem?_eq_some_iff.2 ⟨hi, rfl⟩), hmod⟩, heq⟩

theorem get_mem_byMod {α : Type} {xs : List α} {n : Nat} {i : Nat}
    (hi : i < xs.length) : xs[i] ∈ byMod xs n (i % n) :=
  (mem_byMod_iff (x := xs[i])).2 ⟨i, List.getElem?_eq_some_iff.2 ⟨hi, rfl⟩, rfl⟩

theorem byMod_ne_nil_of_length {α : Type} {xs : List α} {n k : Nat} (_hn : 0 < n) (hk : k < n)
    (hlen : n ≤ xs.length) : byMod xs n k ≠ [] := by
  have hklen : k < xs.length := Nat.lt_of_lt_of_le hk hlen
  have hmem : xs[k] ∈ byMod xs n (k % n) := get_mem_byMod hklen
  rw [Nat.mod_eq_of_lt hk] at hmem
  exact List.ne_nil_of_mem hmem

theorem exists_empty_byMod_of_short {α : Type} {xs : List α} {n : Nat}
    (hlen : xs.length < n) : ∃ k, k < n ∧ byMod xs n k = [] := by
  refine ⟨xs.length, hlen, ?_⟩
  apply List.eq_nil_iff_forall_not_mem.2
  intro x hmem
  rcases (mem_byMod_iff (x := x)).1 hmem with ⟨j, hget, hmod⟩
  rcases List.getElem?_eq_some_iff.1 hget with ⟨hj, _⟩
  have hjn : j < n := Nat.lt_trans hj hlen
  have hjmod : j % n = j := Nat.mod_eq_of_lt hjn
  exact absurd (hjmod.symm.trans hmod) (Nat.ne_of_lt hj)

theorem byMod_disjoint {α : Type} {xs : List α} {n : Nat} (hnd : xs.Nodup)
    {x : α} {k₁ k₂ : Nat}
    (h₁ : x ∈ byMod xs n k₁) (h₂ : x ∈ byMod xs n k₂) : k₁ = k₂ := by
  rcases (mem_byMod_iff (x := x)).1 h₁ with ⟨j, hget₁, hm₁⟩
  rcases (mem_byMod_iff (x := x)).1 h₂ with ⟨t, hget₂, hm₂⟩
  rcases List.getElem?_eq_some_iff.1 hget₁ with ⟨hj, hej⟩
  rcases List.getElem?_eq_some_iff.1 hget₂ with ⟨ht, het⟩
  have hjt : j = t := (hnd.getElem_inj (hi := hj) (hj := ht)).mp (hej.trans het.symm)
  subst hjt
  exact hm₁.symm.trans hm₂

theorem exactly_one_byMod {α : Type} {xs : List α} {n : Nat} (hn : 0 < n) (hnd : xs.Nodup)
    {x : α} (hx : x ∈ xs) :
    ∃ k, k < n ∧ x ∈ byMod xs n k ∧ ∀ k', k' < n → x ∈ byMod xs n k' → k' = k := by
  rcases List.mem_iff_getElem.1 hx with ⟨i, hi, rfl⟩
  refine ⟨i % n, Nat.mod_lt i hn, get_mem_byMod hi, ?_⟩
  intro k' hk' hmem
  exact byMod_disjoint hnd hmem (get_mem_byMod hi)

theorem byMod_nonempty_of_length {α : Type} (xs : List α) (n : Nat) (hn : 0 < n)
    (hlen : n ≤ xs.length) : ∀ k, k < n → byMod xs n k ≠ [] :=
  fun k hk => byMod_ne_nil_of_length (k := k) hn hk hlen

namespace Fixture

theorem threeNamesOnePerResidue :
    byMod ["one", "three", "two"] 3 0 = ["one"] ∧
      byMod ["one", "three", "two"] 3 1 = ["three"] ∧
      byMod ["one", "three", "two"] 3 2 = ["two"] := by
  decide

theorem fourNamesByIndex :
    byMod ["one", "three", "two", "four"] 3 0 = ["one", "four"] ∧
      byMod ["one", "three", "two", "four"] 3 1 = ["three"] ∧
      byMod ["one", "three", "two", "four"] 3 2 = ["two"] := by
  decide

theorem oneModulusKeepsOrder :
    byMod ["b", "a"] 1 0 = ["b", "a"] := by
  decide

theorem shortListLeavesLastResidueEmpty :
    byMod ["one", "two"] 3 2 = ([] : List String) := by
  decide

theorem duplicateSitsInTwoResidues :
    "a" ∈ byMod ["a", "a"] 2 0 ∧ "a" ∈ byMod ["a", "a"] 2 1 := by
  decide

end Fixture

end MitosGate.IndexMod
