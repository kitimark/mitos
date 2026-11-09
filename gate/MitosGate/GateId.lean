namespace MitosGate.Accept

/-- The gates `mitos-gate accept` runs, in the order it reports them (`docs/process.md`, "The
acceptance gate"). -/
inductive GateId
  | provenance | lint | sandbox | statements | axioms | kernels | adequacy
  deriving DecidableEq, Repr

/-- The gate's number, as `docs/process.md` and the verdict line give it. -/
def GateId.num : GateId → Nat
  | .provenance => 0 | .lint => 1 | .sandbox => 2 | .statements => 3 | .axioms => 4
  | .kernels => 5 | .adequacy => 6

/-- The gate's name, as its lines print it. -/
def GateId.name : GateId → String
  | .provenance => "provenance" | .lint => "lint" | .sandbox => "sandbox build"
  | .statements => "statements" | .axioms => "axioms" | .kernels => "kernels"
  | .adequacy => "model adequacy"

/-- Every gate, in order. -/
def GateId.all : List GateId := [.provenance, .lint, .sandbox, .statements, .axioms, .kernels, .adequacy]

theorem GateId.mem_all (g : GateId) : g ∈ GateId.all := by cases g <;> simp [GateId.all]

example : GateId.all.map GateId.num = List.range 7 := rfl

/-- How the gate's lines start, such as `GATE 2 sandbox build`. -/
def GateId.label (g : GateId) : String := s!"GATE {g.num} {g.name}"

end MitosGate.Accept
