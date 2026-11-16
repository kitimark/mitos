# GA-Y5 workflow tree

phase: gate architecture
goal: Own the workflow tree, scalar leaves, and acceptance rules without an L4YAML dependency.
statement: MitosGate.Yaml.Doc.mem_leaves_iff, Doc.leaves_paths_nodup, Doc.key_no_expr, MitosGate.Base.Text.count_eq_zero_iff
touches: gate/MitosGate/Base/Text.lean, gate/MitosGate/Yaml/View.lean, gate/MitosGate/Yaml/Line.lean, gate/YamlViewProperty.lean, gate/yaml-view-test.sh, this file, ops/runs/
must_not_touch: core/, statements.lock, models.lock, .github/, eval/, plan/, .claude/, .cursor/
checks: build, yaml-view-test, workflow-test, imports, lock, core-check, comparator-paranoid, lint-test, accept-toy, cheats, gate-shell-tests, axiom-audit, fixture-timing

## Design

depth: build
revisit_when: The tree API or its acceptance rules change.
modules: View imports only Base.Text. Line imports View to reuse the existing allowedChar symbol and make View part of the executable build. The property test runs through the existing gate/*-test.sh discovery.
types: Node stores ordered text, sequences, and mappings. Seg distinguishes keys and zero-based indexes. Scalar includes empty maps and sequences. Doc carries firstProblem? = none.
statements: Leaf membership is equivalent to scalar lookup. Accepted documents have unique leaf paths and expression-free keys. A nonempty pattern has zero occurrences exactly when hasSub returns false.
reuse: Base.Text.isPrefix and hasSub, the existing shell-test discovery, and the existing allowedChar contract.
cut_line: No YAML parser, reader, L4YAML import, placement policy, or selector policy.
owner_decisions: This is trust infrastructure. The owner merges, after the required independent and Opus xhigh verification.

The acceptance rules live in firstProblem? and its key helper. A mapping rejects ASCII-case-equivalent keys, expression tokens, merge keys, empty keys, and characters outside LF and printable ASCII. Text nodes reject the same forbidden characters. Keys are checked in mapping order before descendants. Child problems retain their complete path.

Traversal is structural, including the mutual list helpers, so literal fixtures reduce under kernel decide. Empty collections are leaves. Child segments identify the same ordered branches for lookup and leaves. Proofs derive child validity and segment uniqueness from the acceptance result before relating lookup to the traversal. The support proofs make View larger than the issue's approximate sketch.

## Verification

The independent property test uses seed 20261117 and 4,000 generated trees. It enumerates expected scalar paths directly from Node constructors, including collection nodes and absent, wrong-kind, and out-of-bounds paths. It compares the complete ordered leaves with that independent list, checks unique paths, and checks every scalar lookup. The run passed 116,130 lookups and 26,851 leaves, plus eight invalid-tree refusals.

Rerun it with `gate/yaml-view-test.sh`.

Three fresh elaborations of the complete View source, including every kernel fixture and proof, took 1.421 s, 1.428 s, and 1.452 s. The spread was 0.031 s. These whole-module measurements bound the fixture cost below the 10 s budget. The command was `lake env lean gate/MitosGate/Yaml/View.lean`, measured with Python time.monotonic.

All four statements compile without sorry. `#print axioms` reports only propext, Classical.choice, and Quot.sound for the three Doc statements, and only propext for count_eq_zero_iff.

The local core `lake check` and `lake comparator --paranoid` both stop before judging with `bwrap: setting up uid map: Read-only file system`. The container cannot create the required user namespace. CI retains the original sandbox and checks.

The requested no-comments pass found no added comments, suppressions, or reshape flags. No comments were deleted or restored.

The available model list does not include Opus. The implementation and available independent review do not claim the required Opus verdict. Hold the merge until that verdict exists.
