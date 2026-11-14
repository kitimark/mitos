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

def prNumber (c : List Char) : Option Nat :=
  match Speech.trim c with
  | '#' :: r =>
    let ds := r.takeWhile digit
    if ds.isEmpty || (r.dropWhile digit).head?.any Char.isAlphanum then none else Speech.num ds 0
  | _ => none

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
