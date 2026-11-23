import MitosGate.Base.Text
import MitosGate.Shadow.Types

/-! UNCHECKED SKETCH (#502). Epoch seconds, the one ISO form GitHub writes and reads, and the HTTP
`Date` header GitHub stamps on every answer.

Two clocks, kept apart on purpose:
* GitHub's clock orders facts and decides what the feed asks for. Every poll reads the `Date`
  header of its first answer (`branches/main`, read with `--include`), and the feed's cursor is
  that time. The next poll asks from `cursor - overlap`. The local clock never reaches the feed:
  `Feed.add` and `Feed.sinceAt` take no local time (`TheFeedIgnoresTheLocalClock`). How long a run
  has been queued is also measured on GitHub's clock (`View.ciHealth`), because GitHub stamps it.
* The local wall clock times the wait: the deadline, the poll interval, how long a head has had no
  `ci` run (its first sighting is local too). `WatchCli` reads it at every step with
  `Std.Time.Timestamp.now`. `--now` exists only for tests, and a step back of the clock makes a
  poll due (`pollDue`), never a wait without end.

Reading reuses `Speech.stamp?` (exactly `YYYY-MM-DDTHH:MM:SSZ`) and `Shadow.days` (Hinnant's
`days_from_civil`). Neither module moves. Everything a `decide +kernel` fixture evaluates works on
`List Char` with `Base.Text` (`split`, `parseNat`) and `Nat.toDigits`: `String.splitOn`,
`String.toNat?`, `String.all` and `toString` are taken to go through loops the kernel does not
reduce, unverified until PR 2's elaboration. `String` appends do reduce: `Snapshot/Fixtures.lean`
proves fixtures over `"Why." ++ footer` by `decide +kernel` on v4.35.0. -/

namespace MitosGate.Watch

abbrev Epoch := Nat

def ofStamp (t : Speech.Stamp) : Epoch := Shadow.Stamp.seconds ⟨t⟩

def ofIso? (s : String) : Option Epoch := (Speech.stamp? s.toList).map ofStamp

def months : List (List Char) :=
  ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].map
    String.toList

/-- The month number of a three-letter English month name. -/
def monthOf? (m : List Char) : Option Nat := go months 1
where
  go : List (List Char) → Nat → Option Nat
    | [], _ => none
    | x :: xs, i => if x = m then some i else go xs (i + 1)

/-- Exactly two decimal digits. -/
def two? : List Char → Option Nat
  | [a, b] => Base.Text.parseNat [a, b]
  | _ => none

/-- Exactly four decimal digits. -/
def four? : List Char → Option Nat
  | [a, b, c, d] => Base.Text.parseNat [a, b, c, d]
  | _ => none

/-- The IMF-fixdate form of an HTTP `Date` header value, `Mon, 23 Nov 2026 10:12:08 GMT`, with no
trailing carriage return (`Gh` strips it from each header line). The weekday is not checked.
Anything else refuses, and the poll fails with the route named (PR 4 confirms the form live). -/
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

/-- `n` in decimal, zero padded to `width` digits. -/
def padChars (width n : Nat) : List Char :=
  let d := Nat.toDigits 10 n
  List.replicate (width - d.length) '0' ++ d

/-- The civil date of a day count, the inverse of `Shadow.days` (Hinnant's `civil_from_days`). -/
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

/-- Up to 2100-01-01. EXPENSIVE: it needs `days (civil z) = z` over the range, a division
argument on Hinnant's eras. It is the one statement with a weaker fallback: if it does not land in
PR 4, `WatchCli` checks `ofIso? (iso e)` at run time before it asks GitHub with `iso e`, and
refuses with exit 1; the fixtures stay. Taking the fallback also deletes this `def`, since the
audit fails on a statement with no theorem: a deviation the PR body records, never a silent one. -/
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
