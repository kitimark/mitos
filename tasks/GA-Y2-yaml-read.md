# GA-Y2: qualified workflow reader

Part of [#354](https://github.com/kitimark/mitos/issues/354). The implementation is split into a
reader PR and a CLI/regression PR so the new trust boundary can be reviewed separately.

## Shape

`MitosGate.Yaml.read` returns our `Doc`, or our `Refusal`. The only authored Lean module that
names the vendor is `gate/MitosGate/Yaml.lean`. It scans with the raw comment side channel,
parses the serialization tree, qualifies tokens, converts it to our `Node`, validates `Doc`,
and compares source and leaf expression counts. It never composes aliases or uses a vendor theorem.

The seam uses nested structural recursion over values and their item/pair lists. Its termination
is checked by Lean. The three `read` statements are proved by cases over our checks and the opaque
result of `parseDoc`; their proofs do not unfold the vendor.

## Refusal table

| Input feature | Refusal | Why |
|---|---|---|
| More than 65536 UTF-8 bytes | `tooLarge` | Bound parser work. |
| Outside LF and printable ASCII | `char` | Exclude control and line-break disagreements before parsing. |
| More than 1024 `[` or `{` characters | `openers` | Bound flow nesting, including quoted openers. |
| Scanner/parser failure | `parse` | Preserve the upstream rendered error. |
| Zero or multiple documents | `documents` | Give one root and avoid document-selection disagreement. |
| A directive | `directive` | Exclude version or tag-handle switches. |
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
- The build audits these declarations and `Doc.ofNode` for only `propext`, `Classical.choice`,
  and `Quot.sound` axioms. It traverses types and bodies reachable from `read`, including private
  names, rejecting vendor unsafe/partial declarations, `implemented_by`, `extern`, and compiler
  `csimp` substitutions. It checks every exported YAML declaration for vendor types.
- Real-parser guards cover the refusal constructors, escape table, multi-line scalars, all
  eight #405 cases, and two scan/parse composition drift cases. Alias refusal itself is guarded
  at the seam: the parser rejects undefined aliases, and a valid alias always follows an anchor
  that the source-order seam refuses first. A real-parser guard checks anchor/alias preservation.

## Trust retained

1. T1: the pinned parser reports decoded serialization nodes and raw scanner comments accurately
   within the qualified subset. Leaf paths come from this unproved correspondence.
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
