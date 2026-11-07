import Mitos.Proofs.Resolve.Edges
import Mitos.Proofs.Resolve.Assumptions
import Mitos.Proofs.Impact

/-!
# Solution module for `Challenge.Resolver`

`lake comparator` (configured by `core/comparator.json`) checks that this module's environment
provides every name the Challenge declares, with the same statements, as kernel-checked terms
using standard axioms only. The definitions and proofs live in the imported modules:

| Challenge name                | proved in                              | task   |
|-------------------------------|----------------------------------------|--------|
| `resolve_sound`               | `Mitos.Proofs.Resolve.Edges`           | P1-002 |
| `resolve_complete`            | `Mitos.Proofs.Resolve.Edges`           | P1-002 |
| `resolve_unresolved_exact`    | `Mitos.Proofs.Resolve.Edges`           | P1-002 |
| `resolve_total`               | `Mitos.Proofs.Resolve.Edges`           | P1-002 |
| `resolve_assumptions_exact`   | `Mitos.Proofs.Resolve.Assumptions`     | P1-003 |
| `resolve_status_honest`       | `Mitos.Proofs.Resolve.Assumptions`     | P1-003 |
| `resolve_retract_exact`       | `Mitos.Proofs.Resolve.Assumptions`     | P1-003 |
| `impact_correct`              | `Mitos.Proofs.Impact`                  | P1-004 |
-/
