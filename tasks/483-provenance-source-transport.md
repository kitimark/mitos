# #483 durable provenance source transport

goal: New source publication contains no URL-bearing atoms while preserving exact legacy source interpretation and record-v1 facts.
statement: MitosGate.Provenance.render_isDecoded; private checkedHex_isCanonical and current_usesLegacy
touches: gate/MitosGate/Provenance/SourceTransport.lean, gate/MitosGate/Provenance/Decode.lean, gate/MitosGate/ProvenanceCli.lean, gate/MitosGate/Snapshot.lean, gate/provenance-transport-test.sh, gate/snapshot-test.sh, .claude/skills/kitimark-mode/SKILL.md, this task, new ops run log
must_not_touch: domain/admission/model policy, source-schema-v1, record-v1, historical evidence, dashboard, assignments, labels, workflow and authentication
checks: native build, standard axioms, transport damage/boundary controls, source/native/record suite, legacy fixtures, imports, statement lock, run log, syntax/lint, core check/comparator, fresh CI artifacts
budget: one coherent implementation round; repeated shape deviations return to architect

## Context

Part of #483 and #327. Deployed baseline `8a350a72a2928368585890c33b047fa4d32dc163` accepts compact canonical schema-v1 JSON in a source-v1 frame. A long unspaced URL can be rewritten during publication, so local rendering alone does not establish durable transport. Evidence suffixes are opaque visible ASCII, may contain another URL, and can be 512 characters; requested-model text may also contain a URL. Those domains stay intact.

## Design

depth: build; compiled signatures, co-located standard-axiom statements, named native observations
revisit_when: repeated codec boundary deviations or failed authorized live publication

Usage first:

```sh
mitos-gate provenance render owner/repo canonical-schema-v1.json > source.block
mitos-gate snapshot raw-snapshot-reads
mitos-gate provenance hook raw-hook-reads owner/repo owner MAIN_SHA
```

The root gets one complete validated section or a refusal with empty stdout. Both read paths keep calling `Provenance.decode repo body`; neither knows the envelope version or codec. Recorder inputs remain raw reads and its immutable canonical output remains record v1.

```lean
Provenance.decode : String → String → Except String (List PullFact)
Provenance.render : String → Lean.Json → Except String String
SourceTransport.readCanonicalJson : String → Except String Lean.Json
SourceTransport.publicationBlock : Lean.Json → String
```

`Decode` owns factual schema interpretation and makes full decode a condition of successful render. The transport seam hides markers, version dispatch, exact framing, caps, hex spelling, strict UTF-8, and canonical compact JSON interpretation. Wire helpers and proofs are private. The public transport functions are only the schema owner's seam, with no caller version/codec choices; the CLI exposes only validated rendering. Boundary discipline keeps shell adapters mechanical.

modules:

| File | One topic | Budget | Layout precedent |
| --- | --- | ---: | --- |
| `gate/MitosGate/Provenance/SourceTransport.lean` | Source-envelope interpretation | 125 lines | prior `Provenance/Decode.lean`, private helpers and co-located proofs |
| `gate/MitosGate/Provenance/Decode.lean` | Source facts | 150 lines | existing strict schema interpreter |
| `gate/MitosGate/ProvenanceCli.lean` | Native provenance adapter | +0 net | existing CLI |
| `gate/MitosGate/Snapshot.lean` | Snapshot axiom audit | +1 | existing theorem list |
| `gate/provenance-transport-test.sh` | Observable transport behavior | 200 lines | `provenance-legacy-test.sh` native test entry |
| `gate/snapshot-test.sh` | Raw snapshot behavior | +70 | existing paired source/native/record observations |
| kitimark skill | Publication procedure | +10 | existing provenance instructions |

reuse: The exact old compact-frame interpreter is moved once, then reused by external v1 and by v2 after recovering its bytes and wrapping them in a private legacy frame. This preserves even legacy refusals caused by marker prefixes inside JSON strings. Both paths require inner byte equality with `Json.compress`, including nested duplicate-key defense. All factual schema helpers, admission rules, caller guards and legacy comparison fixtures remain unchanged.

statements: Successful `render` implies shared decoding succeeds. Private canonical-hex and exact-legacy-reuse statements are audited in their module; the public render statement joins the existing Snapshot standard-axiom audit. No unrestricted roundtrip theorem is claimed for oversized or invalid source data.

fixtures: Native v2 exact rendering, opaque nested/requested URLs, strict alphabet/wrapping/UTF-8/framing/version damage, inner JSON and nested duplicates, framing-sensitive inner prefixes, exact body caps, real native 64528/64529-byte capacity, empty-output refusals; paired v1/v2 snapshots and native admission; raw dashboard to canonical record-v1 parity with unknown/adverse facts. The existing large valid-v1 case remains explicitly legacy.

cut_line: Ship the local transport, compatibility, docs and checks. Deployment and the root's real current-data publication/readback are still required for #483; this PR does not close it or reset #336 history/T0.
deferrals: #483 live proof after owner merge; #327 manual trusted-root assertion authenticity residual; #486 platform capacity, legacy framing controls and previous run-log metadata
owner_decisions: Trust-infrastructure merge remains the owner's; no additional publication authority is created.

## Rationale

The chosen whole-payload envelope hides every URL atom without exposing a risky-field inventory. Source-v2 uses exact markers, a text fence, uppercase hex and canonical 64-character LF rows. Schema-v1 and record-v1 are separate contracts and remain unchanged. One default writer and a closed decoder prevent alternate spellings or fallback publication.

Architect compared two independent inherited-model candidates, each with whole-shape alternatives. Preferred Opus/Fable runners and the later Fable judge were unsupported; no Claude or cross-model verdict is claimed. Root's precommitted rubric tied hex and Base64 at 23/25. Hex became the base for its simpler byte codec and separate transport topic; exact legacy-interpreter reuse was grafted from the Base64 candidate.

We accept lower native-render capacity in exchange for a small canonical codec: unchanged 131072-byte physical payload admits at most 64528 decoded bytes, versus legacy's 131072. Platform limits and the dashboard's human sections can reduce usable publication capacity further (#486). A 64529-byte canonical source remains valid legacy input but new rendering refuses; it never drops events, raises caps or falls back. Base64 would admit more data but needs quantum/padding canonicality. Field/evidence references leak schema inventory and cannot cover arbitrary nested URL suffixes or requested-model URLs; deterministic pretty JSON still leaves long atoms intact.

The red-flag screen finds one transport owner, one factual-schema owner, no temporal staging API, no wire types or codec options exposed to domain callers, no duplicate writer, no copied field list, and no importable private helpers. The two-function transport seam concentrates the protocol; co-located statements and native refusal controls encode its constraints. No generic codec framework is introduced.

The remaining risk is operational: will the new frame survive publication of the deployed current dashboard? Only the root, after owner-merged deployment, can settle that by publishing real current facts against freshly read current dashboard bytes and reading them back through the deployed decoder. These local tests neither authenticate shared-account writers nor prove that deployed result. Unknown identity/effort, adverse events, exact heads, carry and admission remain governed by existing policy.

## Validation

Native transport: 43 checks, retaining the prior 41 and adding junk before the opening v2 fence and after the closing v2 fence. Source/native/record: 187 observations, retaining the prior 159 and adding exact v1/v2 parity. Legacy: all 36 frozen obligations compile. Native build and standard-axiom audits, imports, statement lock, shellcheck, shell syntax, run-log schema and task-design checks pass.

A bounded weakened-decoder control bypassed only canonical hex-row re-encoding: the short-first-row refusal went red. The production source was restored and the full transport suite passed. Initial integration failures identified a raw-JSON mutation test that needed to mutate renderer input, and an incorrect new test expectation about existing rest versus eligibility; their final behavioral assertions are retained.

Local core check/comparator and six lint namespace observations are blocked by read-only uid-map setup. Existing hook-state path tests refuse this sandbox's root directory owned by uid 65534; its provenance-specific observations pass. These environment limits require fresh exact-head CI and uploaded cheat artifacts; no local full cheat-corpus result is claimed. Live publication/readback remains outstanding after owner merge.
