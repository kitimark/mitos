# GA-W2: use decoded workflow placement (#367)

phase: 2
goal: Test land.yml output placement with the proved decoded-tree policy instead of a textual YAML scanner.
statement: none (workflow test integration; reuses Workflow.placementOk_iff and Workflow.placement_sound)
touches: .github/scripts/land-decide.test.sh, this task, a new ops/runs record
must_not_touch: core/, locks, gate/, eval/, workflows, plan/
checks: native build, land-decide suite, workflow suite, shellcheck, imports, lock, runlog
budget: 40 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Design

Implements [#367](https://github.com/kitimark/mitos/issues/367) after #359 landed. The owner
picked option 1 on #336: retain the placement claim and replace its scanner after the proved
checker lands. Main has no scanner, so this is a narrow integration PR into #336's feature
branch. It must enter #336 before #336 can enter main. It is not a GitHub stack: merging a
stack's bottom first would expose the known old scanner bypass. No merge is performed here.

The parent was rebased from `e91b849` to `d7ed9ae` on main, without conflicts. The original
and rebased feature diffs have identical `git patch-id --verbatim` output. Every check survives.

`land-decide.test.sh` uses its existing freshly built `mitos-gate` for one placement check on
the real workflow. The awk `outputs_are_data` implementation is removed. Existing unrelated
permission, event, concurrency and command pins stay unchanged. Every unsafe placement control
now appends a fixture job to a full copy of the live workflow and runs the same binary.
Positive miniature documents continue to isolate accepted scopes and quote styles.

### Original scanner controls

The former `output-scope-fixtures` group retains all eleven snippets, in their original order:

1. Step name with a direct output reference.
2. Step condition with an output reference.
3. `with.script` literal block with an output reference.
4. Script member access with whitespace after `needs`.
5. Script member access split across physical lines.
6. Folded step name with a split output reference.
7. Literal step name containing a hash and an expression.
8. Explicit-indentation literal step name (`|2-`).
9. Multiline quoted step name with a hash and an expression.
10. Case-varied `Needs [ 'decide' ] .Outputs` reference.
11. JavaScript template text disguising an `env` mapping inside a script scalar.

The former `quoted-scalar-fixtures` group retains the eleven unsafe quote disguises:
double and single quotes; `with.script`; escaped double quotes; doubled single quotes;
flow-map `run`; flow-map `with.script`; a `!!str` tag; a scalar on the following line;
an explicit `? run` key; and an escaped `r\u0075n` key. These remain negative controls.

Its twelfth original fixture, `env: INPUT: "two` followed by `lines"`, is valid environment
data and is now an explicit positive control. The old scanner rejected all multiline quotes
conservatively, while the already-approved decoded placement policy accepts this source.
This is a deliberate removal of a false refusal, not an unchanged old expectation. A paired
thirteenth fixture combines the same multiline environment data with `${{ env.INPUT }}` in
`run`; it must still be refused by rule X. No original fixture is dropped.

The existing accepted scope document still covers top-level, job and step environment values,
a folded environment scalar, and a multiline job condition. `quoted-safe.yml` still covers
quoted job conditions and environment values, shell quotes inside plain values, commas and
unfinished quotes inside plain values, escaped/doubled YAML quotes, and unfinished quote text
inside environment and script block scalars.

### Additional controls

`decoded-placement-mutations` adds shape A (a block-looking comment), B (a literal step name),
C (a lone CR), D (`\x6e`), D2 (`\x24`), E (environment indirection into `run`), an alias,
`toJSON(needs)`, `fromJSON(toJSON(needs))`, a computed member, `a#${{`, script indirection,
a bound environment anchor reused as `run: *answers`, and #341's multiline plain scalar case.
The controls assert refusal code, reason and empty stdout; source lines are exact wherever
the existing CLI supplies them. The original unsafe quoted fixtures often hit the reader's
under-indented continuation refusal, whose reason includes the parser's line number; the
flow-map and bound-anchor refusals supply a decoded path instead of a line.

There is one evidence-based correction to #367's requested expectation: #341 item 5 says a
future parsed-YAML check should accept its valid multiline plain scalar. The actual #359
reader already does. The exact safe `run: echo` / `[literal`, followed by
`run: echo , "unfinished`, is retained as a positive full-workflow control. The paired form
with `${{ env.X }}` in the multiline code value is explicitly refused by rule X at the scalar
header's exact source line. Reintroducing a text scanner merely to preserve the old false
refusal would conflict with the migration. The dangerous quoted-continuation controls stay
negative, and no reader policy or proof is changed.

## Validation

The native `lake build mitos-gate` passes (168 jobs). `land-decide.test.sh` passes all 25 groups:
37 full-workflow refusals cover 11 original output-scope snippets, 11 original unsafe quoted
snippets, the paired quoted code-site case, and 14 decoded-placement mutations. The live
workflow and four accepted control documents pass. The inherited workflow suite also passes
147 reader fixtures, 35 structure cases, 37 line-work cases, six live PyYAML comparisons,
52 placement mutations against two land workflows, ten accepted controls, IO and usage.

Shellcheck 0.11.0, actionlint 1.7.12 on the land workflow, `git diff --check`, imports,
the 207-declaration statement lock, and run-log checks pass. This PR adds no Lean source or
reader rule; the native build kernel-checks the inherited policy and fixture declarations.
The full core comparator and cheat corpus are left to the existing CI jobs, not claimed as
local runs of this script-only migration.

The script change relative to rebased #336 is +132/-73 (net +59). The issue's rough -300/+60
estimate did not match the actual 61-line scanner plus existing controls at `e91b849`.
The original heredocs stay inspectable, and the added diagnostic assertions and new controls
account for the increase. The no-comments review of the narrow script diff accepted zero
flags or deletions; fixture hash text is required test data. CodeRabbit CLI
0.9.5 installed, but version/auth/login cannot create `~/.coderabbit` on the read-only home.
Remote PR bot review is separate. The requested Opus model is unavailable in this environment;
this trusted-path change remains held for an independent Opus-xhigh verifier and owner merge.
The author uses the inherited GPT-6 model (exact routed model ID unavailable).

#336's shadow entry criterion, positive R0b trial and its other verifier holds remain with #336.
This PR does not relax them.
