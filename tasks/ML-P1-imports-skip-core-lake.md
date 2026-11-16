# tasks/ML-P1-imports-skip-core-lake.md

phase: gate architecture milestone
goal: The import check skips Lake dependencies under core/.lake and still checks every core module.
statement: none (tooling task)
touches: gate/MitosGate/Imports.lean, gate/Main.lean (imports branch), gate/imports-test.sh, tasks/ML-P1-imports-skip-core-lake.md, ops/runs/<date>/ML-P1-imports-skip-core-lake-builder-1.json
must_not_touch: core/, statements.lock, models.lock, gate/MitosGate/Util.lean, eval/, .github/, plan/
checks: build, imports, imports-test, lock, lint test, core check, comparator --paranoid, accept-toy, cheats, runlog
budget: 20 iterations, 3h wall, 1.5M tokens
escalation: hint, automation, stronger model, pair, split, revisit statement

## Context

Issue #377, part of #372. Dependencies belong under `core/.lake`, outside the module globs
`Mitos.Core`, `Mitos.Core.+`, `Mitos.Impl.+`, `Mitos.Proofs.+`, and `Challenge.+`.

## Design

depth: build
revisit_when: none
modules: Imports.lean owns import traversal; Main.lean supplies the core-only exclusion; imports-test.sh checks the CLI.
types: Imports.check takes an optional List System.FilePath of directories to skip.
statements: none
reuse: System.FilePath.walkDir with an enter predicate; existing checkFile and test helper.
fixtures: excluded dependency, checked nested .lake, checked core violation beside an excluded dependency.
cut_line: Exclude exactly core/.lake from the core walk. Keep allowed imports and all other walks unchanged.
deferrals: Library import policy belongs to #379. Keep leanFiles and its callers unchanged.
owner_decisions: The owner merges this trust-infrastructure change.

## Verification

- Lean v4.35.0 builds the core and gate. `gate/imports-test.sh` passes all 37 cases.
  On the unchanged gate, the new suite has 35 passes and two failures: the dependency is
  checked, and the mixed fixture reports two violations. The nested `.lake` case passes on both.
- `lake exe mitos-gate lock --check` passes for 206 declarations and nine reached spec modules.
  `gate/MitosGate/Util.lean` and the core module globs are unchanged.
- A scratch checkout requires Batteries v4.35.0 at
  `66e469188fe07963e5cf666c7d4433f45b8131c5`, with `lake update` in core and the root.
  Both manifests list it. The unchanged gate reports 596 violations, all inside `core/.lake`.
  The changed gate reports zero and exits 0. An `openat` trace of the changed binary records
  zero opens under `core/.lake/packages/` and 29 core Lean-file opens. A dependency file
  with invalid UTF-8 also leaves the changed command at zero violations and exit 0.
- No-comments review found no added comments, suppressions, deletions, flags, or constraints.

### Performance

The complete warm `lake exe mitos-gate imports` command runs in separate checkouts of the same
base. Both use the same Lean release, core build artifacts, and normal Lake build settings.
Each side has one untimed warmup. Five alternating pairs exceed the issue's three-run minimum
and follow the benchmark skill's repeatability rule. Every run exits 0 with zero violations.
The machine has five CPUs and no concurrent builds during the measured runs.

| Pair | Before, ms | After, ms |
|---|---:|---:|
| 1 | 330.453 | 278.435 |
| 2 | 279.494 | 266.220 |
| 3 | 287.805 | 296.911 |
| 4 | 319.721 | 302.697 |
| 5 | 265.416 | 278.615 |

The median is 287.805 ms before and 278.615 ms after. The ranges are 265.416–330.453 ms and
266.220–302.697 ms. The median is within the 10% regression budget. The ranges overlap, so
this shows no measurable regression and supports no speedup claim. An untimed syscall profile
of the changed binary spends about 11 ms in syscalls; command setup and parser work dominate
the end-to-end time. This measurement covers a warm local run without a library, not cold CI.

### Environment limits

Local `lake check`, `lake comparator --paranoid`, toy acceptance, and the cheat corpus fail
because user namespaces cannot write their UID map in this environment. The lint executable
passes 184 of 190 cases; all six failures concern namespace-backed subprocess tests and report
the same read-only UID-map error. CI must check these paths in its supported sandbox.

The CodeRabbit CLI installer provides version 0.9.5, but `--version`, agent authentication status,
and agent login all fail with `EROFS: read-only file system, mkdir '/home/agent/.coderabbit'`.
The GitHub CodeRabbit review supplies the remote review; no local CLI review result is claimed.
The repository's required Opus verifier is unavailable here. The owner must hold the merge
until that verification and the trust-infrastructure review are satisfied.
