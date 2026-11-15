namespace MitosGate.DecideList

def dropChar (c : Char) : List Char → List Char
  | [] => []
  | x :: xs => if x == c then dropChar c xs else x :: dropChar c xs

def dropTrailNL (s : String) : String :=
  String.ofList (s.toList.reverse.dropWhile (· == '\n') |>.reverse)

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
  | pat, b :: bs => isPrefix pat (b :: bs) || hasSub pat bs

def insertLine (x : String) : List String → List String
  | [] => [x]
  | y :: ys => if y < x then y :: insertLine x ys else x :: y :: ys

/-- `List.mergeSort` does not reduce under `decide`. -/
def sortStrings : List String → List String
  | [] => []
  | x :: xs => insertLine x (sortStrings xs)

def nodupList (xs : List String) : Bool :=
  decide (xs.Nodup)

/-- Coverage is membership, not a sorted spelling. `sortStrings` stays for the timing table. -/
def sameNames (a b : List String) : Bool :=
  nodupList a && nodupList b && a.length == b.length && a.all (b.contains)

theorem mem_iff_of_nodup_length_subset {a b : List String}
    (ha : a.Nodup) (hlen : a.length = b.length) (hsub : a ⊆ b) :
    ∀ x, x ∈ a ↔ x ∈ b := by
  intro x
  constructor
  · exact fun hx => hsub hx
  · intro hx
    cases Classical.em (x ∈ a) with
    | inl hmem => exact hmem
    | inr hna =>
      have hsub' : a ⊆ b.erase x := by
        intro y hy
        have hyx : y ≠ x := fun h => hna (h ▸ hy)
        exact (List.mem_erase_of_ne hyx).2 (hsub hy)
      have hle := List.Nodup.length_le_of_subset ha hsub'
      have hshort : (b.erase x).length = b.length - 1 := List.length_erase_of_mem hx
      have hle' : a.length ≤ b.length - 1 := by simpa [hshort] using hle
      have hpos : 1 ≤ b.length := List.length_pos_of_mem hx
      have hshrink : b.length ≤ b.length - 1 := by simpa [hlen] using hle'
      exact False.elim (Nat.lt_irrefl b.length
        (Nat.lt_of_le_of_lt hshrink (Nat.sub_lt hpos (Nat.succ_pos 0))))

theorem sameNames_iff (a b : List String) :
    sameNames a b = true ↔ a.Nodup ∧ b.Nodup ∧ ∀ x, x ∈ a ↔ x ∈ b := by
  constructor
  · intro h
    unfold sameNames at h
    rw [Bool.and_eq_true] at h
    rcases h with ⟨hrest, hall⟩
    rw [Bool.and_eq_true] at hrest
    rcases hrest with ⟨hnods, hlen⟩
    rw [Bool.and_eq_true] at hnods
    rcases hnods with ⟨ha, hb⟩
    have ha' : a.Nodup := by simpa [nodupList, decide_eq_true_eq] using ha
    have hb' : b.Nodup := by simpa [nodupList, decide_eq_true_eq] using hb
    have hlen' : a.length = b.length := by simpa [beq_iff_eq] using hlen
    have hsub : ∀ x, x ∈ a → x ∈ b := by
      simpa [List.all_eq_true, List.contains_iff_mem] using hall
    exact ⟨ha', hb', mem_iff_of_nodup_length_subset ha' hlen' hsub⟩
  · rintro ⟨ha, hb, hmem⟩
    have hlen : a.length = b.length :=
      List.Perm.length_eq ((List.perm_ext_iff_of_nodup ha hb).2 hmem)
    unfold sameNames
    rw [Bool.and_eq_true, Bool.and_eq_true, Bool.and_eq_true]
    refine ⟨⟨⟨?_, ?_⟩, ?_⟩, ?_⟩
    · simpa [nodupList, decide_eq_true_eq] using ha
    · simpa [nodupList, decide_eq_true_eq] using hb
    · simpa [beq_iff_eq] using hlen
    · simp [List.all_eq_true]
      intro x hx
      exact (hmem x).1 hx

def firstDup (xs : List String) : Option String :=
  xs.find? fun n => xs.count n > 1

end MitosGate.DecideList
