import Init

namespace MitosGate.LockFixture

theorem match_foo : True := .intro

theorem proof_of_x : True := .intro

theorem proof_2 : True := .intro

theorem proof_ : True := .intro

theorem proof_2x : True := .intro

theorem early.eq_2 : True := .intro

def early (b : Bool) : Nat := if b then 1 else 0

theorem earlym.match_1.eq_1 : True := .intro

def earlym : Nat × Bool → String
  | (0, true) => "a"
  | (5, false) => "b"
  | _ => "c"

theorem nested : (∃ n : Nat, ∃ m : Nat, n = m) → True := fun ⟨_, _, _⟩ => .intro

def equation : Bool → Bool
  | true => false
  | false => true

theorem equation.eq_of_id (b : Bool) : equation b = equation b := rfl

theorem equation_true : equation true = false := equation.eq_1

theorem equation_def (b : Bool) : equation b = match b with
    | true => false
    | false => true := equation.eq_def b

theorem earlym.match_1.eq_of_id : @earlym.match_1 = @earlym.match_1 := rfl

theorem earlym.match_1.eq_def : @earlym.match_1 = @earlym.match_1 := rfl

theorem earlym.match_1.eq_unfold : @earlym.match_1 = @earlym.match_1 := rfl

end MitosGate.LockFixture
