import MitosGate.RunLog
import Std.Data.String.ToNat

namespace MitosGate.RunLog

def added : List String → List String → List String
  | [], head => head
  | b :: bs, head => added bs (head.erase b)

theorem count_added (base head : List String) (l : String) :
    (added base head).count l = head.count l - base.count l := by
  induction base generalizing head with
  | nil => simp [added]
  | cons b bs ih =>
    rw [added, ih, List.count_erase, List.count_cons]
    split <;> omega

theorem appendOnly_iff_perm_added {base head : List String} :
    appendOnly base head = true ↔ head.Perm (base ++ added base head) := by
  constructor
  · intro h
    apply List.perm_iff_count.mpr
    intro l
    rw [List.count_append, count_added]
    have := appendOnly_iff_count.mp h l
    omega
  · intro h
    exact appendOnly_iff_perm_append.mpr ⟨_, h⟩

theorem added_perm_of_perm_append {base head a : List String} (h : head.Perm (base ++ a)) :
    (added base head).Perm a := by
  apply List.perm_iff_count.mpr
  intro l
  rw [count_added, List.perm_iff_count.mp h l, List.count_append]
  omega

def sortLines (ls : List String) : List String :=
  ls.mergeSort fun a b => decide (a ≤ b)

theorem sortLines_eq_of_perm {l₁ l₂ : List String} (h : l₁.Perm l₂) :
    sortLines l₁ = sortLines l₂ := by
  have trans : ∀ a b c : String, decide (a ≤ b) = true → decide (b ≤ c) = true →
      decide (a ≤ c) = true := fun _ _ _ hab hbc =>
    decide_eq_true (String.le_trans (of_decide_eq_true hab) (of_decide_eq_true hbc))
  have total : ∀ a b : String, (decide (a ≤ b) || decide (b ≤ a)) = true := fun a b => by
    rcases String.le_total a b with h | h <;> simp [h]
  apply List.Perm.eq_of_pairwise (le := fun a b => decide (a ≤ b) = true)
  · intro a b _ _ hab hba
    exact String.le_antisymm (of_decide_eq_true hab) (of_decide_eq_true hba)
  · exact List.pairwise_mergeSort trans total _
  · exact List.pairwise_mergeSort trans total _
  · exact (List.mergeSort_perm _ _).trans (h.trans (List.mergeSort_perm _ _).symm)

def addedSorted? (base head : List String) : Option (List String) :=
  if appendOnly base head then some (sortLines (added base head)) else none

theorem addedSorted?_eq_none_iff {base head : List String} :
    addedSorted? base head = none ↔ appendOnly base head = false := by
  unfold addedSorted?
  cases appendOnly base head <;> simp

theorem addedSorted?_edit (p s : List String) {l l' : String} (hne : l ≠ l') :
    addedSorted? (p ++ l :: s) (p ++ l' :: s) = none :=
  addedSorted?_eq_none_iff.mpr (appendOnly_edit p s hne)

theorem addedSorted?_delete (p s : List String) (l : String) :
    addedSorted? (p ++ l :: s) (p ++ s) = none :=
  addedSorted?_eq_none_iff.mpr (appendOnly_delete p s l)

theorem addedSorted?_of_perm_append {base head a : List String} (h : head.Perm (base ++ a)) :
    addedSorted? base head = some (sortLines a) := by
  have hb : appendOnly base head = true := appendOnly_iff_perm_append.mpr ⟨a, h⟩
  simp only [addedSorted?, hb, ↓reduceIte, sortLines_eq_of_perm (added_perm_of_perm_append h)]

theorem addedSorted?_union {mb main a m head head' : List String}
    (hhead : head.Perm (mb ++ a)) (hmain : main.Perm (mb ++ m))
    (hunion : head'.Perm (mb ++ a ++ m)) :
    addedSorted? main head' = addedSorted? mb head := by
  rw [addedSorted?_of_perm_append hhead]
  apply addedSorted?_of_perm_append
  have hswap : (mb ++ a ++ m).Perm (mb ++ m ++ a) := by
    rw [List.append_assoc, List.append_assoc]
    exact List.Perm.append_left mb List.perm_append_comm
  exact hunion.trans (hswap.trans (hmain.append_right a).symm)

example : added ["A", "B"] ["A", "B", "D", "C"] = ["D", "C"] := by decide
example : added ["A", "B", "M"] ["A", "B", "C", "M", "D"] = ["C", "D"] := by decide
example : added ["A", "A"] ["A", "B", "A", "A"] = ["B", "A"] := by decide
example : addedSorted? ["A", "B"] ["A", "B'", "C"] = none := by decide
example : addedSorted? ["A", "B"] ["A", "C"] = none := by decide
example : addedSorted? ["A", "A"] ["A", "B"] = none := by decide

end MitosGate.RunLog

namespace MitosGate.ContentId

open RunLog (quote addedSorted? firstMissing? splitLines)

def isRunLog (p : String) : Bool :=
  let cs := p.toList
  "ops/runs/".toList.isPrefixOf cs && ".ndjson".toList.isSuffixOf cs && !(cs.drop 9).contains '/'

example : isRunLog "ops/runs/2026-11-09.ndjson" = true := by decide
example : isRunLog "ops/runs/.ndjson" = true := by decide
example : isRunLog "ops/runs/.x.ndjson" = true := by decide
example : isRunLog "ops/runs/sub/x.ndjson" = false := by decide
example : isRunLog "ops/runs/README.md" = false := by decide
example : isRunLog "ops/runs.ndjson" = false := by decide
example : isRunLog "x/ops/runs/a.ndjson" = false := by decide

def modeHeaders : List String := ["old mode ", "new mode ", "deleted file mode ", "new file mode "]

inductive LineKind where
  | body
  | diffGit
  | mode
  | index
  | hunkHeader
  | unknown
  deriving DecidableEq, Repr

def kind (l : String) : LineKind :=
  match l.toList with
  | ' ' :: _ | '+' :: _ | '-' :: _ | '\\' :: _ => .body
  | cs =>
    if "diff --git ".toList.isPrefixOf cs then .diffGit
    else if "index ".toList.isPrefixOf cs then .index
    else if "@@ ".toList.isPrefixOf cs then .hunkHeader
    else if modeHeaders.any (·.toList.isPrefixOf cs) then .mode
    else .unknown

theorem kind_body {l : String} {c : Char} {t : List Char} (h : l.toList = c :: t)
    (hc : c = ' ' ∨ c = '+' ∨ c = '-' ∨ c = '\\') : kind l = .body := by
  unfold kind
  rw [h]
  rcases hc with rfl | rfl | rfl | rfl <;> rfl

def occ (base o : List String) : Nat → Nat
  | 0 => 0
  | p + 1 => occ base o p + if o.isPrefixOf (base.drop p) then 1 else 0

theorem occ_mono (base o : List String) {m n : Nat} (h : m ≤ n) : occ base o m ≤ occ base o n := by
  induction n with
  | zero => rw [Nat.le_zero.mp h]; exact Nat.le_refl _
  | succ n ih =>
    rcases Nat.lt_or_eq_of_le h with h | h
    · exact Nat.le_trans (ih (Nat.le_of_lt_succ h)) (by simp only [occ]; omega)
    · rw [h]; exact Nat.le_refl _

theorem occ_inj {base o : List String} {p p' : Nat} (hp : o.isPrefixOf (base.drop p) = true)
    (hp' : o.isPrefixOf (base.drop p') = true) (h : occ base o p = occ base o p') : p = p' := by
  rcases Nat.lt_trichotomy p p' with hlt | heq | hgt
  · have := occ_mono base o (Nat.succ_le_of_lt hlt)
    simp only [occ, hp, ↓reduceIte] at this
    omega
  · exact heq
  · have := occ_mono base o (Nat.succ_le_of_lt hgt)
    simp only [occ, hp', ↓reduceIte] at this
    omega

theorem occ_append_left (x base o : List String) (p : Nat) :
    occ (x ++ base) o (x.length + p) = occ (x ++ base) o x.length + occ base o p := by
  induction p with
  | zero => rfl
  | succ p ih =>
    rw [← Nat.add_assoc, occ, ih, occ, List.drop_append, List.drop_eq_nil_of_le (by omega),
      List.nil_append, Nat.add_sub_cancel_left]
    omega

theorem isPrefixOf_append {o l y : List String} (h : o.length ≤ l.length) :
    o.isPrefixOf (l ++ y) = o.isPrefixOf l := by
  induction o generalizing l with
  | nil => simp [List.isPrefixOf]
  | cons a o ih =>
    cases l with
    | nil => simp at h
    | cons b l =>
      simp only [List.cons_append, List.isPrefixOf]
      rw [ih (by simp at h; omega)]

theorem occ_append_right (base y o : List String) {p : Nat} (h : p + o.length ≤ base.length) :
    occ (base ++ y) o p = occ base o p := by
  induction p with
  | zero => rfl
  | succ p ih =>
    rw [occ, occ, ih (by omega), List.drop_append_of_le_length (by omega),
      isPrefixOf_append (by simp; omega)]

theorem occ_succ' (o : List String) : ∀ (l : List String) (n : Nat),
    occ l o (n + 1) = (if o.isPrefixOf l then 1 else 0) + occ l.tail o n
  | l, 0 => by simp [occ]
  | l, n + 1 => by
    rw [occ, occ_succ' o l n, occ, List.drop_tail]
    omega

def occTR (base o : List String) (p : Nat) : Nat := go base p 0
where
  go : List String → Nat → Nat → Nat
    | _, 0, acc => acc
    | l, n + 1, acc => go l.tail n (if o.isPrefixOf l then acc + 1 else acc)

theorem occTR_go (o : List String) : ∀ (l : List String) (n acc : Nat),
    occTR.go o l n acc = acc + occ l o n
  | l, 0, acc => by simp [occTR.go, occ]
  | l, n + 1, acc => by
    rw [occTR.go, occTR_go o l.tail n, occ_succ']
    split <;> omega

@[csimp] theorem occ_eq_occTR : @occ = @occTR := by
  funext base o p
  simp [occTR, occTR_go]

def digits (cs : List Char) : Option (Nat × List Char) :=
  match cs.takeWhile Char.isDigit with
  | [] => none
  | ds => some (ds.foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0, cs.dropWhile Char.isDigit)

def hunkOld (h : String) : Option (Nat × Nat) :=
  match h.toList with
  | '@' :: '@' :: ' ' :: '-' :: cs =>
    match digits cs with
    | some (a, ',' :: cs) =>
      match digits cs with
      | some (b, ' ' :: '+' :: _) => some (a, b)
      | _ => none
    | some (a, ' ' :: '+' :: _) => some (a, 1)
    | _ => none
  | _ => none

example : hunkOld "@@ -3,2 +3,2 @@ theorem t" = some (3, 2) := by decide
example : hunkOld "@@ -1 +1 @@" = some (1, 1) := by decide
example : hunkOld "@@ -0,0 +1,5 @@" = some (0, 0) := by decide
example : hunkOld "@@ -120,7 +121,8 @@" = some (120, 7) := by decide
example : hunkOld "@@ -1,2 @@" = none := by decide
example : hunkOld "@@@ -1,2 -1,2 +1,3 @@@" = none := by decide

/-- Where the hunk's old side starts in the file, counting lines from 0. Git writes the line
before an empty old side, and the first line of any other. -/
def hunkStart (a b : Nat) : Nat := if b = 0 then a else a - 1

def oldSide (body : List String) : List String :=
  body.filterMap fun l =>
    match l.toList with
    | ' ' :: cs | '-' :: cs => some (String.ofList cs)
    | _ => none

def marker (k : Nat) : String := "@@ " ++ toString k

theorem marker_inj {k k' : Nat} (h : marker k = marker k') : k = k' := by
  have := congrArg String.toList h
  simp only [marker, String.toList_append, List.append_cancel_left_eq] at this
  exact Nat.repr_injective (String.toList_inj.mp this)

theorem kind_marker (k : Nat) : kind (marker k) = .hunkHeader := by
  simp [kind, marker, String.toList_append, List.isPrefixOf]

def hunkMarker (base : List String) (h : String) (body : List String) : Option String :=
  match hunkOld h with
  | some (a, b) =>
    let o := oldSide body
    if o.length = b ∧ o.isPrefixOf (base.drop (hunkStart a b)) = true then
      some (marker (occ base o (hunkStart a b)))
    else none
  | none => none

def normalize (base : List String) : List String → Option (List String)
  | [] => some []
  | l :: ls =>
    match kind l with
    | .index => normalize base ls
    | .hunkHeader =>
      match hunkMarker base l (ls.takeWhile (kind · == .body)), normalize base ls with
      | some m, some r => some (m :: r)
      | _, _ => none
    | _ => (normalize base ls).map (l :: ·)

def normalizeTR (base ls : List String) : Option (List String) := go ls #[]
where
  go : List String → Array String → Option (List String)
    | [], acc => some acc.toList
    | l :: ls, acc =>
      match kind l with
      | .index => go ls acc
      | .hunkHeader =>
        match hunkMarker base l (ls.takeWhile (kind · == .body)) with
        | some m => go ls (acc.push m)
        | none => none
      | _ => go ls (acc.push l)

theorem normalizeTR_go (base : List String) : ∀ (ls : List String) (acc : Array String),
    normalizeTR.go base ls acc = (normalize base ls).map (acc.toList ++ ·)
  | [], acc => by simp [normalizeTR.go, normalize]
  | l :: ls, acc => by
    have ih := normalizeTR_go base ls
    cases hk : kind l <;> simp only [normalizeTR.go, normalize, hk, ih]
    case hunkHeader =>
      cases hunkMarker base l (List.takeWhile (fun x => kind x == LineKind.body) ls) <;>
        cases normalize base ls <;> simp
    all_goals (cases normalize base ls <;> simp)

@[csimp] theorem normalize_eq_normalizeTR : @normalize = @normalizeTR := by
  funext base ls
  simp [normalizeTR, normalizeTR_go]

theorem normalize_body {base : List String} :
    ∀ {ls out : List String}, normalize base ls = some out →
      out.filter (kind · == .body) = ls.filter (kind · == .body)
  | [], out, hn => by simp [normalize] at hn; subst hn; rfl
  | l :: ls, out, hn => by
    simp only [normalize] at hn
    split at hn
    · rename_i hk
      rw [normalize_body hn]
      simp [hk]
    · rename_i hk
      split at hn
      · rename_i m r hm hr
        simp only [Option.some.injEq] at hn
        subst hn
        have : kind m = .hunkHeader := by
          simp only [hunkMarker] at hm
          split at hm
          · split at hm
            · simp only [Option.some.injEq] at hm; subst hm; exact kind_marker _
            · simp at hm
          · simp at hm
        simp [this, hk, normalize_body hr]
      · simp at hn
    · cases hr : normalize base ls with
      | none => simp [hr] at hn
      | some r =>
        simp only [hr, Option.map_some, Option.some.injEq] at hn
        subst hn
        simp [List.filter_cons, normalize_body hr]

theorem normalize_ne {base base' p s x y out out' : List String}
    (hx : ∀ l ∈ x, kind l = .body) (hy : ∀ l ∈ y, kind l = .body) (hne : x ≠ y)
    (hn : normalize base (p ++ x ++ s) = some out) (hn' : normalize base' (p ++ y ++ s) = some out') :
    out ≠ out' := by
  intro heq
  have h1 := normalize_body hn
  have h2 := normalize_body hn'
  have ex : x.filter (kind · == .body) = x := List.filter_eq_self.mpr (by simpa using hx)
  have ey : y.filter (kind · == .body) = y := List.filter_eq_self.mpr (by simpa using hy)
  rw [heq, h2] at h1
  simp only [List.filter_append, ex, ey, List.append_assoc] at h1
  exact hne (List.append_cancel_right (List.append_cancel_left h1)).symm

theorem normalize_index {base s : List String} {i : String} (hi : kind i = .index) :
    ∀ {p : List String}, (∀ l ∈ p, kind l ≠ .hunkHeader) →
      normalize base (p ++ i :: s) = normalize base (p ++ s)
  | [], _ => by simp [normalize, hi]
  | l :: p, hp => by
    have hl := hp l (by simp)
    have ih := normalize_index (s := s) (base := base) hi (p := p) (fun l h => hp l (by simp [h]))
    simp only [List.cons_append, normalize]
    split
    · exact ih
    · contradiction
    · rw [ih]

theorem takeWhile_append_stop {f : String → Bool} {a : String} (ha : f a = false) (s : List String) :
    ∀ l : List String, (l ++ a :: s).takeWhile f = l.takeWhile f
  | [] => by simp [ha]
  | b :: l => by
    simp only [List.cons_append, List.takeWhile_cons]
    rw [takeWhile_append_stop ha s l]

theorem normalize_hunk {base s out : List String} {h : String} (hh : kind h = .hunkHeader) :
    normalize base (h :: s) = some out ↔ ∃ m r,
      hunkMarker base h (s.takeWhile (kind · == .body)) = some m ∧
      normalize base s = some r ∧ out = m :: r := by
  simp only [normalize, hh]
  split
  · rename_i m r hm hr
    constructor
    · intro h
      exact ⟨m, r, hm, hr, (Option.some.inj h).symm⟩
    · rintro ⟨m', r', hm', hr', rfl⟩
      rw [hm] at hm'
      rw [hr] at hr'
      cases hm'
      cases hr'
      rfl
  · rename_i hno
    constructor
    · intro h
      cases h
    · rintro ⟨m', r', hm', hr', rfl⟩
      exact absurd hr' (hno m' r' hm')

theorem normalize_split {base s : List String} {h : String} (hh : kind h ≠ .body) :
    ∀ {p out : List String}, normalize base (p ++ h :: s) = some out →
      ∃ a b, normalize base p = some a ∧ normalize base (h :: s) = some b ∧ out = a ++ b
  | [], out, hn => ⟨[], out, rfl, hn, rfl⟩
  | l :: p, out, hn => by
    have hstop : (kind h == LineKind.body) = false := by simp [hh]
    simp only [List.cons_append, normalize] at hn ⊢
    split at hn
    · obtain ⟨a, b, ha, hb, rfl⟩ := normalize_split hh hn
      exact ⟨a, b, ha, hb, rfl⟩
    · rw [takeWhile_append_stop hstop] at hn
      split at hn
      · rename_i m r hm hr
        obtain ⟨a, b, ha, hb, rfl⟩ := normalize_split hh hr
        simp only [Option.some.injEq] at hn
        subst hn
        refine ⟨m :: a, b, ?_, hb, rfl⟩
        simp [hm, ha]
      · simp at hn
    · cases hr : normalize base (p ++ h :: s) with
      | none => simp [hr] at hn
      | some r =>
        simp only [hr, Option.map_some, Option.some.injEq] at hn
        subst hn
        obtain ⟨a, b, ha, hb, rfl⟩ := normalize_split hh hr
        refine ⟨l :: a, b, ?_, hb, rfl⟩
        simp [ha]

theorem normalize_pos_ne {base p s out out' : List String} {h h' : String} {a b a' b' : Nat}
    (hh : kind h = .hunkHeader) (hh' : kind h' = .hunkHeader)
    (ha : hunkOld h = some (a, b)) (ha' : hunkOld h' = some (a', b'))
    (hne : hunkStart a b ≠ hunkStart a' b')
    (hn : normalize base (p ++ h :: s) = some out) (hn' : normalize base (p ++ h' :: s) = some out') :
    out ≠ out' := by
  obtain ⟨x, y, hx, hy, rfl⟩ := normalize_split (by simp [hh]) hn
  obtain ⟨x', y', hx', hy', rfl⟩ := normalize_split (by simp [hh']) hn'
  rw [hx] at hx'
  cases hx'
  obtain ⟨m, r, hm, hr, rfl⟩ := (normalize_hunk hh).mp hy
  obtain ⟨m', r', hm', hr', rfl⟩ := (normalize_hunk hh').mp hy'
  rw [hr] at hr'
  cases hr'
  intro heq
  have hmm : m = m' := (List.cons.inj (List.append_cancel_left heq)).1
  subst hmm
  simp only [hunkMarker, ha, ha'] at hm hm'
  split at hm
  · rename_i c1
    split at hm'
    · rename_i c2
      exact hne (occ_inj c1.2 c2.2 (marker_inj ((Option.some.inj hm).trans (Option.some.inj hm').symm)))
    · cases hm'
  · cases hm

example : normalize ["a", "  exact h", "b"] ["diff --git a/A.lean b/A.lean",
      "index 1111111..2222222 100644", "--- a/A.lean", "+++ b/A.lean", "@@ -1,3 +1,3 @@ theorem t",
      " a", "-  exact h", "+  exact h'", " b"] =
    normalize ["m1", "m2", "a", "  exact h", "b"] ["diff --git a/A.lean b/A.lean",
      "index 3333333..4444444 100644", "--- a/A.lean", "+++ b/A.lean", "@@ -3,3 +3,3 @@ theorem u",
      " a", "-  exact h", "+  exact h'", " b"] := by
  decide

example : normalize ["s", "a", "x", "b", "t", "a", "x", "b"] ["@@ -2,3 +2,3 @@", " a", "-x", "+y", " b"] =
    some ["@@ 0", " a", "-x", "+y", " b"] := by
  decide
example : normalize ["s", "a", "x", "b", "t", "a", "x", "b"] ["@@ -6,3 +6,3 @@", " a", "-x", "+y", " b"] =
    some ["@@ 1", " a", "-x", "+y", " b"] := by
  decide

example : normalize ["a", "x", "b"] ["@@ -2,3 +2,3 @@", " a", "-x", "+y", " b"] = none := by decide

example : normalize ["a", "  exact h"] ["@@ -1,2 +1,2 @@", " a", "-  exact h", "+  exact h'"] ≠
    normalize ["a", "  exact h"] ["@@ -1,2 +1,2 @@", " a", "-  exact h", "+ exact h'"] := by
  decide

example : normalize ["a"] ["@@ -1 +1,2 @@", " a", "+b"] ≠ normalize ["a "] ["@@ -1 +1,2 @@", " a ", "+b"] := by
  decide
example : normalize [] ["@@ -0,0 +1 @@", "+b"] ≠
    normalize [] ["@@ -0,0 +1 @@", "+b", "\\ No newline at end of file"] := by
  decide

example : [kind "\x1b[1mdiff --git a/x b/x", kind "GIT binary patch", kind "Binary files a/x and b/x differ",
    kind "rename from x", kind "similarity index 90%", kind ""] =
    [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown] := by
  decide

example : [kind "diff --git a/x b/x", kind "new file mode 100644", kind "old mode 100644",
    kind "index 0000000..1111111", kind "@@ -0,0 +1 @@", kind "--- /dev/null", kind "+++ b/x"] =
    [.diffGit, .mode, .mode, .index, .hunkHeader, .body, .body] := by
  decide

def octal (n : Nat) : List Char :=
  [Char.ofNat (48 + n / 64 % 8), Char.ofNat (48 + n / 8 % 8), Char.ofNat (48 + n % 8)]

def cEscape (c : Char) : Option (List Char) :=
  match c with
  | '\x07' => some ['\\', 'a']
  | '\x08' => some ['\\', 'b']
  | '\t' => some ['\\', 't']
  | '\n' => some ['\\', 'n']
  | '\x0b' => some ['\\', 'v']
  | '\x0c' => some ['\\', 'f']
  | '\r' => some ['\\', 'r']
  | '"' => some ['\\', '"']
  | '\\' => some ['\\', '\\']
  | c => if c.toNat < 0x20 || 0x7f ≤ c.toNat then some ('\\' :: octal c.toNat) else none

def cQuote (s : String) : String :=
  let cs := s.toList
  if cs.any fun c => (cEscape c).isSome then
    String.ofList ('"' :: cs.flatMap (fun c => (cEscape c).getD [c]) ++ ['"'])
  else s

def diffHeader (path : String) : String :=
  "diff --git " ++ cQuote ("a/" ++ path) ++ " " ++ cQuote ("b/" ++ path)

/-- What git 2.43 prints for `néw<TAB>t"q\.txt`, its UTF-8 bytes read one per `Char`. -/
example : diffHeader "n\xC3\xA9w\tt\"q\\.txt" =
    "diff --git \"a/n\\303\\251w\\tt\\\"q\\\\.txt\" \"b/n\\303\\251w\\tt\\\"q\\\\.txt\"" := by
  decide
example : diffHeader "sp ace.txt" = "diff --git a/sp ace.txt b/sp ace.txt" := by decide
example : diffHeader "d\x7f\x01" = "diff --git \"a/d\\177\\001\" \"b/d\\177\\001\"" := by decide

structure RunFile where
  path : String
  lines : List String
  noEol : Bool

def runsText (runs : List RunFile) : String :=
  String.join <| runs.map fun f =>
    s!"file {f.path.length}:{f.path}\n" ++ String.join (f.lines.map fun l => s!"+{l.length}:{l}\n") ++
      (if f.noEol then "noeol\n" else "")

def preimage (rest : String) (runs : List RunFile) : String :=
  "rest " ++ rest ++ "\nruns\n" ++ runsText runs

example : preimage "e3b0" [⟨"ops/runs/d.ndjson", ["{\"a\":1}", "x"], false⟩] =
    "rest e3b0\nruns\nfile 17:ops/runs/d.ndjson\n+7:{\"a\":1}\n+1:x\n" := by
  decide
example : preimage "e3b0" [⟨"ops/runs/d.ndjson", ["{\"b\":2}"], true⟩] =
    "rest e3b0\nruns\nfile 17:ops/runs/d.ndjson\n+7:{\"b\":2}\nnoeol\n" := by
  decide

def latin1 (b : ByteArray) : String :=
  b.foldl (fun s x => s.push (Char.ofNat x.toNat)) ""

def latin1Bytes (s : String) : ByteArray :=
  s.foldl (fun b c => b.push c.toNat.toUInt8) .empty

/-- Config that changes what `git diff` prints and has no command-line flag, or whose flag an
older git lacks. `-c` wins over every config file and over `GIT_CONFIG_COUNT`. -/
def gitConfig : List String :=
  ["core.quotePath=true", "core.attributesFile=/dev/null", "diff.noprefix=false",
    "diff.mnemonicPrefix=false", "diff.suppressBlankEmpty=false"]

/-- The environment of every git call. The variables that change a diff are removed. Replace refs
and grafts are off, so a clone's own `refs/replace/` or `info/grafts` cannot swap a commit, a tree
or a blob, or give a commit other parents. `LC_ALL=C` keeps git's messages in one language. -/
def gitEnv : Array (String × Option String) :=
  #[("GIT_DIFF_OPTS", none), ("GIT_EXTERNAL_DIFF", none), ("GIT_ATTR_SOURCE", none),
    ("GIT_NO_REPLACE_OBJECTS", some "1"), ("GIT_GRAFT_FILE", some "/dev/null"),
    ("LC_ALL", some "C")]

def diffArgs : Array String :=
  #["diff", "--patch", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", "--text",
    "--full-index", "--diff-algorithm=myers", "--indent-heuristic", "--unified=3",
    "--inter-hunk-context=0", "--src-prefix=a/", "--dst-prefix=b/", "--no-relative",
    "--ignore-submodules=none", "--submodule=short", "-O/dev/null"]

def rawArgs : Array String :=
  #["diff", "--raw", "-z", "--no-abbrev", "--no-color", "--no-ext-diff", "--no-textconv",
    "--no-renames", "--no-relative", "--ignore-submodules=none", "-O/dev/null"]

abbrev M := ExceptT String IO

def git (args : Array String) : M ByteArray := do
  (← IO.getStdout).flush
  let child ← IO.Process.spawn {
    cmd := "git", args := (gitConfig.foldl (fun a c => a ++ #["-c", c]) #["--no-pager"]) ++ args
    env := gitEnv, stdin := .null, stdout := .piped, stderr := .piped }
  let out ← IO.asTask child.stdout.readBinToEnd .dedicated
  let err ← child.stderr.readBinToEnd
  let code ← child.wait
  let out ← (IO.ofExcept out.get : IO ByteArray)
  if code != 0 then
    throw s!"git {args[0]!} exited with {code}: {trim (latin1 err)}"
  return out

def sha256Hex (b : ByteArray) : IO String := do
  let child ← do
    let (stdin, child) ← (← IO.Process.spawn {
      cmd := "sha256sum", args := #["-"], stdin := .piped, stdout := .piped, stderr := .piped }).takeStdin
    stdin.write b
    stdin.flush
    pure child
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← child.stderr.readToEnd
  let code ← child.wait
  let out ← IO.ofExcept out.get
  let hex := (out.splitOn " ").head!
  unless code == 0 && hex.length == 64 do
    throw <| IO.userError s!"sha256sum failed: {err}"
  return hex

def resolve (rev : String) : M String := do
  if rev.isEmpty || rev.startsWith "-" then throw s!"{quote rev} is not a revision"
  let r : Except String ByteArray ←
    (ExceptT.run (git #["rev-parse", "--verify", "--quiet", rev ++ "^{commit}"]) : IO _)
  match r with
  | .ok out => return trim (latin1 out)
  | .error _ => throw s!"{quote rev} is not a commit in this repository"

structure Entry where
  oldMode : String
  newMode : String
  oldOid : String
  newOid : String
  status : String
  path : String

def parseRaw : List String → Except String (List Entry)
  | [] | [""] => .ok []
  | info :: path :: rest =>
    match info.toList with
    | ':' :: cs =>
      match (String.ofList cs).splitOn " " with
      | [om, nm, oo, no, st] => return ⟨om, nm, oo, no, st, path⟩ :: (← parseRaw rest)
      | _ => .error s!"unexpected --raw entry {quote info}"
    | _ => .error s!"unexpected --raw entry {quote info}"
  | [x] => .error s!"unexpected end of --raw output after {quote x}"

def splitBlocks : List String → Except String (List (List String))
  | [] => .ok []
  | l :: ls =>
    if kind l == .diffGit then .ok (go [l] ls)
    else .error s!"the diff does not start with a diff --git line: {quote l}"
where
  go (cur : List String) : List String → List (List String)
    | [] => [cur.reverse]
    | l :: ls => if kind l == .diffGit then cur.reverse :: go [l] ls else go (l :: cur) ls

def blob (oid : String) : M String :=
  return latin1 (← git #["cat-file", "blob", oid])

def runLogLines (e : Entry) : M RunFile := do
  let regular := "a run-log file must be a regular file with mode 100644"
  let (base, head) ← match e.status with
    | "A" =>
      unless e.newMode == "100644" do throw s!"{quote e.path} is added with mode {e.newMode}; {regular}"
      pure ("", ← blob e.newOid)
    | "M" =>
      unless e.oldMode == "100644" && e.newMode == "100644" do
        throw s!"{quote e.path} changes mode from {e.oldMode} to {e.newMode}; {regular}"
      pure (← blob e.oldOid, ← blob e.newOid)
    | "D" => throw s!"{quote e.path} is deleted. Run-log files are append-only (ops/runs/README.md)"
    | st => throw s!"{quote e.path} changes in type (status {quote st}); {regular}"
  let (base, noEol) := (splitLines base, !head.isEmpty && !head.endsWith "\n")
  let head := splitLines head
  match addedSorted? base head with
  | some ls => return ⟨e.path, ls, noEol⟩
  | none =>
    -- `some`, by `firstMissing?_eq_none_iff` and `addedSorted?_eq_none_iff`.
    let i := (firstMissing? base head).getD 0
    throw (s!"line {i + 1} of the merge-base version of {quote e.path} is missing at the head. " ++
      "Run-log lines are append-only: a line already on the base branch may not be edited or " ++
      "deleted (ops/runs/README.md)")

/-- The lines of the file a block's hunks apply to: none when the block adds the file, the line
`--submodule=short` prints for a submodule, and the merge-base blob's lines otherwise. -/
def baseLines (e : Entry) (blk : List String) : M (List String) := do
  if blk.any (·.startsWith "new file mode ") then return []
  if e.oldMode == "160000" then return [s!"Subproject commit {e.oldOid}"]
  return splitLines (← blob e.oldOid)

structure Result where
  mergeBase : String
  rest : String
  restFiles : Nat
  runs : List RunFile
  id : String

def compute (base head : String) : M Result := do
  let b ← resolve base
  let h ← resolve head
  -- `git merge-base` exits 1 when there is none.
  let r : Except String ByteArray ← (ExceptT.run (git #["merge-base", "--all", b, h]) : IO _)
  let mb ← match r.map (splitLines ∘ latin1) with
    | .ok [mb] => pure mb
    | .ok [] => throw "the two commits have no merge-base"
    | .error e => throw s!"the two commits have no merge-base ({e})"
    | .ok _ => throw "the two commits have more than one merge-base"
  let entries ← ExceptT.mk (pure (parseRaw ((latin1 (← git (rawArgs ++ #[mb, h]))).splitOn "\x00")))
  let patch := splitLines (latin1 (← git (diffArgs ++ #[mb, h])))
  if let some i := patch.findIdx? (kind · == .unknown) then
    throw s!"line {i + 1} of the diff is not a line of a text diff: {quote patch[i]!}"
  let mut left ← ExceptT.mk (pure (splitBlocks patch))
  let mut rest : Array String := #[]
  let mut restFiles := 0
  let mut runs : Array RunFile := #[]
  for e in entries do
    -- A change of type (file, symlink, submodule) is two blocks: a deletion and an addition.
    let n := if e.status == "T" then 2 else 1
    let mine := left.take n
    left := left.drop n
    unless mine.length == n && mine.all (·.head? == some (diffHeader e.path)) do
      throw s!"the diff and the --raw listing disagree at {quote e.path}"
    if isRunLog e.path then
      runs := runs.push (← runLogLines e)
    else
      restFiles := restFiles + 1
      for blk in mine do
        let fileBase ← if blk.any (kind · == .hunkHeader) then baseLines e blk else pure []
        match normalize fileBase blk with
        | some ls => rest := rest ++ ls.toArray
        | none => throw s!"a hunk of {quote e.path} does not fit the merge-base version of the file"
  unless left.isEmpty do throw "the diff has a file block that the --raw listing does not have"
  let restHex ← sha256Hex (latin1Bytes (String.join (rest.toList.map (· ++ "\n"))))
  let id ← sha256Hex (latin1Bytes (preimage restHex runs.toList))
  return { mergeBase := mb, rest := restHex, restFiles, runs := runs.toList, id }

/-- A line for a CI log: `oneLine`, and the legacy workflow-command marker `##[`, which GitHub's
runner reads anywhere in a line, written with `oneLine`'s escape for its `[` (#68). Every line
`cli` prints starts with a fixed word, so none starts with `::`. -/
def logLine (s : String) : String :=
  (oneLine s).replace "##[" "##\\u{005B}"

def cli (args : List String) (usage : String) : IO UInt32 := do
  let verbose := args.contains "--verbose"
  match args.filter (· != "--verbose") with
  | [base, head] =>
    try
      match ← (compute base head).run with
      | .ok r =>
        if verbose then
          IO.eprintln s!"merge-base {r.mergeBase}"
          IO.eprintln s!"rest {r.rest} ({r.restFiles} file(s) outside the run logs)"
          for f in r.runs do
            let eol := if f.noEol then ", no newline at end of file" else ""
            IO.eprintln (logLine s!"runs {quote f.path (max := 200)}: {f.lines.length} added line(s){eol}")
        IO.println r.id
        return 0
      | .error e =>
        IO.eprintln (logLine s!"content-id refused: {e}")
        return 1
    catch e =>
      IO.eprintln (logLine s!"content-id stopped on an I/O error: {e}")
      return 1
  | _ =>
    IO.eprintln "content-id needs <base> <head>"
    IO.eprintln usage
    return 2

end MitosGate.ContentId
