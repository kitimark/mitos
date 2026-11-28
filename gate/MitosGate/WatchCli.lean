import MitosGate.Watch

/-! Usage:

  mitos-gate watch unanswered --owner <login> [--issue-comments <file>]
      [--review-comments <file>] [--reviews <file>]

Each file is one route's answer, read with `gh api --paginate --slurp`. It prints one line,
`{"<thread>":[ids]}`: the owner's words that no later answer follows, threads and ids ascending.
Exit 1: a file, an answer or one of the owner's items is refused, with nothing on standard output.
Exit 2: usage. -/

namespace MitosGate.WatchCli

open Watch

structure UnansweredArgs where
  owner : Option String := none
  issueComments : Option String := none
  reviewComments : Option String := none
  reviews : Option String := none

def parseUnanswered : List String → UnansweredArgs → Option UnansweredArgs
  | [], a => some a
  | "--owner" :: v :: rest, a =>
    if a.owner.isSome then none else parseUnanswered rest { a with owner := v }
  | "--issue-comments" :: v :: rest, a =>
    if a.issueComments.isSome then none else parseUnanswered rest { a with issueComments := v }
  | "--review-comments" :: v :: rest, a =>
    if a.reviewComments.isSome then none else parseUnanswered rest { a with reviewComments := v }
  | "--reviews" :: v :: rest, a =>
    if a.reviews.isSome then none else parseUnanswered rest { a with reviews := v }
  | _, _ => none

def placeName : Place → String
  | .issueComment => "issue comment"
  | .reviewComment => "review comment"
  | .review => "review"

def kindName : ItemKind → String
  | .post place => placeName place
  | .close => "close"

def unansweredJson (threads : List (Land.Pr × List Nat)) : String :=
  let entry (t : Land.Pr × List Nat) :=
    s!"\"{t.1}\":[{",".intercalate ((t.2.toArray.qsort (· < ·)).toList.map toString)}]"
  "{" ++ ",".intercalate ((threads.toArray.qsort (·.1 < ·.1)).toList.map entry) ++ "}"

def unanswered (owner : String) (a : UnansweredArgs) : IO UInt32 := do
  let mut posts : List Said := []
  let mut refused := false
  for (flag, file, reader) in [("--issue-comments", a.issueComments, issueComments owner),
      ("--review-comments", a.reviewComments, reviewComments owner),
      ("--reviews", a.reviews, reviews owner)] do
    let some file := file | continue
    match (← readJsonFile file) >>= reader with
    | .error e =>
      IO.eprintln (ciLine s!"watch unanswered: {flag} is refused: {e}")
      refused := true
    | .ok r =>
      for x in r.refused do
        IO.eprintln (ciLine
          s!"watch unanswered: {flag}: {kindName x.kind} {x.id} is refused: {x.why.text}")
        refused := true
      posts := posts ++ r.items
  if refused then return 1
  IO.println (unansweredJson (Watch.unanswered owner answerApps posts))
  return 0

def cli (args : List String) (usage : String) : IO UInt32 := do
  match args with
  | "unanswered" :: rest =>
    match parseUnanswered rest {} with
    | some a =>
      match a.owner with
      | some owner =>
        if owner.isEmpty then
          IO.eprintln "watch unanswered: --owner is empty"
          IO.eprintln usage
          return 2
        try unanswered owner a
        catch e =>
          IO.eprintln (ciLine s!"watch unanswered: stopped on an I/O error: {e}")
          return 1
      | none =>
        IO.eprintln "watch unanswered needs --owner <login>"
        IO.eprintln usage
        return 2
    | none =>
      IO.eprintln "watch unanswered: a flag is unknown, repeated or has no value"
      IO.eprintln usage
      return 2
  | verb :: _ =>
    if ["wait", "own", "status"].contains verb then
      IO.eprintln s!"watch {verb} is not built yet"
    else IO.eprintln usage
    return 2
  | [] =>
    IO.eprintln usage
    return 2

end MitosGate.WatchCli
