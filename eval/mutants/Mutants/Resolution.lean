/-!
# How Lean resolves a name in a generated statement

`Mutants.Challenge` declares every theorem it generates with `_root_.` and writes every name in it as
`_root_.<name>`, so that no declaration of a case can stand in for an approved one. That rests on
how Lean resolves names, which these declarations check whenever the package builds, so a toolchain
that changes it (the nightly canary builds this package with the next one) fails here.

Below, `Spec.X` is the approved name, with value `2`, and each shadow has value `1`:

- a theorem with a dotted name is elaborated inside that namespace, so a plain name finds the shadow
  `<namespace>.<name>` first (`in_namespace_plain`), and so does a `_root_.` name, through a
  declaration with a `_root_` component (`in_namespace_root`). So `_root_.` alone is not enough, and
  the lint refuses `_root_` inside any name a case declares;
- a theorem declared with `_root_.` is elaborated in the root namespace, where a dotted name is
  looked up exactly (`at_root_plain`), and a `_root_.` name too (`at_root_root`), which the runner
  uses.
-/

namespace Mutants.Probe

def Spec.X : Nat := 2

end Mutants.Probe

def Mutants.Probe.Refute.Mutants.Probe.Spec.X : Nat := 1
def Mutants.Probe.Refute.«_root_».Mutants.Probe.Spec.X : Nat := 1

theorem Mutants.Probe.Refute.in_namespace_plain : Mutants.Probe.Spec.X = 1 := rfl
theorem Mutants.Probe.Refute.in_namespace_root : _root_.Mutants.Probe.Spec.X = 1 := rfl
theorem _root_.Mutants.Probe.Refute.at_root_plain : Mutants.Probe.Spec.X = 2 := rfl
theorem _root_.Mutants.Probe.Refute.at_root_root : _root_.Mutants.Probe.Spec.X = 2 := rfl
