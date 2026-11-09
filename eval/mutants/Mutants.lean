import Mutants.Edit
import Mutants.Manifest
import Mutants.Challenge
import Mutants.Verdict
import Mutants.Implied
import Mutants.Lint

/-!
# Mutation testing of the resolver and impact analysis

The pure logic of `mitos-mutants` (`Main.lean`), with its proofs. The cases are in `cases/`; how a
case is judged is in `Mutants.Verdict`, and the case format in `Mutants.Manifest`.
-/
