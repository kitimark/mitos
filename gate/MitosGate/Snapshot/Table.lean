import MitosGate.Speech

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

def heading (l : List Char) : Bool := "## ".toList.isPrefixOf (Speech.trim l)

def section? (ls : List (List Char)) : Option (List (List Char)) :=
  match ls.filter (fun l => Speech.trim l == inFlight) with
  | [_] => some (((ls.dropWhile (fun l => Speech.trim l != inFlight)).drop 1).takeWhile (!heading ·))
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

def separator (c : List Char) : Bool := c.all fun x => x == '-' || x == ':' || x == ' '

def row (l : List Char) : Row :=
  match Speech.trim l with
  | '|' :: _ =>
    match cells (Speech.trim l) with
    | [] :: rest =>
      match rest.reverse with
      | [] :: mid =>
        if mid.all separator then .skip
        else
          match mid.reverse with
          | [pr, _, _, v] =>
            if Speech.trim pr == "PR".toList then .skip
            else
              match prNumber pr with
              | some n => .data n (Speech.trim v)
              | none => .bad
          | _ => .bad
      | _ => .bad
    | _ => .bad
  | _ => .skip

def distinctNats : List Nat → Bool
  | [] => true
  | n :: ns => !ns.contains n && distinctNats ns

def rowsOf (ls : List (List Char)) : Option (List (Nat × List Char)) :=
  let rs := ls.map row
  let ds := rs.filterMap fun
    | .data n v => some (n, v)
    | _ => none
  if rs.contains .bad || !distinctNats (ds.map (·.1)) then none else some ds

def rows (body : String) : Option (List (Nat × List Char)) :=
  (section? (lines body.toList)).bind rowsOf

end MitosGate.Snapshot
