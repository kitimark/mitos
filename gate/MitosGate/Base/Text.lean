/-!
Structural text operations reduce under kernel `decide`, unlike the corresponding String helpers.
Base contains pure functions and proofs only, with no IO or process calls.
Speech's CR-aware lines and core's byte-offset line specification have different contracts.
-/

namespace MitosGate.Base.Text

def split (sep : Char) (cs : List Char) : List (List Char) := go cs []
where
  go : List Char → List Char → List (List Char)
    | [], acc => [acc.reverse]
    | c :: cs, acc => if c = sep then acc.reverse :: go cs [] else go cs (c :: acc)

private theorem split_go_ne_nil (sep : Char) (cs acc : List Char) :
    split.go sep cs acc ≠ [] := by
  induction cs generalizing acc with
  | nil => simp [split.go]
  | cons c cs ih =>
    simp only [split.go]
    split
    · simp
    · exact ih _

def join (sep : Char) : List (List Char) → List Char
  | [] => []
  | p :: ps =>
    match ps with
    | [] => p
    | _ :: _ => p ++ sep :: join sep ps

private theorem join_cons_cons (sep : Char) (p q : List Char) (ps : List (List Char)) :
    join sep (p :: q :: ps) = p ++ sep :: join sep (q :: ps) := rfl

private theorem join_go (sep : Char) (cs acc : List Char) :
    join sep (split.go sep cs acc) = acc.reverse ++ cs := by
  induction cs generalizing acc with
  | nil => simp [split.go, join]
  | cons c cs ih =>
    simp only [split.go]
    split
    · rename_i hc
      subst c
      obtain ⟨p, ps, hp⟩ : ∃ p ps, split.go sep cs [] = p :: ps := by
        cases h : split.go sep cs [] with
        | nil => exact absurd h (split_go_ne_nil sep cs [])
        | cons p ps => exact ⟨p, ps, rfl⟩
      have h := ih []
      rw [hp] at h ⊢
      rw [join_cons_cons, h]
      simp
    · rw [ih]
      simp

theorem join_split (sep : Char) (cs : List Char) : join sep (split sep cs) = cs := by
  simpa [split] using join_go sep cs []

private theorem sep_not_mem_go (sep : Char) (cs acc : List Char) (h : sep ∉ acc) :
    ∀ p ∈ split.go sep cs acc, sep ∉ p := by
  induction cs generalizing acc with
  | nil => simpa [split.go] using h
  | cons c cs ih =>
    simp only [split.go]
    split
    · intro p hp
      simp only [List.mem_cons] at hp
      rcases hp with rfl | hp
      · simpa using h
      · exact ih [] (by simp) p hp
    · rename_i hc
      exact ih (c :: acc) (by simp [h, Ne.symm hc])

theorem sep_not_mem_split (sep : Char) (cs : List Char) :
    ∀ p ∈ split sep cs, sep ∉ p :=
  sep_not_mem_go sep cs [] (by simp)

def lines (cs : List Char) : List (List Char) := split '\n' cs

def splitStr (sep : Char) (s : String) : List String :=
  (split sep s.toList).map String.ofList

example : splitStr ',' ",a,," = ["", "a", "", ""] := by decide +kernel
example : splitStr ',' "" = [""] := by decide +kernel

def linesOf (s : String) : List String := splitStr '\n' s

example : linesOf "a\r\nb\n" = ["a\r", "b", ""] := by decide +kernel
example : linesOf "é\n" = ["é", ""] := by decide +kernel

private def isDigit (c : Char) : Bool :=
  '0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

private def parseDigits (acc : Nat) : List Char → Option Nat
  | [] => some acc
  | c :: cs =>
    if isDigit c then parseDigits (acc * 10 + (c.toNat - '0'.toNat)) cs else none

private theorem parseDigits_eq (cs : List Char) (acc : Nat)
    (h : ∀ c ∈ cs, c.isDigit = true) :
    parseDigits acc cs = some (Nat.ofDigitChars 10 cs acc) := by
  induction cs generalizing acc with
  | nil => simp [parseDigits, Nat.ofDigitChars_nil]
  | cons c cs ih =>
    have hc : isDigit c = true := by
      simpa only [isDigit, Bool.and_eq_true, decide_eq_true_eq] using
        Char.isDigit_iff_toNat.mp (h c (by simp))
    simp only [parseDigits, hc, ↓reduceIte]
    rw [ih _ (fun d hd => h d (by simp [hd])), Nat.ofDigitChars_cons]
    simp [Nat.mul_comm]

def parseNat : List Char → Option Nat
  | [] => none
  | cs => parseDigits 0 cs

theorem parseNat_repr (n : Nat) : parseNat (Nat.repr n).toList = some n := by
  rw [Nat.toList_repr]
  have hne : Nat.toDigits 10 n ≠ [] := Nat.toDigits_ne_nil
  have hp : parseNat (Nat.toDigits 10 n) = parseDigits 0 (Nat.toDigits 10 n) := by
    cases h : Nat.toDigits 10 n with
    | nil => exact absurd h hne
    | cons c cs => rfl
  rw [hp, parseDigits_eq _ _ (fun c hc =>
    Nat.isDigit_of_mem_toDigits (by decide) (by decide) hc), Nat.ofDigitChars_ten_toDigits]

def parseNatStr (s : String) : Option Nat := parseNat s.toList

example : parseNatStr "" = none := by decide +kernel
example : parseNatStr "00" = some 0 := by decide +kernel
example : parseNatStr "42" = some 42 := by decide +kernel
example : parseNatStr "-1" = none := by decide +kernel
example : parseNatStr "+1" = none := by decide +kernel
example : parseNatStr " 1" = none := by decide +kernel
example : parseNatStr "1 " = none := by decide +kernel
example : parseNatStr "1\n" = none := by decide +kernel
example : parseNatStr "١" = none := by decide +kernel

def isPrefix : List Char → List Char → Bool
  | [], _ => true
  | _, [] => false
  | a :: as, b :: bs => a == b && isPrefix as bs

theorem isPrefix_iff (p s : List Char) : isPrefix p s = true ↔ p <+: s := by
  induction p generalizing s with
  | nil => simp [isPrefix]
  | cons a as ih =>
    cases s with
    | nil => simp [isPrefix]
    | cons b bs => simp [isPrefix, ih, List.cons_prefix_cons]

def hasSub : List Char → List Char → Bool
  | [], _ => true
  | _, [] => false
  | pat, b :: bs => isPrefix pat (b :: bs) || hasSub pat bs

theorem hasSub_iff (p s : List Char) : hasSub p s = true ↔ p <:+: s := by
  induction s generalizing p with
  | nil => cases p <;> simp [hasSub]
  | cons b bs ih =>
    cases p with
    | nil => simp [hasSub]
    | cons a as => simp [hasSub, isPrefix_iff, ih, List.infix_cons_iff]

example : isPrefix [] ['a'] = true := by decide +kernel
example : isPrefix ['a'] [] = false := by decide +kernel
example : hasSub [] [] = true := by decide +kernel
example : hasSub "ab".toList "zab".toList = true := by decide +kernel
example : hasSub "ab".toList "acb".toList = false := by decide +kernel

def dropChar (c : Char) : List Char → List Char
  | [] => []
  | x :: xs => if x == c then dropChar c xs else x :: dropChar c xs

example : dropChar '\r' "\ra\rb\r".toList = "ab".toList := by decide +kernel

def dropTrailNL (s : String) : String :=
  String.ofList (s.toList.reverse.dropWhile (· == '\n') |>.reverse)

example : dropTrailNL "a\r\n\n" = "a\r" := by decide +kernel

def firstToken (line : String) : String :=
  let cs := line.toList.dropWhile fun c => c == ' ' || c == '\t'
  String.ofList (cs.takeWhile fun c => c != ' ' && c != '\t')

example : firstToken " \ta\tb" = "a" := by decide +kernel
example : firstToken "a\nb" = "a\nb" := by decide +kernel
example : firstToken "\r a" = "\r" := by decide +kernel

end MitosGate.Base.Text
