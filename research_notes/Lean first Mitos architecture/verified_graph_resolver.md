# Verified Graph-Based Resolution Engine in Lean 4 (survey as of Nov 2026)

Scope note: These notes answer how to build and prove the Mitos trusted core in Lean 4. That core is a resolver from provides/requires "facts" to a typed relationship graph, with provenance, assumption tracking, impact analysis and aggregation. Research environment caveat: the session's network policy blocked direct fetches of `drops.dagstuhl.de`, `kr.org` and `lean-lang.org`. Facts from those hosts come from search-result summaries, not full-text reads. Statements marked "(background knowledge, unverified here)" in Inferences come from the researcher's prior knowledge and were not confirmed by a source in this session.

## Q1. Graph libraries and executable verified graph algorithms in Lean 4

### Takeaway
Mathlib has rich *specification-level* graph vocabulary (SimpleGraph walks/reachability with a decidability instance, relation closures), but no standard executable, verified BFS/DFS/SCC library. The existing Lean 4 verified graph-search code lives in small research repos (BS-DFS, Johnson path enumeration, lean4-search-algorithms, complexitylib). Mitos should write its own small worklist reachability and prove it against `Relation.ReflTransGen` / `TransGen`.

### Cited Findings
- Mathlib provides `SimpleGraph.instDecidableRelReachable`, which needs `[DecidableEq V]`, `[Fintype V]` and `[DecidableRel G.Adj]`. It is built through `reachable_iff_exists_finsetWalkLength_nonempty` and `decidable_of_iff'` over a bounded-length walk search. This is a proof-friendly but exponential-style decision procedure, not an efficient BFS. — [Zulip: Proving Decidable (g.Reachable v0 v1)](https://leanprover-community.github.io/archive/stream/252551-graph-theory/topic/Proving.3A.20Decidable.20(g.2EReachable.20v0.20v1).html); [Zulip: Decidability for connected components](https://leanprover-community.github.io/archive/stream/252551-graph-theory/topic/Decidability.20for.20connected.20components.html)
- `Mathlib.Combinatorics.SimpleGraph.Metric` links reachability to distance, e.g. `SimpleGraph.Reachable.exists_walk_length_eq_edist`. This helps when shortest-walk witnesses are needed. — [Mathlib docs: SimpleGraph.Metric](https://leanprover-community.github.io/mathlib4_docs/Mathlib/Combinatorics/SimpleGraph/Metric)
- `FrankBau/bsdfs_lean` is a Lean 4 formalization of a Bounded-Scope DFS path-enumeration algorithm. It uses Lean core 4.34.1 with no extra libraries. Its author warns that the executable checks membership by linear scan, so the theorems say nothing about running time. — [GitHub bsdfs_lean](https://github.com/FrankBau/bsdfs_lean)
- `FrankBau/johnson_lean` proves soundness, completeness and delay bounds for a Johnson-style simple s–t path enumerator. The Lean function needs *depth guards* (fuel) for termination, and the trace/loop infrastructure is reused from BS-DFS. — [GitHub johnson_lean](https://github.com/FrankBau/johnson_lean)
- A cslib roadmap issue records that complexitylib has breadth-first reachability and Dijkstra over word-RAM. It also records that Behnke/Kilian/Gattinger's `lean4-search-algorithms` has DFS, BFS, Dijkstra and A* over explicit finite weighted digraphs, with A* termination via well-founded recursion. The researcher did not open these repos. — [cslib EpsilonEridaniRoadmap issue #9](https://github.com/cslib-community/EpsilonEridaniRoadmap/issues/9)
- AlgoVeri (2026) is a benchmark for verified code generation on classical algorithms, including graph algorithms, across verifiers including Lean. This indicates that graph algorithm verification in Lean is still an active "benchmark-level" problem, not a solved library. — [AlgoVeri arXiv 2602.09464](https://arxiv.org/pdf/2602.09464)
- Lean's kernel has no termination checker of its own. Definitions must elaborate to structural or well-founded recursion, so the usual options for BFS/DFS are fuel/depth or a measure such as "number of unvisited vertices". — [Zulip: Proving termination in nested inductives](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/Proving.20termination.20in.20nested.20inductives.html)

### Inferences
- (background knowledge, unverified here) Mathlib also has `Digraph` (`Mathlib/Combinatorics/Digraph/Basic.lean`, an `Adj : V → V → Prop` with no symmetry or irreflexivity), `Quiver`/`Quiver.Path` (typed multi-edges; a good fit for *labelled* edges like Mitos's typed relationships) and `Relation.ReflTransGen`/`TransGen` in `Mathlib/Logic/Relation.lean`. Core Lean also has `Relation.ReflTransGen`-style closures used by `grind`/`simp` lemmas. For Mitos, the cleanest spec is `Relation.ReflTransGen (fun a b => (b, a) ∈ edges)` for reverse reachability. `SimpleGraph` is the wrong abstraction because it is undirected and loopless.
- The standard termination measure for worklist reachability over a finite node universe `U` is `(U \ visited).card` (or `U.length - visited.size`), which decreases on each newly visited node. Fuel = `|U|` (or `|U|+1`) is a cheaper-to-prove alternative. A completeness lemma then shows fuel never runs out.
- Correctness of reachability is a two-part invariant proof: (a) soundness, where everything in `visited` is ReflTransGen-reachable; and (b) completeness at termination, where `visited` is closed under successor and contains the source, so it contains the reachable set. This is the classic "closed set containing the seed" argument and needs no path-enumeration machinery.

### Gaps
- Could not confirm the contents, Lean version or maintenance status of `lean4-search-algorithms` or complexitylib's BFS. Found no Lean 4 verified Tarjan/Kosaraju SCC or verified topological sort in a maintained library. (Isabelle's AFP has verified Tarjan/Gabow SCC; that is not confirmed in this session.)
- Could not fetch Mathlib's Digraph/Quiver docs (lean-lang.org/mathlib docs fetch blocked or not attempted). Exact API names should be checked against the pinned Mathlib.

## Q2. Verified Datalog, provenance, and certified result checking

### Takeaway
A Lean 4 Datalog formalization does exist. Tantow, Gerlach, Mennicke and Krötzsch (ITP 2025) built a verified *certificate checker* in Lean 4 for Datalog entailments, with proof-tree and DAG certificate formats produced by the Nemo engine (`knowsys/CertifyingDatalog`). This is the closest prior art to the Mitos resolver and directly validates the "untrusted engine + verified checker" architecture. Coq has the full verified-engine approach (Benzaken/Contejean/Dumbrava, ITP 2017). Semiring provenance theory is mature, but the researcher found no proof-assistant formalization of it.

### Cited Findings
- "Verifying Datalog Reasoning with Lean" (Tantow, Gerlach, Mennicke, Krötzsch; ITP 2025, LIPIcs vol. 352, paper 36, DOI 10.4230/LIPIcs.ITP.2025.36). The authors implement a certificate-based Datalog checker in Lean and verify it against direct formalizations of Datalog semantics (syntax, unification, model theory). They evaluate it on synthetic and real tasks with proofs generated by the Nemo Datalog engine. — [DROPS entry](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ITP.2025.36); [TU Dresden ICCL page](https://iccl.inf.tu-dresden.de/web/Inproceedings3417)
- The paper proposes two JSON encodings for Datalog proofs: standard proof trees, and directed acyclic graphs for succinctness, since shared subproofs make trees blow up. — [DROPS entry](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ITP.2025.36)
- Code: `knowsys/CertifyingDatalog` is "a certified checker for Datalog entailments, written in Lean". It checks proof trees and DAG-encoded proofs, depends on Mathlib (`lake exe cache get`), is Apache-2.0/MIT, has about 303 commits, and is tagged v0.2.0 / archived at Software Heritage. — [GitHub knowsys/CertifyingDatalog](https://github.com/knowsys/CertifyingDatalog); [Reservoir listing](https://reservoir.lean-lang.org/@knowsys/certifyingDatalog)
- A KR 2025 extended abstract of the same work exists. — [ICCL Inproceedings3429](https://iccl.inf.tu-dresden.de/web/Inproceedings3429)
- The Tantow et al. paper cites a model-theoretic formalization of *stratified* Datalog by Schlichtkrull et al. as related work. Its proof assistant was not confirmed here. — [search summary of ITP 2025 PDF](https://drops.dagstuhl.de/storage/00lipics/lipics-vol352-itp2025/LIPIcs.ITP.2025.36/LIPIcs.ITP.2025.36.pdf)
- Coq/SSReflect: Benzaken, Contejean, Dumbrava, "Certifying Standard and Stratified Datalog Inference Engines in SSReflect" (ITP 2017, LNCS pp. 171–188). It mechanizes standard and stratified Datalog with model-theoretic and fixpoint semantics, bottom-up and stratified evaluation, and proofs of soundness, termination, completeness and model minimality. (The title "Towards a verified Datalog engine" given in the brief does not appear to exist; this is the matching paper.) — [HAL hal-01745566](https://hal.archives-ouvertes.fr/hal-01745566/); [dblp](https://dblp1.uni-trier.de/rec/conf/itp/BenzakenCD17.html)
- Follow-up: Bonifati, Dumbrava, Gallego Arias, "Certified Graph View Maintenance with Regular Datalog" (TPLP 2018) reuses the Coq engine for *incremental* graph-view maintenance, with mechanized stratified-satisfaction theory. This is relevant prior art for Mitos's retraction/invalidation theorem. — [arXiv 1804.10565](https://arxiv.org/pdf/1804.10565)
- Dumbrava's 2016 thesis, "A Coq Formalization of Relational and Deductive Databases and Mechanizations of Datalog". — [LRI thesis page](https://www.lri.fr/these.habilitation_en.php%3Fths=745.html)
- Semiring provenance (Green, Karvounarakis, Tannen, PODS 2007): provenance polynomials N[X] are universal for commutative semirings. For recursive Datalog, provenance lives in formal power series N∞[X] (ω-continuous semirings). Why-provenance is an instance. — [PODS 2007 paper](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf); [Tannen PODS 2015 slides](https://www.cis.upenn.edu/~val/15MayPODS.pdf)
- "Revisiting Semiring Provenance for Datalog" (Bourgaux, Ozaki, Peñaloza, Predoiu; KR 2022) argues that semiring provenance is uncontroversial for UCQs but less clear for Datalog. It compares definitions based on derivation trees vs. fixpoints, and treats why-provenance/minimal-derivation variants. — [arXiv 2202.10766](https://arxiv.org/pdf/2202.10766); [KR 2022 proceedings](https://proceedings.kr.org/2022/10/kr2022-0010-bourgaux-et-al.pdf)
- The researcher found no proof-assistant (Coq/Isabelle/Lean) formalization of semiring provenance in searches. — [search: semiring provenance formalized](https://arxiv.org/pdf/2202.10766) (absence noted)

### Inferences
- The Mitos resolver is non-recursive or bounded-depth *positive* Datalog (multi-step resolution is a chain of joins: config-key → deployment → service → repo → HTTP op). Positive Datalog has a unique least model, so soundness and completeness of a derivation are easy to state. Each derived edge's "exact assumption set" corresponds to **why-provenance / lineage** (the set of base facts and rules used in a particular derivation tree). Plain set-of-leaves lineage is the PosBool/Lin semiring; minimal witness sets are why-provenance.
- "Exactly the rules/declarations used in its derivation" is well-defined per *derivation*, not per *fact*. A fact with two independent derivations has two witness sets. Mitos must decide whether an edge carries one chosen derivation (simpler, deterministic) or the set of all minimal witnesses (why-provenance, potentially exponential). "Retracting an assumption invalidates exactly the edges that depend on it" is only true for *all-derivations* semantics: an edge survives if some alternative derivation avoids the retracted assumption. This is the central design choice for the assumption-tracking theorem.
- The DAG certificate format of Tantow et al. maps directly onto Mitos edges with shared sub-derivations, such as many edges sharing "service S built from repo R".

### Gaps
- Could not read the full Tantow et al. paper (dagstuhl/kr.org fetch blocked). Exact theorem names, checker complexity, benchmark numbers (proof sizes, checking times) and whether the checker uses `HashMap` or `List` were not obtained.
- Did not confirm whether Schlichtkrull et al.'s stratified Datalog formalization is in Isabelle (likely, but unverified).
- The researcher found no Lean formalization of semiring or why-provenance.

## Q3. Truth maintenance systems (JTMS/ATMS) as the model for assumption tracking

### Takeaway
The ATMS (de Kleer 1986) is the right conceptual model for Mitos's "each edge lists exactly the assumptions it depends on". ATMS labels are sets of minimal assumption environments, the same thing as why-provenance over assumptions. The researcher found no machine-checked TMS formalization in any proof assistant, so Mitos would be first-of-kind. It should state its theorem in Datalog-provenance terms rather than TMS terms.

### Cited Findings
- De Kleer's ATMS (1986) labels each node with environments (sets of assumptions) under which it holds, and maintains minimal inconsistent environments ("nogoods"). — [academia.edu: Extending the ATMS](https://www.academia.edu/121049762/Extending_the_ATMS); [AAAI-88 paper](https://cdn.aaai.org/AAAI/1988/AAAI88-036.pdf)
- A lattice-theoretic formalization of the ATMS (semantics, label operation, focusing algorithms) exists on paper. It is mathematical, not machine-checked. — [Springer LNCS BFb0028211](https://unpaywall.org/10.1007%2FBFb0028211)
- Reiter & de Kleer (1987) gave the best-known semantics, which formalizes labels but not the label-computation operation, per a 1988 UBC technical report. — [UBC TR-88-11](https://www.cs.ubc.ca/sites/default/files/tr/1988/TR-88-11.pdf)
- No search result turned up a Coq/Isabelle/Lean formalization of a JTMS or ATMS. — [search summary](https://www.academia.edu/21706676/Focusing_ATMS_Problem_Solving_A_Formal_Approach) (absence noted)

### Inferences
- ATMS label invariants map onto four Mitos theorem obligations: *sound* (each environment really derives the node), *complete* (every deriving environment is a superset of some label environment), *minimal* (no environment in a label subsumes another), and *consistent* (no environment is a superset of a nogood). If Mitos stores only one derivation per edge (JTMS-style justification), it loses completeness. Retraction then needs re-derivation: "invalidate, then try to re-prove", as in DRed incremental Datalog maintenance.
- A tractable Lean theorem for retraction: define `derivable (A : Finset Assumption) e` inductively. Prove `recompute (A \ {a}) = { e ∈ recompute A | ∃ env ∈ label e, a ∉ env }`, i.e. retraction is filtering of labels. With full minimal labels this needs no re-run. With single justifications, prove instead that `recompute (A \ {a})` equals running the resolver from scratch, so incremental equals from-scratch.
- AI-originated edges ("never confirmed") fit an ATMS-style tag: a distinguished assumption class `ai(_)`. "Confirmed" becomes a predicate `∀ env ∈ label e, env ∩ AI = ∅` (or `∃`, depending on policy). The theorem then follows from a provenance-propagation lemma: every derived edge's environment includes every input's environment.

### Gaps
- The researcher found no formal verification of TMS algorithms or DRed/incremental Datalog in Lean. The Coq "Certified Graph View Maintenance" is the nearest.

## Q4. Certificate/witness checking vs. full verification

### Takeaway
The certificate-checking pattern is proven in Lean 4 for Datalog specifically (CertifyingDatalog) and is the industrial norm for SAT (LRAT/LPR with CakeML-verified `cake_lpr`). It confines the proof burden to a small checker, at the cost of only guaranteeing *soundness of what was emitted*. Totality ("every requirement is either an edge or listed unresolved") and impact-analysis completeness cannot be obtained from a positive-derivation certificate alone. They need either a verified engine or a verified *completeness check* (e.g., a closure/fixpoint check).

### Cited Findings
- `cake_lpr` (Tan, Heule, Myreen; TACAS 2021, extended in STTT 2023) is a verified LPR/LRAT proof checker in CakeML, verified down to machine code via CakeML's binary extraction. It validated the unsatisfiability proofs of SAT Competition 2020. The journal version adds a compositional format for parallel checking. — [PMC: cake_lpr](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7984575/); [Chalmers: Verified PR and Compositional UNSAT Checking](https://research.chalmers.se/publication/534843); [Springer STTT](https://link.springer.com/doi/10.1007/s10009-022-00690-y)
- The LPR format is backwards compatible with LRAT. Before cake_lpr, the only verified route for PR proofs was a transformation to a weaker proof system. This shows the value of designing the certificate format to suit the checker. — [PMC: cake_lpr](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7984575/)
- CertifyingDatalog checks an untrusted engine's (Nemo's) proof trees or DAGs against a Lean-formalized Datalog semantics. It establishes that facts in the certificate are entailed (soundness), not that the engine found *all* consequences. — [DROPS entry](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ITP.2025.36); [GitHub](https://github.com/knowsys/CertifyingDatalog)
- AWS Cedar's SymCert work decomposes symbolic-compiler correctness into "reducibility" and "interpretability" properties in Lean. This is a reusable decomposition for a verified compiler/translator. It is listed for FMCAD 2026. — [Amazon Science: SymCert](https://www.amazon.science/publications/symcert-verifying-smt-based-policy-analyses); [TU Wien record](https://repositum.tuwien.at/handle/20.500.12708/230492?mode=full)

### Inferences
- Trade-off matrix for Mitos:
  - **Full verification of the resolver** (a Lean function `resolve : Facts → Graph` plus theorems). This gives all properties, including totality and exactness, but the proof effort scales with optimization (indexes, HashMaps, incremental update).
  - **Certificate checking only.** Soundness, scope preservation, AI-not-confirmed and assumption exactness *per emitted edge* all become cheap. Totality is lost unless the certificate also contains, for each unresolved requirement, a *non-derivability witness*. For positive Datalog, that witness is that the emitted fact set is a model, i.e. closed under all rules. Checking "is a model" needs a full rule-application pass, which is essentially evaluating the rules once and is not cheap.
  - **Hybrid (recommended).** Keep a *simple verified reference resolver* in Lean (List/Finset-based, with all theorems). Run a fast untrusted resolver in production (Lean with HashMaps, or Rust/Go). Validate each production output with a verified checker (soundness plus a closure check for totality). Also run Cedar-style differential random testing between the fast resolver and the Lean reference.
- Because Mitos's rule set is fixed and small (a few join patterns, not arbitrary user Datalog), a *closure check* is a linear pass with hash indexes over facts. This makes "certificate + model check" give both soundness *and* completeness cheaply. It is a decisive advantage over general Datalog.

### Gaps
- No quantitative data was obtained on checker performance in CertifyingDatalog (paper full text blocked).

## Q5. Lean 4 proof-engineering toolkit (2024–2026)

### Takeaway
As of Lean 4.35 (Oct 2026), the toolkit for verifying Mitos-style code is mature. It includes `Std.HashMap/TreeMap` lemmas verified against list models, `grind` (SMT-style, since 4.22), `fun_induction`/`fun_cases`, `partial_fixpoint`, and the `Std.Do` Hoare-logic framework for imperative `do`/for-loop code. Std.Do's VC generator was `mvcgen` (4.22–4.34) and is now `vcgen` (4.35, `mvcgen` deprecated). Write the trusted core as pure functional code over `List`/`Array`/`HashMap`, prove with `fun_induction` + `grind`, and reserve `Std.Do`/`vcgen` for any genuinely imperative hot loops.

### Cited Findings
- **Std.Do / mvcgen timeline.**
  - 4.22.0 (Aug 2025): introduced Hoare-logic `Std.Do`, `mvcgen` (turns Hoare triples into VCs closable by `simp`, `grind` or stateful proof mode) and the `SPred` logic of stateful predicates (import `Std.Tactic.Do`).
  - 4.23.0 (Sep 2025): `mvcgen` splits `if`s; adequacy theorems extended to `ReaderM`/`ExceptM`; revised invariant/postcondition API with breaking changes.
  - 4.24.0 (Oct 2025): `mvcgen ... using` invariants and `with` sections; `Std.Do.Triple.mp`.
  - 4.26.0 (Dec 2025): `mvcgen` performance.
  - 4.28.0 (Feb 2026): early-return and lost-VC bug fixes.
  - 4.29.0 (Mar 2026): specs in local context; new extensible `do` elaborator.
  - 4.32.0 (Jul 2026): `mvcgen'` with `until` clause.
  - 4.33.0 (Aug 2026): port to `Std.Internal.Do`; a WP type class beyond monads.
  - 4.35.0 (Oct 2026): **`vcgen`** supersedes `mvcgen` (deprecated). One cited benchmark is 0.32 s vs 66 s.

  Sources: [v4.22.0](https://lean-lang.org/doc/reference/latest/releases/v4.22.0/); [v4.23.0](https://lean-lang.org/doc/reference/latest/releases/v4.23.0/); [v4.24.0](https://lean-lang.org/doc/reference/latest/releases/v4.24.0/); [v4.26.0](https://lean-lang.org/doc/reference/latest/releases/v4.26.0/); [v4.28.0](https://lean-lang.org/doc/reference/latest/releases/v4.28.0/); [v4.29.0](https://lean-lang.org/doc/reference/latest/releases/v4.29.0/); [v4.32.0](https://lean-lang.org/doc/reference/latest/releases/v4.32.0/); [v4.33.0](https://lean-lang.org/doc/reference/latest/releases/v4.33.0/); [v4.35.0](https://lean-lang.org/doc/reference/latest/releases/v4.35.0/). (Search-summary caveat: no v4.34 entry surfaced, and some item dates looked inconsistent. Verify against the pinned toolchain.)
- **`grind`** was released in 4.22.0 as an SMT-style tactic with theory solvers (e.g. `cutsat` for linear integer arithmetic) and standard-library annotations. — [v4.22.0 release notes](https://lean-lang.org/doc/reference/stable/releases/v4.22.0/)
- **Functional induction.**
  - 4.17.0 added auto-generated `foo.fun_cases` theorems (PR #6261).
  - 4.21.0 made `fun_induction`/`fun_cases` unfold the function application in the goal (PR #8104; old behaviour via `set_option tactic.fun_induction.unfolding false`) and pruned contradictory cases (PR #8171).

  Sources: [v4.17.0](https://lean-lang.org/doc/reference/4.20.0/releases/v4.17.0); [v4.21.0](https://lean-lang.org/doc/reference/stable/releases/v4.21.0/)
- **`partial_fixpoint`** lets one define possibly non-terminating functions (e.g. returning `Option`) that are still *logically* defined and provable. A total version can later be recovered with a totality proof (`(f91 n).get (f91_total n)`). This is unlike `partial`, which is opaque to proofs. — [Zulip: McCarthy 91 using partial_fixpoint](https://leanprover-community.github.io/archive/stream/270676-lean4/topic/McCarthy.2091.20function.20using.20partial_fixpoint.html)
- `termination_by`/`decreasing_by` hints are placed directly after the function they apply to, and `decreasing_by` tactics act on all termination goals together (use `all_goals` for per-goal). — [v4.6.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.6.0/)
- **Maps.** The Lean reference states that the basic operations of `HashMap`/`DHashMap`/`TreeMap`/`DTreeMap` (and sets) are verified against simpler list-based models, while some functions (e.g. `HashMap.partition`, `TreeMap.filterMap`) were not yet fully verified at the time of that doc version. Extensional variants `ExtHashMap`/`ExtDHashMap` make propositional equality coincide with the partial-function view. Lemmas about `Raw` (no well-formedness bundled) variants need separate `RawLemmas` imports. — [Lean reference: Maps and Sets](https://lean-lang.org/doc/reference/latest/Basic-Types/Maps-and-Sets/); [API: Std.Data.HashMap.Lemmas](https://lean-lang.org/doc/api/Std/Data/HashMap/Lemmas.html)
- `HashMap.filter`/`filterMap`/`map` lemmas shipped in Lean 4.18.0 (April 2025), per Markus Himmel on Zulip. — [Zulip: Lemmas for Std.HashMap.filter](https://leanprover-community.github.io/archive/stream/113489-new-members/topic/Lemmas.20for.20Std.2EHashMap.2Efilter.20and.20Std.2EHashSet.2Efilter.3F.html)
- Loom (POPL 2026, Gladshtein, Pîrlea, Zhao, Kurin, Sergey): a framework for *foundational multi-modal* verifiers in Lean 4, with automated WP generation, executable semantics and non-determinism, on a monadic shallow embedding. Velvet is a Dafny-style imperative verifier built on Loom (SMT + interactive). Veil is a distributed-protocol verifier (model checking + SMT via Lean-SMT, kernel-checked). Veil 2.0 was unreleased as of Oct 2025. — [Loom POPL'26 PDF](https://ilyasergey.net/assets/pdf/papers/loom-popl26.pdf); [POPL'26 page](https://popl26.sigplan.org/details/POPL-2026-popl-research-papers/79/Foundational-Multi-Modal-Program-Verifiers); [Reservoir: Velvet](https://reservoir.lean-lang.org/@verse-lab/Velvet); [Reservoir: Loom](https://reservoir.lean-lang.org/@verse-lab/Loom); [Lean use case: Veil](https://lean-lang.org/use-cases/veil/); [Zulip Loom discussion](https://leanprover-community.github.io/archive/stream/537981-Loom/topic/Loom.20discussion.html)
- The BS-DFS formalization's explicit caveat that list-membership executables give no runtime guarantees illustrates the List-vs-HashMap trade-off: List is easiest to prove about, but has linear membership. — [GitHub bsdfs_lean](https://github.com/FrankBau/bsdfs_lean)

### Inferences
- **Recommended style for Mitos core:**
  1. Specs as inductive `Prop`s (`Derives : Facts → Edge → Prop`, `Reaches := Relation.ReflTransGen revEdge`).
  2. Executable code as total, pure functions over `Array`/`Std.HashMap` with `termination_by` on a finite measure.
  3. Proofs with `fun_induction` + `grind` + `simp` on the HashMap `getElem?`/`contains` lemma API.
  4. Avoid `partial` in the trusted core; use `partial_fixpoint` or fuel if a measure is awkward.
- `Std.Do`/`vcgen` makes "write it with `for` loops and `let mut`" provable. Given the API churn from 4.22 to 4.35 (mvcgen → mvcgen' → vcgen), pin the toolchain and expect migrations. For a small trusted core, pure recursion plus `fun_induction` is the more stable choice in 2026.
- (background knowledge, unverified here) Lean's `Array`/`HashMap` are updated in place when the reference is unique (reference counting, "functional but in-place"). Pure HashMap code is therefore performant if values are used linearly. Proof-side, `List` and `Finset` remain best-covered, so a standard pattern is to prove about `HashMap` via its `toList`/`getElem?` model lemmas.
- `decide` works only for small closed finite instances. It is useful for unit-test-style theorems on example fact sets (`example : resolve sample = expected := by decide` / `native_decide`) but not for general theorems. `native_decide` trusts the compiler and should be excluded from the trusted-core claims.

### Gaps
- Could not read the Lean reference pages directly (fetch blocked). The verification status of specific map operations in the 4.35 docs, beyond the search-snippet list, is unconfirmed.
- No benchmark data was found comparing List/Array/HashMap in verified Lean code.

## Q6. Real-world Lean 4 verified software with a similar shape, and lessons

### Takeaway
AWS Cedar is the closest industrial analogue: an authorization *evaluator/validator/analyzer* over structured data. Its "verification-guided development" (a small readable Lean model with proofs, plus differential random testing against Rust production code) is the most-proven playbook. Published sizes: about 1.7k LOC Lean model, about 5.7k LOC proofs, about 25k LOC Rust (older table). Proofs concentrate where invariants are deep (the validator: about 4.7k proof LOC for 532 model LOC).

### Cited Findings
- Cedar VGD: write a readable Lean model and prove properties about it, then use differential random testing (DRT) to check that Rust matches the model, plus property-based testing (PBT) for properties not in the model. — [arXiv 2407.01688 "How We Built Cedar"](https://arxiv.org/abs/2407.01688); [AWS Open Source Blog: Lean into verified software development](https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development)
- Sizes from the AWS table: Lean model 1,673 LOC, Lean proofs 5,714 LOC, Rust 24,915 LOC. By component, proofs are 347 LOC (evaluator + authorizer), 4,686 LOC (validator, vs 532 model LOC and 11,251 Rust LOC) and 681 LOC (custom sets/maps). A Lean.org write-up says models are about 10x smaller than production code; the table implies about 15x. — [AWS Open Source Blog](https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development)
- Lean evaluates a DRT input in about 5 µs vs about 7 µs for Rust, enabling millions of nightly differential tests. A new Cedar release requires an up-to-date model, proofs and DRT. — [AWS Open Source Blog](https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development)
- Bugs: proofs found 4 bugs in the validator; DRT and PBT found 21 more across Cedar. — [arXiv 2407.01688](https://arxiv.org/abs/2407.01688)
- Cedar originally used Dafny for models and later moved to Lean. — [sos-vo.org talk](https://sos-vo.org/node/94470); [Lean use case: Cedar](https://lean-lang.org/use-cases/cedar/)
- Cedar's symbolic compiler (`cedar-policy-symcc`) is "formally modeled and verified in Lean", with the Rust core library mapping directly to the Lean model. SymCert generalizes this. — [docs.rs cedar-policy-symcc](https://docs.rs/cedar-policy-symcc); [Amazon Science: SymCert](https://www.amazon.science/publications/symcert-verifying-smt-based-policy-analyses)
- The proof checker pattern in Lean for Datalog (CertifyingDatalog) is a research-grade analogue of the Mitos "facts → derived facts" shape. — [GitHub knowsys/CertifyingDatalog](https://github.com/knowsys/CertifyingDatalog)
- Leo de Moura's ETAPS 2026 industry talk positions Lean as a unified platform for verification, programming and AI. — [ETAPS industry 2026 slides](https://leodemoura.github.io/static/etaps-industry-2026/)

### Inferences
- Proof-to-model ratio rule of thumb from Cedar: about 3.4 proof lines per model line overall, ranging from about 0.7 (evaluator/authorizer) to about 9 (validator, with its type-soundness invariant). Mitos's soundness/scope/AI-tag theorems resemble the "easy" end (structural propagation). Exact assumption tracking with retraction and totality resemble the "validator" end.
- (background knowledge, unverified here) Other Lean 4 industrial examples: **SampCert** (AWS, verified differential-privacy samplers, used in AWS Clean Rooms), **LNSym** (AWS, Arm64 symbolic simulation for crypto), and Veil/Loom (academic). They share Cedar's lesson: keep the trusted model small and executable, and test it against production. "IronLean" from the brief could not be identified.

### Gaps
- No current (2026) Cedar proof-size figures. The table is from an older blog post, and SymCC/SymCert proof sizes were not found.
- SampCert/LNSym facts are not sourced in this session. "IronLean" was not found in any search.
- No public data on Cedar's proof *maintenance* cost (e.g. person-hours per Lean toolchain bump).

## Q7. Recommended formulation for Mitos

### Takeaway
Model resolution as **fixed-rule positive Datalog with derivation-DAG provenance**. Write a small verified reference resolver in Lean 4 over `Finset`/`List` specs and `HashMap`-backed executable code. Prove properties against inductive `Prop` specs (`Derives`, `ReflTransGen`). Make every output edge carry a derivation (a CertifyingDatalog-style DAG), so a tiny verified checker plus a closure check can validate any faster/untrusted resolver. Run Cedar-style differential testing in CI.

### Cited Findings
- The Datalog certificate-checker approach is implemented and verified in Lean 4 with tree and DAG encodings. — [GitHub knowsys/CertifyingDatalog](https://github.com/knowsys/CertifyingDatalog); [DROPS ITP 2025](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ITP.2025.36)
- Verified full Datalog engines with soundness, completeness and termination exist in Coq (bottom-up fixpoint), as a template for a verified reference engine. — [HAL hal-01745566](https://hal.archives-ouvertes.fr/hal-01745566/)
- Model + DRT is industrially proven (Cedar). — [AWS Open Source Blog](https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development)
- Lean's `grind`, `fun_induction` and HashMap lemma API are the 2025–26 tooling for such proofs. — [v4.22.0](https://lean-lang.org/doc/reference/stable/releases/v4.22.0/); [v4.21.0](https://lean-lang.org/doc/reference/stable/releases/v4.21.0/); [Maps and Sets](https://lean-lang.org/doc/reference/latest/Basic-Types/Maps-and-Sets/)

### Inferences
Concrete formulation, as a sketch rather than sourced fact:
1. **Data.** `structure Fact := (repo : RepoId) (kind : Provides | Requires | Binds | BuiltFrom ...) (ident : Identity) (scope : Scope) (origin : Origin /- human|ci|ai -/) (id : FactId)`. Assumptions are `FactId ⊕ RuleId`. Identity matching is a decidable relation `matches : Identity → Identity → Bool`, specified separately, e.g. semver range satisfaction.
2. **Spec.** An inductive `Derives (F : List Fact) : Edge → Deriv → Prop` with one constructor per resolution rule (direct match; config-key→deployment→service→repo→op chain), where `Deriv` is a tree/DAG whose leaves are `FactId`s and nodes are `RuleId`s. Define `assumptions : Deriv → Finset Assumption` structurally.
3. **Theorems, all stated against the spec.**
   - *Soundness*: `e ∈ resolve F → ∃ d, Derives F e d ∧ e.deriv = d`.
   - *Totality*: `∀ r ∈ requires F, (∃ e ∈ resolve F, e.req = r.id) ∨ r ∈ unresolved F`, plus `r ∈ unresolved F → ¬∃ e d, Derives F e d ∧ e.req = r.id` (exact unresolved).
   - *Scope preservation*: `e.scope = combine (leaves e.deriv).scope`, proved by induction on `Derives`.
   - *AI never confirmed*: `(∃ f ∈ leaves e.deriv, f.origin = ai) → e.status ≠ confirmed`.
   - *Exact assumption tracking*: `e.assumptions = assumptions e.deriv`, by structural induction.
   - *Retraction*: `resolve (F.erase a) = (resolve F).filter (a ∉ ·.assumptions)` **iff** derivations are unique per edge. Otherwise prove the weaker `⊇`, plus "an edge is dropped only if every derivation used `a`", which requires all-derivations (why-provenance) labels as in the ATMS.
   - *Impact analysis*: `impact G s = {v | ReflTransGen (flip G.adj) s v}` via the visited-set invariant in Q1.
   - *Aggregation*: the package→repo map `π` is a graph homomorphism, `aggregate G = G.map π`, with `evidence (aggregate G) (π a, π b) = ⋃ {evidence G (a', b') | π a' = π a, π b' = π b}`. Prove by `Finset` lemmas.
4. **Termination.** The resolver is a bounded chain of joins over a finite fact list (no recursion over derived facts beyond a fixed depth), so plain structural recursion suffices. Impact analysis uses a `(nodes \ visited).card` measure.
5. **Execution.** Implement with `Std.HashMap Identity (Array FactId)` indexes. Prove index correctness once (`idx.get? k = some xs ↔ xs = F.filter (·.ident = k)`), then reason about the List spec. Keep `native_decide` out of the trusted core.
6. **Assurance layering (Cedar playbook).** (a) Lean reference with proofs. (b) Optional fast production resolver. (c) Verified Lean checker validating every emitted graph (derivation check + closure check for totality). (d) Nightly DRT between production and reference.
7. **Effort estimate.** Extrapolating Cedar's 3.4:1 proof:model ratio, a roughly 1–2k-line Lean model implies roughly 4–7k lines of proof. Retraction/exactness and aggregation are likely the most expensive. This is an inference, not a measured figure.

### Gaps
- No direct prior art proves *retraction/incremental invalidation exactness* in Lean. The nearest is Coq incremental regular-Datalog view maintenance (Bonifati/Dumbrava/Gallego Arias 2018).
- Whether Mitos needs all-derivations (why-provenance) or single-derivation semantics is a product decision. It determines whether the "exactly the edges that depend on it" theorem is even true as stated.
