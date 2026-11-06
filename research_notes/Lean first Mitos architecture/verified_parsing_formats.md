# Verified Parsing and Formal Semantics of File Formats (Lean 4 focus, as of Nov 2026)

Scope note: this covers verified-parser prior art, Lean 4 projects and techniques, formal specs of the Mitos target formats, UTF-8 byte-span reasoning in Lean, testing to close the remaining gap, and effort data. Mitos plans four proof obligations per extractor: (1) totality and termination, (2) anchoring, meaning each fact cites a byte span that contains the identity, (3) soundness and completeness against a reviewed "format model", (4) parser correctness, as a round trip or as agreement with a grammar.

Network limits in this session: `go.dev` and `arxiv.org` were blocked, so the go.mod grammar and the full Cedar paper could not be fetched directly. Claims that depend on them are marked. GitHub README claims (L4YAML, Proven-Commons/json, lean-json) are reported as the projects state them. I did not audit the proofs myself.

---

## Q1. Verified parser prior art: what exists and which properties does each prove?

### Takeaway
There is mature prior art. Binary formats are served by EverParse (F*), Vest (Verus/Rust) and Narcissus (Coq). These prove parse/serialize inverse properties, non-malleability, and memory and arithmetic safety, and EverParse ships in Windows/Hyper-V. Grammar-based text parsing is covered by CompCert's validated LR(1), CoStar ALL(*), Vermillion LL(1), TRX and the Blaudeau-Shankar PEG/packrat work, and Ridge's combinators. These prove soundness, completeness and termination against a grammar, and in CoStar's case they also detect ambiguity. The established patterns are "certificate validation" (CompCert), "correct-by-construction combinators" (EverParse, Vest, Narcissus) and "interpreter for a grammar, proven once" (TRX, CoStar, packrat). All three carry over to Lean.

### Cited Findings
**Binary / combinator-based (serializer-inverse family)**
- **EverParse (F*/Low*, Project Everest):** EverParse 3D takes a data format description and generates validators. The generated code is verified for memory safety and functional correctness, and the toolchain emits F* specs, Low* implementations and C code. It is built on the LowParse combinator library. — [EverParse 3D docs](https://github.com/project-everest/everparse/blob/82f878503c4beac745803ed89bce2ca40208a987/doc/3d.rst); [EverParse site](https://project-everest.github.io/everparse/)
- **EverParse deployment and properties:** The IETF 123 slides say EverParse-verified code validates packets through the Hyper-V vSwitch in Windows 10/11 and Azure (NVSP, RNDIS, OIDs, NDIS). They list these properties: memory safety, arithmetic safety, functional correctness, double-fetch freedom, non-ambiguity and non-malleability. They also say the work found missing integer and buffer overflow checks in the existing Hyper-V code. — [IETF 123 UFMRG slides](https://datatracker.ietf.org/meeting/123/materials/slides-123-ufmrg-eerprse-00)
- A third-party catalogue reports that nearly 100 messages across 4 protocols were specified in 3D and replaced handwritten code. Treat this as reported, not confirmed by Microsoft. — [PLDB](https://pldb.io/concepts/everparse3d.html)
- **EverCBOR / EverCDDL / EverCOSign (CCS 2025):** These are verified C and Rust CBOR validators, parsers and serializers built on PulseParse, a combinator library based on separation logic for non-malleable formats. They cover only deterministic CBOR (RFC 8949 §4.2) and no floats. EverCDDL is described as the first formalization of CDDL, a schema language, and it generates verified parsers from schemas. The work received the CCS 2025 Distinguished Artifact Award. — [MSR publication](https://www.microsoft.com/en-us/research/publication/evercbor/); [paper PDF](https://www.microsoft.com/en-us/research/wp-content/uploads/2025/10/evercbor.pdf); [EverParse GitHub](https://github.com/project-everest/everparse)
- **Vest (USENIX Security 2025, Cai et al., CMU/MSR):** Formats are written in an RFC-style DSL. Vest generates Rust parsers and serializers that Verus verifies automatically, and it proves that parsing and serialization are mutual inverses. The authors say this makes the code immune to parser malleability and format confusion. They report performance on par with hand-written parsers and resistance to basic digital side channels. Case studies cover Bitcoin blocks, the TLS 1.3 handshake and the Wasm binary format. The artifact's VestLib verifies as "477 verified, 0 errors". — [USENIX page](https://www.usenix.org/conference/usenixsecurity25/presentation/cai-yi); [artifact appendix](https://www.usenix.org/system/files/usenixsecurity25-appendix-cai-yi.pdf); [vest_lib docs](https://docs.rs/vest_lib)
- **Narcissus (ICFP 2019, Delaware, Suriyakarn, Pit-Claudel, Ye, Chlipala; Coq/Fiat):** A format is a relation that captures every valid encoding. The tool synthesizes a decoder that inverts this relation, with a machine-checked correctness proof, and the decoder fails on malformed input. It was used to reimplement packet processing for a full Internet stack in MirageOS with minimal performance loss. — [ICFP 2019 page](https://icfp19.sigplan.org/details/icfp-2019-papers/38/Narcissus-Correct-By-Construction-Derivation-of-Decoders-and-Encoders-from-Binary-Fo); [paper PDF](https://www.cs.purdue.edu/homes/bendy/papers/Narcissus/narcissus.pdf); [CERIAS](https://www.cerias.purdue.edu/research/projects/home/detail/203/narcissus_deriving_correctbyconstruction_decoders_and_encoders_from_binary_formats)

**Grammar-based (soundness/completeness family)**
- **CompCert validated LR(1) (Jourdan, Pottier, Leroy, ESOP 2012):** Menhir produces an automaton and a certificate. A validator written in Coq, and proven sound, checks them, so the generator itself is not trusted. The validator works with canonical LR(1), SLR(1), LALR(1) and Pager's method. On a C99 grammar (87 terminals, 72 nonterminals, 263 productions) the Pager automaton has 505 states. Parsing was 5x slower than the unproved parser it replaced. — [Gallium blog](https://gallium.inria.fr/blog/verifying-a-parser-for-a-c-compiler); [Springer](https://link.springer.com/doi/10.1007/978-3-642-28869-2_20); [Leroy slides](https://www.cs.ox.ac.uk/ralf.hinze/WG2.8/30/slides/xavier.pdf)
- **CoStar (PLDI 2021, Lasser, Casinghino, Fisher, Roux; Coq):** A verified ALL(*) parser, reported as sound and complete for all non-left-recursive grammars. It detects ambiguous inputs, terminates on all inputs, and runs in linear time on several grammars for common languages and data formats. CoStar++ (NFM 2023) adds semantic predicates and actions and remains sound, complete and terminating. The summary of properties comes partly from an aggregator abstract. — [PLDI 2021 page](https://pldi21.sigplan.org/details/pldi-2021-papers/28/CoStar-A-Verified-ALL-Parser); [AMiner abstract](https://www.aminer.cn/pub/60d3093691e01182ead65e02/costar-a-verified-all-parser); [CoStar++ abstract](https://www.aminer.org/pub/64a29614d68f896efa28ca20/verified-all-parsing-with-semantic-actions-and-dynamic-input-validation)
- **Vermillion (ITP 2019, Lasser, Casinghino, Fisher; Coq):** A verified LL(1) parser generator in which both the table generator and the parser are proven sound and complete. **On a JSON data set it ran 2–4x slower than an unverified optimized parser.** An Isabelle/AFP formalization is based on it. — [ITP 2019 PDF](https://drops.dagstuhl.de/storage/00lipics/lipics-vol141-itp2019/LIPIcs.ITP.2019.24/LIPIcs.ITP.2019.24.pdf); [Galois talk](https://galois.com/blog/2019/09/tech-talk-a-verified-ll1-parser-generator/); [AFP LL1_Parser](https://isa-afp.org/entries/LL1_Parser.html)
- **Verbatim / Verbatim++ (Egolf, Lasser, Fisher; Coq):** A verified lexer generator based on Brzozowski derivatives. It is proven correct against a standard lexer specification, which uses maximal munch. — [Tufts colloquium](https://www.cs.tufts.edu/t/colloquia/current/?event=1386)
- **TRX (Koprowski & Binsztok, ESOP 2010 / LMCS 2011; Coq):** A PEG interpreter whose termination and correctness against PEG semantics are proven in Coq. Termination depends on a well-formedness check on the grammar. — [arXiv 1105.2576](https://arxiv.org/pdf/1105.2576); [LMCS](https://lmcs.episciences.org/686/pdf)
- **Blaudeau & Shankar (CPP 2020; PVS):** A verified packrat parser interpreter for PEGs. A "well-formed grammar" notion ensures termination, and ASTs act as proof certificates, recording the parser's computational trace. The packrat (memoized, linear-time) interpreter is proven to return the same results as the reference recursive interpreter, and a packrat parser generator is also verified. — [arXiv 2001.04457](https://arxiv.org/pdf/2001.04457); [CPP 2020](https://popl20.sigplan.org/details/CPP-2020-papers/26/A-Verified-Packrat-Parser-Interpreter-for-Parsing-Expression-Grammars)
- **Ridge (CPP 2011; HOL4):** Sound and complete parsers built directly from grammar specifications for all context-free grammars, using combinators. Memoized versions run in polynomial time. A later paper (SLE 2014) said performance lagged Earley-style methods and moved to an oracle-based design. — [Springer](https://www.springerprofessional.de/en/simple-functional-sound-and-complete-parsing-for-all-context-fre/3781114); [paper PDF](https://cflmark.nms.kcl.ac.uk/hg/regexp/raw-file/1abf8586ee6b/Literature/ridge11parsing.pdf); [Ridge14](https://researchr.org/publication/Ridge14)
- **Verified regex in Lean 4 (Zhuchko, Veanes, Ebner):** CPP 2024 formalized and proved correct, against standard matching semantics, a matcher based on symbolic derivatives with intersection, complement and lookarounds. It is modeled on the .NET NonBacktracking engine. ITP 2025 proved the set of iterated derivatives finite for these extended regexes. The code is at `ezhuchko/re-sharp-smt`. — [MSR CPP 2024](https://www.microsoft.com/en-us/research/?p=1115526); [ITP 2025](https://drops.dagstuhl.de/storage/00lipics/lipics-vol352-itp2025/html/LIPIcs.ITP.2025.16/LIPIcs.ITP.2025.16.html); [GitHub](https://github.com/ezhuchko/re-sharp-smt)

### Inferences
- Taxonomy of properties proven:
  - **Soundness** (output is a valid parse or derivation): every project above.
  - **Completeness** (every string in the language is accepted): CoStar, Vermillion, Ridge, TRX/packrat relative to PEG semantics, and CompCert relative to the automaton.
  - **Unambiguity or ambiguity detection**: CoStar, and EverParse "non-ambiguity".
  - **Serializer inverse or non-malleability**: EverParse, Vest, Narcissus.
  - **Termination**: TRX, Blaudeau-Shankar, CoStar, Ridge.
  - **Memory, arithmetic and double-fetch safety**: EverParse.
- For Mitos (text formats, offline batch scanning, no attacker-controlled memory concerns in Lean), the relevant pattern is the grammar-based family plus a "round trip on the data model" theorem, not low-level memory safety.
- **Pattern to borrow:** CompCert's validator approach. Generate or write the parser any way you like, and prove a small checker, or prove that the parser emits a derivation or certificate that a simple spec can check. This matches Mitos's anchoring obligation well. The parser emits spans plus a witness, and a small verified checker confirms that `bytes[span]` decodes to the identity.
- The Blaudeau-Shankar idea that the parse tree is the proof certificate is directly reusable in Lean. A dependent "parse derivation" type indexed by span can carry anchoring for free.

### Gaps
- **CakeML parser:** I did not retrieve a source in this session. From background knowledge, CakeML uses a PEG-based parser with HOL4 soundness and completeness proofs, but this is unverified here.
- **RockSalt** (verified x86 decoder via regex-like grammars, Coq) and **Jasmin**: no sources retrieved.
- **Derivative-based CFG parsers** (e.g., verified "parsing with derivatives") and Danielsson's total parser combinators in Agda: not retrieved.
- Full-text numbers for Vest proof effort, such as proof lines and person-months, were not available. Only the "477 verified" count was found.

---

## Q2. Lean 4: verified parser projects and proof techniques

### Takeaway
As of late 2026 Lean 4 has **no mature, widely adopted verified-parser library**. There are several new projects (2026). L4YAML from NASA JPL is the most ambitious: a YAML 1.2.2 parser with roughly 5,000 lemmas. A public audit found its headline grammar-equivalence theorem false as stated, which shows how easily a "format model" spec can be wrong. Several JSON projects prove `parse (print v) = v` but not RFC-grammar agreement. The tooling needed is now in place: total `def`s with well-founded recursion, functional induction, the `Std.Do`/`mvcgen` Hoare-logic VC generator for monadic code, and `grind`/`omega`/`simp`/`decide`. The main practical obstacle is that existing combinator libraries (core `Parsec`, `lean4-parser`) use `partial def`, which is opaque to proofs.

### Cited Findings
- **NASA JPL L4YAML:** A YAML 1.2.2 parser, emitter and typed (de)serializer in Lean 4.
  - **Claims:** soundness (accepted input produces a structurally valid data model), parser completeness for well-formed token streams, scanner-to-parser composition correctness, and a universal round trip `parse ∘ emit = id` on well-formed values (`universal_roundtrip`, sorry-free). Every core function is a total `def`, with no `partial def`, `axiom` or `sorry` in the core.
  - **Size:** about 4,975 `lemma`s plus 25 `@[capstone]` theorems. 7 of the 25 rely on `native_decide`, which trusts the compiled evaluator.
  - **Tests:** yaml-test-suite 347/358 event cases. YAML Test Matrix: 308/308 valid event streams and 279/279 JSON oracles.
  - **Correction:** on 2026-09-27 the maintainers corrected the headline `theorem parse_iff_grammar (input) : (∃ docs, parseYaml input = .ok docs) ↔ InYamlLanguage input` as false as stated, after an external audit found four counterexamples. The forward direction is proven but "not yet restrictive", and the converse is open.
  - **Techniques:** fuel-indexed induction, `#guard` compile-time tests, `native_decide`. String.Pos and byte offsets are not discussed.
  - — [GitHub nasa-jpl/L4YAML](https://github.com/nasa-jpl/L4YAML)
- **Proven-Commons/json** (Lean 4.35.0): an RFC 8259 parser and printer.
  - **Headline theorem:** `Json.Spec.parse_print`, parse of print is the identity, using only the standard axioms.
  - **Number layer:** round-trip theorems (`read_print`, `readNumber_wf`, `canonical_eq_of_value_eq`), plus refusal theorems for specific bad inputs by `decide +kernel`.
  - **Not proven:** soundness or completeness against the RFC grammar. These are tested via JSONTestSuite and differential tests against Python `json`/`decimal`.
  - **Representation and status:** works on `List Char`, not `String`/`ByteArray`, and describes itself as "in-progress".
  - — [GitHub Proven-Commons/json](https://github.com/Proven-Commons/json)
- **lean-json (NitheeshWorks):** a Lean port of pydantic-core's JSON layer. It has a total parser, a printer and a proved round trip. Fast-path decoder agreement is proved, while the Float bridge and error offsets are only tested. — [GitHub](https://github.com/NitheeshWorks/lean-json)
- **predictable-machines/lean4-json-schema:** JSON Schema validation with soundness and completeness theorems and a total `validateJson`. — [GitHub](https://github.com/predictable-machines/lean4-json-schema)
- **Lake's TOML:** Lean's build tool Lake ships a TOML v1.0.0 grammar and parser written in Lean (`Lake.Toml.Grammar`). It is a parser encoding, not a verified one. — [Lake.Toml.Grammar docs](https://lean-lang.org/doc/api/Lake/Toml/Grammar.html)
- **Obstacle in `lean4-parser`:** GitHub issue #95, "Make fold combinators total to enable verified parsers", says the core fold combinators are `partial def`. Lean treats these as opaque constants, which blocks proofs about them. — [fgdorais/lean4-parser#95](https://github.com/fgdorais/lean4-parser/issues/95); [Reservoir: Parser](https://reservoir.lean-lang.org/@fgdorais/Parser)
- **Core Parsec:** core Lean has a `Parsec` (formerly `Lean.Data.Parsec`, now `Std.Internal.Parsec`), but a 2022 Zulip thread on Lean parser libraries does not discuss verification. — [Zulip archive](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/parsing.20text.20with.20lean.html)
- **`Std.Do` / `mvcgen`:** these give monadic `do` code a predicate-transformer (weakest-precondition) semantics through `WP` instances. Hoare triples compose over sequencing and control flow. `mvcgen` turns a goal into verification conditions such as loop invariants, which spec lemmas then discharge. Use requires `import Std.Tactic.Do` and `open Std.Do`. The feature is documented in the reference manual from 4.26 through 4.36-rc. — [Lean reference: mvcgen](https://lean-lang.org/doc/reference/latest/The--mvcgen--tactic/Overview/); [reference-manual PR #683](https://github.com/leanprover/reference-manual/pull/683.patch)
- **Cedar (AWS):** the Lean model plus proofs is the "verification-guided development" template. It is the closest industrial precedent for Mitos (details in Q5/Q6). — [arXiv 2407.01688](https://arxiv.org/pdf/2407.01688); [Lean use case](https://lean-lang.org/use-cases/cedar/)
- **Verified regex in Lean 4:** see Q1. This is the existing Lean evidence that derivative-based matching is provable at research quality. — [MSR](https://www.microsoft.com/en-us/research/?p=1115526)

### Inferences
- **Recommended Lean technique stack for Mitos extractors:**
  1. Write parsers as **total functions** over `ByteArray`/`String.Slice`, or a hand-rolled state monad `StateT Pos (Except Err)`. Termination should come from a strictly increasing position: use `termination_by s.size - pos` and `decreasing_by omega`. Do not use `partial def` combinators from core `Parsec`/`lean4-parser`, or else wrap them with "consumes input" (progress) lemmas.
  2. Use **functional induction** (`fun_induction`/`.induct` principles that Lean generates for recursive defs) for soundness and completeness proofs.
  3. Use **`mvcgen` + `Std.Do`** when extractor code is imperative (`for` loops, mutable state). Loop invariants become the anchoring invariant, for example "every fact pushed so far has span ⊆ [0, pos) and its bytes decode to its identity".
  4. Use **`omega`** for offset arithmetic, **`simp`/`grind`** for structural goals, and **`decide`/`#guard`** for concrete regression examples. Avoid `native_decide` in the trusted core if the trust story matters, since L4YAML flags it explicitly.
- **Obligation (1), totality:** realistic and cheap for every format, because Lean enforces it.
- **Obligation (2), anchoring:** realistic and cheap if spans are produced by construction, through a `Located α` type that carries `start stop : Pos` and a proof that `extract start stop = text`. Alternatively, have a tiny verified checker re-validate each emitted fact against the file bytes, CompCert-style.
- **Obligation (3), soundness and completeness against a small format model:** realistic for line- and token-oriented formats (go.mod, requirements.txt, Dockerfile instructions, proto top-level declarations). It also works for JSON-family formats if the model is defined over the parsed data model, not the raw text.
- **Obligation (4), full grammar agreement:** the expensive and risky part. L4YAML shows that even a large effort can state the wrong theorem. Round trip on the data model (`parse (print v) = v`) is the realistic version of (4), and grammar agreement should be limited to small formats.
- **Risk:** the specification is the weak point. The L4YAML correction, and the Proven-Commons decision to explicitly not claim grammar agreement, both point to the "format model" as what needs human review. Keep it small and executable so it can also be differentially tested.

### Gaps
- No Lean FRO blog post or Zulip thread specifically on verified Parsec lemmas was found. I could not confirm whether `Std.Internal.Parsec` has any proven lemmas, such as monotone position.
- L4YAML's lines of code/proof and person-months are not stated.
- I did not confirm whether the "four counterexamples" audit is published separately. It is only reported on the L4YAML README.

---

## Q3. Formal specs of target formats and how hard each is to formalize

### Takeaway
Only JSON (RFC 8259 ABNF), TOML (ABNF in the toml-lang repo, labeled "not authoritative" in older revisions), XML 1.0 (W3C EBNF plus well-formedness constraints) and proto3 (EBNF on protobuf.dev, admitted incomplete) have published grammars. go.mod has an EBNF-style grammar in the Go modules reference, though I could not fetch it in this session. YAML 1.2 has a huge, context-sensitive production set, and conformance is judged in practice by yaml-test-suite. Dockerfile has no official formal grammar: BuildKit's handwritten parser is the reference. Most Mitos facts depend on semantic layers above syntax (indirect markers, npm lockfile semantics, Maven inheritance, compose merging), and there the "format model" must be written by hand.

### Cited Findings
- **TOML:**
  - The toml-lang repo hosts `toml.abnf` (RFC 5234 ABNF). An older pinned revision warns: "WARNING: This document is a work-in-progress and should not be considered authoritative." — [toml-lang toml.abnf](https://github.com/toml-lang/toml/blob/bb47759841ac368d86eb7a459bd7eea7162b9a80/toml.abnf)
  - go-toml v2's copy (243 lines) states that all valid TOML matches it, "however certain invalid documents would need to be rejected as per the semantics described in the supporting text". These semantic rules include duplicate keys and table redefinition. — [go-toml toml.abnf](https://www.github.com/pelletier/go-toml/blob/v2/toml.abnf)
  - A Lean 4 TOML grammar already exists in Lake. — [Lake.Toml.Grammar](https://lean-lang.org/doc/api/Lake/Toml/Grammar.html)
- **proto3:**
  - The official spec is EBNF. — [protobuf.dev proto3 spec](https://protobuf.dev/reference/protobuf/proto3-spec)
  - The Editions 2023 spec says it "is known to be incomplete, particularly regarding whitespace handling", that the C++ `protoc` is the source of truth, and that the grammar describes a handwritten parser not based on a formal grammar. — [Edition 2023 spec](https://protobuf.dev/reference/protobuf/edition-2023-spec)
  - Buf publishes a more complete spec with a test corpus covering features Google's docs omit or get wrong. — [buf.build spec](https://buf.build/docs/reference/protobuf-language-spec/)
- **Dockerfile:**
  - No official formal grammar was found. Community parsers either use their own grammars, like Rust `dockerfile-parser`, which "does not handle BuildKit parser directives", or target BuildKit semantics via fixture dumps, like dockerfile-dlang against BuildKit v0.13.2. — [dockerfile-parser](https://docs.rs/crate/dockerfile-parser/latest/); [dockerfile-dlang](https://code.dlang.org/packages/dockerfile-dlang)
- **YAML:**
  - Practical conformance is measured against yaml-test-suite, and claims vary by suite version. For example, one parser's README claimed 100% while `make test` showed 9 failures. — [yaml-reference-parser#13](https://github.com/yaml/yaml-reference-parser/issues/13)
  - 1.1 → 1.2 changed directive scoping. — [yaml-test-suite#45](https://www.github.com/yaml/yaml-test-suite/issues/45)
  - L4YAML's 11 test diffs are attributed to suite-version skew, and its grammar-equivalence theorem was corrected (see Q2). — [L4YAML](https://github.com/nasa-jpl/L4YAML)
- **go.mod:**
  - The `golang.org/x/mod/modfile` `Require` struct carries `Mod` and an `Indirect bool` that records a `// indirect` comment. Direct and indirect requires are kept in separate blocks and moved between blocks when the marking changes. — [modfile commit](https://go.googlesource.com/mod/+/37dd6891021a152661f432ba5349c6527c243c02%5E%21/)
  - Example: `golang.org/x/mod v0.25.0 // indirect` in its own block. — [go.googlesource example go.mod](https://go.googlesource.com/example/+/refs/heads/master/go.mod)
  - Important: `// indirect` is semantically meaningful but lexically a comment. The format model must therefore treat comments as data, which a standard "comments are whitespace" grammar would discard.
- **JSON:** the RFC 8259 grammar is small, and Lean projects already prove the round trip. — [Proven-Commons/json](https://github.com/Proven-Commons/json)

### Inferences (feasibility matrix, my assessment)
Legend: T = totality, A = anchoring, S/C = soundness/completeness against the format model, RT = round trip, G = grammar agreement. Effort: Low / Med / High.

| Format | Spec status | T | A | S/C vs model | RT | G | Notes |
|---|---|---|---|---|---|---|---|
| requirements.txt | PEP 508 + pip docs (prose + grammar) | Low | Low | Low–Med (line-oriented; model = PEP 508 subset; exclude `-r`, `-e`, URLs initially) | Med | Med | Line continuation, env markers, `#` comments. |
| go.mod | EBNF in Go modules reference (not fetched) | Low | Low | Low–Med; model must include `// indirect` comment, block vs line form, `replace`/`exclude` | Med | Med | Validate against `go mod edit -json`. |
| JSON (package.json, package-lock.json, OpenAPI-JSON) | RFC 8259 ABNF | Low | Low–Med (string escapes mean span text ≠ decoded identity; anchor to the raw lexeme and prove decode(raw) = identity) | Low for syntax; Med for npm semantics (lockfile v1/v2/v3 shapes, `dev`/`optional`/`peer` flags) | Low–Med (precedent exists) | Med | Duplicate keys: RFC says SHOULD be unique; the model must pick a rule (e.g. last wins, like JS). |
| TOML (Cargo.toml) | ABNF + prose semantic rules | Low | Med (dotted keys, inline tables: one identity can be spread across several spans) | Med; Cargo semantics (`[dependencies]`, `[target.'cfg'.dependencies]`, `workspace = true`) | Med | Med–High (ABNF ignores redefinition rules) | Lake's Lean TOML parser exists as a starting point. |
| proto3 | EBNF, admitted incomplete; protoc is the reference | Low | Low | Low–Med for imports/packages/service declarations | Med | Med | Use Buf corpus + `protoc --descriptor_set_out` as oracle. |
| Dockerfile | No formal grammar; BuildKit handwritten | Low | Low–Med (line continuations, heredocs, escape directive) | Med for `FROM`/`ARG` substitution | Low value | n/a (no grammar to agree with) | Model = "instruction list after continuation joining". |
| XML (pom.xml) | W3C EBNF + well-formedness constraints; namespaces separate | Low | Med (entities/CDATA mean span ≠ value) | Med–High (Maven parent POM inheritance, properties `${...}`, dependencyManagement) | Med | High (full XML incl. DTD) | Restrict to an XML subset (no DTD/external entities); syntax is easy, Maven semantics are the hard part. |
| YAML subset (docker-compose, OpenAPI-YAML, GH Actions) | YAML 1.2.2, very large; L4YAML exists | Med | Med–High (block scalars, anchors/aliases, flow vs block) | High for full YAML; Med for a declared subset (no anchors/tags, block style + plain/quoted scalars, JSON-compatible) | Med | High (L4YAML shows the risk) | Consider building on or auditing L4YAML rather than writing new. Compose merging/interpolation is a separate semantic layer. |
| OpenAPI | JSON Schema-defined over JSON/YAML | inherits | inherits | Med (model only the fields Mitos extracts) | — | — | Facts sit over the JSON/YAML data model, so proofs can be stated over the data model. |

- **Structural recommendation:** use a two-layer design.
  1. A verified **syntax layer** per surface syntax: JSON, TOML, YAML-subset, XML-subset, and line-oriented. It produces a data model in which each node is annotated with its byte span.
  2. Per-ecosystem **semantic extractors** that are pure functions over that annotated tree.
  Obligation (3) is then proved once per extractor over trees, and obligation (2) follows from the span annotations invariant of layer 1. Six syntax layers serve all twelve formats.

### Gaps
- Could not fetch the go.mod grammar from go.dev/ref/mod, because the network blocked go.dev. The report writer should cite it directly. From memory it is a lexical spec with `GoMod = { Directive }`, `RequireDirective`, and similar productions, but this is not verified in this session.
- No source retrieved on StrictYAML or on formal analyses of YAML 1.2 grammar complexity, such as production count or context-sensitive indentation parameters.
- No source retrieved on formalizations of XML 1.0 in any prover. I did not find one in this session.
- PEP 508 grammar for requirements.txt not retrieved.

---

## Q4. Proving byte offsets and spans with UTF-8 strings in Lean

### Takeaway
Lean 4 `String` is UTF-8 with byte-based positions. Since v4.25.0 (2025-11-14) core has **checked positions and slices**: `String.ValidPos`, later the checked `String.Pos`, and `String.Slice`. These carry a proof that the offset lies on a UTF-8 character boundary and within bounds, alongside the unchecked `String.Pos.Raw`. Mitos's anchoring obligation can therefore be stated as types, with no separate proof.

### Cited Findings
- The Lean reference manual says: "A `Pos s` is a byte offset in `s` together with a proof that this position is at a UTF-8 character boundary". `String.Pos.Raw` is the unchecked variant, and the docs recommend the checked type because it leads to less error handling and fewer edge cases. — [Lean reference: Strings](https://lean-lang.org/doc/reference/latest/Basic-Types/Strings/)
- Validity: `IsValid s p ↔ p ≤ s.rawEndPos ∧ (s.toByteArray.extract p.byteIdx s.utf8ByteSize).IsValidUTF8`. The Boolean form is `String.Pos.Raw.isValid`. — [Init.Data.String.Basic docs](https://leanprover-community.github.io/mathlib4_docs/Init/Data/String/Basic.html)
- The Lean 4.25.0 release notes (2025-11-14) say a PR "introduces safe alternatives to String.Pos and Substring that can only represent valid positions/slices". It adds `String.ValidPos`, `String.Slice` and `String.Pos.IsValidForSlice`, and a follow-up adds `LT`/`LE` on `ValidPos`. — [Lean 4.25.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.25.0/)
- Lemmas such as `String.Pos.isValidUTF8_extract`, `isUTF8FirstByte_byte` and `utf8ByteSize_byte` exist in `Init.Data.String.Lemmas`. Their exact statements were not checked. — [Init.Data.String.Lemmas.Basic (mirror)](https://leanmachinelearning.org/LML/docs/Init/Data/String/Lemmas/Basic.html)

### Inferences
- **Recommended representation:**
  - Read files as `ByteArray`, which is total and needs no UTF-8 validity assumption. Validate UTF-8 once with `String.fromUTF8?`/`IsValidUTF8`, then work on `String`/`String.Slice` with checked positions.
  - Represent evidence as `{ start stop : s.Pos // start ≤ stop }`, with the snippet `s.extract start stop` or `Slice`.
  - The anchoring theorem becomes `∀ f ∈ extract s, (s.extract f.span.start f.span.stop).contains f.identity`, or better, the exact `= f.rawLexeme` together with `decode f.rawLexeme = f.identity`.
- **For JSON/TOML/YAML/XML escapes:** the identity, e.g. a package name after unescaping, may differ from the raw bytes. Anchoring should therefore be stated as "the span's text is a lexeme whose decoding equals the identity". This is a stronger, more honest statement than substring containment. Most package names are ASCII-only and escape-free in practice, so a fast path can prove literal containment.
- Since Mitos reports byte spans to external tools, prove that `pos.byteIdx` matches the raw `ByteArray` offset. This is true by definition in Lean's representation (`String.toByteArray`/`utf8ByteSize`).
- **Version risk:** the String API was reworked in 4.25 and later, and older Substring-based code and lemmas may have been renamed or deprecated. Pin the toolchain and expect churn. Proven-Commons/json avoided the issue by using `List Char`, which makes position proofs easier but loses byte offsets.

### Gaps
- I did not verify how complete the lemma library for `String.Slice`/`ValidPos` is as of Lean 4.3x (e.g., lemmas relating `extract` of adjacent slices, or `Slice` splitting). Check before committing.
- Whether `Std.Internal.Parsec` has been ported to `String.Slice`/checked positions was not determined.

---

## Q5. Differential and property-based testing to close the remaining gap

### Takeaway
Cedar is the established template: a readable Lean model plus proofs, with production code differentially tested against the model, plus property-based testing where no model exists yet. Lean's **Plausible** library gives property-based testing (PBT) inside Lean, and the Lean model can serve as the test oracle. For Mitos the real tools (`go mod edit -json`, npm, `protoc`, `cargo metadata`, BuildKit, Maven `help:effective-pom`) are the oracles for validating the human-written format model itself. This is the gap proofs cannot close.

### Cited Findings
- **Cedar's verification-guided development:**
  - A readable, executable Lean model with proofs, plus differential random testing (DRT) of Rust production code against it, plus PBT for unmodeled parts.
  - Proofs found 4 validator bugs, and DRT/PBT found 21 more.
  - A release ships only if the model, proofs and differential tests are current.
  - Lean evaluates a DRT input in about 5 µs versus about 7 µs for Rust, which makes millions of nightly cases feasible.
  - — [arXiv 2407.01688](https://arxiv.org/pdf/2407.01688); [AWS Open Source blog](https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development)
- **Plausible:** property testing that runs inside the Lean tactic framework (the `plausible` tactic, or `#eval Testable.check`). It needs `Repr`, `Shrinkable` and `SampleableExt` instances, or `deriving Arbitrary` for algebraic data types, a handler contributed by an AWS intern. A known issue (April 2025) is kernel errors when it is used inside recursive executable functions. — [Reservoir: plausible](https://reservoir.lean-lang.org/@leanprover-community/plausible); [Zulip: Plausible inside functions](https://leanprover-community.github.io/archive/stream/113488-general/topic/Plausible.20inside.20functions.html); [Zulip: Review request Plausible#35](https://leanprover-community.github.io/archive/stream/348111-batteries/topic/Review.20request.20for.20Plausible.2335.html)
- **Alternatives:** LSpec, with a fork that adds Plausible-backed `checkPlausibleIO`, and LeanHypothesis, which wraps Python Hypothesis. — [LSpec fork](https://github.com/ngernest/LSpec); [LeanHypothesis](https://github.com/alok/LeanHypothesis)
- **Testing practice in Lean format projects:**
  - Proven-Commons/json tests the gap it does not prove (grammar agreement) with JSONTestSuite and differential testing against Python `json`. — [Proven-Commons/json](https://github.com/Proven-Commons/json)
  - L4YAML uses yaml-test-suite and the YAML Test Matrix. — [L4YAML](https://github.com/nasa-jpl/L4YAML)
- **Conformance corpora:**
  - Buf maintains a protobuf test corpus. — [buf.build](https://buf.build/docs/reference/protobuf-language-spec/)
  - dockerfile-dlang tests against BuildKit fixture dumps. — [dockerfile-dlang](https://code.dlang.org/packages/dockerfile-dlang)

### Inferences
- **Proposed Mitos assurance stack per format:**
  1. Proofs of T, A and S/C against the Lean format model.
  2. Round trip `parse ∘ print = id` on the data model, with Plausible-generated values (fast to test before it is proven).
  3. Differential tests of model plus extractor against the real tool on real-world corpora:
     - go.mod vs `go mod edit -json`
     - package-lock vs `npm ls --json`
     - Cargo vs `cargo metadata`
     - proto vs `protoc --descriptor_set_out`
     - Dockerfile vs BuildKit's parser (`dockerfile2llb`, or a JSON dump of the parse)
     - pom vs `mvn help:effective-pom`
     - YAML vs yaml-test-suite and a reference library
  4. Standard corpora: JSONTestSuite, toml-test, yaml-test-suite, Buf corpus.
- Differential testing is the only practical check that the **format model matches reality**, i.e. the "small human-reviewed" spec. Proofs only connect code to the model.

### Gaps
- No published Lean project was found that differentially tests against `go`/`npm` tools specifically.
- Plausible's maturity (generator quality for structured text, shrinking) beyond the README was not assessed. The FVSpec paper (arXiv 2606.01008) on PBTs as Lean challenges was surfaced but not read, because arxiv.org is blocked.

---

## Q6. Effort estimates and reported experience

### Takeaway
Hard numbers are scarce. Cedar's Lean model is about 1.7k LOC against about 25k LOC of Rust, with about 5.7k lines of proof, which is roughly a 3.4:1 proof-to-model ratio. Its hardest proof (validator soundness) took 18 person-days. L4YAML needed about 5,000 lemmas for one complex format and still had a false headline theorem. Verified parsers usually cost a 2–5x slowdown against optimized unverified ones (CompCert 5x, Vermillion 2–4x), while combinator frameworks with code generation (Vest, EverParse) report parity.

### Cited Findings
- **Cedar:** the Lean model is about 1,700 lines against about 25,000 lines of Rust. Lean proofs total about 5,700 lines. The validator soundness proof, the most complex, took 18 person-days. — [AWS blog (KO)](https://aws.amazon.com/ko/blogs/opensource/lean-into-verified-software-development/); [AWS blog (ES)](https://aws.amazon.com/es/blogs/opensource/lean-into-verified-software-development/)
- **L4YAML:** about 4,975 lemmas plus 25 capstones, with no LOC or person-time stated. — [L4YAML](https://github.com/nasa-jpl/L4YAML)
- **CompCert's verified C99 parser:** 5x slower than the parser it replaced. — [Gallium blog](https://gallium.inria.fr/blog/verifying-a-parser-for-a-c-compiler)
- **Vermillion:** 2–4x slower than an unverified optimized LL(1) parser on JSON. — [ITP 2019](https://drops.dagstuhl.de/storage/00lipics/lipics-vol141-itp2019/LIPIcs.ITP.2019.24/LIPIcs.ITP.2019.24.pdf)
- **Vest:** on par with or faster than hand-written unverified parsers. — [USENIX](https://www.usenix.org/conference/usenixsecurity25/presentation/cai-yi)
- **CoStar:** linear time on common grammars. — [AMiner](https://www.aminer.cn/pub/60d3093691e01182ead65e02/costar-a-verified-all-parser)

### Inferences (rough planning numbers, my estimates; not sourced)
- **Line-oriented extractor** (go.mod, requirements.txt, Dockerfile) with T + A + S/C against a small model:
  - Order of 300–800 lines of Lean code+proof.
  - About 1–3 person-weeks each for an engineer fluent in Lean.
  - Grammar agreement adds roughly the same again.
- **Verified JSON syntax layer with spans** (T + A + round trip): about 1–2 person-months, since existing Lean JSON round-trip projects can be studied or reused. Proving RFC-grammar soundness and completeness adds about 1 person-month.
- **TOML with spans** (T + A + round trip on the data model, plus duplicate-key/table rules): about 2–3 person-months.
- **YAML subset:** about 2–4 person-months for a tightly restricted subset. Full YAML 1.2.2 is a multi-person-year effort (L4YAML scale). Prefer reusing or auditing L4YAML.
- **XML subset with no DTD:** about 2 person-months for syntax. The Maven semantic model (inheritance, properties) is a separate, larger task that may be better left as "model + differential test" without full proofs.
- Apply Cedar's roughly 3:1 proof:model ratio as a sanity check. Most cost goes into the semantic models and their review, not into totality or anchoring.

### Gaps
- No published person-month figures for EverParse, Vest, Narcissus, CoStar or L4YAML were found in this session. Proof-to-code ratios for verified parsers specifically, rather than Cedar's policy engine, remain unknown.
- The Cedar full paper (arXiv) could not be fetched, so the figures come from AWS blog editions.
