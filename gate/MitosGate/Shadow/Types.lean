import MitosGate.Land
import MitosGate.Speech.Syntax

/-!
What `mitos-gate shadow` scores: the record a `decide` run leaves, and a merge of the window.
-/

namespace MitosGate.Shadow

open Land

/-- A UTC time as the number `YYYYMMDDHHMMSS` (`Speech.stamp?`), so `<` orders two as time. -/
abbrev Stamp := Speech.Stamp

/-- Days from 1970-01-01 to a Gregorian date from 1970 on. -/
def days (y m d : Nat) : Nat :=
  let y := if m ≤ 2 then y - 1 else y
  let era := y / 400
  let yoe := y - era * 400
  let doy := (153 * ((m + 9) % 12) + 2) / 5 + d - 1
  era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468

/-- Seconds from 1970-01-01T00:00:00Z. The difference of two stamps as numbers is not their
difference in seconds: a minute is 100 of them. -/
def seconds (t : Stamp) : Nat :=
  let part (k : Nat) := t / 10 ^ k % 100
  days (t / 10 ^ 10) (part 8) (part 6) * 86400 + part 4 * 3600 + part 2 * 60 + t % 100

inductive Trigger
  | mainMoved
  | gateDone (head : Sha) (conclusion : String)
  | comment (pr : Pr) (id : Nat)
  | dispatch
  deriving DecidableEq

structure Cost where
  setup : Nat
  fetch : Nat
  snapshot : Nat
  decide : Nat
  reads : Nat

structure TreeOf where
  commit : Sha
  tree : Sha

structure Record where
  run : Nat
  trigger : Trigger
  read : Stamp
  main : Sha
  tool : Sha
  cost : Cost
  prs : List Obs
  trees : List TreeOf

structure Merge where
  pr : Pr
  time : Stamp
  before : Sha
  head : Sha
  tree : Sha

namespace Fixture

theorem theEpochIsZero : seconds 19700101000000 = 0 := by decide +kernel
theorem aDayOfThisWindow : seconds 20261114000000 = 1794614400 := by decide +kernel
theorem aLeapDay : seconds 20240229120000 = 1709208000 := by decide +kernel
theorem aLeapCentury : seconds 20000301000000 = 951868800 := by decide +kernel
theorem aCenturyThatIsNotLeap : seconds 21000301000000 = 4107542400 := by decide +kernel
theorem aMinuteIsSixtySeconds : seconds 20261113120100 - seconds 20261113120059 = 1 := by
  decide +kernel
theorem aYearEndsInOneSecond : seconds 20270101000000 - seconds 20261231235959 = 1 := by
  decide +kernel

end Fixture

end MitosGate.Shadow
