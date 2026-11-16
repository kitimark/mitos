# tasks/ML-A1-proof-import-scopes.md

phase: gate architecture milestone
goal: Only core proofs may import Mathlib, and the import rule checks every gate source.
statement: none (tooling task)
touches: gate/MitosGate/Imports.lean, gate/Main.lean, gate/imports-test.sh, docs/process.md, tasks/ML-A1-proof-import-scopes.md, ops/runs/<date>/ML-A1-proof-import-scopes-builder-1.json
must_not_touch: core/, statements.lock, models.lock, eval/, .github/, plan/, gate/MitosGate/Util.lean, gate/MitosGate/Lint.lean, gate/MitosGate/Accept.lean
checks: build, imports, imports-test, lock, lint test, core check, comparator --paranoid, accept-toy, cheats, runlog
budget: 20 iterations, 3h wall, 1.5M tokens
escalation: hint, automation, stronger model, pair, split, revisit statement

## Context

Issue #379 follows #377. The owner picked option (b), including (a), on #342. This change
implements the proof-only import policy. Resolver-spec imports remain for #392.

## Design

depth: build
revisit_when: none
modules: Imports.lean owns one ordered path-scope table and traversal; Main.lean runs both walks and describes the policy; imports-test.sh pins CLI behavior; process.md records the check.
types: Scope has a component-matched path, allowed import roots, and an exact-file flag. allowedFor chooses the first matching row, with no allowed roots when none matches.
statements: none
reuse: Existing header parser, component-based import-root check, exact core/.lake exclusion, Base policy, vendor policy, and seam scan.
fixtures: Mathlib allowed in Proofs and rejected in every other core scope; forbidden direct Lean, Batteries, and MathlibX imports; ProofsX lookalike; non-Proofs imports of Mitos.Proofs; gate files at both depths; vendor, Base, and exact seam regressions.
cut_line: Permit Mathlib only under core/Mitos/Proofs, prohibit Mitos.Proofs elsewhere in core, and check every gate source. Preserve the narrower Base rules and the vendored parser and exact YAML seam exceptions.
deferrals: Spec library imports belong to #392. A tracked core/.lake check is deferred to #380 in the #411 verifier catch-up. No dependency pin or proof rewrite belongs here.
owner_decisions: The owner merges this trust-infrastructure change. The Opus-xhigh verification required by #379 is unavailable in this environment and remains a merge hold.

The ordered table selects the locked spec before other core paths, Proofs before other core paths,
and Base, the vendor, and the exact seam before other gate paths. A scope compares complete path
components, so ProofsX is outside Proofs. Exact entries do not cover child directories.

Mathlib imports load Lean's meta code into proof elaboration. Kernel replay through `lake check`
and `lake comparator --paranoid` remains the trust guard. Direct Lean imports in core, plugin
import policy, the spec, the Challenge, and library pins remain unchanged.

## Verification

- Lean v4.35.0 builds the core and gate. The CLI import suite passes all 59 cases.
  The unchanged gate passes 49 and fails 10, with the historical summary restored in the test
  harness so the comparison tests behavior. Two failures also pin the new single diagnostic
  for a spec import that the old overlapping walks reported twice.
- `lake exe mitos-gate imports` exits 0 with exactly
  `0 import violation(s) in core/ and gate/`.
- `lake exe mitos-gate lock --check` passes for 206 declarations and nine reached spec modules.
- A supplemental gpt-6-astra-xhigh verifier passes 240 scope and header-parser probes and
  240 CLI probes at `5a0edf8`, with no blocking or minor findings. This does not replace the
  required Opus verifier.
- In a scratch checkout, Mathlib v4.35.0 is required in core, with
  `MATHLIB_NO_CACHE_ON_UPDATE=1 lake update` in core and the root. Both manifests contain
  Mathlib and its eight dependency packages. A proof importing `Mathlib.Data.List.Nodup`
  fails on the unchanged gate and passes on this gate. The same import in a gate file fails
  and names that file. An `openat` trace of the new binary reads no source under `core/.lake`.
- `bash -n gate/imports-test.sh` passes. The run-log check passes before the push.

### Performance

The full warm `lake exe mitos-gate imports` command runs in checkouts of the same base, with
one untimed warmup per side and five alternating pairs. Each timed run exits 0, prints the
expected zero-violation summary, and writes no stderr. Both builds use the same Lean release
and normal Lake settings. No build runs during measurement. The machine has five CPUs.

| Pair | Before, ms | After, ms |
|---|---:|---:|
| 1 | 207.665 | 228.396 |
| 2 | 282.833 | 248.960 |
| 3 | 219.542 | 227.791 |
| 4 | 217.456 | 228.953 |
| 5 | 198.850 | 218.079 |

The medians are 217.456 ms before and 228.396 ms after, a 5.0% increase within the 10%
budget. The ranges are 198.850 to 282.833 ms and 218.079 to 248.960 ms. These overlapping
ranges support no stable speed difference. The changed command also checks 56 gate headers
that were previously unchecked. An untimed syscall profile shows Lake's process coordination,
filesystem metadata, and file reads on this path, including 1,859 metadata calls and 723 opens.
This measures a warm local command, not cold CI or Mathlib elaboration.

### Environment limits

Local `lake check`, `lake comparator --paranoid`, and toy acceptance fail because user
namespaces cannot write their UID map. The cheat runner reports no verdict because `unshare`
hits the same read-only UID-map error. The lint executable passes 184 of 190 cases. Its six
failures concern namespace-backed subprocess tests and report that same error. CI must verify
these checks in its supported sandbox.

The CodeRabbit CLI is version 0.9.5, but its version, agent authentication status, and agent
login commands all fail with `EROFS: read-only file system, mkdir '/home/agent/.coderabbit'`.
No local CLI review result is claimed. The GitHub PR supplies the remote review.

The root's no-comments pass reviewed the four implementation files at `5a0edf8`. It found no new
comments, suppressions, section banners, constraints, deletions, restorations, reruns, or flags.
No fixes, encodings, or open constraints resulted.
