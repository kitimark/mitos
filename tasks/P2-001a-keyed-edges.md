# tasks/P2-001a-keyed-edges.md

phase: 2
goal: Every edge record is keyed by one derivation. The five restated statements and the repo-level
  view hold for the Phase 1 resolver with one line changed, and
  `cd core && lake comparator --paranoid` accepts the unchanged Challenge.
statement: restates Mitos.Spec.Sound, Complete, UnresolvedExact, AssumptionsExact and StatusHonest
  (this PR is their spec PR, under P2-000's exception); adds Mitos.Spec.retract_repo, proved in the
  core with no Challenge line; proves again the twelve theorems of core/Challenge/Resolver.lean
touches: core/Mitos/Core/Graph.lean, core/Mitos/Core/Spec/Derivations.lean (new),
  core/Mitos/Core/Spec/Resolve.lean, core/Mitos/Core/Spec/Adequacy.lean,
  core/Mitos/Core/Spec/Repo.lean (new), core/Mitos/Core.lean, line 17 of
  core/Mitos/Impl/Resolve.lean, core/Mitos/Proofs/Resolve/, eval/score/Score.lean, statements.lock
  and examples/acme/accepted/ToyRequire.json (both generated), the files of
  tasks/P2-005a-migrate-mutants.md, this file, ops/runs/
must_not_touch: core/Challenge/, core/comparator.json, core/lakefile.toml,
  core/Mitos/Core/Fact.lean, core/Mitos/Core/Lines.lean, core/Mitos/Core/Obligations.lean,
  core/Mitos/Core/ModelExamples.lean, core/Mitos/Impl/Impact.lean, every other line of
  core/Mitos/Impl/Resolve.lean, core/Mitos/Proofs/Resolver.lean, models.lock, gate/, eval/cheats/,
  eval/fixtures/, eval/score/Main.lean, examples/acme/Models/, .github/, docs/, plan/, .claude/
checks: build, imports, lock, core lake check, comparator --paranoid, acme build, accept-toy
  (recorded again with --record at the head), mitos-lint-test and cheats (in ci), the scorer on
  eval/fixtures/toy, eval/mutants build, the full mutant run (default and --paranoid)
budget: 40 iterations · 10h wall · 4M tokens (the architect's estimate; P2-005a's work is inside it)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-001a in `plan/phase-2.md`, issue #203. P2-005a (#205,
  `tasks/P2-005a-migrate-mutants.md`) lands in the same PR, because a change to `Edge` breaks every
  mutant case at once.
- The design this row builds on: the D1 sketch on
  [#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795051235) and the owner's
  decisions on it
  ([comment](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085)). The plan's
  Scope decisions repeat them. #160 holds the plan review's follow-ups; its item 1 (a binding from
  an identity to itself) is P2-001b's.
- This PR is a spec PR that carries its implementation and proofs (plan, Scope decisions). P2-000
  (#202) records that exception in `docs/process.md` and merges first. #147 (P2-011) is recommended
  first. The owner merges this PR (`spec-approved`).
- Already on `main`: #133's renames (#169, #170), so the plan's `req`, `prov`, `src` and `dst` are
  `requiringFactId`, `providingFactId`, `requiringRepo` and `providingRepo`; both #101 PRs (#215,
  #232), so the Challenge has twelve theorems and `statements.lock` 165 declarations; the mutant
  corpus is 42 cases (22 refuted, no known gap, 20 cheat cases rejected).
- Design written at plan time by an arena of two runners and a judge (Rationale, Synthesis
  decision). It was checked by reading `main` at e5bd16c and the toolchain's sources. The sketch
  type-checks on Lean v4.35.0 against `main` at e5bd16c, with `sorry` bodies only where the design
  says (the regenerated lock had 206 declarations).

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists. `core/Challenge/` and `core/comparator.json` are in the plan's Owns cell for this row. They
are under `must_not_touch` because the design needs no diff in them: a needed diff means the design
is wrong, and the builder stops.

depth: build, for this row and for P2-005a. Types, statements and fixtures are below. New theorem
bodies are `sorry`; a proof that moves is `main`'s text.

revisit_when: re-check after #202 merges (P2-000; it changes no type here). At branch time, read
`eval/mutants/cases/` again (#231 may have added cases), confirm that no other PR touched `core/`,
and if the toolchain was bumped (#147), type-check the sketch on it.

modules: one topic per file. Line counts are rough budgets with proofs filled in. A build that
outgrows this map reports it as a deviation and does not split silently.
- `core/Mitos/Core/Graph.lean`: the records a resolver reads and writes (located facts, the
  derivation key, the repo-level key, edges, resolutions), with unique ids, retraction and
  `Affects`. 61 → about 95 lines. Edited in place. It gains `Derivation` with two accessors,
  `RepoKey`, the reshaped `Edge`, two `Edge` accessors, and two theorems that move in
  (`WellFormed.eq_of_id` from `Proofs/Resolve/Basic.lean`, `wellFormed_retract` from
  `eval/mutants/Mutants/Implied.lean`). `matchesB` leaves.
- `core/Mitos/Core/Spec/Derivations.lean` (new): which derivations a fact list has. The direct
  rule's premise (`matchesB`), `Chain` with its builder `Chain.direct` and its readers `origins`
  and `repoKey`, `derivations`, and the five laws. About 110 lines. Copies
  `core/Mitos/Core/Lines.lean` (definitions, then their theorems, in namespace `Mitos`).
- `core/Mitos/Core/Spec/Resolve.lean`: the twelve statements. 52 → about 52 lines. In place.
- `core/Mitos/Core/Spec/Adequacy.lean`: what the statements reject, and what they force on small
  inputs. 127 → about 185 lines. In place. The consequence theorems copy
  `Model.Adequate.sound_on_golden` in `ModelExamples.lean`. The span theorems stay here, a second
  topic this row leaves in place (deferrals).
- `core/Mitos/Core/Spec/Repo.lean` (new, named by the plan): the repo-level view under retraction,
  `retract_repo` and its two-provision example. About 50 lines. Copies `ModelExamples.lean` (a
  generic theorem, then its use).
- `core/Mitos/Core.lean`: the import list. Without the two new lines the new files build but are
  not locked, because the lock reads the environment of module `Mitos.Core`.
- `core/Mitos/Impl/Resolve.lean`: line 17 of `mkEdge`. No other byte, and no new import: 38 mutant
  cases match exact text in this file.
- `core/Mitos/Proofs/Resolve/Basic.lean`: what `resolve` lists. 42 → about 28 lines. It stays the
  only proof file that imports `Mitos.Impl.Resolve`, because `cheat_proofs_own_hole` replaces that
  import with its own copy of the implementation.
- `core/Mitos/Proofs/Resolve/Edges.lean`: sound, complete, unresolved-exact, total. 32 → about 50.
- `core/Mitos/Proofs/Resolve/Assumptions.lean`: assumptions-exact, status-honest, retract-exact.
  53 → about 60.
- `core/Mitos/Proofs/Resolve/Nodup.lean`: no-duplicates. About 65. Keys are `.direct r.id p.id`.
- `core/Mitos/Impl/Impact.lean`, `core/Mitos/Proofs/Impact.lean`,
  `core/Mitos/Proofs/Impact/Nodup.lean`: no diff expected. `Impl/Impact.lean` is under
  `must_not_touch`. A proof edit in the other two is a deviation to report.
- `eval/score/Score.lean`: the fixture scorecard. 154 → about 150 lines. `RepoEdge` goes and
  `Mitos.RepoKey` takes its place.
- Generated at the head: `statements.lock`, `examples/acme/accepted/ToyRequire.json`.

### Usage (caller's view)

The owner reads the spec. Each restated statement is one sentence about derivations:

| Statement | Reads |
|---|---|
| `Sound` | every edge is the record of one derivation: same key, same repo-level key |
| `Complete` | every derivation has an edge record |
| `UnresolvedExact` | the unresolved list holds exactly the requirements no derivation starts at |
| `AssumptionsExact` | an edge's assumptions and its derivation's origins hold the same items |
| `StatusHonest` | confirmed exactly when no assumption is AI-proposed and every derivation of its requirement ends at its provider fact |

The resolver writes one record per derivation. This is the whole implementation diff:

```lean
def mkEdge (fs : List Located) (r p : Located) : Edge :=
  { requiringRepo := r.repo, providingRepo := p.repo, ident := r.fact.ident, scope := r.fact.scope,
    key := .direct r.id p.id,
    assumes := assumptionsOf r p,
    status := statusOf fs r (assumptionsOf r p) }
```

A proof names the derivation an edge records (drafts, not built):

```lean
theorem resolve_sound : Spec.Sound resolve := by
  intro fs _ e he
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := mem_edges.mp he
  exact ⟨Chain.direct r p, mem_derivations.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl, rfl⟩

theorem resolve_complete : Spec.Complete resolve := by
  intro fs _ c hc
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := mem_derivations.mp hc
  exact ⟨mkEdge fs r p, mem_edges.mpr ⟨r, hr, p, hp, hm, rfl⟩, rfl⟩
```

A mutant refutation fixes the input and lets `decide` find the rest. Sixteen of the 22 keep their
text. One that names a key names a `Derivation`:

```lean
theorem resolve_assumptions_exact : ¬ Spec.AssumptionsExact Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

theorem resolve_retract_exact : ¬ Spec.RetractExact Impl.resolve := by
  intro h
  have := h fs prov.origin (by unfold WellFormed; decide) (.direct 0 1)
  revert this
  decide
```

The scorer groups by the key the core proves things about:

```lean
def collapse (es : List Edge) : List (RepoKey × Status) :=
  es.foldl (init := []) fun acc e =>
    if acc.any (·.1 == e.repoKey) then
      acc.map fun (k, s) => (k, if k == e.repoKey && e.status == .inferred then .inferred else s)
    else acc ++ [(e.repoKey, e.status)]
```

Anyone who retracts an assumption can filter the stored records and get the repo-level edges a
fresh run would give:

```lean
example (fs : List Located) (a : Assumption) (wf : WellFormed fs) (k : RepoKey) :
    k ∈ (Impl.resolve (retract a fs)).edges.map Edge.repoKey ↔
      k ∈ ((Impl.resolve fs).edges.filter (fun e => !(e.assumes.contains a))).map Edge.repoKey :=
  Spec.retract_repo Proofs.resolve_sound Proofs.resolve_retract_exact fs a wf k
```

types:

`core/Mitos/Core/Graph.lean`. `Assumption`, `Assumption.isAI`, `Located` and `Status` keep their
text. This block takes the place of `Edge` and the `Edge.key` def (lines 29 to 40 on `main`):

```lean
inductive Derivation where
  | direct (requiringFactId providingFactId : Nat)
  deriving DecidableEq, Repr

def Derivation.requiringFactId : Derivation → Nat
  | .direct r _ => r

def Derivation.providingFactId : Derivation → Nat
  | .direct _ p => p

structure RepoKey where
  requiringRepo : String
  providingRepo : String
  ident         : Identity
  scope         : Scope
  deriving DecidableEq, Repr

structure Edge extends repoKey : RepoKey where
  key     : Derivation
  assumes : List Assumption
  status  : Status
  deriving DecidableEq, Repr

def Edge.requiringFactId (e : Edge) : Nat := e.key.requiringFactId

def Edge.providingFactId (e : Edge) : Nat := e.key.providingFactId
```

`Resolution`, `Resolver`, `WellFormed`, `retract` and `Affects` keep their text, and `matchesB`
leaves. Two theorems move in with `main`'s proof text, the first right after `WellFormed` and the
second right after `retract`, and both old copies are deleted:

```lean
theorem WellFormed.eq_of_id {fs : List Located} (wf : WellFormed fs) :
    ∀ {a b : Located}, a ∈ fs → b ∈ fs → a.id = b.id → a = b

theorem wellFormed_retract {fs : List Located} (a : Assumption) (wf : WellFormed fs) :
    WellFormed (retract a fs)
```

Their proofs are `Proofs/Resolve/Basic.lean` lines 22 to 35 and `Mutants/Implied.lean` lines 18
to 20. An edge's four repo-level fields are `RepoKey`'s, so `e.requiringRepo` means
`e.repoKey.requiringRepo`, and every `Edge` literal on `main` keeps its field names.

`core/Mitos/Core/Spec/Derivations.lean`, the whole file:

```lean
import Mitos.Core.Graph

namespace Mitos

def matchesB (r p : Located) : Bool :=
  r.fact.kind == .requires && p.fact.kind == .provides && r.fact.ident == p.fact.ident

structure Chain where
  key         : Derivation
  requirement : Located
  via         : List Located
  provision   : Located
  deriving DecidableEq, Repr

def Chain.direct (r p : Located) : Chain :=
  { key := .direct r.id p.id, requirement := r, via := [], provision := p }

def Chain.origins (c : Chain) : List Assumption :=
  (c.requirement :: c.via ++ [c.provision]).map (·.origin)

def Chain.repoKey (c : Chain) : RepoKey :=
  { requiringRepo := c.requirement.repo, providingRepo := c.provision.repo,
    ident := c.requirement.fact.ident, scope := c.requirement.fact.scope }

def derivations (fs : List Located) : List Chain :=
  fs.flatMap fun r => (fs.filter (matchesB r)).map (Chain.direct r)

theorem mem_derivations {fs : List Located} {c : Chain} :
    c ∈ derivations fs ↔
      ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p := sorry

theorem derivations_key_ends {fs : List Located} {c : Chain} (h : c ∈ derivations fs) :
    c.key.requiringFactId = c.requirement.id ∧ c.key.providingFactId = c.provision.id := sorry

theorem derivations_key_inj {fs : List Located} (wf : WellFormed fs) {c d : Chain}
    (hc : c ∈ derivations fs) (hd : d ∈ derivations fs) (h : c.key = d.key) : c = d := sorry

theorem mem_derivations_retract {a : Assumption} {fs : List Located} {c : Chain} :
    c ∈ derivations (retract a fs) ↔ c ∈ derivations fs ∧ a ∉ c.origins := sorry

theorem derivations_single_provider {fs : List Located} (wf : WellFormed fs) {c : Chain}
    (hc : c ∈ derivations fs) :
    (∀ d ∈ derivations fs, d.requirement.id = c.requirement.id →
        d.provision.id = c.provision.id) ↔
      (fs.filter (matchesB c.requirement)).length = 1 := sorry

end Mitos
```

`core/Mitos/Core/Spec/Resolve.lean`. The import becomes `Mitos.Core.Spec.Derivations`. The five
restated statements are below. `Total` (between `UnresolvedExact` and `AssumptionsExact`),
`RetractExact`, `ImpactCorrect` and the four no-duplicates statements keep their text and their
places.

```lean
def Sound (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∃ c ∈ derivations fs,
    c.key = e.key ∧ c.repoKey = e.repoKey

def Complete (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ c ∈ derivations fs, ∃ e ∈ (R fs).edges, e.key = c.key

def UnresolvedExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ i, i ∈ (R fs).unresolved ↔
    ∃ r ∈ fs, r.id = i ∧ r.fact.kind = .requires ∧
      ∀ c ∈ derivations fs, c.requirement.id ≠ r.id

def AssumptionsExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∀ c ∈ derivations fs, c.key = e.key →
    (∀ a ∈ e.assumes, a ∈ c.origins) ∧ ∀ a ∈ c.origins, a ∈ e.assumes

def StatusHonest (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges,
    (e.status = .confirmed ↔
      ((∀ a ∈ e.assumes, a.isAI = false) ∧
        ∀ c ∈ derivations fs, c.requirement.id = e.requiringFactId →
          c.provision.id = e.providingFactId))
```

`core/Mitos/Core/Spec/Adequacy.lean`. `req`, `prov`, `provAI`, `wf`, `wfAI`, `wf1` and the span
section (`accented` to `mid_char_span_not_anchored`) keep their text. The twelve theorems from
`nothing_not_complete` to `doubled_impact_not_nodup` keep their statements word for word. The
proofs of `nothing_not_complete`, `backwards_not_sound`, `nothing_unresolved_not_exact`,
`forgetful_not_exact`, `trusting_ai_not_honest`, `sticky_not_retract_exact` (its key is
`.direct 0 1`) and `same_key_edges_not_nodup` change. Most become a `have` at the fixture input,
then `revert this` and `decide`, as `char_span_not_anchored` is on `main`. The other five are
expected to stand. New or changed declarations:

```lean
def provDeclared : Located :=
  { prov with id := 2, path := "PROVIDES", origin := .humanDeclaredOutsideSource "sdk/PROVIDES" }

def twoProvisions : List Located := [req, prov, provDeclared]

theorem wfTwoProvisions : WellFormed twoProvisions := by unfold WellFormed; decide

def goodEdge : Edge :=
  { requiringRepo := "web", providingRepo := "sdk", ident := req.fact.ident, scope := .runtime,
    key := .direct 0 1,
    assumes := [.extractor "npm"], status := .confirmed }

theorem twoProvisions_derivations :
    derivations twoProvisions = [Chain.direct req prov, Chain.direct req provDeclared] := by
  decide

theorem sound_records_the_derivation {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R [req, prov]).edges,
      e.key = Derivation.direct 0 1 ∧ e.repoKey = goodEdge.repoKey := sorry

theorem complete_keeps_both_derivations {R : Resolver} (hc : Complete R) :
    (∃ e ∈ (R twoProvisions).edges, e.key = Derivation.direct 0 1) ∧
      ∃ e ∈ (R twoProvisions).edges, e.key = Derivation.direct 0 2 := sorry

theorem unresolved_exact_skips_resolved {R : Resolver} (hu : UnresolvedExact R) :
    0 ∉ (R [req, prov]).unresolved := sorry

theorem assumptions_exact_lists_leaf_origins {R : Resolver} (ha : AssumptionsExact R) :
    ∀ e ∈ (R twoProvisions).edges, e.key = Derivation.direct 0 2 →
      ∀ a, a ∈ e.assumes ↔ (a = req.origin ∨ a = provDeclared.origin) := sorry

theorem status_honest_two_provisions_inferred {R : Resolver} (hh : StatusHonest R) :
    ∀ e ∈ (R twoProvisions).edges, e.requiringFactId = 0 → e.status = .inferred := sorry
```

`core/Mitos/Core/Spec/Repo.lean`, the whole file:

```lean
import Mitos.Core.Spec.Adequacy

namespace Mitos.Spec

theorem retract_repo {R : Resolver} (hs : Sound R) (hr : RetractExact R) :
    ∀ fs a, WellFormed fs → ∀ k,
      k ∈ (R (retract a fs)).edges.map Edge.repoKey ↔
        k ∈ ((R fs).edges.filter (fun e => !(e.assumes.contains a))).map Edge.repoKey := sorry

theorem declaration_retracted_repo_edge_stays {R : Resolver} (hs : Sound R) (hc : Complete R) :
    Adequacy.goodEdge.repoKey ∈
      (R (retract Adequacy.provDeclared.origin Adequacy.twoProvisions)).edges.map
        Edge.repoKey := sorry

theorem extractor_retracted_repo_edge_goes {R : Resolver} (hs : Sound R) :
    Adequacy.goodEdge.repoKey ∉
      (R (retract Adequacy.req.origin Adequacy.twoProvisions)).edges.map Edge.repoKey := sorry

end Mitos.Spec
```

`core/Mitos/Core.lean` imports, in order: `Fact`, `Lines`, `Obligations`, `ModelExamples`, `Graph`,
`Spec.Derivations`, `Spec.Resolve`, `Spec.Adequacy`, `Spec.Repo`.

`core/Mitos/Proofs/Resolve/`: the twelve Challenge theorems keep their names and statements.
`mem_providers`, `mem_edges`, `mem_assumptionsOf`, `contains_assumptionsOf`, `assumptionsOf_nodup`
and `resolve_edge_list_nodup` keep their statements. One helper changes its statement, and
`Edges.lean` gains one:

```lean
theorem mem_keys {fs : List Located} {k : Derivation} {P : Edge → Bool} :
    k ∈ ((resolve fs).edges.filter P).map Edge.key ↔
      ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ P (mkEdge fs r p) = true ∧
        k = .direct r.id p.id := sorry

theorem no_derivation_iff_no_provider {fs : List Located} (wf : WellFormed fs) {r : Located}
    (hr : r ∈ fs) :
    (∀ c ∈ derivations fs, c.requirement.id ≠ r.id) ↔ ∀ p ∈ fs, matchesB r p = false := sorry
```

`eval/score/Score.lean`: `RepoEdge`, `RepoEdge.ofEdge`, `RepoEdge.type` and `RepoEdge.render` go.
`Scorecard.predicted : List (RepoKey × Status)`, `Scorecard.labels : List RepoKey`, `score` takes
`List RepoKey`, and `Scorecard.render` calls `edgeType` and `renderEdge`. `collapse` is under
Usage. `parseLabels` returns `List RepoKey` and keeps its checks and messages; it builds each label
as `{ requiringRepo := src, providingRepo := dst, ident := { kind, key }, scope }`. The rest:

```lean
def edgeType (k : RepoKey) : String := s!"{k.ident.kind}/{scopeName k.scope}"

def renderEdge (k : RepoKey) : String :=
  s!"`{k.requiringRepo}` → `{k.providingRepo}` ({edgeType k} `{k.ident.key}`)"
```

To type-check the core sketch: in a copy of `core/` at `main`, apply the `Graph.lean`,
`Spec/Derivations.lean`, `Spec/Resolve.lean`, `Spec/Adequacy.lean`, `Spec/Repo.lean` and `Core.lean`
changes above, give the six adequacy theorems whose proofs change `sorry` bodies, and elaborate
the `MitosCore` library only, in one build. `Mitos.Impl` and `Mitos.Proofs` need the `mkEdge` line
and the proof edits first.

statements:

Restated (the texts are the `Spec/Resolve.lean` block):

| Statement | Phase 1 clause | Phase 2 clause |
|---|---|---|
| `Sound` | some matching `r`, `p` in `fs` carry the edge's two fact ids, and four field equations | some `c ∈ derivations fs` has `c.key = e.key ∧ c.repoKey = e.repoKey` |
| `Complete` | every matching `r`, `p` has an edge with their ids | every `c ∈ derivations fs` has an edge with `e.key = c.key` |
| `UnresolvedExact` | last clause `∀ p ∈ fs, matchesB r p = false` | last clause `∀ c ∈ derivations fs, c.requirement.id ≠ r.id` |
| `AssumptionsExact` | for the `r`, `p` with the edge's ids, `∀ a, a ∈ e.assumes ↔ (a = r.origin ∨ a = p.origin)` | for the `c` with the edge's key, `e.assumes` and `c.origins` each hold the other's items |
| `StatusHonest` | guard `∀ r ∈ fs, r.id = e.requiringFactId`, second conjunct `(fs.filter (matchesB r)).length = 1` | no guard, second conjunct `∀ c ∈ derivations fs, c.requirement.id = e.requiringFactId → c.provision.id = e.providingFactId` |

- `StatusHonest` is in the plan's form: every derivation of its requirement reaches the same
  single provider, where a provider is a provider fact. Comparisons are on ids, so `decide`
  compares numbers.
- With the input fixed, and `i` given for `UnresolvedExact`, each of the five is decidable. So a
  refutation is `have := h fs wf; revert this; decide`.
- Text kept, word for word: `Total`, `RetractExact`, `ImpactCorrect`, `EdgesNodup`,
  `UnresolvedNodup`, `AssumptionsNodup`, `ImpactNodup`. `Total` still reads `e.requiringFactId`,
  which is now a def through the key.

New locked theorems, sixteen lines (`WellFormed.eq_of_id` is not pinned by the lock, because
`Lock.isGenerated` skips names whose last component starts with `eq_`; renaming the lemma would pin
it):
- `Graph.lean`: `WellFormed.eq_of_id`, `wellFormed_retract` (both moved, statements unchanged).
- `Spec/Derivations.lean`, the five laws:
  - `mem_derivations`: the derivations are exactly Phase 1's matches.
  - `derivations_key_ends`: a chain's key names its two end facts. This is what makes
    `Edge.requiringFactId` mean "the requirement's id".
  - `derivations_key_inj`: with unique ids, the key determines the chain.
  - `mem_derivations_retract`: retracting `a` keeps exactly the derivations with no fact of origin
    `a`. It needs no `WellFormed` and no induction.
  - `derivations_single_provider`: for a derivation `c`, "every derivation of its requirement ends
    at its provider" holds exactly when the requirement has one matching provision. This is the
    status rule's agreement with Phase 1.
- `Spec/Repo.lean`: `retract_repo` (the #156 signature, from `Sound` and `RetractExact`) and the
  two example theorems.
- `Spec/Adequacy.lean`: `wfTwoProvisions`, `twoProvisions_derivations` and the five consequence
  theorems.

Challenge and comparator: `core/Challenge/Resolver.lean` and `core/comparator.json` get no diff.
The same twelve theorem names and two definition names are compared, and their meaning moves
through `Mitos.Spec.*`.

`statements.lock`, predicted from how a line is hashed (the text of the declaration's own type
and value, `gate/MitosGate/Lock.lean`). The regenerated file decides; the PR body lists the diff
against this list. 165 → about 207 declarations.
- Changed: `Spec.Sound`, `Complete`, `UnresolvedExact`, `AssumptionsExact`, `StatusHonest`
  (restated); `Spec.RetractExact` and `Spec.EdgesNodup` (the key type is in their terms);
  `ctor Edge.mk`; `Edge.key` (now a field of type `Derivation`); `Edge.assumes`, `Edge.status`;
  `Edge.requiringFactId`, `Edge.providingFactId` (value only); `instDecidableEqEdge`,
  `instReprEdge`; `ctor Affects.step` and `ctor Affects.below.step` (their types now read
  `e.repoKey.providingRepo`); `Spec.Adequacy.goodEdge` and the five adequacy theorems whose
  statement updates a field of `goodEdge`.
- Removed: `Edge.requiringRepo`, `Edge.providingRepo`, `Edge.ident`, `Edge.scope` (they are
  `RepoKey`'s projections now).
- Added: `Derivation`, `RepoKey` and `Chain` with their constructors, readers and instances;
  `Edge.repoKey`; `Chain.direct`, `Chain.origins`, `Chain.repoKey`; `derivations`; `provDeclared`,
  `twoProvisions`; the sixteen theorems.
- Unchanged, byte for byte: `Spec.Total`, `Spec.ImpactCorrect`, `Spec.ImpactNodup`,
  `Spec.UnresolvedNodup`, `Spec.AssumptionsNodup`, `matchesB` (it only changes file), and every
  line outside the graph.

reuse:
- `Mitos.matchesB`, `WellFormed`, `retract`: same text, same lock lines.
- `Mitos.Impl.providers`, `assumptionsOf`, `statusOf`, `isRequirement`, `resolve`: untouched.
- `Proofs.mem_edges`, `mem_assumptionsOf`, `contains_assumptionsOf`: the proofs still start from
  them. `resolve_retract_exact` keeps its `mem_keys` filter proof.
- `Spec.Adequacy.req`, `prov`, `goodEdge`: the new fixtures add one fact to them.
- `Model.Adequate.sound_on_golden`: the pattern for a consequence on a named input.
- The Phase 1 refutation pattern, `have := h fs wf; revert this; decide`.

fixtures:

Locked Lean fixtures:
- Phase 1 agreement: `mem_derivations` and `derivations_single_provider`. The proof of
  `resolve_status_honest` uses the second, so the agreement carries weight.
- `twoProvisions_derivations`: the two-provision input has exactly two derivations, the direct
  chains to `prov` and to `provDeclared`. A wrong `derivations` fails it in the kernel.
- One consequence per restated statement. Each stops proving if the restated clause is weakened,
  which a `¬ S (constant resolver)` theorem does not always do.
  - `sound_records_the_derivation`: on `[req, prov]` every edge of a sound resolver has key
    `.direct 0 1` and the web-to-sdk repo key. Pins `c.key = e.key`.
  - `complete_keeps_both_derivations`: on `twoProvisions` a complete resolver has a record for
    `.direct 0 1` and one for `.direct 0 2`. Pins option C: two derivations to one repo are two
    records.
  - `unresolved_exact_skips_resolved`: `0` is not listed on `[req, prov]`. Pins the derivation
    clause.
  - `assumptions_exact_lists_leaf_origins`: the record of `.direct 0 2` assumes the extractor and
    the declaration, nothing else. It also shows that the two inclusions give Phase 1's `↔`.
  - `status_honest_two_provisions_inferred`: two provider facts in one repo make every edge of the
    requirement `inferred`, the reading #160 item 1 states.
- The two-derivation retract example on `twoProvisions`: web requires `sdk`, and repo sdk provides
  it once through the extractor and once through a human declaration, so one repo-level edge has
  two derivations.
  - `declaration_retracted_repo_edge_stays`: retract the declaration and web-to-sdk stays, because
    `.direct 0 1` avoids it.
  - `extractor_retracted_repo_edge_goes`: retract the extractor and it goes, because both
    derivations rest on the requirement.
- The twelve Phase 1 adequacy theorems, with unchanged statements.

Run-level fixtures the builder reports:
- `comparator`: `cd core && lake comparator --paranoid` accepts.
- `challenge-untouched`: this prints nothing:
  `git diff origin/main -- core/Challenge core/comparator.json core/lakefile.toml`
- `impl-one-line`: `git diff --numstat origin/main -- core/Mitos/Impl` prints
  `1 1 core/Mitos/Impl/Resolve.lean` and nothing else. With `comparator`, this says the Phase 1
  resolver meets the Phase 2 statements.
- `additive-step`: after step 1, `lake exe mitos-gate lock --check` prints `+` lines only. The
  moves and additions change no approved declaration, `matchesB` included.
- `reshape-step`: after step 2, three cases are refuted, by
  `lake --dir eval/mutants exe mitos-mutants --paranoid src_dst_swapped impact_reversed requirer_origin_forgotten`.
  They cover a `Sound` refutation over repo strings, an `Edge` literal under `Affects.step`, and
  `Impl.mkEdge` with a retraction.
- `lock`: `lake exe mitos-gate lock --check` passes at the head, and the lock lists
  `Mitos.Spec.retract_repo` and `Mitos.mem_derivations` (both new files reach `Core.lean`).
- `scorecard-unchanged`: `lake --dir eval/score exe mitos-score eval/fixtures/toy` prints the same
  bytes as on `main`.
- `accept-recorded`: at the head, after the last rebase, the accept line of "Before each push"
  with `--record` added is accepted, and only `core_sha256` differs in the record.
- `core-build-cost`: wall time of a clean `cd core && lake build MitosCore` before and after, one
  run each, stated as one run. Every judging directory builds the core from source, so a slow
  fixture proof is paid in each accept and cheat run.
- P2-005a's fixtures are in its task file.

### Order of edits

Run one Lean build at a time. A parallel build once took the container down. The comparator is
green after each of steps 1 to 4. Steps 5 to 8 change no file under `core/`.

| Step | Edit | Must pass before the next step |
|---|---|---|
| 1 | Additive. `Graph.lean` gains `Derivation`, its accessors and `RepoKey`; `WellFormed.eq_of_id` and `wellFormed_retract` move in, and their copies in `Proofs/Resolve/Basic.lean` and `Mutants/Implied.lean` are deleted. New `Spec/Derivations.lean` takes `matchesB` and adds `Chain`, `derivations` and the laws. `Core.lean` and `Spec/Resolve.lean` import it. `Edge` and every statement are untouched | `cd core && lake build && lake comparator --paranoid`; `lake --dir eval/mutants build`; `additive-step` |
| 2 | Reshape only. `Edge extends repoKey : RepoKey`, still with `requiringFactId`, `providingFactId` and the pair-valued `Edge.key` def. No statement text and no literal changes | the same two builds; `reshape-step`. A proof that needs more than a reworded `simp` set is a stop-and-report |
| 3 | The switch. `key : Derivation` replaces the two fields, the `Edge.key` def goes, the two accessor defs arrive. Five statements restated. `goodEdge` and the adequacy proofs that change. Line 17 of `Impl/Resolve.lean`. `Proofs/Resolve/{Edges,Assumptions,Nodup}.lean` | `cd core && lake build && lake check && lake comparator --paranoid` |
| 4 | `Spec/Adequacy.lean` gains `provDeclared`, `twoProvisions`, `twoProvisions_derivations` and the five consequence theorems. New `Spec/Repo.lean`; `Core.lean` imports it | `cd core && lake build && lake check`; `lake build && lake exe mitos-gate imports` |
| 5 | `lake exe mitos-gate lock` | `lake exe mitos-gate lock --check` |
| 6 | P2-005a (`tasks/P2-005a-migrate-mutants.md`) | `lake --dir eval/mutants build`; the full run, default then `--paranoid` |
| 7 | `eval/score/Score.lean` | `scorecard-unchanged` |
| 8 | After the last rebase: the lock again if `main` moved, the accept record, the task files, the run logs (`ops/runs/<UTC date>/P2-001a-builder-<attempt>.json` and `P2-005a-builder-<attempt>.json`) | the gate |

Proof outlines (not built):
- `mem_derivations`: unfold `derivations`, then `List.mem_flatMap`, `List.mem_map`,
  `List.mem_filter`, as `Proofs.mem_edges` does.
- `derivations_key_ends`, `derivations_key_inj`: from `mem_derivations`. The second uses
  `Derivation.direct.inj` and `WellFormed.eq_of_id` twice.
- `mem_derivations_retract`: `mem_derivations` on both sides, `List.mem_filter` for `retract`, and
  the origins of a direct chain are `[r.origin, p.origin]`.
- `derivations_single_provider`: forward, every element of the filtered list is the chain's
  provision by `WellFormed.eq_of_id`, the list has no duplicate because its ids are a sublist of
  unique ids, and it holds the provision, so its length is 1 (`List.eq_replicate_iff`,
  `List.nodup_replicate`). Backward, the list is `[q]` (`List.length_eq_one_iff`), so `q` is the
  provision, and a derivation with the same requirement id has the same requirement and a
  provision in that list.
- `retract_repo`: `RetractExact` moves the key across. `Sound` at both inputs gives two chains
  with one key, `mem_derivations_retract` puts both in `derivations fs`, and `derivations_key_inj`
  makes them one chain, so the repo keys agree. `wellFormed_retract` gives the second
  `WellFormed`.
- The two examples: `Complete` at the retracted input gives a record for `Chain.direct req prov`,
  and `Sound` gives it that chain's repo key. After retracting the extractor no derivation is
  left, so `Sound` leaves no edge.
- `resolve_unresolved_exact` and `resolve_total`: `main`'s proofs, with
  `no_derivation_iff_no_provider` between the derivation clause and `providers`. The first now
  uses `WellFormed`.
- `resolve_assumptions_exact`: `derivations_key_inj` makes the chain `Chain.direct r p`, whose
  origins are `[r.origin, p.origin]`; then `mem_assumptionsOf` both ways.
- `resolve_status_honest`: `(mkEdge fs r p).requiringFactId` is `r.id` by `rfl`;
  `derivations_single_provider` at `Chain.direct r p` turns the new clause into
  `(providers fs r).length = 1`; the rest is `main`'s proof.
- `resolve_edges_nodup`: `main`'s proof with keys `Derivation.direct r.id p.id`;
  `(Derivation.direct.inj heq).2` and `.1` take the place of `congrArg Prod.snd` and
  `congrArg Prod.fst`.

The builder stops and reports when:
- `core/Challenge/`, `core/comparator.json`, `Impl/Impact.lean` or `Fact.lean` needs an edit;
- a `find=` anchor would have to move, or a `breaks=` case no longer refutes a theorem it lists;
- the scorecard changes on the toy fixture;
- a restated statement fails for the Phase 1 resolver (the counterexample goes to a spec issue);
- step 2 needs more than a reworded `simp` set;
- a file outgrows its line in `modules`.

Before each push, the lines the change can affect, one at a time, from the repository root:

```bash
lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check
(cd core && lake check && lake comparator --paranoid)
(cd examples/acme && lake build)
lake --dir eval/mutants build && lake --dir eval/mutants exe mitos-mutants --paranoid
lake --dir eval/score build && lake --dir eval/score exe mitos-score eval/fixtures/toy
lake exe mitos-gate accept --workspace examples/acme --plugin ToyRequire --model Models.ToyRequire.model --paranoid
```

cut_line: ships the types and laws above, five restated statements, `Spec/Repo.lean`, the fixtures,
the one-line resolver change with all twelve proofs, the scorer on `RepoKey`, the regenerated lock
and accept record, and P2-005a. The PR says `Closes #203` and `Closes #205`. It leaves out
`FactKind.binds`, `Derivation.bound`, `Edge.through` and `Affects.through` (P2-001b), new mutants
(P2-005b), the union view's status rule (P2-009a), the derivation count (P2-010), and any change to
how proofs are organised beyond what the restated statements force.

deferrals:
- To P2-001b (#204), as a contract:
  - `FactKind.binds`; `Derivation.bound` with two more accessor arms; `boundB`, `Chain.bound` and
    a second list in `derivations`; `Edge.through` and `Affects.through`; one more conjunct in
    `Sound` (`e.through = c.via.map (·.repo)`).
  - `Chain`, `Chain.origins`, `Chain.repoKey`, `Complete`, `UnresolvedExact`, `AssumptionsExact`,
    `StatusHonest`, `Total`, `RetractExact`, `retract_repo` and both `Mutants.Implied` theorems
    keep their statements.
  - `mem_derivations` is restated for two rules, and `derivations_single_provider` gains the
    hypothesis that `fs` holds no binding fact. The implementation's status rule, which counts
    providers, is replaced there.
  - `via` is `[]` in every chain of this PR. Its first fixtures are P2-001b's chain adequacy
    theorems.
  - #160 item 1 (a binding from an identity to itself) stays there.
  - The span theorems leave `Spec/Adequacy.lean` for their own file, a move the lock does not see,
    when the chain fixtures land.
- To P2-005b (#206): a mutant that keeps one edge per repo-level key. It breaks
  `resolve_complete` on two provisions in one repo and pins option C against the implementation,
  as `complete_keeps_both_derivations` pins it in the spec.
- To P2-009a (#210) and P2-009b (#211): the scorer's repo-level edge is `Mitos.RepoKey`;
  `Score.RepoEdge` is gone; `labels.tsv` keeps its format. P2-009a's status flip is an edit of
  `collapse` as written under Usage.
- To P2-010 (#212): "derivations per repo-level edge" is the number of edge records with one
  `repoKey`. That this equals the number of derivations follows from `EdgesNodup`, `Sound`,
  `Complete` and `derivations_key_inj`; it is not stated as a theorem here.
- To P2-012 (#213): mutants run nightly only, so this PR's mutant evidence is a local run
  (#107 items 2 and 3).
- From #231: if its cases merge first, they join P2-005a's table.
- No row, so the PR's follow-up issue: a core file that `core/Mitos/Core.lean` does not import
  builds without being locked, which only a `gate/` check can close.

owner_decisions:

Settled by the plan (#159) and #156, followed as written: option C; the union view is proved and
is not a Challenge line; rules are constructors of `Derivation`; statements quantify over the
finite list; this spec PR carries its implementation and proofs (P2-000); the status rule in the
plan's refined form; `binds` waits for P2-001b.

Design defaults the owner sees at `spec-approved`. They are this design's calls, not the owner's
rulings. The builder follows each until the owner says otherwise on #203.
- O1. `Edge extends repoKey : RepoKey`, where the #156 sketch had four flat fields and a def. One
  list of the repo-level fields. Cost: four `Edge.*` lock lines go and `Affects.step`'s line
  changes.
- O2. `AssumptionsExact` as two inclusions, where the sketch kept Phase 1's `∀ a, … ↔ …`. Same
  meaning, and decidable at a fixed input.
- O3. `Sound` pins `c.repoKey = e.repoKey` instead of four separate equations.
- O4. The fixture set: nine locked theorems beyond "adequacy theorems re-proved".
- O5. Names: `Chain.requirement`, `via`, `provision`, `origins`;
  `Derivation.direct (requiringFactId providingFactId : Nat)`; the new file
  `core/Mitos/Core/Spec/Derivations.lean`.
- O6. Two provider facts in one repo make the requirement's edges `inferred`
  (`status_honest_two_provisions_inferred`).
- O7. The scorer moves to `Mitos.RepoKey` in this PR, though it would compile unchanged.

## Rationale

### Problem
P2-001a replaces the pair of fact ids on an edge with a derivation key and restates five approved
statements, in a PR that also carries the implementation, the proofs and 42 mutant cases, because
changing `Edge` breaks all of them at once. Four things constrain the shape. The owner reviews
statements, so every new locked line costs review. The mutant cases match exact text in the
implementation, so the resolver's text is close to frozen. Refutations must stay `decide`-able and
replayable by five kernels. And P2-001b lands a second rule right after, so anything stated here
as "a requirement and a provision" is restated twice.

### Facts this design rests on (checked against `main` at e5bd16c)
- A lock line hashes the text of the declaration's own type and value and does not name its
  module. The lock reads the environment of module `Mitos.Core`.
- Every judging directory builds `Mitos.Core.+` from source (`gate/MitosGate/Accept.lean`,
  `judgeLakefile`), and an accept record hashes every `.lean` file under `core/Mitos`.
- Of the 42 mutant cases, 38 edit `Mitos/Impl/Resolve.lean`, 4 edit `Mitos/Impl/Impact.lean`, and
  one of the 38 (`cheat_proofs_own_hole`) also edits `Mitos/Proofs/Resolve/Basic.lean`. There are
  21 distinct `find=` texts, and each must occur exactly once (`Mutants/Edit.lean`, `splitOnce`).
  None holds `requiringFactId`.
- Refutations are replayed by five kernels under `--paranoid`, and the replay has been fragile:
  four status cases write their strings with `String.ofList` (`tasks/P1-006-mutation-testing.md`,
  "String literals and the replay kernels").
- PR CI does not build `eval/mutants`; the nightly job and the canary do.
- `eval/score/Score.lean` reads `requiringRepo`, `providingRepo`, `ident`, `scope` and `status` of
  an edge, none of the fields this PR changes, and keeps its own `RepoEdge` with the same four
  things.
- Lean v4.35.0 parses `structure S extends name : P` (`Lean/Parser/Command.lean`, `structParent`).
  A parent's field gets no projection on the child, so `e.requiringRepo` elaborates to
  `e.repoKey.requiringRepo`. No file on `main` names `Edge.requiringRepo`, `Edge.providingRepo`,
  `Edge.ident` or `Edge.scope` as a function, and none builds an `Edge` with `⟨…⟩`.

### Shape
A derivation has two forms: its identity (`Derivation`, fact ids tagged by the rule) and its
instance over a fact list (`Chain`, the facts under that key). An edge is the record of one
derivation: a repo-level key, a derivation key, and what the resolver adds (`assumes`, `status`).
Each field of `Edge` is pinned by one statement: `Sound` pins the two keys, `AssumptionsExact`
pins `assumes`, `StatusHonest` pins `status`.

Statements never look inside a key. They compare keys and read ends from the chain. The
exceptions are the two accessors: `Total`'s approved text reads `e.requiringFactId`, and
`StatusHonest` reads both. `derivations_key_ends` is the locked link between them and the chain.

The laws carry the reasoning that holds for any rule set built this way: keys determine chains,
retraction filters by origins, keys name the ends. `retract_repo` and both `Mutants.Implied`
theorems use only those, so P2-001b's `bound` rule changes none of their statements. The
implementation's proofs use `mem_derivations` and `derivations_single_provider`, the two facts
that are about the direct rule.

The implementation is not rebuilt on `derivations`. It keeps its own enumeration and its Phase 1
status rule, so `Sound` and `Complete` stay real proofs, the enumeration mutants keep their
anchors, and "Phase 2's statements say what Phase 1's said" is checked by the unchanged resolver
meeting them.

Interface depth: a consumer of resolver output sees `Edge` (two keys, assumptions, status). A spec
reader sees twelve statements over one list. A rule author adds one constructor, one premise,
one chain builder and one list in `derivations`. Hidden behind that are the five laws and the
fact that exact retraction is a filter. `Chain`'s four fields stay exposed, because statements
read them.

### Synthesis decision
Two runners (A on opus, B on fable) and one judge; no second cross-judge ran. The two converged on
the core: `Derivation` in `Graph.lean`, a `Chain` list, accessor defs that keep `Total`'s text,
`matchesB` beside the enumeration, the two `WellFormed` lemmas in the core, one changed line in the
resolver, no anchor moved, and the scorer on `RepoKey`.

Base: B. It hides more behind a smaller surface (`Edge` contains its `RepoKey`, `Sound` has two
conjuncts, three of the five laws hold for any rule), it guards a builder better
(`must_not_touch` as a tripwire, the reshape step, the stop list), and its fixtures pin each
restated clause.

From A:
- the new core file sits in `core/Mitos/Core/Spec/`, inside the row's Owns cell;
- `AssumptionsExact` as two inclusions, so every restated statement is decidable at a fixed input
  and no refutation names `Impl.mkEdge`;
- the field names `requirement` and `provision`, in the style of #133's renames;
- the kernel fixture on `derivations` itself;
- the lock evidence that the moves change no approved declaration, and "line 17 only";
- the proof drafts for the implementation.

Rejected:
- A's flat `Edge` with `RepoKey` and `Edge.repoKey` in `Spec/Repo.lean`: three hand-synced lists
  of the four fields.
- A's `Chain` without `via`: P2-001b would change `Chain` again.
- A's locked `no_derivation_iff_no_match`: it is a proof helper now, outside the lock.
- B's `core/Mitos/Core/Chain.lean`: outside the Owns cell.
- B's locked `repo_union` and `retract_repo_derivation`: two statements the plan does not name;
  the examples prove directly.
- B's unused `Complete` hypothesis on the second example.

### Tradeoffs accepted
- We accept two spellings of an edge's fact ids (`e.requiringFactId`, `e.key.requiringFactId`) in
  exchange for `Total`'s text and lock line staying as approved. New code writes the first.
- We accept a `via` field that is `[]` in every chain of this PR in exchange for `Chain` being
  final before P2-001b.
- We accept that `Derivation` sits in `Graph.lean` and its rules in `Spec/Derivations.lean`, so a
  new rule touches two files (the compiler links them), in exchange for moving no approved
  declaration except `matchesB`.
- We accept sixteen new locked theorem lines in exchange for each restated clause having a
  fixture that stops proving when the clause is weakened, and for the laws being stated once.
- We accept that `Affects.step`'s lock line changes with no text change, and that four `Edge.*`
  projection lines leave the lock, in exchange for one field list for the repo-level key.
- We accept that `AssumptionsExact` no longer reads as Phase 1's `↔` in exchange for a statement
  `decide` can check whole.
- We accept that the implementation's status rule still counts providers, which is right only
  while `direct` is the only rule, in exchange for a one-line implementation diff and an agreement
  theorem its proof must use.
- We accept a scorer change the build does not force in exchange for one definition of the
  repo-level edge before P2-009a, P2-009b and P2-010 build on it.
- We accept `Spec/Adequacy.lean` at about 185 lines with the span theorems still in it.

### Alternatives considered
- Flat `Edge` with `def Edge.repoKey` (the #156 sketch). Same surface, but the four repo-level
  fields are listed in `Edge`, in `RepoKey` and in the def, and an edge field added later is
  silently outside the view. It is the fallback if step 2 fails, and no statement text changes
  with it.
- An inductive relation `Derives fs c`. Not decidable at a fixed input, and the plan fixed the
  list form.
- The implementation as `(derivations fs).map …`. Shortest proofs, but the enumeration would live
  in the locked core where no mutant may edit, six cases lose their anchors, and `Sound` and
  `Complete` become near-tautologies.
- One statement, "the edges are the images of the derivations". The deepest interface, but the
  plan fixes five restated statements, and the Challenge names and every `breaks=` list hang on
  them.
- Everything in `Graph.lean`, as the #156 sketch had it. One file with two topics, at about 200
  lines.
- Phase 1 copies of the five statements with equivalence theorems. The strongest agreement claim,
  but it doubles the locked text and cannot survive P2-001b.

### Open questions and risks (for the builder to measure)
- The sketch type-checks on Lean v4.35.0 against `main` at e5bd16c, with `sorry` bodies only where
  the design says (the regenerated lock had 206 declarations).
- Does step 2, the reshape alone, need no proof change? It is its own step so that a surprise
  from `extends` shows before the statements move.
- Do all 22 refutations replay on five kernels now that the terms go through `derivations`? If a
  kernel rejects a `decide` that Lean accepts, the fallbacks are in P2-005a's task file.
- Do the adequacy proofs written with `decide` replay under `lake check`? If one does not, that
  proof is written in `main`'s `obtain` and `simp` style.
- How much does the core's clean build grow (`core-build-cost`)?
- Does the regenerated lock match the prediction? Any other line goes in the PR body with its
  reason.
- Lemma names at v4.35.0 (`List.eq_replicate_iff`, `List.length_eq_one_iff`) may need adapting.

### Next implementation step
Step 1: add `Derivation`, `RepoKey` and `Spec/Derivations.lean` with its five laws, and move
`WellFormed.eq_of_id` and `wellFormed_retract` into `Graph.lean`, with `Edge` untouched, the
comparator green and `additive-step` shown.

## Done when
- [x] all `checks` pass locally at the head, one Lean build at a time
- [x] every run-level fixture under Design holds, and P2-005a's
- [x] the PR body lists the lock diff against the prediction and says `Closes #203` and
      `Closes #205`
- [x] no `sorry`, no new axioms
- [x] run-log records written (ops/runs/)
