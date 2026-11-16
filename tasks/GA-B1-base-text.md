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
The design judge and the required Opus trust verifier are unavailable in this environment; these Codex opinions do not replace those model requirements.

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
- Core `lake check`, `lake comparator --paranoid`, toy acceptance, and the full cheat corpus were attempted locally. Nested namespaces fail on a read-only uid map. An escalated core check reaches bubblewrap but fails because `/run/user` is absent under its read-only root. No sandbox or checker setting was changed. CI must supply those results.
- Build timing runs are in progress. They alternate five matched affected-module rebuilds per side and retain unrelated compiled artifacts. They measure compilation and linking through `lake build mitos-gate`, rather than a cold full build or a warm no-op.

## Done when

- [ ] All applicable checks pass locally or have a recorded environment limitation and a passing CI check.
- [x] All five generic statements are proved with no sorry or new axioms.
- [x] Old and new helpers produce identical outputs for the recorded short-input characterization.
- [x] The unchanged shard CLI script passes.
- [x] The new attempt record is added under ops/runs/.
- [ ] The user and CodeRabbit review comments are answered at the PR head.
