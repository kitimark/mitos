import MitosGate.Base.Text
import MitosGate.IndexMod

namespace MitosGate.CheatsShard

open MitosGate.Base.Text
open MitosGate.IndexMod

def modeFull : String := "full"
def modeComparator : String := "comparator"
def failNeedle : String := "<-- FAIL"
def failMark : String := "  " ++ failNeedle

def allBehave (n : Nat) : String := s!"cheat corpus: all {n} cases behave as expected"

structure Shard where
  modulus : Nat
  residue : Nat
  modulus_pos : 0 < modulus
  residue_lt : residue < modulus

def Shard.mk? (n k : Nat) : Option Shard :=
  if hn : 0 < n then
    if hk : k < n then some ⟨n, k, hn, hk⟩ else none
  else
    none

def Shard.parse (s : String) : Option Shard :=
  match splitStr '/' s with
  | [a, b] =>
    match parseNatStr a, parseNatStr b with
    | some k, some n => Shard.mk? n k
    | _, _ => none
  | _ => none

inductive RunRefusal
  | noCases
  | emptyShard (k : Nat)
  deriving DecidableEq, Repr

def RunRefusal.text : RunRefusal → String
  | .noCases => "no cheat cases in the case directory"
  | .emptyShard k =>
    s!"shard {k} would be empty, and mitos-gate cheats with no names runs the whole corpus"

/-- `List.range n` allocates `n` cells, so a modulus of `10^10` would hang before refusing. -/
def firstEmpty (names : List String) (n : Nat) : Option Nat :=
  if names.length < n then some names.length else none

def selection (names : List String) (s : Shard) : Except RunRefusal (List String) :=
  if names.isEmpty then .error .noCases
  else
    match firstEmpty names s.modulus with
    | some k => .error (.emptyShard k)
    | none => .ok (byMod names s.modulus s.residue)

def renderCaseList (names : List String) : String :=
  if names.isEmpty then "" else String.intercalate "\n" names ++ "\n"

def parseCaseList (txt : String) : List String :=
  let ls := linesOf txt
  match ls.getLast? with
  | some "" => ls.dropLast
  | _ => ls

theorem firstEmpty_none_iff {names : List String} {n : Nat} (hn : 0 < n) :
    firstEmpty names n = none ↔ ∀ k, k < n → byMod names n k ≠ [] := by
  constructor
  · intro h
    cases Nat.lt_or_ge names.length n with
    | inl hlt =>
      simp [firstEmpty, hlt] at h
    | inr hge =>
      exact byMod_nonempty_of_length names n hn hge
  · intro hall
    cases Nat.lt_or_ge names.length n with
    | inl hlt =>
      rcases exists_empty_byMod_of_short hlt with ⟨k, hk, hempty⟩
      exact absurd hempty (hall k hk)
    | inr hge =>
      have hnot : ¬ names.length < n := Nat.not_lt_of_le hge
      simp [firstEmpty, hnot]

theorem selection_error_empty {s : Shard} :
    selection [] s = .error .noCases := by
  simp [selection]

theorem selection_ok_of_count {names : List String} {s : Shard} (hne : names ≠ [])
    (hempty : ∀ k, k < s.modulus → byMod names s.modulus k ≠ []) :
    selection names s = .ok (byMod names s.modulus s.residue) := by
  have hfind : firstEmpty names s.modulus = none :=
    (firstEmpty_none_iff s.modulus_pos).2 hempty
  simp [selection, hne, List.isEmpty_iff, hfind]

namespace Fixture

def modAndRes : Option Shard → Option (Nat × Nat)
  | some s => some (s.modulus, s.residue)
  | none => none

theorem parseShardAcceptsMatrix :
    modAndRes (Shard.parse "0/3") = some (3, 0) ∧
      modAndRes (Shard.parse "1/3") = some (3, 1) ∧
      modAndRes (Shard.parse "2/3") = some (3, 2) ∧
      Shard.parse "3/3" = none ∧ Shard.parse "0/0" = none ∧
      Shard.parse "k/3" = none ∧ Shard.parse "0/3/1" = none := by
  decide

def three : List String := ["one", "three", "two"]

theorem roundtripThree :
    parseCaseList (renderCaseList three) = three := by
  decide

theorem shortDirectoryFindsEmptyResidue :
    firstEmpty ["one", "two"] 3 = some 2 := by
  decide

end Fixture

end MitosGate.CheatsShard
