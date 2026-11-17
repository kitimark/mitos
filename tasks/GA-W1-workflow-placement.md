# GA-W1: decoded workflow placement (#359)

phase: 2
goal: Refuse misplaced needs identifiers and expressions pasted into script values.
statement: Workflow.placementOk_iff, Workflow.placement_sound (gate policy; no locked specification changes)
touches: gate/MitosGate/Workflow/Placement.lean, gate/MitosGate/WorkflowCli.lean, gate/MitosGate/Yaml.lean (diagnostic helpers), gate/Main.lean (usage), gate/workflow-test.sh, gate/workflow-placement-check.py, gate/workflow-fixtures/placement-land-336.yml, this task, a new ops/runs record
must_not_touch: vendor bytes, reader admission/proofs, View, core/, locks, workflows, plan/
checks: build, workflow fixtures, imports, lock, runlog, vendor provenance, core check/comparator, lint, toy acceptance, cheats
budget: 40 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

Implements [#359](https://github.com/kitimark/mitos/issues/359), following the reader's owned
`Yaml.Doc` boundary from #354 and #399. Replacing #336's scanner remains #367.

## Design

`mentionsNeeds` scans ASCII identifier tokens (letters, digits and underscore), folds ASCII
letters, and compares whole tokens with `needs`. It therefore catches `NEEDS`, `toJSON(needs)`
and computed members while excluding `unneeds-x` and `needs_x`.

Rule N permits a matching decoded value only at `env.*`, `jobs.*.env.*`,
`jobs.*.steps[i].env.*`, `jobs.*.if`, or `jobs.*.needs` and its sequence elements. Paths are
exact; nested maps under an environment variable and step `if` values are outside that set.
Structural keywords use their lowercase workflow spelling. Job and variable names are wildcards.

Rule X refuses every `${{` token in `jobs.*.steps[i].run` and
`jobs.*.steps[i].with.script`, including expressions that name no `needs`. Supplying a value
through `env.X`, a step output or `$GITHUB_ENV` does not bypass the code-site rule. Ordinary
shell `$X` expansion remains accepted.

One `leafPlacementOk` predicate implements both rules. `placementOk_iff` proves that checking
all leaves is equivalent to both universal rules over `Doc.scalarAt?`. `placement_sound`
combines that equivalence with `read_conserves`: source expression count equals decoded leaf
expression count, all decoded text values obey both rules, and any source expression entails
an expression-containing decoded text value outside a code site. Its statement names only our
tree and text operations, never an L4YAML type.

The CLI calls the existing reader once, walks its leaves with that same predicate, and exits
0 on acceptance, 1 on a reader or placement refusal, and 2 on usage or IO failure. Rule N has
diagnostic priority when both N and X fail on the same leaf. Placement emits a single compact
line, path and reason and no stdout. Existing `parse` and `leaves` behavior is retained.

### Source locations

`Doc` deliberately has no source spans. Diagnostic-only helpers inside the existing YAML seam
rescan only a refused document. `textLines?` skips key and empty scalar tokens, requires complete
ordered equality between the remaining decoded values and nonempty text leaves, and zips their
paths with scanner start lines. Escapes, repeated values and folded/literal scalar headers keep
the scanner's positions. A failed scan or alignment leaves the refusal path without guessing a
line; it never changes acceptance. No vendor type appears in either helper's public signature.

For conservation refusals, a private helper compares each decoded scalar's expression count
with its raw source segment up to the next token, locating the first change. Alias diagnostics
use a positioned alias token or the scanner's undefined-alias error. Character/comment errors
retain their existing reader lines. Only the new `placement` verb adds these diagnostics;
`parse`, `leaves`, `read` and the reader proof bodies remain unchanged.

A raw decoded-text search is deliberately absent: an escaped run value can match an unrelated
comment. A regression asserts the escaped value's actual start line, while native seam controls
cover empty/null values, repeated flow values and alignment failure. These diagnostics are not
a formally proved source map; the acceptance theorems do not depend on them.

### Evidence boundary

Short `decide +kernel` examples cover identifier boundaries, the path policy, leaf policy, and
complete accepted/refused documents for the environment indirection case. Alias, D2 and `x6e`
decoding are exercised through the native reader in the CLI suite. They are not kernel reader
fixtures: a direct `decide +kernel` experiment stops reducing at `Yaml.read`.

The historical workflow fixture is the exact `.github/workflows/land.yml` from #336 head
`e91b849a20390d839d04baa82c8e85eb8d2f166e`. Keeping it in the repository makes the check independent
of the branch's later deletion or change. The suite accepts both this fixture and the live
workflow, then injects actual job code paths into both. Shapes A, B, C (CR/NEL/LS/PS), D, D2,
E, alias, computed members, `toJSON`, `fromJSON`, `with.script`, `a#${{`, literal/folded blocks,
step-output and environment indirection controls all assert refusal. Positive controls cover
each allowed site, dependency sequences, ordinary shell expansion and nonmatching identifiers.

## Validation

The native build passes. `gate/workflow-test.sh` preserves 147 reader fixtures, 35 structure
cases, 37 line-work cases and six PyYAML-equal live workflows. Placement passes both land
workflows, 48 mutations with exact line/reason assertions, ten accepted controls, the escaped
value/comment control, missing-file handling and usage errors. Both new theorems depend only
on `propext`, `Classical.choice` and `Quot.sound`.

Imports, the 207-declaration statement lock, run-log validation and vendor provenance pass.
Core replay/comparison and toy acceptance stop at `bwrap: setting up uid map: Read-only file
system`. Six of 190 lint cases and the 104 cheat runs likewise cannot start their user
namespaces; they are not reported as passing. Sandbox checks are retained.

Three paired fresh elaborations of the affected source modules used `lake env lean <file>`,
default flags, Lean 4.35.0, cached dependencies and no concurrent builds. Baseline sources are
copied from `66cfa0d` with `git show`; the same head dependency cache serves both sides. This
measures source elaboration, including examples and audits, not a clean native rebuild.
`Main`'s usage-string-only edit is outside this timed scope.

| Scope | Trial seconds | Range | Spread |
| --- | --- | --- | --- |
| Baseline YAML + CLI | 3.708281, 3.494014, 3.331532 | 3.331532–3.708281 | 0.376748 |
| Head YAML + Placement + CLI | 5.769550, 5.870484, 5.752133 | 5.752133–5.870484 | 0.118350 |

The median added elaboration is 2.275536 seconds. Individual baseline `(YAML, CLI)` samples
are `(2.884459, 0.823821)`, `(2.681714, 0.812300)`, `(2.522541, 0.808992)`; head
`(YAML, Placement, CLI)` samples are `(2.749366, 2.147762, 0.872421)`,
`(2.899492, 2.164932, 0.806059)`, `(2.822884, 2.057576, 0.871673)`.

The requested no-comments pass accepted the source with zero deletions, flags, suppressions
or open constraints. CodeRabbit CLI 0.9.5 installed, but version/auth status/login all fail
before authentication with `EROFS: read-only file system, mkdir '/home/agent/.coderabbit'`.
XDG overrides do not change that location. A writable `~/.coderabbit`, followed by
`coderabbit auth login --agent`, is required for that local review; remote PR review is separate.
The independent Opus-xhigh verifier required for trust infrastructure is unavailable here;
this task does not authorize a merge or claim that verdict.
