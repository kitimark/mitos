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

def sameNames (a b : List String) : Bool :=
  nodupList a && nodupList b && sortStrings a == sortStrings b

def firstDup (xs : List String) : Option String :=
  xs.find? fun n => xs.count n > 1

end MitosGate.DecideList
