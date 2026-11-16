import Mitos.Core

namespace MitosGate.LockFixture

theorem match_foo : True := .intro

theorem proof_of_x : True := .intro

theorem proof_2 : True := .intro

theorem proof_ : True := .intro

theorem proof_2x : True := .intro

def equation : Bool → Bool
  | true => false
  | false => true

theorem equation_true : equation true = false := equation.eq_1

theorem equation_def (b : Bool) : equation b = match b with
    | true => false
    | false => true := equation.eq_def b

end MitosGate.LockFixture

theorem Mitos.Assumption.isAI.match_1.eq_of_id : True := .intro

theorem Mitos.Assumption.isAI.match_1.eq_def : True := .intro

theorem Mitos.Assumption.isAI.match_1.eq_unfold : True := .intro
