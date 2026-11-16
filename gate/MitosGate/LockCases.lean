import MitosGate.Lock
import MitosGate.LockFixture

open Lean MitosGate

run_cmd do
  let core ← Lock.importRoot `MitosGate.LockFixture
  let cases := [
    (`Mitos.WellFormed.eq_of_id, false),
    (`Mitos.Assumption.isAI.match_1.eq_of_id, false),
    (`Mitos.Assumption.isAI.match_1.eq_def, false),
    (`Mitos.Assumption.isAI.match_1.eq_unfold, false),
    (`MitosGate.LockFixture.match_foo, false),
    (`MitosGate.LockFixture.proof_of_x, false),
    (`MitosGate.LockFixture.proof_, false),
    (`MitosGate.LockFixture.proof_2x, false),
    (`MitosGate.LockFixture.equation.eq_1, true),
    (`MitosGate.LockFixture.equation.eq_def, true),
    (`Mitos.Assumption.isAI.match_1, true),
    (`Mitos.Model.Adequate.constant_not_sound_complete.match_1_1, true),
    (`MitosGate.LockFixture.proof_2, true)]
  for (n, generated) in cases do
    unless core.env.contains n do
      throwError "missing lock fixture {n}"
    unless Lock.isGenerated core.env n == generated do
      throwError "isGenerated {n} should be {generated}"
  let matcherEquation := `Mitos.Assumption.isAI.match_1.eq_1
  unless Lock.isGenerated core.env matcherEquation do
    throwError "equations under an imported matcher should be generated"
