import MitosGate.Shadow.Types

namespace MitosGate.Watch

structure Epoch where
  seconds : Nat
  deriving DecidableEq, Repr

instance : LT Epoch := ⟨fun a b => a.seconds < b.seconds⟩
instance : LE Epoch := ⟨fun a b => a.seconds ≤ b.seconds⟩
instance (a b : Epoch) : Decidable (a < b) := inferInstanceAs (Decidable (a.seconds < b.seconds))
instance (a b : Epoch) : Decidable (a ≤ b) := inferInstanceAs (Decidable (a.seconds ≤ b.seconds))

def ofStamp (t : Speech.Stamp) : Epoch := ⟨Shadow.Stamp.seconds ⟨t⟩⟩

def ofIso? (s : String) : Option Epoch := (Speech.stamp? s.toList).map ofStamp

namespace Fixture

theorem readNow : ofIso? "2026-11-23T10:12:08Z" = some ⟨1795428728⟩ := by decide +kernel
theorem readRefusesMillis : ofIso? "2026-11-23T10:12:08.000Z" = none := by decide +kernel

/-- error: failed to synthesize instance of type class
  HSub Epoch Epoch -/
#guard_msgs (substring := true) in
example (a b : Epoch) := a - b

/-- error: Type mismatch -/
#guard_msgs (substring := true) in
example (n : Nat) : Epoch := n

end Fixture

end MitosGate.Watch
