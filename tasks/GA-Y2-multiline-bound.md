# GA-Y2: multiline source admission (#431)

phase: 2
goal: Refuse excessive raw line-prefix work before vendor work and qualify the admitted frontier.
statement: none (owned gate policy; no locked meaning changes)
touches: gate/MitosGate/Yaml.lean, gate/workflow-check.py, gate/workflow-fixtures/line-work.yml, gate/workflow-fixtures/cases.json, gate/workflow-resource-benchmark.py, tasks/GA-Y2-multiline-bound.md, tasks/GA-Y2-multiline-checks.json, tasks/GA-Y2-yaml-read.md, tasks/GA-Y2-workflow-cli.md, ops/runs/2026-11-17/GA-Y2-431-builder-1.json
must_not_touch: vendor bytes, core/, locks, plan/, workflows, View, CLI
checks: native behavior, seeded differential, resource qualification, build, imports, lock, core check/comparator, lint, toy acceptance, cheats
budget: 40 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit design

Part of [#354](https://github.com/kitimark/mitos/issues/354), closing
[#431](https://github.com/kitimark/mitos/issues/431). The scalar, root and document-marker
families also address [#437](https://github.com/kitimark/mitos/issues/437) m1/m2.
General duplicate-key optimization remains #413 m2; benchmark process portability remains #437 m3.
Historical #420 samples in `GA-Y2-resource-checks.json` are unchanged.

## Design

depth: build; private byte-prefix counter, allowance, owned refusal, guard and audited theorem
revisit_when: any finite scalar/marker-frontier trial exceeds the CPU/RSS gate below

Callers continue using `Yaml.read source : Except Refusal Doc` once. The CLI continues using
`mitos-gate workflow parse|leaves file`. Accepted documents have the same decoded leaves.
After earlier guards pass, a source whose cumulative line-prefix work exceeds 16,777,216
returns `.lineWork fullCount`; both verbs exit 1, produce no stdout and render
`: refused: cumulative line-prefix bytes {fullCount} exceeds 16777216`.

For one-based raw UTF-8 byte offsets, W is the sum of offsets ending in LF. One linear
`ByteArray.foldl` keeps offset and total; it never materializes prefixes. The counter's byte
unit is unconditional, including before the ASCII guard, although the guard still runs first.
LF in quotes, escaped continuations, block data, comments, blanks, nonmapping roots and
repeated document-end markers all contributes. An unterminated last line adds no new term.

The owned seam gains private `maxLineWork : Nat := 16777216`,
`sourceLineWork : String → Nat`, and audited
`read_lineWork : read src = .ok d → sourceLineWork src ≤ maxLineWork`.
The only new public type surface is `Refusal.lineWork (prefixBytes : Nat)`. `parseDoc` checks it
immediately after directive and structural admission, before `scanWithComments`. The existing
`read`, `read_size`, `read_chars` and `read_conserves` statements and bodies stay unchanged.
The new theorem follows `read_structure` and joins the axiom audit. It proves admission, with
no claim about vendor runtime or YAML correspondence. Vendor bytes and provenance stay unchanged.

The preserved priority is bytes, characters, openers, source directives, structural characters,
then cumulative line-prefix work, then scanner/parser, subset qualification, owned validation,
comments and conservation. All admission stays behind the existing one-call interface; there
is no extra public option, intermediate source type, scalar-style lexer or caller-side counter.

| Module | Owned topic and change | Existing layout reused |
| --- | --- | --- |
| `Yaml.lean` | Private source policy, owned error and proof; about 35 added lines | structure allowance and audit |
| `workflow-check.py`, fixture/cases | Native both-verb work boundary and priority regressions | structure case table and `check` |
| `workflow-resource-benchmark.py` | Named frontier sources and checked fresh-process evidence | `workloads`, oracle and `wait4` |
| This note and `GA-Y2-multiline-checks.json` | Design and raw qualification evidence | historical resource note/artifact |
| Existing reader/CLI task notes | Minimal current-contract links; history retained | prior #420 entry |

## Synthesis and resynthesis

Two structurally distinct candidates were compared: raw LF≤1,024 and cumulative raw-prefix
positions at LF≤16 MiB. The root initially selected LF for its explicit caller-visible unit
and smaller policy surface. The root's five rubric scores were A 5/5/5/5/4 and B 5/5/4/4/5
(coverage, invariants, interface/policy, compatibility, falsifiable qualification). Both keep
vendor work behind the boundary and preserve the existing invariants. The cross-judge accepted
A with B's finite resource gate grafted below.

A was rejected by that gate: clean long-first-line double-quoted input, 65,536 bytes and 1,024
LF, used 2.232004 seconds child CPU on trial five (2.235700 wall; 99,836 KiB native RSS).
Its five CPU samples span 1.399545–2.232004 seconds, median 1.464599. Work stopped immediately.
The initially uniform 245,748-KiB RSS samples were contaminated by the Python oracle parent's
resident highwater, as a controlled inflated-parent experiment confirmed; they are retained
separately and are not native RSS evidence. The fresh measurement helper execs a small process,
then `wait4` measures only its native child. An independent GNU time check reports 102,400 KiB
for the double-quoted input, consistent with the clean helper's 99,680–102,700 KiB range.

The root then replaced A entirely with B's one prefix-work guard. There is no additional LF
limit. B directly bounds repeated raw-prefix geometry; simply guessing a lower LF allowance
would retain substantial cost variation and reduce compatibility. Short documents with more
than 1,024 LF deliberately remain admissible. The byte-prefix counter adds an accumulator
and a less familiar error unit, accepted in exchange for discriminating long early content
from cheap short lines. Current ci.yml has W=8,094,495, leaving about 2.07× work headroom
under 16,777,216; its 25,576 bytes and 604 LF remain accepted.

The byte-prefix proxy conservatively charges unrelated earlier comments and scalars. It is
neither an allocation count nor a vendor complexity theorem. A post-parse check cannot protect
the scanner; a vendor optimization changes the approved pin and is outside this scope.
The design screen found no second admission path, exposed vendor representation, new module,
pass-through interface, shared writable cache or meaning held only in comments. The named
refusal, theorem and exact native cases encode the rule.

## Decision recorded before measurements

Expected claim: the new policy rejects the reported multiline and marker families before
scanning; on the named host, the measured admitted boundary families have the recorded
wall/CPU/RSS distributions. This is not a universal two-second or memory bound.

The finite scalar-frontier qualification gate is **every trial child CPU≤2 seconds and peak
RSS≤262,144 KiB**, with all expected exits and outputs checked. It includes root scalars and
document-end families that pass source admission but are rejected after scanning. If any
trial exceeds either gate, stop adding code or pushing and return the exact evidence to the
root for resynthesis. Do not weaken the targets after observing samples. Collection and
duplicate-key costs remain separately named, without a reader-wide two-second claim.

Build the production native executable first; no builds or unrelated tests overlap timing.
Qualify every accepted ordered leaf against PyYAML 6.0.3, using explicit deep paths where
necessary, and every refusal against exact stderr/exit/no-stdout. Measure at least five fresh
children per family, alternating forward/reverse order. Retain all wall, child CPU and per-child
RSS samples, medians/ranges, source byte/LF/structure counts, hashes, toolchain and host limits.
Record load and inspect a separate unreported trace for a slow frontier. CPU near wall plus
low syscall time establishes CPU work; without a stable profile do not present a guessed source
hotspot as measured attribution. A difference smaller than run spread is not a speedup.

## Evidence

A's test-first 1,025-LF fixture was accepted by baseline through both verbs. B's exact
W=16,777,217 fixture then fails against A through both verbs: it produces the old 5,788-LF
refusal rather than the new cumulative-work refusal. Its W−1 and W controls must accept with
one exact `a: x` leaf. No huge historical baseline is replayed.

The final 6,491-byte fixture has 5,788 LF and W=16,777,217. Main `305e3f3`'s native binary
accepts it through both verbs; `leaves` returns exactly `a: x`. The final binary refuses it
through both verbs with the exact cumulative-work diagnostic and no stdout. The W−1 and W
controls accept. All 147 fixtures (146 retained plus this one), unchanged 35 structure cases
and 37 line-work cases pass, including earlier-priority collisions and post-scan controls.
All six current workflows keep their PyYAML-equal leaf counts: ci 247, nightly 55,
clear-needs-rebase 15, land-protection 29, land 50 and update-prs 27. The unchanged seeded
700-mutation differential keeps 250 accepts/450 refusals with no leaf mismatch or PANIC.

The complete native resource matrix qualifies 90 families and measures five fresh children
per family, 450 trials total, with zero status/output failures. Every scalar/marker-frontier
trial passes the predeclared CPU/RSS gates. Full sources retain byte/LF/W/structure counts;
accepted leaves match PyYAML or explicit deep-path expectations. Historic huge attacks are
only run against the guarded binary. Several old mapping/comment/blank/multiline controls
now deliberately receive line-work refusals. Rejection time is not parser acceleration.

| Family | Median wall seconds (range) | Median child CPU seconds (range) | Maximum native RSS, KiB |
| --- | ---: | ---: | ---: |
| 65,536-byte double quote, 257 LF, W=16,743,808 | 0.400030 (0.395902–0.440345) | 0.396473 (0.391618–0.436436) | 104,436 |
| 65,536-byte plain scalar, 257 LF, W=16,744,064 | 0.073284 (0.068325–0.079588) | 0.070328 (0.065202–0.077563) | 135,976 |
| Compact depth 2,047 plus 2,046 document ends | 0.381890 (0.375488–0.513296) | 0.378579 (0.370450–0.507467) | 164,972 |
| Existing 65,536-byte compact frontier | 0.243896 (0.231061–0.256717) | 0.238104 (0.227583–0.251910) | 166,504 |
| Current ci.yml | 0.067335 (0.064801–0.080113) | 0.065103 (0.060693–0.073676) | 97,156 |

The largest observed trial is 0.513296 seconds wall / 0.507467 seconds CPU; the largest
observed RSS is 166,504 KiB. These are finite observations, not universal maxima. The host
has five logical CPUs, a four-CPU quota and a 16 GiB memory limit. The full measured runner
hash matches the checked-in runner. No builds or unrelated tests overlap timing. The helper's
startup and independent leaf qualification are outside the timed region; `wait4` records the
native child. A 220 MB parent-allocation crosscheck yields 94,560 KiB native RSS, versus
94,152 KiB from GNU time, so the oracle parent's highwater is excluded.

Separate unreported double/plain `strace -c` runs each have 130 syscalls, totaling 0.008514
and 0.011955 seconds. Native CPU close to wall and small syscall time support CPU-dominated
work. No sampled native-stack profile was collected, so scanner prefix rebuilding/retention
is source evidence rather than a measured hotspot attribution. Run spread does not support
a precise speedup claim. The [raw evidence](GA-Y2-multiline-checks.json) retains the rejected A
samples, their RSS caveat, initial B and full B samples, hashes, exact diagnostics and traces.

Build, imports, the 207-declaration statement lock and vendor byte/startup inventory pass.
Core replay, paranoid comparison, toy acceptance and the cheat corpus stop at read-only UID
maps. Lint passes 184/190; the remaining six cases have the same namespace failure. No sandbox
check is disabled. CodeRabbit CLI 0.9.5 is installed, but version/auth prerequisites fail with
`EROFS` creating `/home/agent/.coderabbit`; no CLI review ran. Remote PR review is separate.
The no-comments pass found zero added comments/docstrings and changed no source.
CodeRabbit then identified a recursive-alias hang in the new live-workflow oracle traversal.
A one-line native admission check now runs before composition: a temporary recursive-alias
workflow changes from a two-second timeout to a prompt failed check (0.224 seconds), and the
complete 147+35+37/live-leaf behavior suite still passes. The reader and resource runner are
unchanged; the retained resource samples remain tied to the measured pre-rebase executable.

Reproduce after building the native executable:

```bash
python3 gate/workflow-check.py .lake/build/bin/mitos-gate
python3 gate/workflow-differential.py --bin .lake/build/bin/mitos-gate
python3 gate/workflow-resource-benchmark.py --output /tmp/workflow-multiline-qualification
```

This implementation is GPT-6.1 xhigh work. Repository Claude model aliases are unavailable;
it is not an independent Opus verdict. The owner merges trusted paths and the required
independent Opus-xhigh verification remains a separate merge requirement.
