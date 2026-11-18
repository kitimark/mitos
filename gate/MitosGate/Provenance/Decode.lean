import Lean.Data.Json
import MitosGate.Provenance
import MitosGate.Speech.Commit
import MitosGate.Provenance.SourceTransport

namespace MitosGate.Provenance

open Lean (Json)
open Land (Sha Pr Teammate Author Verdict Result Obs)

private def get (j : Json) (k : String) : Except String Json :=
  (j.getObjVal? k).mapError fun _ => "missing field"

private def text (j : Json) : Except String String := j.getStr?.mapError fun _ => "expected text"

private def fields (j : Json) (allowed : List String) : Except String Unit := do
  let fs ← j.getObj?.mapError fun _ => "expected object"
  unless fs.toList.all (fun f => allowed.contains f.1) do throw "unrecognized field"

private def array (j : Json) (limit : Nat) : Except String (List Json) := do
  let xs ← j.getArr?.mapError fun _ => "expected array"
  unless xs.size ≤ limit do throw "array exceeds bound"
  return xs.toList

private def sha (j : Json) : Except String Sha := do
  let s ← text j
  unless Speech.isSha s.toList do throw "expected full head"
  return s

private def token (s : String) (limit : Nat) : Bool :=
  !s.isEmpty && s.length ≤ limit && s.toList.all (fun c =>
    c.isLower || c.isDigit || c == '-' || c == '_' || c == '.')

private def optionalText (j : Json) (k : String) : Except String (Option String) :=
  match j.getObjVal? k with
  | .error _ => .ok none
  | .ok .null => .ok none
  | .ok x => do
    let s ← text x
    unless !s.isEmpty && s.length ≤ 128 && s.toList.all (fun c => ' ' ≤ c && c ≤ '~') do
      throw "invalid requested model"
    return some s

private def identity (j : Json) : Except String Identity := do
  let provider ← get j "provider" >>= text
  let actor ← get j "actor" >>= text
  unless token provider 32 && token actor 64 do throw "invalid identity"
  let actualModel ← match ← get j "actualModel" with
    | .null => pure none
    | x => do
      let s ← text x
      unless token s 128 && (ModelIdentity.key provider s).isSome &&
          !["opus", "sonnet", "haiku", "fable", "gpt", "codex", "grok", "claude"].contains s do
        throw "unknown actual model"
      unless provider != "claude" || (ModelIdentity.claudeKey s).isSome do
        throw "unrecognized Claude model"
      pure (some s)
  return ⟨provider, actor, actualModel, ← optionalText j "requestedModel"⟩

private def author (j : Json) : Except String AuthorFact := do
  fields j ["head", "provider", "actor", "actualModel", "requestedModel"]
  return ⟨← get j "head" >>= sha, ← identity j⟩

private def effort (j : Json) : Except String (Option Effort) :=
  match j with
  | .null => .ok none
  | .str "low" => .ok (some .low)
  | .str "medium" => .ok (some .medium)
  | .str "high" => .ok (some .high)
  | .str "xhigh" => .ok (some .xhigh)
  | .str "max" => .ok (some .max)
  | _ => .error "unrecognized effort"

private def result (j : Json) : Except String Result :=
  match j with
  | .str "pass" => .ok .pass
  | .str "fail" => .ok .fail
  | .str "hold" => .ok .hold
  | .str "wordingOnly" => .ok .wordingOnly
  | _ => .error "unrecognized result"

private def verdict (repo : String) (n : Nat) (j : Json) : Except String VerdictFact := do
  fields j ["head", "provider", "actor", "actualModel", "requestedModel", "effort", "result",
    "order", "evidence"]
  let order ← (← get j "order").getNat?.mapError fun _ => "invalid event order"
  unless 0 < order && order ≤ 1000000000 do throw "invalid event order"
  let evidence ← get j "evidence" >>= text
  let evidenceStart := s!"https://github.com/{repo}/pull/{n}#"
  unless evidence.startsWith evidenceStart && evidenceStart.length < evidence.length && evidence.length ≤ 512 &&
      evidence.toList.all (fun c => '!' ≤ c && c ≤ '~') do throw "invalid public evidence"
  return ⟨← get j "head" >>= sha, ← identity j, ← get j "effort" >>= effort,
    ← get j "result" >>= result, order, evidence⟩

private def consistentActors (xs : List Identity) : Bool :=
  xs.all fun a => xs.all fun b => a.actor != b.actor || a.provider == b.provider

private def pull (repo : String) (j : Json) : Except String PullFact := do
  fields j ["number", "author", "verdicts"]
  let n ← (← get j "number").getNat?.mapError fun _ => "invalid pull number"
  unless 0 < n do throw "invalid pull number"
  let a ← get j "author" >>= author
  let vs ← (← get j "verdicts" >>= fun v => array v 256).mapM (verdict repo n)
  unless (vs.map (·.order)).eraseDups.length == vs.length do throw "duplicate event order"
  unless (vs.map (·.evidence)).eraseDups.length == vs.length do throw "duplicate event evidence"
  unless consistentActors (a.identity :: vs.map (·.identity)) do throw "conflicting actor provider"
  return ⟨n, a, vs⟩

def decodePayload (repo : String) (j : Json) : Except String (List PullFact) := do
  fields j ["version", "repository", "pulls"]
  let version ← (← get j "version").getNat?.mapError fun _ => "unrecognized source version"
  unless version == 1 do throw "unrecognized source version"
  unless (← get j "repository" >>= text) == repo do throw "repository mismatch"
  let ps ← (← get j "pulls" >>= fun p => array p 256).mapM (pull repo)
  unless (ps.map (·.number)).eraseDups.length == ps.length do throw "duplicate pull"
  return ps

def decode (repo body : String) : Except String (List PullFact) := do
  decodePayload repo (← SourceTransport.readCanonicalJson body)

def render (repo : String) (j : Json) : Except String String := do
  let body := SourceTransport.publicationBlock j
  let _ ← decode repo body
  return body

theorem render_isDecoded {repo : String} {j : Json} {body : String}
    (h : render repo j = .ok body) : ∃ facts, decode repo body = .ok facts := by
  unfold render at h
  dsimp only at h
  cases hd : decode repo (SourceTransport.publicationBlock j) with
  | error e =>
    rw [hd] at h
    change (Except.error e : Except String String) = .ok body at h
    cases h
  | ok facts =>
    rw [hd] at h
    change (Except.ok (SourceTransport.publicationBlock j) : Except String String) = .ok body at h
    cases h
    exact ⟨facts, hd⟩

end MitosGate.Provenance
