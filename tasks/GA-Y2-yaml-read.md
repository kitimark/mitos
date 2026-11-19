# GA-Y2: qualified workflow reader

Part of [#354](https://github.com/kitimark/mitos/issues/354). The implementation is split into a
reader PR and a CLI/regression PR so the new trust boundary can be reviewed separately.

## Shape

`MitosGate.Yaml.read` returns our `Doc`, or our `Refusal`. The only authored Lean module that
names the vendor is `gate/MitosGate/Yaml.lean`. After the source limits, it refuses every
column-zero `%` line, sources with more than 2,048 raw `-?:,[{` characters, and cumulative
line-prefix work above 16,777,216 bytes before calling the parser. The latter sums the one-based
UTF-8 byte offsets ending in LF; [#431's design and qualification](GA-Y2-multiline-bound.md)
records its conservative policy and finite resource evidence.
It scans with the raw comment side channel,
parses the serialization tree, qualifies tokens, converts it to our `Node`, validates `Doc`,
and compares source and leaf expression counts. It never composes aliases or uses a vendor theorem.

The seam uses nested structural recursion over values and their item/pair lists. Its termination
is checked by Lean. The three `read` statements are proved by cases over our checks and the opaque
result of `parseDoc`; their proofs do not unfold the vendor.

## Refusal table

| Input feature | Refusal | Why |
|---|---|---|
| More than 65536 UTF-8 bytes | `tooLarge` | Bound input size. This cap alone does not establish a practical time or memory guarantee. |
| Outside LF and printable ASCII | `char` | Exclude control and line-break disagreements before parsing. |
| More than 1024 `[` or `{` characters | `openers` | Bound flow nesting, including quoted openers. |
| More than 2048 raw `-`, `?`, `:`, `,`, `[` or `{` characters | `structureChars` | Bound admitted collection indicators before scanning. Quoted, comment and scalar data also count. |
| Cumulative one-based byte offsets ending LF exceed 16777216 | `lineWork` | Bound raw prefix geometry before scanning, after the earlier source guards. Every LF context contributes. |
| Scanner/parser failure | `parse` | Preserve the upstream rendered error. |
| Zero or multiple documents | `documents` | Give one root and avoid document-selection disagreement. |
| A source line starting with `%`, or a reported directive | `directive` | Exclude standard and reserved directives before the pin can discard them. |
| A root other than mapping | `rootNotMapping` | Workflows must be mappings. |
| Block header containing indentation digit | `blockIndicator` | Exclude compact-nest indentation disagreements. |
| Anchor, alias or tag | `anchor`, `alias`, `tag` | Exclude expansion and type resolution. |
| Complex or explicit key | `complexKey` | Explicit keys can disappear at this parser pin (#405). |
| Quoted or block key | `keyStyle` | Keep keys plain. |
| Nonempty flow mapping or nested flow list | `flow` | Exclude implicit-key collection interpretations. |
| Expression in a flow list scalar | `flow` | Keep expression-bearing flow collections out of the subset. |
| Plain flow scalar containing `?` or beginning `:` | `flow` | PyYAML interprets these as keys or rejects them. Quoted forms remain accepted. |
| Case-insensitive duplicate, expression/merge/empty key, decoded disallowed character | `view` | Enforced by our `Doc.ofNode`, with the first offending path. |
| Expression in raw scanner comment text | `exprInComment` | Avoid a separate source-comment grammar. |
| Source/leaf expression counts differ | `conserve` | Refuse expression creation or loss through decoding. |
| Repeated block chomping indicators | `parse` | This pin accepts malformed headers (#405). |
| Empty or all-LF block scalar | `parse` | This pin disagrees with YAML on empty block chomping (#405). |

Explicit simple keys and empty block scalars are conservative extra refusals. They occur in none
of the six accepted main workflows. The vendor is unchanged. Multi-document comment loss cannot
hide an expression because raw scanner comments are used and multiple documents are refused.
Primary tags are retained by the parser and refused by the seam, or rejected by the scanner.

## Proofs and audit

- `read_size`: an accepted source has at most `maxBytes` UTF-8 bytes.
- `read_chars`: every accepted source character satisfies `allowedChar`.
- `read_conserves`: the source `${{` count equals the sum of leaf expression counts.
- The private `read_structure` proves that an accepted source has at most `maxStructureChars`
  charged characters. It unfolds only owned checks and is included in the axiom audit.
- The private `read_lineWork` proves the cumulative byte-prefix allowance for accepted sources
  and joins the same audit. It makes no vendor runtime claim; the three public proofs are unchanged.
- The build audits these declarations and `Doc.ofNode` for only `propext`, `Classical.choice`,
  and `Quot.sound` axioms. It traverses types and bodies reachable from `read`, including private
  names, rejecting unsafe/partial declarations and `implemented_by`, `extern`, and compiler
  `csimp` substitutions within the `L4YAML.*` namespace. The one accepted `implemented_by` is
  the `ctorIdx` reader Lean itself attaches, from v4.36.0-rc1, to a multi-constructor inductive:
  the kernel term stays that inductive's `casesOn` index table, and the runtime term is the
  compiler's unsafe `getObjTagNat` reader from `Init.Prelude`. A same-named declaration in any
  other module is refused, including on the pinned toolchain, which has no such constant. A hand-written `implemented_by`, including one whose
  name and body imitate that reader, and one that copies the compiler's metadata but changes the
  runtime body or the kernel table, is still rejected. The check is not an inventory of
  arbitrary vendor namespaces, startup code, or later declarations. It checks declarations
  exported in `MitosGate.Yaml` for exposed `L4YAML.*` types.
- Real-parser guards cover the refusal constructors, escape table, multi-line scalars, all
  eight #405 cases, and two scan/parse composition drift cases. Alias refusal itself is guarded
  at the seam: the parser rejects undefined aliases, and a valid alias always follows an anchor
  that the source-order seam refuses first. A real-parser guard checks anchor/alias preservation.

## Design for #420

problem: Compact block sequences bypass the flow-opener cap and cause quadratic scanner work and retained parser paths. Wide mappings also cause quadratic owned validation work.
usage: Callers continue to call Yaml.read once and receive Doc or Refusal. Both workflow verbs return exit 1 with no leaves when source structure exceeds the allowance.
modules: Yaml.lean owns the private source counter, its limit and the owned refusal. workflow-check.py and workflow-fixtures own native behavior cases. workflow-resource-benchmark.py owns repeatable adversarial input generation and process measurements.
types: Refusal gains structureChars carrying the full raw count. The counter and maxStructureChars remain private, with no vendor types exposed.
statements: The existing read_size, read_chars and read_conserves statements and proof bodies stay unchanged. The private read_structure proves the owned source-count allowance for every accepted source. No theorem connects this count to vendor runtime complexity.
reuse: The new guard runs inside parseDoc, after the existing directive filter and before scanWithComments. Existing size, character, opener and directive priority remains unchanged.
fixtures: Exact allowance and one-over cases, a 65,535-byte compact sequence, conservative scalar and comment refusals, mixed block/flow structure, commas in flat flow lists and refusal-priority collisions run through both CLI verbs.
cut_line: Bound source admission without changing vendor bytes, View validation, audit traversal, theorem statements, CLI flags or existing caller behavior on accepted sources.
deferrals: The general duplicate-key optimization remains #413 m2. Residual multiline scalar cost is #431, before #359, #360 and #361 consume pull-request YAML.
owner_decisions: The owner merges this trust-infrastructure change. The required Opus-xhigh verifier is unavailable in this runtime, and no substitute verdict satisfies that requirement.

The architect comparison selected a single document-wide raw punctuation allowance over per-line
indicator and indentation limits. Boundary discipline puts the check before all vendor work.
Minimize reader load keeps it within the existing adapter with one counter and one refusal.
The alternative geometry limits require a more involved nesting argument and leave wide maps
unrestricted. The selected policy also charges commas so flat flow breadth spends the same allowance.

The allowance of 2,048 preserves the existing 1,024-quoted-opener acceptance case and leaves
1,086 characters above ci.yml's current count of 962. This is a conservative subset decision.
Long scripts, quoted data and comments can be refused even when their punctuation is not YAML
structure. No quote lexer is added. The unchanged quadratic algorithms can still be expensive
inside the allowance. Measurements describe tested families, not a universal time or memory bound.

The issue's literal formula with 32,766 dashes occupies 65,537 bytes and already hits tooLarge.
The regression uses 32,765 dashes, occupies 65,535 bytes and reaches the new structure refusal.
The oversized formula remains a separate precedence control.

## Trust retained

1. T1: the pinned parser reports decoded serialization nodes and raw scanner comments accurately
   within the qualified subset. Source filtering excludes every column-zero `%` line, because
   the pin silently drops reserved directives. Leaf paths come from this unproved correspondence.
2. T2: the pinned parser's startup and syntax declarations remain as packaged by #397.
3. T3: the Lean compiler/runtime, including exit-on-panic in the CLI.
4. T4: the conversion seam and source block-header read, tested but not proved against YAML.
5. T5: upstream panic sites abort with exit 1 after CLI initialization; fuel exhaustion refuses.
6. T6: GitHub interprets accepted YAML as this parser does. The refusals, conservation and
   differential bound this gap; owner review of workflow changes remains necessary.
7. T7: the unchanged vendor bytes match the approved pin, checked by the provenance gate.

## Verification

Reader build and guards pass locally with Lean 4.35.0. The CLI/regression PR records workflow
leaf equality, seeded differential results and matched build/runtime observations. Independent
Codex review and the required independent Opus-xhigh verdict are separate; this runtime cannot
provide an Opus verdict. The owner retains merge authority for both trust-critical PRs.

The no-comments pass found no added comments, suppressions or reshape findings in the reader and
integration diff. Nothing was deleted or restored. Local `core/lake check` and
`core/lake comparator --paranoid` both stop before checking at
`bwrap: setting up uid map: Read-only file system`. The sandbox remains enabled.

## Audit qualification round

Scratch mutations reproduced three gaps in the first audit: aliases could hide a vendor type,
recursive `partial` definitions hide their runtime body in a compiler companion, and a companion's
body could reach an `implemented_by` helper absent from the kernel body.

The corrected audit follows type aliases whose declared result reduces to `Sort`, including
private and generic aliases and an alias of `Type`. It follows vendor compiler companion
bodies in the same dependency traversal. A companion of a total safe definition can carry
Lean's generated `partial` flag, as `Scanner.scanLoopFull` does. That compiler artifact stays
within T3. An opaque source declaration with a runtime companion is refused, as are unsafe
companions and forbidden metadata or dependencies reached through a companion.

The final clean reader and a clean private opaque dependency compile. Scratch copies with real
recursive partial dependencies, including one hidden behind a private opaque wrapper, fail with
the intended audit error. A forged companion that reaches an `implemented_by` helper is also
rejected at that helper. Safe manually named companions with no forbidden metadata remain a
compiler-semantics and parser-provenance assumption under T1, T3 and T7; no such manual companion
exists in the pinned vendor source.

The final mutation matrix has 16 expected outcomes: two clean controls compile and all fourteen
negative cases fail with their intended audit messages. It includes direct runtime attributes,
private wrappers, the effective companion-only override, and six public or private type-alias forms.

## Opus directive qualification

The Opus-xhigh review at `335259e` found that reserved directives disappear from the pinned
scanner's tokens and comments. A source expression in `%MITOS` could therefore balance a new
expression decoded from `\x24` in a leaf. The original native CLI accepted that complete exploit,
an ordinary `%FOO` directive, comment-like directive text, multiple balancing directives and a
directive following a document-end marker.

The source check now refuses any literal column-zero `%` line before scanning, after the size,
character and opener limits. This is intentionally conservative: YAML accepts quoted scalar
continuations such as `a: "x\n%FOO\ny"`, but this reader refuses that source form too. Same-line
quoted percent signs and indented quoted or block-scalar percent data remain accepted. This
avoids a second quote/comment lexer at the boundary and keeps the vendored bytes unchanged.

Real-parser guards cover the exploit and its directive variants, both excluded quoted-continuation
styles and accepted percent-data controls. Two additional guards pin expression-bearing flat flow
lists and nested flow lists. The three read statements and audit remain unchanged. Nonblocking
Opus findings are tracked with the existing character-guard cleanup in #413.
