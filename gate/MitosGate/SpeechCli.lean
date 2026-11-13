import Lean.Data.Json
import MitosGate.Speech

open Lean (Json)

namespace MitosGate.SpeechCli

open Speech
open RunLog (quote Message)

private def msg (s : String) : Message := Message.ofString s

private def field (k : String) (j : Json) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!".{k}: missing"

private def str (k : String) (j : Json) : Except String String := do
  match (← field k j).getStr? with
  | .ok s => return s
  | .error _ => throw s!".{k}: expected a string"

private def stamp (k : String) (j : Json) : Except String Stamp := do
  match stamp? (← str k j).toList with
  | some t => return t
  | none => throw s!".{k}: expected YYYY-MM-DDTHH:MM:SSZ"

def comment (j : Json) : Except String Comment := do
  let id ← match (← field "id" j).getNat? with
    | .ok n => pure n
    | .error _ => throw ".id: expected a natural number"
  let login ← (str "login" (← field "user" j)).mapError (".user" ++ ·)
  let slug ← match ← field "performed_via_github_app" j with
    | .null => pure none
    | a => some <$> (str "slug" a).mapError (".performed_via_github_app" ++ ·)
  return ⟨id, login, slug, ← stamp "created_at" j, ← stamp "updated_at" j, ← str "body" j⟩

def comments (text : String) : Except String (List Comment) := do
  let j ← (Json.parse text).mapError (s!"not JSON: {·}")
  let a ← match j.getArr? with
    | .ok a => pure a.toList
    | .error _ => throw "expected a list of comments"
  a.mapIdx (fun i c => (comment c).mapError (s!"[{i}]{·}")) |>.mapM id

def parsePushes (text : String) : Except Message (List Carry.Push) := do
  let ps ← (RunLog.splitLines text).mapM Carry.parsePush
  for p in ps do
    unless isSha p.before.toList && isSha p.after.toList do
      throw (msg "a push's before or after is not a lowercase 40-hex sha: " ++
        quote (p.before ++ " " ++ p.after))
  return ps

def whyName : Why → String
  | .notOwner => "not-owner"
  | .unknownApp => "app-outside-the-list"
  | .noRecord => "app-post-without-record"
  | .malformed => "malformed-record"
  | .notLand => "record-not-land"
  | .wrongTask => "record-for-another-pr"
  | .wrongProvider => "record-from-another-provider"
  | .footer => "footer"
  | .protocolFence => "record-without-app"
  | .noWord => "no-word"
  | .markup => "fence-or-html-in-the-comment"
  | .link => "link-in-the-comment"
  | .quoteContinuation => "inside-a-quote"
  | .nested => "record-not-at-top-level"
  | .hold => "hold"
  | .severalWords => "several-words"
  | .badArgument => "bad-argument"
  | .unknownCommit => "unknown-commit"
  | .ambiguousCommit => "ambiguous-commit"
  | .noHead => "no-head-at-that-second"

def line (x : Ctx) (cs : List Comment) (pushes : List Carry.Push) (c : Comment) : Message :=
  let r := read x pushes c
  let n := r.pos cs c
  match r with
  | .land s => msg s!"{c.id} ownerLand@{n} {s} land"
  | .hold why => msg s!"{c.id} ownerHold@{n} {whyName why}"
  | .editHold => msg s!"{c.id} ownerHold@{n} edited"
  | .agent t s => msg s!"{c.id} agentLand@{n} {t.provider} " ++ quote t.name ++ msg s!" {s} record"
  | .ignored why => msg s!"{c.id} ignored {whyName why}"

structure Args where
  owner : Option String := none
  pr : Option Nat := none
  pushes : Option String := none
  file : Option String := none

def parse : List String → Args → Option Args
  | [], a => some a
  | "--owner" :: v :: rest, a => if a.owner.isSome then none else parse rest { a with owner := v }
  | "--pr" :: v :: rest, a =>
    if a.pr.isSome then none else v.toNat?.bind fun n => parse rest { a with pr := n }
  | "--pushes" :: v :: rest, a =>
    if a.pushes.isSome then none else parse rest { a with pushes := v }
  | v :: rest, a => if a.file.isSome || v.startsWith "--" then none else parse rest { a with file := v }

def cli (args : List String) (usage : String) : IO UInt32 := do
  let some { owner := some owner, pr := some pr, pushes, file := some file } := parse args {} | do
    IO.eprintln "speech needs --owner <login>, --pr <n> and one comments file, with at most one --pushes <tsv>"
    IO.eprintln usage
    return 2
  try
    let ps ← match pushes with
      | none => pure []
      | some p =>
        match parsePushes (← IO.FS.readFile p) with
        | .ok ps => pure ps
        | .error e =>
          IO.eprintln (msg "speech: the pushes are refused: " ++ e).ciLine
          return 1
    match comments (← IO.FS.readFile file) with
    | .error e =>
      IO.eprintln (ciLine s!"speech: the comments are refused: {e}")
      return 1
    | .ok cs =>
      let x : Ctx := { owner, pr, known := ps.flatMap fun p => [p.before, p.after] }
      for c in cs do
        if c.login == owner then IO.println (line x cs ps c).ciLine
      return 0
  catch e =>
    IO.eprintln (ciLine s!"speech: stopped on an I/O error: {e}")
    return 1

end MitosGate.SpeechCli
