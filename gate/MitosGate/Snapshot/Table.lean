import MitosGate.Snapshot.Block

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

def cells : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    if c == '|' then [] :: cells cs
    else
      match cells cs with
      | [] => [[c]]
      | x :: xs => (c :: x) :: xs

def inFlight : List Char := "## In flight".toList

def saysInFlight (l : List Char) : Bool := Speech.trim l == inFlight

def outsideListItems (heading : List Char) : Bool := heading.head? == some '#'

def section? (ls : List (List Char)) : Option (List (List Char)) :=
  match ls.filter saysInFlight with
  | [line] =>
    let (above, rest) := ls.span (!saysInFlight ·)
    if !outsideListItems line || above.any (start · == .runsPastHeadings) then none
    else some ((rest.drop 1).takeWhile (start · != .heading))
  | _ => none

def linkOpen : List Char := "](https://github.com/".toList

def repoChar (c : Char) : Bool := c.isAlphanum || c == '-' || c == '_' || c == '.'

def after? (p l : List Char) : Option (List Char) :=
  if p.isPrefixOf l then some (l.drop p.length) else none

/-- Reads from just after `[#`. GitHub draws `[#7](https://github.com/owner/name/pull/7)` as `#7`,
so the cell reads as 7 only when the link is a pull request link that ends in the same digits. -/
def linkedNumber (r : List Char) : Option Nat :=
  match after? linkOpen (r.dropWhile digit) with
  | none => none
  | some u =>
    match after? ['/'] (u.dropWhile repoChar) with
    | none => none
    | some v =>
      match after? ("/pull/".toList ++ r.takeWhile digit ++ [')']) (v.dropWhile repoChar) with
      | none => none
      | some w =>
        if (r.takeWhile digit).isEmpty || (u.takeWhile repoChar).isEmpty ||
            (v.takeWhile repoChar).isEmpty || w.head?.any Char.isAlphanum then none
        else Speech.num (r.takeWhile digit) 0

def prNumber (c : List Char) : Option Nat :=
  match Speech.trim c with
  | '#' :: r =>
    let ds := r.takeWhile digit
    if ds.isEmpty || (r.dropWhile digit).head?.any Char.isAlphanum then none else Speech.num ds 0
  | '[' :: '#' :: r => linkedNumber r
  | _ => none

def LinkedCellIsItsPullLink : Prop :=
  ∀ r n, linkedNumber r = some n →
    ∃ ds owner name rest,
      r = ds ++ linkOpen ++ owner ++ ['/'] ++ name ++ "/pull/".toList ++ ds ++ [')'] ++ rest ∧
      ds ≠ [] ∧ Speech.num ds 0 = some n ∧ owner ≠ [] ∧ owner.all repoChar = true ∧
      name ≠ [] ∧ name.all repoChar = true ∧ rest.head?.any Char.isAlphanum = false

def OnlyALinkedCellIsNew : Prop :=
  ∀ c n, prNumber c = some n →
    (Speech.trim c).head? = some '#' ∨
      ∃ r, Speech.trim c = '[' :: '#' :: r ∧ linkedNumber r = some n

theorem after?_eq {p l r : List Char} (h : after? p l = some r) : l = p ++ r := by
  unfold after? at h
  split at h
  · next hp =>
    cases h
    exact (List.prefix_iff_eq_append.1 (List.isPrefixOf_iff_prefix.1 hp)).symm
  · cases h

theorem all_takeWhile (p : Char → Bool) : ∀ l : List Char, (l.takeWhile p).all p = true
  | [] => rfl
  | c :: cs => by
    by_cases h : p c <;> simp [h, all_takeWhile p cs]

theorem linkShape {r u v w td tu tv : List Char} (hr : r = td ++ (linkOpen ++ u))
    (hu : u = tu ++ (['/'] ++ v)) (hv : v = tv ++ ("/pull/".toList ++ td ++ [')'] ++ w)) :
    r = td ++ linkOpen ++ tu ++ ['/'] ++ tv ++ "/pull/".toList ++ td ++ [')'] ++ w := by
  subst hv hu hr
  simp [List.append_assoc]

theorem linkedCellIsItsPullLink : LinkedCellIsItsPullLink := by
  intro r n h
  unfold linkedNumber at h
  split at h
  · cases h
  · next u hu =>
    split at h
    · cases h
    · next v hv =>
      split at h
      · cases h
      · next w hw =>
        split at h
        · cases h
        · next hc =>
          simp only [Bool.or_eq_true, not_or, Bool.not_eq_true] at hc
          obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := hc
          refine ⟨r.takeWhile digit, u.takeWhile repoChar, v.takeWhile repoChar, w, ?_, ?_, h, ?_,
            all_takeWhile _ _, ?_, all_takeWhile _ _, h4⟩
          · refine linkShape (u := u) (v := v) ?_ ?_ ?_
            · rw [← after?_eq hu]; exact (List.takeWhile_append_dropWhile ..).symm
            · rw [← after?_eq hv]; exact (List.takeWhile_append_dropWhile ..).symm
            · rw [← after?_eq hw]; exact (List.takeWhile_append_dropWhile ..).symm
          · intro e; simp [e] at h1
          · intro e; simp [e] at h2
          · intro e; simp [e] at h3

theorem onlyALinkedCellIsNew : OnlyALinkedCellIsNew := by
  intro c n h
  unfold prNumber at h
  split at h
  · next r e => exact .inl (by rw [e]; rfl)
  · next r e => exact .inr ⟨r, e, h⟩
  · cases h

inductive Row
  | skip
  | data (n : Nat) (verdict : List Char)
  | bad
  deriving DecidableEq

def betweenOuterPipes (l : List Char) : Option (List (List Char)) :=
  match cells l with
  | [] :: rest =>
    match rest.reverse with
    | [] :: inner => some inner.reverse
    | _ => none
  | _ => none

def delimiterCell (c : List Char) : Bool :=
  let t := Speech.trim c
  let t := if t.head? == some ':' then t.drop 1 else t
  let t := if t.getLast? == some ':' then t.dropLast else t
  !t.isEmpty && t.all (· == '-')

def headerRow (l : List Char) : Bool :=
  match betweenOuterPipes (Speech.trim l) with
  | some [pr, _, _, _] => Speech.trim pr == "PR".toList
  | _ => false

def delimiterRow (l : List Char) : Bool :=
  match betweenOuterPipes (Speech.trim l) with
  | some cs => cs.length == 4 && cs.all delimiterCell
  | none => false

def row (l : List Char) : Row :=
  match Speech.trim l with
  | '|' :: _ =>
    match betweenOuterPipes (Speech.trim l) with
    | some [pr, _, _, v] =>
      match prNumber pr with
      | some n => .data n (Speech.trim v)
      | none => .bad
    | _ => .bad
  | t => if t.contains '|' then .bad else .skip

inductive Above
  | blankOrHeading
  | headerOfPair
  | nonBlank

def Above.of (l : List Char) : Above := if blank l then .blankOrHeading else .nonBlank

def rowsAfter : Above → List (List Char) → List Row
  | _, [] => []
  | .headerOfPair, l :: ls => .skip :: rowsAfter (.of l) ls
  | .blankOrHeading, l :: ls =>
    if headerRow l && ls.head?.any delimiterRow then .skip :: rowsAfter .headerOfPair ls
    else row l :: rowsAfter (.of l) ls
  | .nonBlank, l :: ls => row l :: rowsAfter (.of l) ls

def piped (l : List Char) : Bool := (Speech.trim l).head? == some '|'

/-- GitHub's Markdown reads a non-blank line under a table row as one more row, even with no pipe
in it, so only a row may follow a row. -/
def rowsUnderRows : List (List Char) → Bool
  | a :: b :: ls => (!piped a || blank b || piped b) && rowsUnderRows (b :: ls)
  | _ => true

def distinctNats : List Nat → Bool
  | [] => true
  | n :: ns => !ns.contains n && distinctNats ns

def textOrBlank (l : List Char) : Bool := start l == .text || start l == .blank

def rowsOf (ls : List (List Char)) : Option (List (Nat × List Char)) :=
  let rs := rowsAfter .blankOrHeading ls
  let ds := rs.filterMap fun
    | .data n v => some (n, v)
    | _ => none
  if !ls.all textOrBlank || rs.contains .bad || !rowsUnderRows ls || !distinctNats (ds.map (·.1))
  then none
  else some ds

def rows (body : String) : Option (List (Nat × List Char)) :=
  (section? (lines body.toList)).bind rowsOf

end MitosGate.Snapshot
