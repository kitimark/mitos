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
`jobs.*.steps[i].with.script`, including expressions that name no `needs`. The final action
input name is compared with ASCII case folding, so `SCRIPT` and `sCrIpT` also match. Supplying a value
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
workflows, 52 mutations with exact line/reason assertions, ten accepted controls, the escaped
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
| Baseline YAML + CLI | 4.754146, 4.053214, 3.792342 | 3.792342–4.754146 | 0.961804 |
| Head YAML + Placement + CLI | 8.455691, 6.956694, 6.888903 | 6.888903–8.455691 | 1.566788 |

After the action-input security fix, the median added elaboration is 2.903480 seconds.
Individual baseline `(YAML, CLI)` samples are (3.604005, 1.150141), (3.037318, 1.015896), (2.782168, 1.010174);
head `(YAML, Placement, CLI)` samples are (3.153926, 3.417399, 1.884367), (3.493551, 2.500096, 0.963047), (3.050032, 2.867362, 0.971508).

The requested no-comments pass accepted the source with zero deletions, flags, suppressions
or open constraints. CodeRabbit CLI 0.9.5 installed, but version/auth status/login all fail
before authentication with `EROFS: read-only file system, mkdir '/home/agent/.coderabbit'`.
XDG overrides do not change that location. A writable `~/.coderabbit`, followed by
`coderabbit auth login --agent`, is required for that local review; remote PR review is separate.
The independent Opus-xhigh verifier required for trust infrastructure is unavailable here;
this task does not authorize a merge or claim that verdict.

## Review fix: case-insensitive action input names

CodeRabbit reproduced `with.SCRIPT: ${{ github.event.comment.body }}` passing at `f1e5af3`.
The same native input exited 0 locally; adding the CLI regression before the fix made the
suite fail with that exit. This differs from workflow structural keywords: the runner's
[input handler](https://github.com/actions/runner/blob/main/src/Runner.Worker/Handlers/Handler.cs#L175)
uppercases action input names to `INPUT_*`, and the toolkit's
[getInput](https://github.com/actions/toolkit/blob/main/packages/core/src/core.ts#L151) does the same.

`codeAt` now folds only the final action input name. Lowercase `script` remains covered,
ordinary inputs remain outside the code set, and structural `jobs`, `steps`, `with` and `run`
keywords retain their exact spelling. Kernel controls pin all of those distinctions. Two
native cases on each land workflow use the verified github-script v7 commit
`f28e40c7f34bde8b3046d885e986cb6290c5673b`: uppercase `SCRIPT` with the comment body, and mixed
case with `${{ env.X }}` after an allowed environment value refers to `needs`. Neither script
value mentions `needs`, so these controls require rule X rather than rule N. The direct
reproducer now exits 1 with rule X at the actual sixth source line.

The related environment-only `INPUT_SCRIPT` route was also inspected. For github-script,
ActionManifestManager gives the declared script input an empty default, ActionRunner fills
absent inputs from those defaults, and the handler overwrites `INPUT_SCRIPT` with that input.
No additional environment-only github-script bypass was established. This is an inspection
of that action path, not a claim about arbitrary third-party action behavior.

The security-fix delta rebuild and full workflow suite pass, as do imports and the unchanged
statement lock. The requested no-comments delta pass reports zero comments, suppressions,
deletions, flags or open constraints. The security review thread is answered with the fixing
commit and left open for the owner under the repository's review policy.
