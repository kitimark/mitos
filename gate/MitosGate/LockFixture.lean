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

theorem congrm.match_1.congr_eq_1 : True := .intro

def congrm : Nat → List Nat → Nat
  | 0, _ => 0
  | _ + 1, [] => 1
  | n + 1, x :: xs => x + congrm n xs

theorem congrm_step (n x : Nat) (xs : List Nat) :
    congrm (n + 1) (x :: xs) = x + congrm n xs := by
  simp [congrm]

namespace Plain

theorem rec : True := .intro
theorem sizeOf_spec : True := .intro
theorem noConfusionType : True := .intro
theorem ctorIdx : True := .intro
theorem ofNat_ctorIdx : True := .intro
theorem toCtorIdx : True := .intro
theorem ofNat : True := .intro
theorem ctorElim : True := .intro
theorem ctorElimType : True := .intro
theorem inj : True := .intro
theorem injEq : True := .intro
theorem repr : True := .intro
theorem decEq : True := .intro
theorem noConfusion : True := .intro
theorem casesOn : True := .intro
theorem recOn : True := .intro
theorem below : True := .intro
theorem brecOn : True := .intro
theorem congr_eq_1 : True := .intro
theorem induct : True := .intro
theorem fun_cases : True := .intro
theorem eq_1 : True := .intro
theorem match_1 : True := .intro

end Plain

axiom HiddenAx.inj : False

private axiom privAx : False

axiom _internalAx : False

private def privHelper : Nat := 1

inductive Color where
  | red
  | green (n : Nat)
  deriving DecidableEq, Repr

inductive Tag where
  | a
  | b
  | c
  deriving DecidableEq

inductive Rel : Nat → Nat → Prop where
  | step (n : Nat) : Rel n (n + 1)
  | trans {a b c : Nat} : Rel a b → Rel b c → Rel a c

structure Box where
  val : Nat

mutual
  def mutEven : Nat → Bool
    | 0 => true
    | n + 1 => mutOdd n
  def mutOdd : Nat → Bool
    | 0 => false
    | n + 1 => mutEven n
end

theorem mutEven_zero : mutEven 0 = true := mutEven.eq_1

theorem mutOdd_zero : mutOdd 0 = false := mutOdd.eq_1

def wfDown (n : Nat) : Nat :=
  if h : n = 0 then 0 else wfDown (n / 2)
termination_by n

theorem wfDown_zero : wfDown 0 = 0 := by
  rw [wfDown.eq_1]
  rfl

def withWhere (n : Nat) : Nat := go n 0
where
  go : Nat → Nat → Nat
    | 0, acc => acc
    | k + 1, acc => go k (acc + 1)

theorem withWhere_go_zero (acc : Nat) : withWhere.go 0 acc = acc := withWhere.go.eq_1 acc

partial def partLoop (n : Nat) : Nat := partLoop n

private partial def privPartLoop (n : Nat) : Nat := privPartLoop n

def usesPrivPart (n : Nat) : Nat := privPartLoop n

end MitosGate.LockFixture
