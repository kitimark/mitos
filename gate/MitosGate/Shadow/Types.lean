import MitosGate.Land
import MitosGate.Speech.Syntax

namespace MitosGate.Shadow

open Land

structure Stamp where
  digits : Speech.Stamp
  deriving DecidableEq

instance : LT Stamp := ⟨fun a b => a.digits < b.digits⟩
instance : LE Stamp := ⟨fun a b => a.digits ≤ b.digits⟩
instance (a b : Stamp) : Decidable (a < b) := inferInstanceAs (Decidable (a.digits < b.digits))

def days (y m d : Nat) : Nat :=
  let y := if m ≤ 2 then y - 1 else y
  let era := y / 400
  let yoe := y - era * 400
  let doy := (153 * ((m + 9) % 12) + 2) / 5 + d - 1
  era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468

def Stamp.seconds (t : Stamp) : Nat :=
  let part (k : Nat) := t.digits / 10 ^ k % 100
  days (t.digits / 10 ^ 10) (part 8) (part 6) * 86400 + part 4 * 3600 + part 2 * 60 +
    t.digits % 100

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
  main : Option Sha
  tool : Sha
  cost : Cost
  prs : List Obs
  trees : List TreeOf

structure Merge where
  pr : Pr
  time : Stamp
  before : Option Sha
  head : Sha
  tree : Option Sha

namespace Fixture

theorem theEpochIsZero : Stamp.seconds ⟨19700101000000⟩ = 0 := by decide +kernel
theorem aDayOfThisWindow : Stamp.seconds ⟨20261114000000⟩ = 1794614400 := by decide +kernel
theorem aLeapDay : Stamp.seconds ⟨20240229120000⟩ = 1709208000 := by decide +kernel
theorem aLeapCentury : Stamp.seconds ⟨20000301000000⟩ = 951868800 := by decide +kernel
theorem aCenturyThatIsNotLeap : Stamp.seconds ⟨21000301000000⟩ = 4107542400 := by decide +kernel
theorem aMinuteIsSixtySeconds :
    Stamp.seconds ⟨20261113120100⟩ - Stamp.seconds ⟨20261113120059⟩ = 1 := by decide +kernel
theorem aYearEndsInOneSecond :
    Stamp.seconds ⟨20270101000000⟩ - Stamp.seconds ⟨20261231235959⟩ = 1 := by decide +kernel

/-- error: failed to synthesize instance of type class
  HSub Stamp Stamp -/
#guard_msgs (substring := true) in
example (a b : Stamp) := a - b

end Fixture

end MitosGate.Shadow
