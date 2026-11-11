namespace MitosGate.Accept

inductive GateId
  | provenance | lint | sandbox | statements | axioms | kernels | adequacy
  deriving DecidableEq, Repr

def GateId.num : GateId → Nat
  | .provenance => 0 | .lint => 1 | .sandbox => 2 | .statements => 3 | .axioms => 4
  | .kernels => 5 | .adequacy => 6

def GateId.name : GateId → String
  | .provenance => "provenance" | .lint => "lint" | .sandbox => "sandbox build"
  | .statements => "statements" | .axioms => "axioms" | .kernels => "kernels"
  | .adequacy => "model adequacy"

inductive Cause
  | judged
  | ioError
  deriving DecidableEq, Repr

def GateId.all : List GateId := [.provenance, .lint, .sandbox, .statements, .axioms, .kernels, .adequacy]

theorem GateId.mem_all (g : GateId) : g ∈ GateId.all := by cases g <;> simp [GateId.all]

example : GateId.all.map GateId.num = List.range 7 := rfl

def GateId.label (g : GateId) : String := s!"GATE {g.num} {g.name}"

end MitosGate.Accept
