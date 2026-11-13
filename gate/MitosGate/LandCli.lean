import Lean.Data.Json
import MitosGate.Land
import MitosGate.Util

/-!
# `mitos-gate land`: one snapshot in, one decision out

`mitos-gate land [<snapshot.json>]` reads one snapshot, from the file or, with no argument or `-`,
from standard input, and prints the decision of `MitosGate.Land` as one line of JSON. A snapshot
that is not well formed is refused with one line on standard error and exit 1. A usage error is
exit 2. A decision that stops, waits or holds is still exit 0: it is the answer.

The snapshot is what a reader has already parsed from GitHub; this command parses no comment.

```
{ "prs": [ <pull request>, ... ],
  "me": { "provider": "claude", "name": "orchestrator" },   -- with "pr": the caller of `land`
  "pr": 153,
  "event": { "kind": "gateDone", "pr": 153, "gate": "success" } }   -- optional: who wakes
```

A pull request has the fields of `Land.Obs`: `pr`, `updatable`, `enforced`, `head`, `pushes` (each
`{byUpdater, before, after}`, newest first), `ids` (each `{sha, id}`), `paths` (absent: not read),
`base` (`{kind: current | conflict | mergedMain | unread}` or `{kind: clean, replay}`), `gate`,
`author` (`{who, model}`, absent: not known), `verdicts` (each `{said, head, judge, model,
result}`), `botAt` (absent: the bot has not reviewed), `delegates`, `words` (each `{kind:
ownerLand, said, about}`, `{kind: ownerHold, said}` or `{kind: agentLand, who, said, about}`, in
ascending comment id) and `rest`. An absent optional field says the safe thing: nothing is known,
so nothing is covered, reviewed or unkept.

The decision is `{"next": <pr or null>, "plan": ..., "step": ..., "wake": ...}`. `step` is there
when the snapshot names `me` and `pr`, and `wake` when it names an `event`.

What this module checks, and the decision does not: every object has only the keys it defines and
every value its type; a commit is 1 to 64 letters and digits (so no printed line holds text that a
runner could read as a command); pull request numbers are distinct; a pull request's words are in
ascending comment id, because the newest owner word is the last one listed; and no two words share
a comment id, which statement 13 (`nextIgnoresListingOrder`) needs.
-/

open Lean (Json)

namespace MitosGate.LandCli

open MitosGate.Land

/-! ## Decoding: the boundary

An error is a path and a message, written `.prs[0].words[1].said: expected a natural number`. A
leaf says `: message`; each object key and list index puts itself before it. -/

private abbrev D (α : Type) := Json → Except String α

private def obj (allowed : List String) (j : Json) : Except String Unit := do
  let o ← match j.getObj? with
    | .ok o => pure o
    | .error _ => throw ": expected an object"
  for k in o.keys do
    unless allowed.contains k do throw s!".{k.quote}: not a field here"

private def at' (k : String) (d : D α) (j : Json) : Except String α :=
  match j.getObjVal? k with
  | .error _ => .error s!".{k}: missing"
  | .ok v => (d v).mapError fun e => s!".{k}{e}"

private def opt (k : String) (d : D α) (j : Json) : Except String (Option α) :=
  match j.getObjVal? k with
  | .error _ => .ok none
  | .ok v => (d v |>.map some).mapError fun e => s!".{k}{e}"

private def nat : D Nat := fun j =>
  match j.getNat? with
  | .ok n => .ok n
  | .error _ => .error ": expected a natural number"

private def bool : D Bool := fun j =>
  match j.getBool? with
  | .ok b => .ok b
  | .error _ => .error ": expected true or false"

private def str : D String := fun j =>
  match j.getStr? with
  | .ok s => .ok s
  | .error _ => .error ": expected a string"

/-- A commit: 1 to 64 letters and digits. Nothing else is printed back. -/
private def sha : D Sha := fun j => do
  let s ← str j
  unless 0 < s.length && s.length ≤ 64 && s.all fun c => c.isAlphanum do
    throw ": expected a commit, 1 to 64 letters and digits"
  return s

private def list (d : D α) : D (List α) := fun j =>
  match j.getArr? with
  | .error _ => .error ": expected a list"
  | .ok a => a.toList.mapIdx (fun i v => (d v).mapError fun e => s!"[{i}]{e}") |>.mapM id

/-- A string that is one of the names in the table. -/
private def named (table : List (String × α)) : D α := fun j => do
  let s ← str j
  match table.lookup s with
  | some v => return v
  | none => throw s!": {s.quote} is not one of {", ".intercalate (table.map (·.1.quote))}"

/-- An object `{kind, ...}`: the table gives, for each kind, its other keys and its decoder. -/
private def tagged (table : List (String × List String × D α)) : D α := fun j => do
  let k ← at' "kind" str j
  match table.lookup k with
  | none => throw s!".kind: {k.quote} is not one of {", ".intercalate (table.map (·.1.quote))}"
  | some (keys, d) =>
    obj ("kind" :: keys) j
    d j

private def teammate : D Teammate := fun j => do
  obj ["provider", "name"] j
  return ⟨← at' "provider" str j, ← at' "name" str j⟩

private def push : D Push := fun j => do
  obj ["byUpdater", "before", "after"] j
  return ⟨← at' "byUpdater" bool j, ← at' "before" sha j, ← at' "after" sha j⟩

private def idPair : D (Sha × String) := fun j => do
  obj ["sha", "id"] j
  return (← at' "sha" sha j, ← at' "id" str j)

private def result : D Result :=
  named [("pass", .pass), ("fail", .fail), ("hold", .hold), ("wordingOnly", .wordingOnly)]

private def verdict : D Verdict := fun j => do
  obj ["said", "head", "judge", "model", "result"] j
  return ⟨← at' "said" nat j, ← at' "head" sha j, ← at' "judge" teammate j, ← at' "model" str j,
    ← at' "result" result j⟩

private def author : D Author := fun j => do
  obj ["who", "model"] j
  return ⟨← at' "who" teammate j, ← at' "model" str j⟩

private def word : D Word := tagged
  [("ownerLand", ["said", "about"], fun j => do
      return .ownerLand ⟨← at' "said" nat j, ← at' "about" sha j⟩),
   ("ownerHold", ["said"], fun j => return .ownerHold (← at' "said" nat j)),
   ("agentLand", ["who", "said", "about"], fun j => do
      return .agentLand (← at' "who" teammate j) ⟨← at' "said" nat j, ← at' "about" sha j⟩)]

private def base : D Base := tagged
  [("current", [], fun _ => return .current),
   ("clean", ["replay"], fun j => return .clean (← at' "replay" sha j)),
   ("conflict", [], fun _ => return .conflict),
   ("mergedMain", [], fun _ => return .mergedMain),
   ("unread", [], fun _ => return .unread)]

private def gate : D Gate :=
  named [("success", .success), ("failure", .failure), ("cancelled", .cancelled),
    ("skipped", .skipped), ("pending", .pending), ("missing", .missing)]

private def observation : D Obs := fun j => do
  obj ["pr", "updatable", "enforced", "head", "pushes", "ids", "paths", "base", "gate", "author",
    "verdicts", "botAt", "delegates", "words", "rest"] j
  return { pr := ← at' "pr" nat j, updatable := ← at' "updatable" bool j,
           enforced := ← at' "enforced" bool j, head := ← at' "head" sha j,
           pushes := ← at' "pushes" (list push) j, ids := ← at' "ids" (list idPair) j,
           paths := ← opt "paths" (list str) j, base := ← at' "base" base j,
           gate := ← at' "gate" gate j, author := ← opt "author" author j,
           verdicts := ← at' "verdicts" (list verdict) j, botAt := ← opt "botAt" sha j,
           delegates := ← at' "delegates" (list teammate) j, words := ← at' "words" (list word) j,
           rest := ← at' "rest" bool j }

private def event : D Event := tagged
  [("mainMoved", [], fun _ => return .mainMoved),
   ("updaterPushed", ["pr"], fun j => return .updaterPushed (← at' "pr" nat j)),
   ("gateDone", ["pr", "gate"], fun j => return .gateDone (← at' "pr" nat j) (← at' "gate" gate j)),
   ("botReviewed", ["pr"], fun j => return .botReviewed (← at' "pr" nat j)),
   ("conflictFound", ["pr"], fun j => return .conflictFound (← at' "pr" nat j)),
   ("landWord", ["pr"], fun j => return .landWord (← at' "pr" nat j)),
   ("ownerSpoke", ["pr"], fun j => return .ownerSpoke (← at' "pr" nat j))]

/-! ## The snapshot -/

structure Snapshot where
  prs : List Obs
  me : Option Teammate
  pr : Option Pr
  event : Option Event

private def snapshot : D Snapshot := fun j => do
  obj ["prs", "me", "pr", "event"] j
  return { prs := ← at' "prs" (list observation) j, me := ← opt "me" teammate j,
           pr := ← opt "pr" nat j, event := ← opt "event" event j }

def Word.said : Word → Nat
  | .ownerLand m => m.said
  | .ownerHold s => s
  | .agentLand _ m => m.said

private def firstDup : List Nat → Option Nat
  | [] => none
  | x :: xs => if xs.contains x then some x else firstDup xs

private def ascending (l : List Nat) : Bool := (l.zip l.tail).all fun p => p.1 < p.2

/-- The conditions the decision relies on and does not check (see the module doc). -/
def Snapshot.check (s : Snapshot) : Except String Unit := do
  if let some p := firstDup (s.prs.map (·.pr)) then
    throw s!"pull request {p} is listed twice"
  for o in s.prs do
    unless ascending (o.words.map Word.said) do
      throw s!"pull request {o.pr}: the words are not in ascending comment id"
  if let some d := firstDup (s.prs.flatMap fun o => o.words.map Word.said) then
    throw s!"comment {d} is used by two words"
  match s.me, s.pr with
  | none, none => pure ()
  | some _, some p =>
    unless s.prs.any (·.pr == p) do throw s!"pr: pull request {p} is not in prs"
  | _, _ => throw "me and pr go together: give both or neither"

/-! ## The decision -/

structure Decision where
  next : Option Pr
  plan : Plan
  step : Option Step
  wake : Option Wake

def Snapshot.decide (s : Snapshot) : Decision :=
  let q := queueOf s.prs
  { next := (Land.next q).map (·.2.pr), plan := plan q,
    step := match s.me, s.pr with
      | some me, some p => (s.prs.find? (·.pr == p)).map (step me q)
      | _, _ => none,
    wake := s.event.map (wakeOf s.prs) }

/-! ## Encoding -/

private def kind (k : String) (fields : List (String × Json) := []) : Json :=
  Json.mkObj (("kind", Json.str k) :: fields)

private def n (x : Nat) : Json := Lean.toJson x

def planJson : Plan → Json
  | .push pr expect replay =>
    kind "push" [("pr", n pr), ("expect", .str expect), ("replay", .str replay)]
  | .idle => kind "idle"

def stuckName : Stuck → String
  | .conflict => "conflict" | .contentChanged => "contentChanged" | .red => "red"
  | .historyError => "historyError" | .unread => "unread"

def stopJson : Stop → Json
  | .held => kind "stop" [("why", "held")]
  | .unenforced => kind "stop" [("why", "unenforced")]
  | .notEligible => kind "stop" [("why", "notEligible")]
  | .stuck why => kind "stop" [("why", "stuck"), ("stuck", .str (stuckName why))]
  | .noEntry => kind "stop" [("why", "noEntry")]

def stepJson : Step → Json
  | .enter about => kind "enter" [("about", .str about)]
  | .wait ahead => kind "wait" [("ahead", n ahead)]
  | .awaitPush head => kind "awaitPush" [("head", .str head)]
  | .awaitGate head => kind "awaitGate" [("head", .str head)]
  | .merge head => kind "merge" [("head", .str head)]
  | .present head => kind "present" [("head", .str head)]
  | .stop why => stopJson why

def wakeJson : Wake → Json
  | .nobody => kind "nobody"
  | .lander pr => kind "lander" [("pr", n pr)]
  | .holder pr => kind "holder" [("pr", n pr)]
  | .orchestrator => kind "orchestrator"

def Decision.json (d : Decision) : Json :=
  Json.mkObj <|
    [("next", d.next.elim Json.null n), ("plan", planJson d.plan)] ++
    (d.step.map fun s => [("step", stepJson s)]).getD [] ++
    (d.wake.map fun w => [("wake", wakeJson w)]).getD []

/-! ## The command -/

/-- The decision for the text of a snapshot, or why the snapshot is refused. -/
def run (text : String) : Except String Json := do
  let j ← match Json.parse text with
    | .ok j => pure j
    | .error e => throw s!"not JSON: {e}"
  let s ← (snapshot j).mapError fun e => if e.startsWith "." then (e.drop 1).toString else "snapshot" ++ e
  s.check
  return s.decide.json

def cli (args : List String) (usage : String) : IO UInt32 := do
  let path? ← match args with
    | [] | ["-"] => pure (some none)
    | [p] => pure (some (some p))
    | _ => pure none
  let some path := path? | do
    IO.eprintln "land takes at most one argument, the snapshot file (default: standard input)"
    IO.eprintln usage
    return 2
  try
    let text ← match path with
      | none => (← IO.getStdin).readToEnd
      | some p => IO.FS.readFile p
    match run text with
    | .ok j =>
      IO.println (ciLine j.compress)
      return 0
    | .error e =>
      IO.eprintln (ciLine s!"land: the snapshot is refused: {e}")
      return 1
  catch e =>
    IO.eprintln (ciLine s!"land: stopped on an I/O error: {e}")
    return 1

end MitosGate.LandCli
