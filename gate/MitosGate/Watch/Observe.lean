import Lean.Data.Json
import MitosGate.Base.Text
import MitosGate.Watch.Voice

namespace MitosGate.Watch

open Lean (Json)
open Land (Pr)

inductive ItemKind
  | post (place : Place)
  | close
  deriving DecidableEq, Repr

structure Refused where
  kind : ItemKind
  id : Nat
  thread : Option Pr
  why : Excerpt
  deriving DecidableEq

structure Reading (α : Type) where
  items : List α
  refused : List Refused

namespace Field

def get (k : String) (j : Json) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!".{k}: missing"

def str (k : String) (j : Json) : Except String String := do
  match (← get k j).getStr? with
  | .ok s => return s
  | .error _ => throw s!".{k}: expected a string"

def nat (k : String) (j : Json) : Except String Nat := do
  match (← get k j).getNat? with
  | .ok n => return n
  | .error _ => throw s!".{k}: expected a natural number"

def text (k : String) (j : Json) : Except String String := do
  match ← get k j with
  | .null => return ""
  | .str s => return s
  | _ => throw s!".{k}: expected a string or null"

def time (k : String) (j : Json) : Except String Epoch := do
  match ofIso? (← str k j) with
  | some t => return t
  | none => throw s!".{k}: expected YYYY-MM-DDTHH:MM:SSZ"

def login (j : Json) : Except String (Option String) := do
  match ← get "user" j with
  | .null => return none
  | u => some <$> (str "login" u).mapError (".user" ++ ·)

def thread (k : String) (j : Json) : Except String Pr := do
  match (Base.Text.split '/' (← str k j).toList).getLast? >>= Base.Text.parseNat with
  | some n => return n
  | none => throw s!".{k}: expected a URL that ends with a number"

end Field

def located (j : Json) : Except String (List (String × Json)) := do
  let pages ← match j.getArr? with
    | .ok a => pure a
    | .error _ => throw "expected a list of pages"
  if pages.isEmpty then throw "expected at least one page"
  let mut out := #[]
  for p in [0:pages.size] do
    match pages[p]!.getArr? with
    | .error _ => throw s!"[{p}]: expected a page, a list of items"
    | .ok items =>
      for i in [0:items.size] do
        out := out.push (s!"[{p}][{i}]", items[i]!)
  return out.toList

def collect (place : Place) (owner : String) (thread : Json → Except String Pr)
    (said : Nat → Pr → Json → Except String (Option Said)) (j : Json) :
    Except String (Reading Said) := do
  let mut items := #[]
  let mut refused := #[]
  for (path, c) in ← located j do
    let who ← (Field.login c).mapError (path ++ ·)
    unless who == some owner do continue
    let id ← (Field.nat "id" c).mapError (path ++ ·)
    match thread c with
    | .error e => refused := refused.push ⟨.post place, id, none, Excerpt.of (path ++ e)⟩
    | .ok t =>
      match said id t c with
      | .error e => refused := refused.push ⟨.post place, id, some t, Excerpt.of (path ++ e)⟩
      | .ok none => pure ()
      | .ok (some p) => items := items.push p
  return ⟨items.toList, refused.toList⟩

def issueComments (owner : String) (j : Json) : Except String (Reading Said) :=
  collect .issueComment owner (Field.thread "issue_url") (fun id thread c => do
    let via ← match ← Field.get "performed_via_github_app" c with
      | .null => pure Via.null
      | a => Via.app <$> (Field.str "slug" a).mapError (".performed_via_github_app" ++ ·)
    return some ⟨.issueComment, id, thread, owner, via, ← Field.time "created_at" c,
      ← Field.time "updated_at" c, none, ← Field.text "body" c⟩) j

def reviewComments (owner : String) (j : Json) : Except String (Reading Said) :=
  collect .reviewComment owner (Field.thread "pull_request_url") (fun id thread c =>
    return some ⟨.reviewComment, id, thread, owner, .noKey, ← Field.time "created_at" c,
      ← Field.time "updated_at" c, none, ← Field.text "body" c⟩) j

/-- A pending review is the owner's draft: not posted yet, and it has no time. -/
def reviews (owner : String) (j : Json) : Except String (Reading Said) :=
  collect .review owner (Field.thread "pull_request_url") (fun id thread c => do
    let state ← Field.str "state" c
    if state == "PENDING" then return none
    let submitted ← Field.time "submitted_at" c
    return some ⟨.review, id, thread, owner, .noKey, submitted, submitted, some state,
      ← Field.text "body" c⟩) j

def readJsonFile (path : System.FilePath) : IO (Except String Json) := do
  match String.fromUTF8? (← IO.FS.readBinFile path) with
  | none => return .error s!"{path}: not valid UTF-8"
  | some s => return (Json.parse s).mapError fun e => s!"{path}: {e}"

end MitosGate.Watch
