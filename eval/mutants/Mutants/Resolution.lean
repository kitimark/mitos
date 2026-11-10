namespace Mutants.Probe

def Spec.X : Nat := 2

end Mutants.Probe

def Mutants.Probe.Refute.Mutants.Probe.Spec.X : Nat := 1
def Mutants.Probe.Refute.«_root_».Mutants.Probe.Spec.X : Nat := 1

theorem Mutants.Probe.Refute.in_namespace_plain : Mutants.Probe.Spec.X = 1 := rfl
theorem Mutants.Probe.Refute.in_namespace_root : _root_.Mutants.Probe.Spec.X = 1 := rfl
theorem _root_.Mutants.Probe.Refute.at_root_plain : Mutants.Probe.Spec.X = 2 := rfl
theorem _root_.Mutants.Probe.Refute.at_root_root : _root_.Mutants.Probe.Spec.X = 2 := rfl
