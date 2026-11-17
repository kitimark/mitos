import MitosGate.Lock
import MitosGate.LockFixture

open Lean MitosGate

run_cmd do
  let core ← Lock.importRoot `MitosGate.LockFixture
  let cases := [
    (`MitosGate.LockFixture.equation.eq_of_id, false),
    (`MitosGate.LockFixture.earlym.match_1.eq_of_id, false),
    (`MitosGate.LockFixture.earlym.match_1.eq_def, false),
    (`MitosGate.LockFixture.earlym.match_1.eq_unfold, false),
    (`MitosGate.LockFixture.early.eq_2, false),
    (`MitosGate.LockFixture.earlym.match_1.eq_1, false),
    (`MitosGate.LockFixture.match_foo, false),
    (`MitosGate.LockFixture.proof_of_x, false),
    (`MitosGate.LockFixture.proof_, false),
    (`MitosGate.LockFixture.proof_2x, false),
    (`MitosGate.LockFixture.equation.eq_1, true),
    (`MitosGate.LockFixture.equation.eq_def, true),
    (`MitosGate.LockFixture.earlym.match_1, true),
    (`MitosGate.LockFixture.nested.match_1_1, true),
    (`MitosGate.LockFixture.proof_2, true)]
  for (n, generated) in cases do
    unless core.env.contains n do
      throwError "missing lock fixture {n}"
    unless Lock.isGenerated core.env n == generated do
      throwError "isGenerated {n} should be {generated}"
  for n in [`MitosGate.LockFixture.early.eq_3,
      `MitosGate.LockFixture.earlym.match_1.eq_2] do
    if core.env.contains n then
      throwError "expected absent equation probe {n}"
    unless Lock.isGenerated core.env n do
      throwError "absent reserved equations should be generated {n}"
  for n in [`MitosGate.LockFixture.earlym.match_1.eq_def,
      `MitosGate.LockFixture.earlym.match_1.eq_unfold] do
    unless isReservedName core.env n do
      throwError "expected reserved-name query to reserve {n}"
  for n in [`MitosGate.LockFixture.equation.eq_of_id,
      `MitosGate.LockFixture.earlym.match_1.eq_of_id,
      `MitosGate.LockFixture.earlym.match_1.eq_def,
      `MitosGate.LockFixture.earlym.match_1.eq_unfold] do
    unless (core.env.find? n).any (·.type.getUsedConstants.contains n.getPrefix) do
      throwError "expected fixture type to reference its owner {n}"
