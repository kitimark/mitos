import Lean.Data.Json
import Lean.CoreM
import Lean.Util.CollectAxioms
import MitosGate.Util

namespace MitosGate.Provenance.SourceTransport

open Lean (Json)

private def legacyStart : String := "<!-- mitos-provenance:v1 -->"
private def legacyEnd : String := "<!-- /mitos-provenance:v1 -->"
private def currentStart : String := "<!-- mitos-provenance:v2 -->"
private def currentEnd : String := "<!-- /mitos-provenance:v2 -->"

private def legacyFrame (payload : String) : String :=
  legacyStart ++ "\n```json\n" ++ payload ++ "\n```\n" ++ legacyEnd

private def bodyOk (body : String) : Except String Unit := do
  unless body.utf8ByteSize ≤ 262144 do throw "dashboard exceeds bound"
  unless (body.splitOn "<!-- mitos-provenance:").length == 2 &&
      (body.splitOn "<!-- /mitos-provenance:").length == 2 do
    throw "missing or duplicate source section"

private def legacy (body : String) : Except String Json := do
  bodyOk body
  let [_, after] := body.splitOn legacyStart | throw "unrecognized source version"
  let [inside, _] := after.splitOn legacyEnd | throw "malformed source section"
  let ["", framed] := inside.splitOn "\n```json\n" | throw "expected canonical JSON fence"
  let [payload, ""] := framed.splitOn "\n```\n" | throw "expected canonical JSON fence"
  unless payload.utf8ByteSize ≤ 131072 do throw "payload exceeds bound"
  let j ← (Json.parse payload).mapError fun _ => "malformed JSON"
  unless j.compress == payload do throw "expected canonical single-line JSON"
  return j

private def rows : Nat → List Char → List String
  | 0, _ => []
  | _ + 1, [] => []
  | n + 1, cs => String.ofList (cs.take 64) :: rows n (cs.drop 64)

private def hex64 (text : String) : String :=
  let digits := text.toUTF8.toList.flatMap fun b =>
    [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)]
  String.intercalate "\n" (rows (digits.length + 1) digits)

private def hexChar (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('A' ≤ c && c ≤ 'F')

private def pairs : List Char → Except String (List UInt8)
  | [] => .ok []
  | [_] => .error "incomplete hex byte"
  | a :: b :: cs => do
    unless hexChar a && hexChar b do throw "invalid hex byte"
    return UInt8.ofNat (16 * hexVal a + hexVal b) :: (← pairs cs)

private def checkedHex (payload text : String) : Except String String :=
  if hex64 text == payload then .ok text else .error "expected canonical hex64"

private def unhex64 (payload : String) : Except String String := do
  let bytes ← pairs (payload.toList.filter (· != '\n'))
  let some text := String.fromUTF8? ⟨bytes.toArray⟩ | throw "invalid UTF-8 payload"
  checkedHex payload text

private def currentText (body : String) : Except String String := do
  bodyOk body
  let [_, after] := body.splitOn currentStart | throw "unrecognized source version"
  let [inside, _] := after.splitOn currentEnd | throw "malformed source section"
  let ["", framed] := inside.splitOn "\n```text\n" | throw "expected canonical text fence"
  let [payload, ""] := framed.splitOn "\n```\n" | throw "expected canonical text fence"
  unless payload.utf8ByteSize ≤ 131072 do throw "payload exceeds bound"
  let text ← unhex64 payload
  unless text.utf8ByteSize ≤ 131072 do throw "decoded payload exceeds bound"
  return text

private def current (body : String) : Except String Json := do
  legacy (legacyFrame (← currentText body))

def readCanonicalJson (body : String) : Except String Json := do
  bodyOk body
  if (body.splitOn currentStart).length == 2 then current body else legacy body

def publicationBlock (j : Json) : String :=
  currentStart ++ "\n```text\n" ++ hex64 j.compress ++ "\n```\n" ++ currentEnd

private theorem checkedHex_isCanonical {payload text result : String}
    (h : checkedHex payload text = .ok result) : hex64 result = payload := by
  unfold checkedHex at h
  split at h
  · cases h
    simpa using ‹(hex64 text == payload) = true›
  · cases h

private theorem current_usesLegacy {body : String} {j : Json}
    (h : current body = .ok j) :
    ∃ text, legacy (legacyFrame text) = .ok j := by
  unfold current at h
  cases ht : currentText body with
  | error e =>
    rw [ht] at h
    change (Except.error e : Except String Json) = .ok j at h
    cases h
  | ok text =>
    rw [ht] at h
    exact ⟨text, h⟩

open Lean in
#eval show CoreM Unit from do
  for n in [``checkedHex_isCanonical, ``current_usesLegacy] do
    for a in ← collectAxioms n do
      unless [``propext, ``Classical.choice, ``Quot.sound].contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Provenance.SourceTransport
