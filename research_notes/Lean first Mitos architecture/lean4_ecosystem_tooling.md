# Lean 4 ecosystem for a real-world CLI analysis tool (Mitos), as of 2026-11-06

Method note: Most core-library findings come from reading the `leanprover/lean4` source tree directly. I used a sparse clone of `master` at commit `a2f1a642` (2026-11-06), whose `src/CMakeLists.txt` says version 4.37 (dev), plus git history back to 2024-06. Release tags at that time: latest stable **v4.35.0** (released 2026-10-12), latest RC **v4.36.0-rc2** (2026-10-27). Community-library findings come from each repo's README and `lean-toolchain` file, fetched from raw.githubusercontent.com. lean-lang.org (including the reference manual, Reservoir and FRO roadmap pages) and leodemoura.github.io did not resolve from this sandbox. Claims about those pages come only from search-result snippets and are marked as such.

Release cadence for context: Lean ships monthly. v4.27.0 came out 2026-01-24, v4.28.0 2026-02-17, v4.30.0 2026-05-26, v4.31.0 2026-06-13, v4.32.0 2026-07-13, v4.33.0 2026-08-10, v4.34.0 2026-09-14 and v4.35.0 2026-10-12 — [Lean release notes index](https://lean-lang.org/doc/reference/latest/releases/) (search snippet).

## Data formats: JSON, TOML, YAML, XML, Protobuf, CSV (and whether source positions/byte spans are preserved)

### Takeaway
JSON is in core and actively maintained, but its AST has **no source positions**. TOML exists only inside Lake: `Lake.Toml` targets TOML v1.0.0 and does keep `Syntax` refs, which carry byte positions. Using it as a library pulls in the Lean frontend, which makes binaries large. YAML now has two community libraries: L4YAML (NASA JPL, verified, passes the full yaml-test-suite) and lean-yaml (pre-v1, with position-carrying rich AST). XML was **removed from core in Feb 2026**. I found no Protobuf or CSV library. Mitos will likely need its own position-preserving parsers for JSON, and probably for several other formats.

### Cited Findings
**JSON (`Lean.Data.Json`, core, maintained)**
- The AST is `inductive Json | null | bool | num (JsonNumber) | str (String) | arr (Array Json) | obj (Std.TreeMap.Raw String Json)`. It has no position or span field. Objects are stored in a sorted TreeMap, so the original key order is not kept — [src/Lean/Data/Json/Basic.lean](https://github.com/leanprover/lean4/blob/master/src/Lean/Data/Json/Basic.lean)
- The parser is written with `Std.Internal.Parsec` over `String` (file header credits Gabriel Ebner and Marc Huisinga). The module also has `Printer`, `Elab` (the `json%` syntax), `FromToJson` deriving and `Stream` — [src/Lean/Data/Json/Parser.lean](https://github.com/leanprover/lean4/blob/master/src/Lean/Data/Json/Parser.lean); directory listing of [src/Lean/Data/Json](https://github.com/leanprover/lean4/tree/master/src/Lean/Data/Json)
- Recent hardening, all from git history:
  - Rejects duplicate object keys in `Json.parse` (#15628, 2026-10-12).
  - Rejects nesting deeper than 10000 levels (#15996, 2026-10-30).
  - Limits number exponents (#15574, 2026-10-14).
  - Faster writing of non-ASCII strings (#16022, 2026-10-27).
  - Faster `FromJson` for big inductives (#11981, 2026-01-13).
  - Source: [lean4 PR #15628](https://github.com/leanprover/lean4/pull/15628), [#15996](https://github.com/leanprover/lean4/pull/15996), [#16022](https://github.com/leanprover/lean4/pull/16022)

**TOML (`Lake.Toml`, inside Lake)**
- The grammar is described as "A Lean encoding of the v1.0.0 TOML grammar" and links toml.io v1.0.0 and the 1.0.0 ABNF. One code comment says the ABNF allows DEL "but the test suite does not", so it was checked against a test suite — [src/lake/Lake/Toml/Grammar.lean](https://github.com/leanprover/lean4/blob/master/src/lake/Lake/Toml/Grammar.lean)
- Every value carries a `ref : Syntax`, for example `| string (ref : Syntax) (s : String)`, `| array (ref : Syntax) (xs : Array Value)` and `| table' (ref : Syntax) (xs : RBDict Name Value ...)`. `Syntax` carries `SourceInfo` with UTF-8 byte positions, so source spans are recoverable — [src/lake/Lake/Toml/Data/Value.lean](https://github.com/leanprover/lean4/blob/master/src/lake/Lake/Toml/Data/Value.lean)
- The entry point is `Lake.Toml.loadToml (ictx : InputContext) : EIO MessageLog Table`. It is built on Lean's own `Lean.Parser` framework and calls `mkEmptyEnvironment` before running the `toml` parser and `elabToml`. Using it therefore means linking the Lean compiler frontend (`Lean.Parser`, `Lean.Elab`) — [src/lake/Lake/Toml/Load.lean](https://github.com/leanprover/lean4/blob/master/src/lake/Lake/Toml/Load.lean)
- It lives in the `Lake` package namespace and is written for `lakefile.toml`. Recent Lake commits are about schema work ("prepare lakefile.toml schema for move to tombi", #15797, 2026-10-20). I saw no commits that present it as a general-purpose library — lean4 git log for `src/lake/Lake/Toml` ([#15797](https://github.com/leanprover/lean4/pull/15797))
- I found no `toml-test` suite vendored in the lean4 tree. A `git ls-tree` search for "toml-test" found nothing; `tests/lake` holds only example lakefiles — lean4 repo tree at `a2f1a642`

**YAML (community only)**
- **L4YAML** (github.com/nasa-jpl/L4YAML, mirrored at metalogiclabs/L4YAML):
  - A "machine-verified YAML 1.2.2 parser, schema layer, and dumper" with FFI adapters for C, Python and Rust. Pinned to `leanprover/lean4:v4.32.0`.
  - The core is total: "no `partial def`, no `axiom`, no `sorry`".
  - Proven properties: parse soundness, parser completeness relative to the token grammar, scanner→parser composition, and universal round-trip (`parse ∘ emit`). There are 25 capstone theorems, 7 of which are backed by `native_decide`.
  - One open converse remains (grammar completeness). The README admits that `InYamlLanguage` is currently over-approximated, so the forward acceptance theorem is "not yet restrictive".
  - README claims: "passes every case: all 308 valid event streams and all 279 JSON oracles match byte-for-byte, and every invalid input is rejected (event 402/402, JSON 282/282)". The event-stream output path (`parseStreamMarkedLoop`) is an *unverified* mirror of the verified parser.
  - Ships `ParserLimits` presets (strict, default, permissive, unlimited) for untrusted input. It has `Indexed/` "Position-indexed foundations (CharStream, TokenStream…)". The README does not clearly say whether the user-facing `YamlValue` carries source spans.
  - Source: [nasa-jpl/L4YAML README](https://github.com/nasa-jpl/L4YAML), [metalogiclabs/L4YAML](https://github.com/metalogiclabs/L4YAML)
- **lean-yaml** (tripp-smith):
  - Self-described as "pre-v1… useful for a supported YAML subset… not yet a full YAML 1.2.2 implementation". Pinned to Lean v4.29.1 and depends on fgdorais/lean4-parser.
  - Its "Rich AST with source positions/ranges, directives, comments, node trivia…" makes it the clearer option for position-preserving extraction. It also has a `YamlValue` model that keeps mapping order.
  - Plans to rewrite the line-oriented parser on lean4-parser.
  - Source: [tripp-smith/lean-yaml README](https://github.com/tripp-smith/lean-yaml)

**XML**
- `Lean.Data.Xml` was **removed** from core in commit `1ed3ce200`, 2026-02-04, "chore: remove unused `Lean.Data.Xml` (#12302)". It is absent from `src/Lean/Data` on master — [lean4 PR #12302](https://github.com/leanprover/lean4/pull/12302)
- Core still has `Lean.Data.Html` and `Lean.Data.Markdown`, which are used for docstrings and output — [src/Lean/Data](https://github.com/leanprover/lean4/tree/master/src/Lean/Data)

**Protobuf / CSV**
- The Lean core source tree has no Protobuf or CSV modules (directory listings of `src/Lean/Data` and `src/Std`) — [lean4 src/Std](https://github.com/leanprover/lean4/tree/master/src/Std)

### Inferences
- For evidence citations, core JSON is not usable as-is: no spans, and key order is lost. Mitos would need its own JSON parser that records spans. This is small, because the core parser is about 200 lines of Parsec and can serve as a template.
- Linking `Lake.Toml` brings in Lean's frontend. Expect binaries in the tens of MB (see the binary-size section). It is feasible but heavyweight. Porting the grammar to a standalone Parsec-based parser is a reasonable alternative. In either case, check spec compliance against the official `toml-test` suite yourself, since no such evidence is visible in-tree.
- YAML has gone from "does not exist" (before 2025) to two options. L4YAML has the strongest conformance and verification story. lean-yaml has the clearer position-preserving rich AST but is incomplete. Both are new, single-organisation projects, so pin and vendor them.
- XML (Maven `pom.xml`, `.csproj`, Android manifests): there is nothing in core anymore. Mitos must write its own parser, or shell out or use FFI to a C library such as libxml2 or expat.

### Gaps
- I could not verify the L4YAML or lean-yaml commit dates, star counts or maintenance activity, because the GitHub API was blocked in this session.
- I could not confirm whether L4YAML's public `YamlValue` or document types expose line, column or byte spans.
- I found no Protobuf, CSV, INI, HCL, Dockerfile or Gradle (Groovy/Kotlin DSL) parsers in Lean. I ran no dedicated Reservoir search for CSV or Protobuf, because reservoir.lean-lang.org was unreachable from this sandbox.
- I found no published JSON parsing performance numbers (MB/s) for `Lean.Json.parse`.

## Parsing infrastructure: Parsec, lean4-parser/ParseIt, Lean's own syntax framework for DSLs, tree-sitter

### Takeaway
Core ships `Std.Internal.Parsec`, a small parser-combinator library over `String` and `ByteArray`. Its namespace is still `Internal`, but core's JSON and HTTP code use it. fgdorais/lean4-parser is being **deprecated** in favour of lean4-parseit (support ends 2027-06-30). Lean's own extensible `syntax`/macro/elab framework is real, used in production (Lake TOML is built on it), and suitable for an embedded extraction-rule DSL. Tree-sitter bindings now exist (predictable-machines/lean4-tree-sitter v0.1.0), but they are early.

### Cited Findings
- `Std.Internal.Parsec` provides `Parsec ι α` with `fail`, `tryCatch`, `orElse`, `attempt`, `eof`, `many`, `many1`, `any`, `satisfy`, `notFollowedBy`, `peek?`, `skip`, `manyChars`. There are `String` and `ByteArray` instantiations. The String iterator exposes `pos it := it.2.offset`, a byte offset — [src/Std/Internal/Parsec/Basic.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Internal/Parsec/Basic.lean), [Parsec/String.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Internal/Parsec/String.lean)
- fgdorais/lean4-parser README: "**Users are urged to use the Lean 4 ParseIt library instead: github.com/fgdorais/lean4-parseit**… Support for the Lean 4 Parser library is scheduled to end on June 30, 2027." Its `lean-toolchain` is `v4.36.0-rc2`, so it is still kept current. Its parsers run over `String.Slice` — [fgdorais/lean4-parser](https://github.com/fgdorais/lean4-parser); also listed on [Reservoir @fgdorais/parser](https://reservoir.lean-lang.org/@fgdorais/parser)
- Lake's TOML parser is written with Lean's own `Lean.Parser` combinators: `toml.fn.run ictx {env, ...}` followed by an elaboration step (`elabToml`). The built-in syntax framework can parse non-Lean languages and keeps `Syntax` source info — [src/lake/Lake/Toml/Load.lean](https://github.com/leanprover/lean4/blob/master/src/lake/Lake/Toml/Load.lean)
- **lean4-tree-sitter** (predictable-machines):
  - "Safe Lean 4 wrappers around tree-sitter C API (parser, tree, node, query)".
  - Typed grammar schemas only for Java, Python and Kotlin.
  - An extraction engine that produces `Declaration` arrays "with source locations".
  - "Kernel-checked proofs of mapping totality, cross-language consistency, and source map correctness".
  - Requires Lean v4.32.0 and a C compiler. Builds through a Makefile that vendors grammars. Install tag `v0.1.0`.
  - Source: [predictable-machines/lean4-tree-sitter](https://github.com/predictable-machines/lean4-tree-sitter), [announcement blog](https://predictablemachines.com/blog/announcing-lean4-tree-sitter/)

### Inferences
- An extraction-rule DSL can be embedded as Lean syntax (`declare_syntax_cat`, `syntax`, `macro_rules`, `elab`). This is the same mechanism that Lake, the `json%` elaborator (`Lean/Data/Json/Elab.lean`) and Verso use. Rules then become ordinary Lean terms you can prove things about. This is one of Lean's strongest differentiators.
- For runtime parsing of manifest formats, a small Parsec layer with byte-offset positions is the low-risk path. Avoid starting on lean4-parser given its deprecation. Evaluate lean4-parseit, which I did not inspect.
- Tree-sitter: the FFI pattern works and v0.1.0 exists, but grammar coverage (Java, Python, Kotlin) and maturity are limited. For other languages (JS/TS, Go, Rust), Mitos would add grammars itself. Proofs over tree-sitter output can only be relative to the trusted C parser.

### Gaps
- I did not inspect lean4-parseit (API, maturity, position tracking).
- I found no benchmark comparing Parsec throughput with hand-written parsers.
- I did not verify lean4-tree-sitter's last-commit date or adoption.

## Tree-sitter / C FFI: how hard, and real binding examples

### Takeaway
C FFI is routine and well-trodden. Production-quality examples include the official **leansqlite** (Lean FRO repo, bundles the SQLite amalgamation, builds with plain `lake build`), several libcurl bindings, two raylib bindings, and tree-sitter. Lake compiles C sources and links them. The cost is hand-written C shims that use the `lean_object*` API and reference counting.

### Cited Findings
- **leanprover/leansqlite**:
  - "Lean bindings for SQLite… bundles the SQLite amalgamation and compiles it directly alongside the Lean FFI bindings", so no system install is needed.
  - Layered as raw FFI, then `SQLite.LowLevel`, then a higher-level API. Builds with `lake build`; tests run with `lake test`.
  - Toolchain `v4.36.0-rc2`, so it is maintained.
  - Source: [leanprover/leansqlite README](https://github.com/leanprover/leansqlite). The Lean account announced the open-sourcing: [Lean on X](https://x.com/leanprover/status/2015873346672734611)
- **curl-lean** (proofinity-it): "A comprehensive HTTP client and WebSocket library for Lean 4 built on top of libcurl, providing both low-level FFI bindings and high-level monadic interfaces". Toolchain `v4.35.0` — [proofinity-it/curl-lean](https://github.com/proofinity-it/curl-lean)
- The awesome-lean list also names `leancurl` and `LeanHttp` (libcurl-backed, TLS, redirects, HTTP/2). I did not verify these — [awesome-lean-programming](https://github.com/saviorand/awesome-lean-programming) (search snippet)
- raylib: `funexists/raylean` targets raylib 5.5. `KislyjKisel/Raylib.lean` targets raylib 4.5.0 and builds via a submodule, pkg-config or custom paths — [funexists/raylean](https://github.com/funexists/raylean), [KislyjKisel/Raylib.lean](https://github.com/KislyjKisel/Raylib.lean)
- Core FFI infrastructure exists in the compiler tree: `src/Lean/Compiler/ExternAttr.lean`, `FFI.lean`, `ExportAttr.lean` — [src/Lean/Compiler](https://github.com/leanprover/lean4/tree/master/src/Lean/Compiler)
- L4YAML shows the reverse direction: it exposes a Lean library through a C ABI (`l4yaml_parse(...)`) to Python and Rust — [nasa-jpl/L4YAML](https://github.com/nasa-jpl/L4YAML)

### Inferences
- From prior knowledge, not re-fetched this session: bindings use `@[extern "c_fn"] opaque f : ... → IO ...` on the Lean side. C shims use `lean.h` (`lean_object*`, `lean_box`/`lean_unbox`, `lean_alloc_external` with a finalizer class for wrapped C pointers, `lean_io_result_mk_ok`). Lakefiles declare `extern_lib` or `input_file`/`target` entries to compile `.c` files and `moreLinkArgs` for system libraries. Expect roughly 1–3 days to wrap a focused C API surface such as tree-sitter's parse/node/query.
- Bundling C sources (as leansqlite does) is the most portable distribution pattern.

### Gaps
- I did not fetch the reference manual's FFI chapter because lean-lang.org was blocked. Exact current Lake syntax (`extern_lib` versus newer `moreLinkObjs` and target forms) should be checked.
- I found no maintained LLVM or libgit2 bindings in this search, and did not look specifically.

## Systems IO: process spawning (git), filesystem, hashing, HTTP, concurrency, time

### Takeaway
Process spawning, filesystem access, tasks/async and time are all in core. Std now also has libuv-based async, TCP/UDP/DNS and an **HTTP/1.1 server** that left `Internal` in v4.31 (June 2026). Core has **no high-level HTTP client and no TLS**, so calling an HTTPS LLM API means a `curl` subprocess or curl-lean FFI. Core has **no SHA-256** either. One pure-Lean SHA-256 package exists (LeanSha256 v0.1.0, Sept 2026); otherwise use `git hash-object`/`sha256sum` or FFI.

### Cited Findings
- `IO.Process` in `Init/System/IO.lean` has `structure StdioConfig`, `structure SpawnArgs extends StdioConfig`, `def output (args : SpawnArgs) (input? : Option String := none) : IO Output` and `def run (args) : IO String` — [src/Init/System/IO.lean](https://github.com/leanprover/lean4/blob/master/src/Init/System/IO.lean)
- `Init/System` also has `FilePath`, `Promise`, `CancelToken`, `Platform` and `Uri` — [src/Init/System](https://github.com/leanprover/lean4/tree/master/src/Init/System)
- `Std.Async` has `Basic`, `ContextAsync`, `DNS`, `IO`, `Process`, `Select`, `Signal`, `System`, `TCP`, `Timer`, `UDP`, built on libuv (`Std/Internal/UV/*`). `Std.Net` has `Addr` — [src/Std/Async](https://github.com/leanprover/lean4/tree/master/src/Std/Async)
- A `Context` type for cancellation with propagation was added in v4.28.0 (#11499) — [Lean 4.28.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.28.0/) (search snippet)
- Async and Http were moved "from Internal to Std" (#13511, 2026-04-23, shipped in v4.31.0) — [lean4 PR #13511](https://github.com/leanprover/lean4/pull/13511); [v4.31.0 notes](https://lean-lang.org/doc/reference/latest/releases/v4.31.0/) (search snippet)
- `Std.Http` module doc: "A low-level HTTP/1.1 server implementation for Lean. This library provides a pure, sans-I/O protocol implementation that can be used with the `Async` library…" It supports keep-alive, chunked encoding and streaming bodies.
  - The tree has `Data` (Request, Response, Headers, URI, Body…), `Protocol/H1` (state machine, Parser, Reader, Writer, Redirect) and `Server`. There is no `Client` module and no TLS files anywhere in the tree.
  - Source: [src/Std/Http.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Http.lean)
- Some client-side pieces exist at the protocol level: `RedirectPlan`, a pure RFC 9110 redirect-decision module (#13901, 2026-07-23), and "complete bodyless HTTP responses on the client" (#14062). HTTP/1.1 parsing and framing fixes were still landing on 2026-11-06 (#16282), and v4.35.0 fixed server stalls from idle keep-alive connections (#15043) — [lean4 PR #13901](https://github.com/leanprover/lean4/pull/13901), [#16282](https://github.com/leanprover/lean4/pull/16282), [v4.35.0 notes](https://lean-lang.org/doc/reference/latest/releases/v4.35.0/) (search snippet)
- `Std.Async.Process` got a fix on 2026-10-24 for "out-of-range ids and correct libuv address, environment and process-title handling" (#15653) — [lean4 PR #15653](https://github.com/leanprover/lean4/pull/15653)
- `Std.Time` exists with `Date`, `DateTime`, `Duration`, `Format`, `Zoned` and `Notation` — [src/Std/Time](https://github.com/leanprover/lean4/tree/master/src/Std/Time)
- Hashing: a grep for sha256/SHA-256 in `src/Std`, `src/Lean/Data` and `src/Init/System` found nothing. Lake's utilities (`Lake/Util/Git.lean`, `Proc.lean`) shell out to git — [src/lake/Lake/Util](https://github.com/leanprover/lean4/tree/master/src/lake/Lake/Util)
- **LeanSha256** (etheorem): a pure-Lean SHA-256 following FIPS 180-4 §6.2, with no dependencies and CAVP test vectors. v0.1.0 is dated 2026-09-11. It is a mirror of the etheorem monorepo — [Reservoir @etheorem/LeanSha256](https://reservoir.lean-lang.org/@etheorem/LeanSha256) (search snippet)
- A SHA-3/SHAKE package (`@gdncc/cryptography`) is labelled educational, "not meant for production cryptography" — [Reservoir @gdncc/cryptography](https://reservoir.lean-lang.org/@gdncc/cryptography) (search snippet)

### Inferences
- Spawning `git` (`git rev-parse`, `git ls-tree`, `git cat-file --batch`) through `IO.Process.spawn` or `output` is the pragmatic way to read pinned commits. A git-object reader written in Lean would also need zlib. I found no zlib binding, but did not search specifically.
- For LLM calls, a `curl` subprocess is the zero-dependency option. curl-lean is the in-process option. Std.Http alone cannot do HTTPS.
- For content hashing: use git's own object IDs (SHA-1/SHA-256 from git) or LeanSha256. The latter is pure Lean, which makes it attractive for proofs, but expect it to be much slower than OpenSSL. This is unbenchmarked.
- Concurrency: `Task`/`IO.asTask` (core, from prior knowledge) plus `Std.Async` give parallel per-repository scanning. Lean's reference-counted runtime is thread-safe and multi-threaded.

### Gaps
- I did not verify the license or maintenance of LeanSha256, or its performance.
- I have no evidence of a TLS binding (OpenSSL or rustls) other than via libcurl.
- I could not read v4.36.0 release notes for further HTTP/Async changes.

## Data structures: verified Std containers, Array, ByteArray/String/UTF-8 offsets

### Takeaway
Std has a large, verified container family: HashMap/HashSet/DHashMap, TreeMap/TreeSet/DTreeMap, and "Ext" variants with extensional equality. Each has a dedicated Lemmas file with hundreds to over a thousand theorems. Strings are UTF-8 with byte-indexed positions (`String.Pos.byteIdx`), which suits byte-span evidence. Core also has `String.Slice` and `ByteSlice`.

### Cited Findings
- `src/Std/Data` contains `HashMap`, `HashSet`, `DHashMap`, `ExtHashMap`, `ExtHashSet`, `ExtDHashMap`, `TreeMap`, `TreeSet`, `DTreeMap`, `ExtTreeMap`, `ExtTreeSet`, `ExtDTreeMap`, `Iterators`, `String` and `ByteSlice` — [src/Std/Data](https://github.com/leanprover/lean4/tree/master/src/Std/Data)
- Theorem counts at 2026-11-06 (`grep -c theorem Lemmas.lean`):

  | Lemmas file | Theorems |
  |---|---|
  | HashMap/Lemmas.lean | 683 |
  | DHashMap/Lemmas.lean | 968 |
  | HashSet/Lemmas.lean | 325 |
  | TreeMap/Lemmas.lean | 993 |
  | DTreeMap/Lemmas.lean | 1332 |

  These exclude the separate `RawLemmas` and `IteratorLemmas` files — [src/Std/Data/HashMap/Lemmas.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Data/HashMap/Lemmas.lean), [TreeMap/Lemmas.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Data/TreeMap/Lemmas.lean)
- Core `Lean.Json` itself switched object storage to `Std.TreeMap.Raw`, a sign that these containers are the blessed ones — [src/Lean/Data/Json/Basic.lean](https://github.com/leanprover/lean4/blob/master/src/Lean/Data/Json/Basic.lean)
- `String.Pos` has `byteIdx : Nat` (in `Init/Prelude.lean`), so positions are UTF-8 byte offsets — [src/Init/Prelude.lean](https://github.com/leanprover/lean4/blob/master/src/Init/Prelude.lean)
- Late-2025 refactors route `String` functions through `String.Slice` (#11357, 2025-11-25) — [lean4 PR #11357](https://github.com/leanprover/lean4/pull/11357)
- `Std.ByteSlice` is "a modified version of the `SubArray` code" for byte arrays — [src/Std/Data/ByteSlice.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Data/ByteSlice.lean)
- The FRO Year 3 workshop slides list library work as "map containers, iterators, systematic library development" — [Breitner, FRO Lean Workshop @ ITP 2025 slides](https://icetcs.github.io/frocos-itp-tableaux25/slides/itp/lean1-breitner.pdf) (search snippet)

### Inferences
- Byte-offset positions plus verified maps make Lean well suited to span-carrying fact stores where proofs about lookups and merges are wanted.
- The String API has churned (moves to `String.Slice`). Pin the toolchain and budget for migrations on upgrade.
- Arrays are mutated in place when uniquely referenced (functional-but-in-place). This is from prior knowledge, not re-verified here.

### Gaps
- I found no published benchmarks for Std.HashMap against Rust or C++ maps.

## Build/distribution: Lake, native executables, binary size, cross-platform, Reservoir, toolchain pinning, compile times

### Takeaway
Lake (bundled with Lean) builds native executables by compiling Lean to C and then using the bundled clang. The **new LCNF compiler has been the default since mid-2025**. Binaries statically link the runtime: a few MB for trivial programs, but **tens of MB (60–89 MB reported) once you import the `Lean` frontend**, which `Lake.Toml` requires. Toolchains are pinned per project via `lean-toolchain` and elan. Releases are monthly, with frequent breaking API changes.

### Cited Findings
- The new compiler was enabled on 2025-06-14 ("feat: enable the new compiler", `7f8ccd842`), and the `compiler.enableNew` option was removed on 2025-07-08 (#9252). `src/Lean/Compiler/LCNF` is the pipeline; `Old.lean` remains — [lean4 PR #9252](https://github.com/leanprover/lean4/pull/9252)
- The pipeline compiles Lean to C. A January 2026 Zulip reply confirmed "Lean compiles to C. In theory it could go through LLVM without C" — [Zulip: Two questions about building Lean with compiler optimization](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/Two.20questions.20about.20building.20Lean.20with.20compiler.20optimization.html) (search snippet)
- Binary size:
  - Simple programs are around 5 MB because "The runtime is statically linked into the binary" — [Zulip: Reducing binary size](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/Reducing.20binary.20size.html)
  - A 2023 thread reports about 60 MB with std4, and a 2024 thread reports 89 MB: "if you depend on any module in Lean, all Lean code will be linked into your binary" — [Zulip: Large binary sizes](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/Large.20binary.20sizes.html), [Zulip: Reducing executable size](https://leanprover-community.github.io/archive/stream/113488-general/topic/Reducing.20executable.20size.html). These threads predate 2025 and may be outdated after the module system and new compiler.
- The module system (`module`, `public import`, `public section`) is now pervasive in core sources, for example every file inspected starts with `module` — [src/Std/Http.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Http.lean)
- Lake remains active: "package-specified cache services" (#16302, 2026-11-06), "`copy` option for path dependencies" (#15142, 2026-09-17), and module-system options in the TOML schema (#14083) — [lean4 PR #16302](https://github.com/leanprover/lean4/pull/16302)
- Toolchain pins seen across libraries:

  | Library | `lean-toolchain` |
  |---|---|
  | leansqlite, lean4-parser | v4.36.0-rc2 |
  | curl-lean | v4.35.0 |
  | L4YAML, lean4-tree-sitter | v4.32.0 |
  | lean-yaml | v4.29.1 |

  Source: each repo's `lean-toolchain` (e.g. [leansqlite](https://github.com/leanprover/leansqlite))
- Reservoir (reservoir.lean-lang.org) is the package index. Packages pin by git tag or rev in `lakefile` `[[require]]` — [Reservoir @fgdorais/parser](https://reservoir.lean-lang.org/@fgdorais/parser), [@etheorem/LeanSha256](https://reservoir.lean-lang.org/@etheorem/LeanSha256)
- Current roadmap: the FRO switched to six-month roadmaps. "Year 4 – Part 1" covers Sept 2026 – Feb 2027 and focuses on hardening Verso, Blueprints and Games, plus enabling "external teams [to] verify real software in Lean" — [Lean FRO Year 4 Part 1 Roadmap](https://lean-lang.org/fro/roadmap/y4-1) (search snippet), [Year 3 roadmap](https://lean-lang.org/fro/roadmap/y3/) (search snippet)

### Inferences
- **Version skew is the biggest practical risk.** Different libraries pin six different toolchains, from v4.29.1 to v4.36.0-rc2. Combining L4YAML, tree-sitter, curl-lean and SQLite will force upgrading or forking some of them, because Lake needs one toolchain per build. Vendor dependencies and plan to bump toolchains roughly quarterly.
- To keep binaries small, avoid importing `Lean` (and therefore `Lake.Toml`) in the shipped executable. Depend only on `Init` and `Std`, and reimplement TOML on Parsec.
- Cross-platform: elan ships toolchains for Linux, macOS and Windows (from prior knowledge). FFI-heavy dependencies (tree-sitter grammars, curl) are where cross-platform builds break.

### Gaps
- I found no current (2026) measurements of binary size or compile time for a Std-only CLI under the new compiler and module system.
- I could not confirm Reservoir package counts or the indexing criteria, because the site was unreachable.

## Real-world non-math software in Lean 4 and lessons

### Takeaway
Lean is used for real software mainly in "verified model + production implementation" setups, where AWS Cedar is the flagship, and in Lean's own tooling (Lake, the language server, doc-gen4, Verso). Fully Lean-native application software is emerging but young: a RealWorld web-app experiment, a SQLite binding and an HTTP server in Std. Performance is competitive for algorithmic cores, and the library ecosystem is the bottleneck.

### Cited Findings
- **AWS Cedar:**
  - Lean models are differentially tested against the production Rust using millions of random inputs. "On average, Lean takes 5 microseconds to evaluate a differential testing input, compared to 7 microseconds for Rust", which enables "millions of test cases nightly".
  - Releases are gated on the model, proofs and differential tests being up to date.
  - Proofs found 4 validator bugs; differential and property-based testing found 21 more.
  - Sources: [AWS Open Source Blog: Lean Into Verified Software Development](https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development), [How We Built Cedar (arXiv 2407.01688, 2024)](https://arxiv.org/pdf/2407.01688)
  - A Zulip thread cautions that the 5 μs vs 7 μs figure is not a rigorous benchmark — [Zulip: Mysterious quote suggests that Lean is faster than Rust](https://leanprover-community.github.io/archive/stream/113488-general/topic/Mysterious.20quote.20suggests.20that.20Lean.20is.20faster.20than.20Rust.html)
  - A 2026 de Moura talk lists Cedar as used by AWS Verified Permissions and Verified Access — [Lean: A Unified Platform… (ETAPS industry 2026)](https://leodemoura.github.io/static/etaps-industry-2026/) (search snippet)
- **RealWorld app experiment (2026):** a Medium-clone backend and frontend in Lean 4 passed the RealWorld test suite. Reported sizes conflict: about 1,033 backend lines versus about 1,600 for the whole app. The author flagged HTTP server performance limits and the immaturity of libraries; Postgres, crypto and HTML libraries were being built by the community — [zeli.app (ja)](https://zeli.app/ja/story/50088748), [zeli.app (zh)](https://zeli.app/zh/story/50088748). These are secondary aggregator summaries.
- **NASA JPL's L4YAML** is a non-math verified-parser project with C, Python and Rust bindings — [nasa-jpl/L4YAML](https://github.com/nasa-jpl/L4YAML)
- **Lake** is itself a substantial non-math Lean program: a build system with a TOML parser, git handling and cache services — [src/lake](https://github.com/leanprover/lean4/tree/master/src/lake)
- **Std.Http server** comes from the Lean FRO (author Sofia Rodrigues, 2025–2026) — [src/Std/Http.lean](https://github.com/leanprover/lean4/blob/master/src/Std/Http.lean)

### Inferences
- The Cedar pattern of a Lean reference model, proofs and differential testing against fast production code is the best-proven industrial pattern. Mitos could apply it to resolution logic, even if some extractors use FFI or tree-sitter.
- "Lean 4 first" is feasible for orchestration, the data model, resolution logic and simple manifest parsers. Most formats will require writing (and proving) Mitos's own parsers. Plan for FFI or subprocesses for git, TLS/HTTP, tree-sitter and possibly XML.

### Gaps
- I did not obtain primary sources for SampCert (AWS), LNSym, Aeneas, lean4-cli, doc-gen4 or ProofWidgets in this session, so their status is unverified here.
- I have no quantitative productivity data for Lean versus Rust or Go.
