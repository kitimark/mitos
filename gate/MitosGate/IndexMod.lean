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

/-- `(i + 1) % n` wraps to `0` only on the last residue. -/
theorem succ_mod_eq (i n : Nat) (hn : 0 < n) :
    (i + 1) % n = if i % n = n - 1 then 0 else i % n + 1 := by
  have hlt : i % n < n := Nat.mod_lt i hn
  have hshift : (i + 1) % n = (i % n + 1) % n := by
    calc (i + 1) % n
        = (1 + i) % n := by rw [Nat.add_comm]
      _ = (1 + i % n) % n := (Nat.add_mod_mod 1 i n).symm
      _ = (i % n + 1) % n := by rw [Nat.add_comm]
  rw [hshift]
  by_cases h : i % n = n - 1
  · simp only [h]
    have : n - 1 + 1 = n := Nat.succ_pred_eq_of_pos hn
    rw [this]
    simp [Nat.mod_self]
  · have hlt1 : i % n + 1 < n := by omega
    simp [h, Nat.mod_eq_of_lt hlt1]

theorem byMod_sublist {α : Type} (xs : List α) (n k : Nat) : (byMod xs n k).Sublist xs := by
  unfold byMod
  have hs :
      (List.map Prod.fst (List.filter (fun p : α × Nat => p.2 % n == k) xs.zipIdx)).Sublist
        (List.map Prod.fst xs.zipIdx) :=
    List.Sublist.map _ List.filter_sublist
  simpa [List.zipIdx_map_fst] using hs

theorem byMod_nodup {α : Type} {xs : List α} (hnd : xs.Nodup) (n k : Nat) :
    (byMod xs n k).Nodup :=
  List.Nodup.sublist (byMod_sublist xs n k) hnd

private def shiftIdx {α : Type} (p : α × Nat) : α × Nat :=
  (p.1, p.2 + 1)

theorem byMod_cons_zero {α : Type} (x : α) (xs : List α) {n : Nat} (hn : 0 < n) :
    byMod (x :: xs) n 0 = x :: byMod xs n (n - 1) := by
  unfold byMod
  have hfilter :
      List.filter (fun p : α × Nat => p.2 % n == 0) ((x, 0) :: xs.zipIdx 1) =
        (x, 0) :: List.filter (fun p : α × Nat => p.2 % n == 0) (xs.zipIdx 1) := by
    simp [List.filter, Nat.mod_eq_of_lt hn]
  rw [List.zipIdx_cons, hfilter, List.map_cons]
  have hshift :
      List.filter (fun p : α × Nat => p.2 % n == 0) (xs.zipIdx 1) =
        List.map shiftIdx (List.filter (fun p : α × Nat => p.2 % n == n - 1) xs.zipIdx) := by
    rw [List.zipIdx_succ]
    simp only [List.filter_map]
    refine congrArg (List.map shiftIdx) (List.filter_congr ?_)
    intro p _
    show ((p.2 + 1) % n == 0) = (p.2 % n == n - 1)
    rw [succ_mod_eq p.2 n hn]
    by_cases h : p.2 % n = n - 1 <;> simp [h]
  rw [hshift, List.map_map]
  have hfst : Prod.fst ∘ shiftIdx (α := α) = Prod.fst := by
    funext p
    rfl
  simp [hfst]

theorem byMod_cons_succ {α : Type} (x : α) (xs : List α) {n k : Nat} (hk : k + 1 < n) :
    byMod (x :: xs) n (k + 1) = byMod xs n k := by
  unfold byMod
  have hn : 0 < n := Nat.lt_trans (Nat.succ_pos k) hk
  have hfilter :
      List.filter (fun p : α × Nat => p.2 % n == k + 1) ((x, 0) :: xs.zipIdx 1) =
        List.filter (fun p : α × Nat => p.2 % n == k + 1) (xs.zipIdx 1) := by
    simp [List.filter, Nat.mod_eq_of_lt hn]
  rw [List.zipIdx_cons, hfilter]
  have hshift :
      List.filter (fun p : α × Nat => p.2 % n == k + 1) (xs.zipIdx 1) =
        List.map shiftIdx (List.filter (fun p : α × Nat => p.2 % n == k) xs.zipIdx) := by
    rw [List.zipIdx_succ]
    simp only [List.filter_map]
    refine congrArg (List.map shiftIdx) (List.filter_congr ?_)
    intro p _
    show ((p.2 + 1) % n == k + 1) = (p.2 % n == k)
    rw [succ_mod_eq p.2 n hn]
    by_cases h : p.2 % n = n - 1
    · have hleft : ((0 : Nat) == k + 1) = false := by
        simp
      have hright : ((n - 1) == k) = false := by
        simp
        intro heq
        have : k + 1 = n := by
          rw [← heq]
          exact Nat.succ_pred_eq_of_pos hn
        omega
      simp [h, hleft, hright]
    · simp [h]
  rw [hshift, List.map_map]
  have hfst : Prod.fst ∘ shiftIdx (α := α) = Prod.fst := by
    funext p
    rfl
  simp [hfst]

theorem flatMap_range_nil {α : Type} (n : Nat) (f : Nat → List α) (h : ∀ k, f k = []) :
    (List.range n).flatMap f = [] := by
  induction n with
  | zero => simp
  | succ n ih =>
    simp [List.range_succ, List.flatMap_append, List.flatMap_cons, List.flatMap_nil, h, ih]

theorem flatMap_range_congr {α : Type} {n : Nat} {f g : Nat → List α}
    (h : ∀ k, k < n → f k = g k) :
    (List.range n).flatMap f = (List.range n).flatMap g := by
  induction n with
  | zero => simp
  | succ n ih =>
    simp only [List.range_succ, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
      List.append_nil]
    rw [ih fun k hk => h k (Nat.lt_trans hk (Nat.lt_succ_self n)),
      h n (Nat.lt_succ_self n)]

theorem flatMap_range_cons {α : Type} (n : Nat) (f : Nat → List α) :
    (List.range (n + 1)).flatMap f = f 0 ++ (List.range n).flatMap (fun k => f (k + 1)) := by
  simp only [List.range_succ_eq_map, List.flatMap_cons, List.flatMap_map, Nat.succ_eq_add_one]

theorem byMod_join_perm {α : Type} (xs : List α) {n : Nat} (hn : 0 < n) :
    ((List.range n).flatMap (byMod xs n)).Perm xs := by
  induction xs generalizing n with
  | nil =>
    exact List.Perm.of_eq (flatMap_range_nil n (byMod [] n) fun _ => by simp [byMod])
  | cons x xs ih =>
    cases n with
    | zero => exact absurd hn (Nat.not_lt_zero 0)
    | succ m =>
      have htail :
          (List.range m).flatMap (fun k => byMod (x :: xs) (m + 1) (k + 1)) =
            (List.range m).flatMap (byMod xs (m + 1)) :=
        flatMap_range_congr fun k hk => byMod_cons_succ x xs (Nat.succ_lt_succ hk)
      have hjoin :
          (List.range (m + 1)).flatMap (byMod (x :: xs) (m + 1)) =
            x :: (byMod xs (m + 1) m ++ (List.range m).flatMap (byMod xs (m + 1))) := by
        rw [flatMap_range_cons, byMod_cons_zero x xs (Nat.succ_pos m), Nat.succ_sub_one, htail]
        simp
      have hrot :
          (byMod xs (m + 1) m ++ (List.range m).flatMap (byMod xs (m + 1))).Perm
            ((List.range (m + 1)).flatMap (byMod xs (m + 1))) := by
        simpa [List.range_succ, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
          List.append_nil] using
          List.perm_append_comm (l₁ := byMod xs (m + 1) m)
            (l₂ := (List.range m).flatMap (byMod xs (m + 1)))
      exact (List.Perm.of_eq hjoin).trans
        ((List.Perm.cons x hrot).trans (List.Perm.cons x (ih (Nat.succ_pos m))))

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
