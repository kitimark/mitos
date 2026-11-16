# GA-B1: structural text helpers

phase: gate architecture
goal: Gate callers share one kernel-reducible text module with proved specifications.
statement: none (tooling task)
touches: gate/MitosGate/Base/Text.lean, gate/MitosGate/DecideText.lean, gate/MitosGate/DecideList.lean, gate/MitosGate/CheatsPlan.lean, gate/MitosGate/CheatsShard.lean, gate/MitosGate/CheatsFixture.lean, gate/MitosGate/CheatsRecord.lean, gate/MitosGate/Imports.lean, gate/Main.lean, gate/imports-test.sh
must_not_touch: statements.lock, models.lock, core/, eval/, .github/, .claude/, .cursor/, plan/
checks: build, imports, imports-test, lock, core-check, comparator-paranoid, accept-toy, cheats, lint-test, cheats-shard-test
budget: 40 iterations · 2h wall
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

[Issue #346](https://github.com/kitimark/mitos/issues/346) is part of
[the gate architecture tracker](https://github.com/kitimark/mitos/issues/372).
The owner's follow-up also requires checking the optional Base root module and pinning rejected import lookalikes.

## Design

depth: build; the signatures and generic proofs compile on Lean v4.35.0.
revisit_when: none
modules:
- `Base/Text.lean` owns structural text operations, their specifications, and short kernel fixtures. About 210 lines, following the local Cheats definition/proof layout.
- `DecideText.lean` is deleted. `DecideList.lean` retains only the list operations and their existing proofs.
- The four Cheats callers keep their existing responsibilities and import the new text owner.
- `Imports.lean` owns parsed import checks. `Main.lean` wires both Base locations into the CLI check.
- `imports-test.sh` owns real CLI regression cases for allowed and rejected imports.

types: Primitive text is `List Char`. Split parts are `List (List Char)`. String wrappers adapt existing callers without normalizing text.
statements: `join_split`, `sep_not_mem_split`, `parseNat_repr`, `isPrefix_iff`, `hasSub_iff`.
reuse: Generalize the reverse-accumulator LF proofs in Cheats. Reuse Init's decimal representation, prefix, and infix lemmas.
fixtures: empty and adjacent/trailing separators, Unicode, ASCII decimal rejection and leading zeros, prefix/infix edges, CR preservation, space/tab token boundaries, Base root and import lookalikes.
cut_line: Replace the legacy text owner and the text half of DecideList. Check the optional Base root as well as its directory.
deferrals: Other line splitters remain in #351, other number parsers in #352, and the list half in #350. A behavior lint for Base IO is outside this change; the module contract states the pure Base rule.
owner_decisions: The user merges this trust-critical PR. No spec path changes.

### Caller usage

```lean
import MitosGate.Base.Text
open MitosGate.Base.Text

example : splitStr '/' "1/3" = ["1", "3"] := by decide +kernel
example : parseNatStr "03" = some 3 := by decide +kernel
```

`parseNat` takes a character list. `parseNatStr` preserves the old string parser contract.
Empty input is rejected, and every accepted character is an ASCII decimal digit.
The splitter preserves empty parts. LF lines preserve CR.
`dropTrailNL` removes trailing LF only, and `firstToken` splits only on space and tab.

### Synthesis decision

Two independent Codex designers compared a reverse-current-part accumulator with the legacy suffix-first splitter.
The suffix-first alternative keeps the old body but retains an unreachable empty recursive result branch.
The accumulator removes that branch and directly generalizes the existing reconstruction and separator-exclusion proofs.
Both designers recommended it. The root selected it and adopted the second designer's shared file-check operation for the import fence.
The design judge and Claude model aliases are unavailable in this Codex environment. These design opinions do not replace independent trust review, including the required Opus verifier.

Keep the allowed Base root and scan its source with the same policy as its descendants.
Rejecting the root would require another name-policy exception.
Checking the optional file reuses the parser and closes the demonstrated transitive escape without changing allowed imports.

## Evidence

- `lake build`, `lake exe mitos-gate imports`, and `lake exe mitos-gate lock --check` pass.
- `gate/imports-test.sh` passes all 15 CLI cases. The old binary accepted a forbidden root import with zero violations; the new binary rejects it with the root file and line.
- `lake exe mitos-lint-test` passes all 190 cases outside the command sandbox. Inside it, six child-namespace cases fail before their fixtures start.
- `gate/cheats-shard-test.sh` passes unchanged. Run-log validation passes against main's records.
- A local characterization compares 400 inputs of at most three characters over seven characters, plus 57 patterns against all 400 inputs. All 23,200 output rows match exactly before and after. The shared SHA-256 is `e08d2e9004053d6ba9b7a40b0e0a6b108ebd4e975d328cf6a807524312e64d6a`.
- The five generic specifications and the short kernel fixtures compile using implicit Init alone.
- Core `lake check`, `lake comparator --paranoid`, toy acceptance, and the full cheat corpus were attempted locally. Nested namespaces fail on a read-only uid map. An escalated core check reaches bubblewrap but fails because `/run/user` is absent under its read-only root. No sandbox or checker setting was changed. CI must supply those results. At head `6c28981`, its core check and paranoid comparator steps passed; full corpus and final-head results remain on the PR checks.

### Build timing

No measurable change in the affected-module rebuild time was found.
The median was 36.370 seconds before and 36.744 seconds after, with five alternating runs per side.
The ranges overlap, from 35.348 to 39.760 seconds before and 35.269 to 39.159 seconds after.
Every timed build exited successfully and compiled and linked the gate.

| Pair | Before, seconds | After, seconds |
| --- | ---: | ---: |
| 1 | 36.370 | 36.744 |
| 2 | 36.546 | 39.159 |
| 3 | 39.760 | 35.269 |
| 4 | 36.054 | 35.613 |
| 5 | 35.348 | 37.702 |

Each run executes `lake build mitos-gate` after removing the Lean and C build artifacts for DecideList, CheatsShard, CheatsRecord, CheatsPlan, CheatsFixture, Imports, and Main.
The baseline also invalidates DecideText, while the candidate invalidates Base.Text.
Each run removes the gate executable as well. Unrelated gate and core artifacts remain cached.
The baseline is `cdacf4e`, and the candidate's executable code is `6c28981`.
This measures a matched text-and-caller rebuild, not a cold full build or a warm no-op.
The initial baseline full build also passed, but its unrelated Snapshot fixtures make it unsuitable for comparison.

The affected rebuild logs show CheatsFixture as the longest compilation step.
CPU observations during compilation show Lean as the active CPU consumer.
The machine has five CPUs. No other task ran CPU-heavy checks during these timings.
The 0.374-second median difference is smaller than either side's run-to-run spread.

## Done when

- [ ] All applicable checks pass locally or have a recorded environment limitation and a passing CI check.
- [x] All five generic statements are proved with no sorry or new axioms.
- [x] Old and new helpers produce identical outputs for the recorded short-input characterization.
- [x] The unchanged shard CLI script passes.
- [x] The new attempt record is added under ops/runs/.
- [ ] The user and CodeRabbit review comments are answered at the PR head.
