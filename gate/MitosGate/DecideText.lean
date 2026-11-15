namespace MitosGate.DecideText

private def isDigit (c : Char) : Bool :=
  '0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat

private def parseDigits (acc : Nat) : List Char → Option Nat
  | [] => some acc
  | c :: cs =>
    if isDigit c then parseDigits (acc * 10 + (c.toNat - '0'.toNat)) cs else none

/-- `String.toNat?` does not reduce under `decide`. -/
def parseNat (s : String) : Option Nat :=
  match s.toList with
  | [] => none
  | cs => parseDigits 0 cs

private def splitChar (sep : Char) : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    let rest := splitChar sep cs
    if c == sep then [] :: rest
    else
      match rest with
      | [] => [[c]]
      | y :: ys => (c :: y) :: ys

/-- `String.splitOn` does not reduce under `decide`. -/
def splitStr (sep : Char) (s : String) : List String :=
  (splitChar sep s.toList).map String.ofList

def linesOf (s : String) : List String :=
  splitStr '\n' s

end MitosGate.DecideText
