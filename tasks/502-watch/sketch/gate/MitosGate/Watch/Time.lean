import MitosGate.Base.Text
import MitosGate.Shadow.Types

namespace MitosGate.Watch

abbrev Epoch := Nat

def ofStamp (t : Speech.Stamp) : Epoch := Shadow.Stamp.seconds ⟨t⟩

def ofIso? (s : String) : Option Epoch := (Speech.stamp? s.toList).map ofStamp

def months : List (List Char) :=
  ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].map
    String.toList

def monthOf? (m : List Char) : Option Nat := go months 1
where
  go : List (List Char) → Nat → Option Nat
    | [], _ => none
    | x :: xs, i => if x = m then some i else go xs (i + 1)

def two? : List Char → Option Nat
  | [a, b] => Base.Text.parseNat [a, b]
  | _ => none

def four? : List Char → Option Nat
  | [a, b, c, d] => Base.Text.parseNat [a, b, c, d]
  | _ => none

def ofHttpDate? (s : List Char) : Option Epoch :=
  match Base.Text.split ' ' s with
  | [_, dd, mon, yyyy, hms, ['G', 'M', 'T']] =>
    match Base.Text.split ':' hms with
    | [hh, mi, ss] => do
      let d ← two? dd
      let m ← monthOf? mon
      let y ← four? yyyy
      let h ← two? hh
      let n ← two? mi
      let c ← two? ss
      if 1 ≤ d && d ≤ 31 && 1970 ≤ y && h < 24 && n < 60 && c < 60 then
        some (Shadow.days y m d * 86400 + h * 3600 + n * 60 + c)
      else none
    | _ => none
  | _ => none

def padChars (width n : Nat) : List Char :=
  let d := Nat.toDigits 10 n
  List.replicate (width - d.length) '0' ++ d

def civil (z : Nat) : Nat × Nat × Nat :=
  let z := z + 719468
  let era := z / 146097
  let doe := z - era * 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  (yoe + era * 400 + (if m ≤ 2 then 1 else 0), m, d)

def isoChars (e : Epoch) : List Char :=
  let (y, m, d) := civil (e / 86400)
  let s := e % 86400
  padChars 4 y ++ '-' :: padChars 2 m ++ '-' :: padChars 2 d ++ 'T' :: padChars 2 (s / 3600) ++
    ':' :: padChars 2 (s / 60 % 60) ++ ':' :: padChars 2 (s % 60) ++ ['Z']

def iso (e : Epoch) : String := String.ofList (isoChars e)

def IsoReadsBack : Prop :=
  ∀ e : Epoch, e < 4102444800 → ofIso? (iso e) = some e

namespace Fixture

theorem isoNow : isoChars 1795428728 = "2026-11-23T10:12:08Z".toList := by decide +kernel
theorem isoEpoch : isoChars 0 = "1970-01-01T00:00:00Z".toList := by decide +kernel
theorem isoLeapDay : isoChars 1709164800 = "2024-02-29T00:00:00Z".toList := by decide +kernel
theorem readNow : ofIso? "2026-11-23T10:12:08Z" = some 1795428728 := by decide +kernel
theorem readRefusesMillis : ofIso? "2026-11-23T10:12:08.000Z" = none := by decide +kernel
theorem httpDateNow : ofHttpDate? "Mon, 23 Nov 2026 10:12:08 GMT".toList = some 1795428728 := by
  decide +kernel
theorem httpDateRefusesAnotherZone :
    ofHttpDate? "Mon, 23 Nov 2026 10:12:08 UTC".toList = none := by decide +kernel

end Fixture

end MitosGate.Watch
