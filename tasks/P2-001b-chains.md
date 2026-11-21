# tasks/P2-001b-chains.md

phase: 2
goal: A requirement reaches its provider through a binding fact. `derivations` lists those chains,
  the resolver writes one edge record per chain with the binding's repo in `Edge.through`, impact
  counts a change in that repo, and `cd core && lake comparator --paranoid` accepts the unchanged
  Challenge.
statement: restates Mitos.Spec.Sound (one conjunct added) and the laws Mitos.mem_derivations and
  Mitos.derivations_single_provider; adds Mitos.mem_derivations_of_noBinds and the chain adequacy
  theorems of core/Mitos/Core/Spec/Chains.lean (new); Complete, UnresolvedExact, Total,
  AssumptionsExact, StatusHonest, RetractExact, ImpactCorrect and the four no-duplicates statements
  keep their text while their meaning extends to chains (this PR is their spec PR, under P2-000's
  exception); proves again the twelve theorems of core/Challenge/Resolver.lean
touches: core/Mitos/Core/Fact.lean, core/Mitos/Core/Graph.lean,
  core/Mitos/Core/Spec/Derivations.lean, core/Mitos/Core/Spec/Resolve.lean (one line),
  core/Mitos/Core/Spec/Adequacy.lean (one proof line), core/Mitos/Core/Spec/Repo.lean (proof lines),
  core/Mitos/Core/Spec/Chains.lean (new), core/Mitos/Core/Spec.lean (one import line),
  core/Mitos/Impl/Resolve.lean, core/Mitos/Impl/Impact.lean,
  core/Mitos/Proofs/Resolve/{Basic,Edges,Assumptions,Nodup}.lean, core/Mitos/Proofs/Impact.lean,
  the mutant files in the table under "Mutant migration", statements.lock and
  examples/acme/accepted/ToyRequire.json and examples/acme/accepted/GoMod.json (all three
  generated), this file, the scratch example in tasks/P2-007-gomod-plugin.md, ops/runs/,
  gate/lock-meaning-test.sh (review deviation below)
must_not_touch: core/Challenge/, core/comparator.json, core/lakefile.toml,
  core/Mitos/Core/Lines.lean, core/Mitos/Core/Obligations.lean, core/Mitos/Core/ModelExamples.lean,
  core/Mitos/Proofs/Impact/Nodup.lean, core/Mitos/Proofs/Resolver.lean, every other file in
  eval/mutants/ (eval/mutants/Mutants/Implied.lean included), new mutant cases (P2-005b),
  eval/score/, eval/fixtures/, examples/acme/Models/, examples/acme/Plugins/, models.lock,
  examples/acme/models.lock, the rest of gate/, eval/cheats/, .github/, docs/, plan/, .claude/
checks: build, imports, lock, core lake check, comparator --paranoid, acme build, accept-toy and
  accept-gomod (both recorded again with --record --paranoid at the head), mitos-lint-test and
  cheats (in ci), the scorer on eval/fixtures/toy, eval/mutants build, the full mutant run (default
  and --paranoid, one case per invocation)
budget: 20 iterations · 5h wall · 2M tokens (the sketch below was built whole, every proof filled in)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-001b in `plan/phase-2.md` (wave W4), issue #204. It waits for P2-001a, merged as #277
  (`tasks/P2-001a-keyed-edges.md`), whose deferrals hand this row a contract. P2-005b (#206) and
  P2-009a (#210) wait for this row.
- Owner decisions on the Phase 2 draft:
  [#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085), repeated in the
  plan's Scope decisions: option C, rules are constructors of `Derivation`, statements quantify over
  the finite list `derivations fs`, `binds` in Phase 2, impact through bindings, the refined status
  rule. The owner ruled out self-binding derivations (O1).
- This is a spec PR that carries its implementation and proofs (plan, Scope decisions; P2-000).
  The owner merges it (`spec-approved`).
- **Answer to the root's question on #276 (lock lines that move with no change of meaning).** Yes,
  the design must place its declarations, and it does. Measured with `lake exe mitos-gate lock
  --check` on the built sketch: of the 20 `-` lines, none moves for an unrelated reason. Seven are
  derived instances of a type this PR changes (`Derivation`, `Edge`, `FactKind`) or of the one
  structure that holds a `FactKind` (`Fact`); they differ in `aux=` only, except
  `instDecidableEqFactKind`, whose value changes too. The placement rules, each measured
  (Rationale, "Lock lines that move with no change of meaning"):
  - `Identity` and `Scope` stay at the top of `Fact.lean` with `Identity` first, and `FactKind`
    moves to just above `Fact`. Any other order moved `instReprScope` or `instDecidableEqSpan`.
  - `Edge.through` is the last field, so `Edge.assumes` and `Edge.status` keep their lines.
  - New definitions go below `Chain.repoKey` in `Derivations.lean`, or in a new file, so `Chain` and
    its instances keep their lines.
- **Answer on the records.** Both `examples/acme/accepted/ToyRequire.json` and
  `examples/acme/accepted/GoMod.json` must be recorded again, and only `core_sha256` changes in
  each. `core_sha256` hashes the plugin surface, and this row changes its `Fact.lean`. The
  plan's row names only `ToyRequire.json` because it predates P2-007's merge (#286). `GoMod.json` is
  stale on `main` already: at c280558 its `core_sha256` is `8ae154a0…`, the value before #277,
  where `ToyRequire.json` holds `f7d74757…`. No plugin, model or `models.lock` file changes, because
  only `FactKind` gains a constructor and no plugin or model matches on it.
- Where the plan and `main` differ:
  - **D1. The Owns cell allows "the `find=` lines its `Impl/` edit moves", and the design moves
    more in `eval/mutants/cases/`.** Eight `find=` texts move (`ai_ignored`, `status_requirer_only`,
    `unresolved_dropped`, `unresolved_inverted`, `first_provider_only`, `edges_duplicated`,
    `first_fact_skipped`, `unresolved_lists_provisions`), together with their paired `replace=`
    texts except `unresolved_dropped`'s unchanged `[]`. Four additional anchors move because the
    review fix caches each row; the replacements preserve each mutant's original fault. The `replace=` copy of `Impl/Resolve.lean` inside
    `cheat_proofs_own_hole` is not a `find=` line and must be regenerated, or the case fails at the
    build and pins nothing (P2-005a, rule R6); it has no fallback. The new `Affects` constructor needs one more induction case in
    `impact_includes_self/Refute.lean`.
    Fallback for that line only: define `Affects.step` over the edge's legs and drop the
    constructor; not built, and it moves two more anchors.
  - **D2. The lock needs to reach `Spec/Chains.lean`.** The current spec entry point is
    `core/Mitos/Core/Spec.lean`, which imports the chain fixtures for the lock.
  - **D3. The plan says `FactKind.binds` "changes `Fact` for every plugin".** On `main` only
    `FactKind` gains a constructor, and no plugin or model matches on it (grep over `examples/`,
    `eval/cheats/`, `gate/`). Both plugins are accepted by gates 0 to 6 with no edit.
  - **D4. The plan's row names only `ToyRequire.json`.** The Owns cell's glob
    `examples/acme/accepted/*.json` already covers `GoMod.json`, so no ruling is needed (see the
    answer on the records above).
  - **D5. #160 item 1 is stale against the plan's refined status rule.** It says a requirement with
    a direct and a bound derivation to one provider turns `inferred`; the plan says it stays
    `confirmed`, and P2-001a's `StatusHonest` already has the refined form.
  - **D6. The plan and #156 put `boundB`, `Chain` and `derivations` in `Graph.lean`.** P2-001a put
    them in `Spec/Derivations.lean`. This design follows `main`.
  - **D7. Landing this file needs one edit outside it.** `.claude/scripts/plan-tasks.pending` lists
    `P2-001b`, and `plan-tasks.test.sh` fails a listed row that has a valid file. The PR that adds
    this file removes the line (`.claude/` is the owner's).
  - **D8. P2-001a's deferral "the span theorems leave `Spec/Adequacy.lean` when the chain fixtures
    land" does not apply.** The fixtures go to their own file, so `Adequacy.lean` does not grow. The
    move goes to this PR's follow-up issue (deferrals).
- No open PR touches `core/`, `eval/mutants/`, `eval/score/`, `examples/acme/`, `statements.lock`
  or `models.lock`: the judge read all 4 open PRs over REST at c280558. The two runners built on
  d614a47, and `main` has moved to c280558 since, but
  `git diff --stat d614a47 c280558 -- core eval examples statements.lock models.lock` prints
  nothing: only `gate/` shard files, `docs/process.md`, `ci.yml`, `plan/`, `tasks/` and `ops/` moved.
- Design written at plan time by an arena of two runners (opus and sonnet) and a judge
  (Rationale, Synthesis decision). The judged sketch, every proof filled in, was built in a scratch
  copy of `main` at c280558 on Lean v4.35.0. Its results are the run-level fixtures below, marked
  "measured".

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists. `core/Challenge/`, `core/comparator.json` and `eval/score/Score.lean` are in the plan's Owns
cell for this row. They are under `must_not_touch` because the design needs no diff in them: a
needed diff means the design is wrong, and the builder stops.

depth: build. Every type, definition and statement below is final text. Every proof was written
and checked (`lake build`, `lake check`, `lake comparator --paranoid`); the ones that are not a
two-case copy of `main` are in the Appendix, and the rest follow the routes under `statements`.

revisit_when: none for the design. At branch time: `git fetch origin main`, then
`git diff --stat c280558 origin/main -- core eval/mutants eval/score examples statements.lock
models.lock lean-toolchain lakefile.toml` must print nothing. If it prints a file, read the change
against this design first (a toolchain bump (#147) or a new mutant case (#231 style) would move it).
Re-read `eval/mutants/cases/`: a case added since, whose `find=` holds `(providers fs r).isEmpty`,
`&& (providers fs r)` or `statusOf fs r (`, or whose `Refute.lean` does an `induction` on `Affects`,
joins the migration table. Apply the owner's O1 ruling before step 3.

modules: one topic per file. Line counts are measured in the judged build. A build that outgrows
this map reports it as a deviation and does not split silently.
- `core/Mitos/Core/Fact.lean`: facts and spans. 154 → 155 lines. `Identity` moves to the top, above
  `Scope`; `FactKind` moves down to sit directly above `Fact` and gains `binds (to : Identity)`.
  No other byte changes.
- `core/Mitos/Core/Graph.lean`: the records a resolver reads and writes. 91 → 97. In place: one
  `Derivation` constructor, one arm in each accessor, the `Edge.through` field (last, with a
  default), one `Affects` constructor.
- `core/Mitos/Core/Spec/Derivations.lean`: which derivations a fact list has. 94 → 135. New
  declarations sit below `Chain.repoKey`, so nothing with a hygienic name moves. Copies its own
  layout (definitions, then the laws). Adds `boundB`, `Chain.bound`, `Chain.through`, a second
  list in `derivations`, `NoBinds` and `mem_derivations_of_noBinds`; restates `mem_derivations` and
  `derivations_single_provider`; the other three laws keep their statements and gain a case in
  their proofs.
- `core/Mitos/Core/Spec/Resolve.lean`: the twelve statements. 52 → 52. One line of `Sound`.
- `core/Mitos/Core/Spec/Adequacy.lean`: 191 → 191. One `obtain` pattern. The span theorems stay (D8).
- `core/Mitos/Core/Spec/Repo.lean`: 54 → 54. Five `obtain` patterns. No statement changes.
- `core/Mitos/Core/Spec/Chains.lean` (new): what the statements force on chain inputs. 207 lines.
  Copies the fixture half of `Spec/Adequacy.lean` (inputs as defs, a `WellFormed` theorem per input,
  one consequence theorem per statement whose meaning extends).
- `core/Mitos/Core/Spec.lean`: one import line, `Mitos.Core.Spec.Chains`, last. This makes the
  chain fixtures reachable from the locked spec.
- `core/Mitos/Impl/Resolve.lean`: the resolver. 27 → 73. Full text under `types`.
- `core/Mitos/Impl/Impact.lean`: `fires` reads `through`. 23 → 25.
- `core/Mitos/Proofs/Resolve/Basic.lean`: what `resolve` lists, and how the ends of a requirement
  match its derivations. 27 → 120 after the cache equivalence helpers. It stays the only proof file that imports `Mitos.Impl.Resolve`
  (`cheat_proofs_own_hole` replaces that import).
- `core/Mitos/Proofs/Resolve/Edges.lean`: sound, complete, unresolved-exact, total. 49 → 44.
- `core/Mitos/Proofs/Resolve/Assumptions.lean`: assumptions-exact, status-honest, retract-exact.
  58 → 92.
- `core/Mitos/Proofs/Resolve/Nodup.lean`: no-duplicates. 66 → 81.
- `core/Mitos/Proofs/Impact.lean`: impact-correct. 72 → 76. `Proofs/Impact/Nodup.lean` keeps every
  byte (it reads only `(fires_iff.mp _).2`).
- Generated at the head: `statements.lock`, `examples/acme/accepted/ToyRequire.json`,
  `examples/acme/accepted/GoMod.json`.
- Mutant files: the eleven `mutant` files and one `Refute.lean` under "Mutant migration".

### Usage (caller's view)

A plugin states a binding as a fact. Its `ident` is the identity it binds, the one a requirement
names; its kind carries the identity it binds it to:

```lean
{ kind := .binds { kind := "svc", key := "orders-db" },
  ident := { kind := "env", key := "DATABASE_URL" }, span := ⟨0, 12⟩ }
```

The owner reads one new rule and one new conjunct. A chain is a requirement, a binding of the
requirement's identity, and a provision of the bound identity:

```lean
def boundB (r b p : Located) : Bool :=
  r.fact.kind == .requires && b.fact.ident == r.fact.ident &&
    b.fact.kind == .binds p.fact.ident && p.fact.kind == .provides && p.fact.ident != r.fact.ident

def Sound (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∃ c ∈ derivations fs,
    c.key = e.key ∧ c.repoKey = e.repoKey ∧ c.through = e.through
```

The resolver writes one record per chain, built from the direct record, so the four repo-level
fields have one writer:

```lean
def assumptionsVia (r b p : Located) : List Assumption :=
  (assumptionsOf r p).insert b.origin

def mkBoundEdge (fs : List Located) (r b p : Located) : Edge :=
  { mkEdge fs r p with
    key := .bound r.id b.id p.id, through := [b.repo],
    assumes := assumptionsVia r b p,
    status := statusOf fs r p (assumptionsVia r b p) }
```

A record's status asks every derivation of its requirement, through any rule:

```lean
def ends (fs : List Located) (r : Located) : List Located :=
  providers fs r ++ fs.flatMap (boundProviders fs r)

def statusOf (fs : List Located) (r p : Located) (assumes : List Assumption) : Status :=
  if assumes.all (fun a => !a.isAI) && (ends fs r).all (·.id == p.id) then .confirmed
  else .inferred
```

The usage above states the canonical status rule. The implementation caches `summarizeEnds`
once per row and passes its O(1) `accepts` result through the optional `same` argument of the
edge constructors. `summarizeEnds_accepts` and `resolve_eq` preserve that rule for every input,
including duplicate IDs. Proofs use the canonical expansion in `resolve_eq`; runtime uses rows.

Impact analysis follows bindings: a change in the repo that holds the binding reaches the
requirer.

```lean
example : "web" ∈ Impl.impact [Spec.Chains.chainEdge] "deploy" :=
  (Proofs.impact_correct _ _ _).mpr (.through (e := Spec.Chains.chainEdge) (by simp) (by decide))
```

A proof splits on the rule. Each Phase 2a proof gains a bound case with the same shape:

```lean
theorem resolve_sound : Spec.Sound resolve := by
  intro fs _ e he
  rcases mem_edges.mp he with ⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · exact ⟨Chain.direct r p, mem_derivations.mpr (.inl ⟨r, hr, p, hp, hm, rfl⟩), rfl, rfl, rfl⟩
  · exact ⟨Chain.bound r b p, mem_derivations.mpr (.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩),
      rfl, rfl, rfl⟩
```

types:

`core/Mitos/Core/Fact.lean`. `Identity` moves to the top, `FactKind` moves to just above `Fact` and
gains `binds`, and nothing else in the file changes (the diff is Appendix A1):

```lean
inductive FactKind where
  | provides
  | requires
  | binds (to : Identity)
  deriving DecidableEq, Repr
```

`core/Mitos/Core/Graph.lean`. `Assumption`, `Located`, `Status`, `RepoKey`, `Edge.requiringFactId`,
`Edge.providingFactId`, `Resolution`, `Resolver`, `WellFormed`, `retract` and both moved theorems
keep their text.

```lean
inductive Derivation where
  | direct (requiringFactId providingFactId : Nat)
  | bound (requiringFactId bindingFactId providingFactId : Nat)
  deriving DecidableEq, Repr

def Derivation.requiringFactId : Derivation → Nat
  | .direct r _ => r
  | .bound r _ _ => r

def Derivation.providingFactId : Derivation → Nat
  | .direct _ p => p
  | .bound _ _ p => p

structure Edge extends repoKey : RepoKey where
  key     : Derivation
  assumes : List Assumption
  status  : Status
  through : List String := []
  deriving DecidableEq, Repr

inductive Affects (es : List Edge) : (changed : String) → (dependent : String) → Prop where
  | step {e : Edge} : e ∈ es → Affects es (changed := e.providingRepo) (dependent := e.requiringRepo)
  | through {e : Edge} {b : String} : e ∈ es → b ∈ e.through →
      Affects es (changed := b) (dependent := e.requiringRepo)
  | trans {x y z : String} : Affects es x y → Affects es y z → Affects es x z
```

`through` is the last field and has a default, so every `Edge` literal on `main` (the adequacy
fixtures, 16 `Refute.lean` and `mutant` files, `mkEdge`) builds unchanged. `RepoKey` does not gain
it: the repo-level edge is one per set of derivations, whatever repo holds the binding.

`core/Mitos/Core/Spec/Derivations.lean`. `matchesB`, `Chain`, `Chain.direct`, `Chain.origins` and
`Chain.repoKey` keep their text and places. Inserted after `Chain.repoKey`, then `derivations`
replaced:

```lean
def boundB (r b p : Located) : Bool :=
  r.fact.kind == .requires && b.fact.ident == r.fact.ident &&
    b.fact.kind == .binds p.fact.ident && p.fact.kind == .provides && p.fact.ident != r.fact.ident

def Chain.bound (r b p : Located) : Chain :=
  { key := .bound r.id b.id p.id, requirement := r, via := [b], provision := p }

def Chain.through (c : Chain) : List String :=
  c.via.map Located.repo

def derivations (fs : List Located) : List Chain :=
  fs.flatMap fun r => (fs.filter (matchesB r)).map (Chain.direct r) ++
    fs.flatMap fun b => (fs.filter (boundB r b)).map (Chain.bound r b)

def NoBinds (fs : List Located) : Prop := ∀ b ∈ fs, ∀ i, b.fact.kind ≠ .binds i
```

`Chain.through` is written with `Located.repo`, not `(·.repo)`, so its locked value holds no
macro-scoped binder name. `NoBinds` goes below `mem_derivations_retract`, where it is first used.

`core/Mitos/Core/Spec/Resolve.lean`: the last line of `Sound` becomes
`c.key = e.key ∧ c.repoKey = e.repoKey ∧ c.through = e.through`. Nothing else changes.

`core/Mitos/Core/Spec/Chains.lean`: the whole file is Appendix A3. Its inputs are `needDb`, `bindDb`
and `provDb` (a requirement in `web`, a binding in `deploy`, a provision in `orders`), `chain`,
`chainEdge`, `bindAI` and `chainAI` (the binding's origin is AI-proposed), `bindStaging` and
`twoBindings` (a second binding of the same requirement, in `staging`), `forkBind`, `forkProv` and
`fork` (a requirement with a direct provider and a bound chain to another), and `selfBind` and
`selfBound` (a binding from an identity to itself).

`core/Mitos/Impl/Resolve.lean`, the whole file:

```lean
import Mitos.Core.Spec

namespace Mitos.Impl

def providers (fs : List Located) (r : Located) : List Located :=
  fs.filter (matchesB r)

def boundProviders (fs : List Located) (r b : Located) : List Located :=
  match b.fact.kind with
  | .binds _ => fs.filter (boundB r b)
  | _ => []

def ends (fs : List Located) (r : Located) : List Located :=
  providers fs r ++ fs.flatMap (boundProviders fs r)

abbrev EndSummary := Bool ⊕ Nat

def summarizeEnds (ps : List Located) : EndSummary :=
  match ps with
  | [] => .inl true
  | p :: rest => if rest.all (·.id == p.id) then .inr p.id else .inl false

def EndSummary.accepts (s : EndSummary) (id : Nat) : Bool :=
  match s with
  | .inl acceptsAll => acceptsAll
  | .inr candidate => candidate == id

def assumptionsOf (r p : Located) : List Assumption :=
  if r.origin = p.origin then [r.origin] else [r.origin, p.origin]

def assumptionsVia (r b p : Located) : List Assumption :=
  (assumptionsOf r p).insert b.origin

def statusOf (fs : List Located) (r p : Located) (assumes : List Assumption)
    (same : Bool := (ends fs r).all (·.id == p.id)) : Status :=
  if assumes.all (fun a => !a.isAI) && same then .confirmed
  else .inferred

def mkEdge (fs : List Located) (r p : Located)
    (same : Bool := (ends fs r).all (·.id == p.id)) : Edge :=
  { requiringRepo := r.repo, providingRepo := p.repo, ident := r.fact.ident, scope := r.fact.scope,
    key := .direct r.id p.id,
    assumes := assumptionsOf r p,
    status := statusOf fs r p (assumptionsOf r p) same }

def mkBoundEdge (fs : List Located) (r b p : Located)
    (same : Bool := (ends fs r).all (·.id == p.id)) : Edge :=
  { mkEdge fs r p same with
    key := .bound r.id b.id p.id, through := [b.repo],
    assumes := assumptionsVia r b p,
    status := statusOf fs r p (assumptionsVia r b p) same }

def isRequirement (l : Located) : Bool := l.fact.kind == .requires

def resolveOne (fs : List Located) (r : Located) : List Edge × List Nat :=
  let direct := providers fs r;
  let groups := fs.map fun b => (b, boundProviders fs r b);
  let allEnds := direct ++ groups.flatMap Prod.snd;
  let summary := summarizeEnds allEnds;
  (direct.map (fun p => mkEdge fs r p (summary.accepts p.id)) ++
    groups.flatMap (fun (b, ps) => ps.map fun p => mkBoundEdge fs r b p (summary.accepts p.id)),
   if isRequirement r && allEnds.isEmpty then [r.id] else [])

def resolve : Resolver := fun fs =>
  let rows := fs.map (resolveOne fs);
  { edges := rows.flatMap Prod.fst
    unresolved := rows.flatMap Prod.snd }

end Mitos.Impl
```

`mkBoundEdge` takes the four repo-level fields from `mkEdge`, so `requiringRepo := r.repo,
providingRepo := p.repo` still occurs once (seven mutant cases find it), and it has no `let`: it
repeats `assumptionsVia r b p` as `mkEdge` repeats `assumptionsOf r p`, so the one-line copy inside
`cheat_proofs_own_hole` can be made from the file by a mechanical rule (Appendix A5). The status rule is the
plan's sentence in the implementation's terms: confirmed when nothing under the record is
AI-proposed and every derivation of the requirement ends at this record's provider. It replaces
`(providers fs r).length == 1`, as P2-001a's deferral said.

`core/Mitos/Impl/Impact.lean`: only `fires` changes. `impactGo` and `impact` keep every byte.

```lean
def fires (x : String) (seen : List String) (e : Edge) : Bool :=
  (e.providingRepo == x || seen.contains e.providingRepo ||
      e.through.any fun b => b == x || seen.contains b) &&
    !seen.contains e.requiringRepo
```

`core/Mitos/Proofs/`: the twelve Challenge theorems keep their names and statements. Helpers, with
their text in Appendix A4:

```lean
-- Basic.lean (mem_providers, matchesB_requires, mem_assumptionsOf keep their text)
theorem mem_boundProviders {fs : List Located} {r b p : Located} :
    p ∈ boundProviders fs r b ↔ p ∈ fs ∧ boundB r b p = true
theorem mem_ends {fs : List Located} {r q : Located} :
    q ∈ ends fs r ↔ q ∈ fs ∧ (matchesB r q = true ∨ ∃ b ∈ fs, boundB r b q = true)
theorem mem_edges {fs : List Located} {e : Edge} :
    e ∈ (resolve fs).edges ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ e = mkEdge fs r p) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ e = mkBoundEdge fs r b p
theorem mem_assumptionsVia {r b p : Located} {a : Assumption} :
    a ∈ assumptionsVia r b p ↔ a = r.origin ∨ a = b.origin ∨ a = p.origin
theorem ends_derivations {fs : List Located} (wf : WellFormed fs) {r : Located} (hr : r ∈ fs)
    {P : Located → Prop} :
    (∀ c ∈ derivations fs, c.requirement.id = r.id → P c.provision) ↔ ∀ q ∈ ends fs r, P q

-- Edges.lean (replaces no_derivation_iff_no_provider)
theorem no_derivation_iff_no_end {fs : List Located} (wf : WellFormed fs) {r : Located}
    (hr : r ∈ fs) :
    (∀ c ∈ derivations fs, c.requirement.id ≠ r.id) ↔ (ends fs r).isEmpty

-- Assumptions.lean (contains_assumptionsOf keeps its text)
theorem statusOf_confirmed {fs : List Located} (wf : WellFormed fs) {r p : Located} (hr : r ∈ fs)
    (assumes : List Assumption) :
    statusOf fs r p assumes = .confirmed ↔
      ((∀ a ∈ assumes, a.isAI = false) ∧
        ∀ c ∈ derivations fs, c.requirement.id = r.id → c.provision.id = p.id)
theorem mem_keys {fs : List Located} {k : Derivation} {P : Edge → Bool} :
    k ∈ ((resolve fs).edges.filter P).map Edge.key ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ P (mkEdge fs r p) = true ∧
          k = .direct r.id p.id) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ P (mkBoundEdge fs r b p) = true ∧
          k = .bound r.id b.id p.id
theorem contains_assumptionsVia {r b p : Located} {a : Assumption} :
    (assumptionsVia r b p).contains a = false ↔ r.origin ≠ a ∧ b.origin ≠ a ∧ p.origin ≠ a

-- Nodup.lean (assumptionsOf_nodup, resolve_edge_list_nodup keep their text)
theorem assumptionsVia_nodup (r b p : Located) : (assumptionsVia r b p).Nodup

-- Impact.lean (impactGo_closed and impact_correct keep their text)
theorem fires_iff {x : String} {seen : List String} {e : Edge} :
    fires x seen e = true ↔
      (e.providingRepo = x ∨ e.providingRepo ∈ seen ∨ ∃ b ∈ e.through, b = x ∨ b ∈ seen) ∧
        e.requiringRepo ∉ seen
def Closed (es : List Edge) (x : String) (out : List String) : Prop :=
  ∀ e ∈ es, (e.providingRepo = x ∨ e.providingRepo ∈ out ∨ ∃ b ∈ e.through, b = x ∨ b ∈ out) →
    e.requiringRepo ∈ out
```

`List.Nodup.insert` and `List.nodup_insert` do not exist at v4.35.0, so `assumptionsVia_nodup` splits
on `b.origin ∈ assumptionsOf r p` and uses `List.insert_of_mem` and `List.insert_of_not_mem`.

statements:

Restated: `Sound` gains `c.through = e.through`. With the key and the repo-level key it already
pins, every field of an edge except `assumes` and `status` now has its statement in `Sound`, and
those two have theirs (`AssumptionsExact`, `StatusHonest`).

Text kept, meaning extended to chains, each pinned by a fixture in `Spec/Chains.lean`: `Complete`
(a record per chain), `UnresolvedExact` (a requirement met only through a binding is resolved, and
one with no binding is not), `Total`, `AssumptionsExact` (the binding's origin is under the
record), `StatusHonest` (an AI-proposed binding makes the record `inferred`; every derivation of
the requirement, through any rule, is compared), `RetractExact`, `ImpactCorrect`
(`Affects.through`), the four no-duplicates statements. With every input fixed each statement stays
decidable, so a refutation is still `have := h fs wf; revert this; decide`.

Laws in `Spec/Derivations.lean` (the file's text is Appendix A2):

| Law | Reads |
|---|---|
| `mem_derivations` (restated) | a derivation is a direct match, or a requirement, a binding and a provision (`boundB`) |
| `mem_derivations_of_noBinds` (new) | with no binding fact, the derivations are exactly Phase 1's matches |
| `derivations_single_provider` (restated) | with no binding fact, "every derivation of a requirement ends at one provider" is Phase 1's "one matching provider" |
| `derivations_key_ends`, `derivations_key_inj`, `mem_derivations_retract` | statements unchanged; each proof gains the bound case |

```lean
theorem mem_derivations {fs : List Located} {c : Chain} :
    c ∈ derivations fs ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ c = Chain.bound r b p

theorem mem_derivations_of_noBinds {fs : List Located} (hnb : NoBinds fs) {c : Chain} :
    c ∈ derivations fs ↔ ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p

theorem derivations_single_provider {fs : List Located} (wf : WellFormed fs) (hnb : NoBinds fs)
    {c : Chain} (hc : c ∈ derivations fs) :
    (∀ d ∈ derivations fs, d.requirement.id = c.requirement.id →
        d.provision.id = c.provision.id) ↔
      (fs.filter (matchesB c.requirement)).length = 1
```

`mem_derivations_of_noBinds` is the plan's sentence "With no binding fact, `derivations fs` holds
exactly Phase 1's matches", locked, since `mem_derivations` no longer says it. It is also the one
place `derivations_single_provider` reads the direct rule from. `derivations_single_provider` is
used by no proof now; it stays as the Phase 1 agreement of the status rule.

Chain adequacy theorems, `core/Mitos/Core/Spec/Chains.lean` (all proved in the check; the text is
Appendix A3):

```lean
theorem noBinds_twoProvisions : NoBinds twoProvisions
theorem chain_derivations : derivations chain = [Chain.bound needDb bindDb provDb]
theorem sound_records_the_binding {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R chain).edges,
      e.key = Derivation.bound 0 1 2 ∧ e.through = ["deploy"] ∧ e.repoKey = chainEdge.repoKey
theorem sound_direct_edges_have_no_through {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R [req, prov]).edges, e.through = []
theorem unresolved_exact_binding_resolves {R : Resolver} (hu : UnresolvedExact R) :
    0 ∉ (R chain).unresolved
theorem unresolved_exact_needs_the_binding {R : Resolver} (hu : UnresolvedExact R) :
    0 ∈ (R [needDb, provDb]).unresolved
theorem assumptions_exact_lists_binding {R : Resolver} (ha : AssumptionsExact R) :
    ∀ e ∈ (R chain).edges, e.key = Derivation.bound 0 1 2 →
      ∀ a, a ∈ e.assumes ↔ (a = needDb.origin ∨ a = bindDb.origin ∨ a = provDb.origin)
theorem status_honest_ai_binding_inferred {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R chainAI).edges, e.status = .inferred
theorem twoBindings_derivations :
    derivations twoBindings =
      [Chain.bound needDb bindDb provDb, Chain.bound needDb bindStaging provDb]
theorem complete_keeps_both_bindings {R : Resolver} (hc : Complete R) :
    (∃ e ∈ (R twoBindings).edges, e.key = Derivation.bound 0 1 2) ∧
      ∃ e ∈ (R twoBindings).edges, e.key = Derivation.bound 0 3 2
theorem binding_retracted_chain_goes {R : Resolver} (hs : Sound R) :
    (R (retract bindDb.origin chain)).edges = []
theorem binding_retracted_repo_edge_stays {R : Resolver} (hs : Sound R) (hc : Complete R) :
    chainEdge.repoKey ∈ (R (retract bindStaging.origin twoBindings)).edges.map Edge.repoKey
theorem fork_derivations :
    derivations fork = [Chain.direct req prov, Chain.bound req forkBind forkProv]
theorem status_honest_fork_inferred {R : Resolver} (hh : StatusHonest R) :
    ∀ e ∈ (R fork).edges, e.requiringFactId = 0 → e.status = .inferred
theorem selfBound_derivations :
    derivations selfBound = [Chain.direct req prov]
theorem status_honest_self_binding_confirmed {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R selfBound).edges, e.status = .confirmed
theorem binding_change_affects_requirer {I : List Edge → String → List String}
    (hi : ImpactCorrect I) : "web" ∈ I [chainEdge] "deploy"
```

The two status fixtures that conclude for every record take `Sound` and `AssumptionsExact` too,
because `StatusHonest` alone relates a record's status to its own `assumes`, and only those two tie
`assumes` and the key to a chain (the same gap as V1 on #276). `status_honest_fork_inferred` needs
neither: if the record were `confirmed`, `StatusHonest` makes both derivations of the requirement
end at its provider, and they end at two different facts.

Proof routes (Appendix A4 has the ones that are not a two-case copy of `main`):
- Each `resolve_*` proof on `main` that starts from `mem_edges` or `mem_derivations` splits on the
  rule. Its direct case is `main`'s text; its bound case is the same text with `Chain.bound r b p`,
  `mkBoundEdge fs r b p` and `mem_assumptionsVia`.
- `mem_assumptionsVia`: `List.mem_insert_iff`, `mem_assumptionsOf` and `or_left_comm`.
- `resolve_unresolved_exact`: rewrite `resolve_eq`, then `main`'s proof with `no_derivation_iff_no_end` in place of
  `no_derivation_iff_no_provider`; it follows from `ends_derivations` at `P := fun _ => False`.
- `resolve_total`: from `resolve_complete`, `derivations_key_ends` and `resolve_unresolved_exact`.
- `resolve_status_honest`: both cases are `statusOf_confirmed wf hr _`, which is
  `ends_derivations` at `P := fun q => q.id = p.id` and a `split`.
- `resolve_retract_exact`: `main`'s filter argument over the two-rule `mem_keys`, with
  `contains_assumptionsVia` for the bound case.
- `resolve_edges_nodup`: the keys are `fs.flatMap` of direct keys `++` bound keys;
  `List.pairwise_flatMap` and `List.pairwise_append`, with the constructor mismatch between the
  two blocks and `Derivation.requiringFactId` across requirements.
- `impactGo_sound`: a fired edge fires through its provider (`step`) or a binding repo
  (`through`), each from `x` or from a repo already seen (`trans`).
- `affects_closed`: the induction gains `| through he hb => …` (the third disjunct of `Closed`).

reuse:
- `matchesB`, `Chain`, `Chain.direct`, `Chain.origins`, `Chain.repoKey`, `RepoKey`, `WellFormed`,
  `retract`, `wellFormed_retract`, `WellFormed.eq_of_id`, `retract_repo`: unchanged text.
- `Spec.Adequacy.req`, `prov`, `provDeclared`, `twoProvisions`, `wf`: the fork, the self-binding and
  the Phase 1 agreement fixtures start from them.
- `Proofs.mem_providers`, `mem_assumptionsOf`, `contains_assumptionsOf`, `assumptionsOf_nodup`,
  `resolve_edge_list_nodup`, `impactGo_closed`, `impact_correct`, `impact_nodup`: unchanged.
- `Mutants.total_of_complete_unresolved` and `retract_of_sound_complete_assumptions` build
  unchanged: `obtain ⟨c, hc', hck, -⟩ := hs …` takes the new third conjunct into `-`.
- `Spec.retract_repo`'s two examples are the pattern for `binding_retracted_repo_edge_stays`.
- The Phase 1 refutation pattern; P2-005a's fallbacks if a replay kernel rejects a `decide`.

fixtures:

Locked Lean fixtures (`Spec/Chains.lean`, Appendix A3, 36 lines of the lock). Each stops proving
when the clause it names is weakened, which a `¬ S (constant resolver)` theorem does not always do.

| Fixture | Pins |
|---|---|
| `chain_derivations`, `twoBindings_derivations`, `fork_derivations`, `selfBound_derivations`, `noBinds_twoProvisions` | the kernel evaluates `boundB` and `derivations` on four inputs, and `NoBinds` holds on Phase 1's own two-provision input, so the Phase 1 agreement laws apply to it. A wrong `boundB` or `derivations` fails in the kernel |
| `sound_records_the_binding` | the new conjunct: an edge of a sound resolver on the chain input has key `.bound 0 1 2`, `through = ["deploy"]`, and the web-to-orders repo key past the binding's repo |
| `sound_direct_edges_have_no_through` | on a direct chain the third conjunct says `through = []`, so the field's default is a statement, not a convention |
| `complete_keeps_both_bindings` | two bindings of one requirement, in two repos, are two derivations and two records (option C on chains) |
| `unresolved_exact_binding_resolves`, `unresolved_exact_needs_the_binding` | both directions: a requirement met only through a binding is not listed, and with no binding it is |
| `assumptions_exact_lists_binding` | the record assumes the binding's origin too: the leaf origins of all three facts |
| `status_honest_ai_binding_inferred` | an AI-proposed binding makes every record of its input `inferred` |
| `status_honest_fork_inferred` | the plan's status rule, other half: a requirement with a direct provider and a bound chain to another provider has only `inferred` records |
| `selfBound_derivations`, `status_honest_self_binding_confirmed` | #160 item 1 (O1): a binding from an identity to itself yields only the direct record, which is `confirmed` |
| `binding_retracted_chain_goes` | retract the binding's origin and the chain's record goes |
| `binding_retracted_repo_edge_stays` | retract one of two bindings and the web-to-orders repo-level edge stays, because the other chain avoids it (the #156 staging and prod example) |
| `binding_change_affects_requirer` | a change in `deploy` reaches `web` in any correct `impact` |
| `wfChain`, `wfChainAI`, `wfTwoBindings`, `wfFork`, `wfSelfBound` | the five inputs have unique ids |

Run-level fixtures the builder reports. "Measured" means the judged sketch produced it at c280558.
- `comparator`: `cd core && lake comparator --paranoid` prints `Your solution is okay!`. Measured:
  all five kernels accept (lean4lean 2063 declarations; con-leche and con-ron 2066). The replay
  covers the Challenge's closure, not `Spec/Chains.lean`, which `lake build` and `lake check`
  check.
- `challenge-untouched`: `git diff origin/main -- core/Challenge core/comparator.json
  core/lakefile.toml` prints nothing.
- `lake-check`: `cd core && lake check` accepts, axioms `Classical.choice, propext, Quot.sound`.
  Measured.
- `core-build`: `cd core && lake build` after `rm -rf .lake/build` builds 23 jobs with no warning and
  no `sorry`. Measured.
- `chain-run`: a scratch file importing `Mitos.Proofs.Resolver`, elaborated with `lake env lean`
  from `core/`, shows by `decide`: `(Impl.resolve Spec.Chains.chain).edges.map Edge.key =
  [.bound 0 1 2]`, its `unresolved = []`, its `edges.map Edge.through = [["deploy"]]`,
  `(Impl.resolve Spec.Chains.chainAI).edges.map Edge.status = [.inferred]`,
  `(Impl.resolve Spec.Chains.selfBound).edges.map Edge.status = [.confirmed]`,
  `(Impl.resolve Spec.Chains.fork).edges.map Edge.status = [.inferred, .inferred]`,
  `(Impl.resolve Spec.Chains.twoBindings).edges.map Edge.through = [["deploy"], ["staging"]]`,
  `(Impl.resolve [Spec.Chains.needDb, Spec.Chains.provDb]).unresolved = [0]`; and by `decide +kernel`:
  `Impl.impact (Impl.resolve Spec.Chains.chain).edges "deploy" = ["web"]` and the same at `"web"`
  is `[]`. Measured: all hold, and `#eval` of the chain's edges prints
  `[(Mitos.Derivation.bound 0 1 2, ["deploy"], Mitos.Status.confirmed)]`.
- `fact-step`: after step 1, `lake exe mitos-gate lock --check` prints `+ ctor Mitos.FactKind.binds`
  and `-`/`+` pairs for `instDecidableEqFact`, `instDecidableEqFactKind` and `instReprFactKind`,
  and no other line: three `-` and four `+`. Measured on `main` with only `Fact.lean` changed.
- `lock`: at the head `lake exe mitos-gate lock` writes 252 declarations (206 on `main`), and the
  diff is exactly the list under "Lock prediction". Measured.
- `lock-lists-chains`: `grep -c 'Spec.Chains' statements.lock` prints 36.
- `imports`: `lake exe mitos-gate imports` prints `0 import violation(s) in core/`. Measured.
- `scorecard-unchanged`: `lake --dir eval/score exe mitos-score eval/fixtures/toy` prints the same
  bytes as on `main`, with no edit to `eval/score/`. Measured: 868 bytes, identical to `main`'s.
- `mutants-build`: `lake --dir eval/mutants build`, `warningAsError` on, with no edit outside the
  migration table. Measured.
- `all-cases-as-expected`: every one of the 42 cases as expected, 22 refuted and 20 cheat cases
  rejected, default and `--paranoid`, one case per invocation (several cases in one invocation were
  killed by the container's memory limit at about 5 GB RSS, V4 on #276). Measured on the judged
  sketch: default mode, all 42 as expected (22 refuted, no known gap, 20 cheat cases rejected);
  `--paranoid` for the original six edited cases, all as expected (`cheat_proofs_own_hole` is UNBOUND, rejected
  at values, with the evidence line `Const does not match between challenge and target
  'Mitos.Impl.mkEdge'`). The builder runs the other 36 with `--paranoid` too.
- `cheat-evidence-unchanged`: the `.refutation.log` of `cheat_own_hole` and `cheat_namespace_shadow`
  show `Built Mitos.Proofs.RefuteCase` and then the comparator's reason
  (`Const does not match … 'Mitos.Impl.resolve'`, `… statement do not match …`), not an error in
  `RefuteCase.lean`. Measured by the opus runner at d614a47.
- `accept-recorded`: at the head, after the last rebase, both accept lines of "Before each push"
  with `--record` are ACCEPTED, and only `core_sha256` differs in each record. Measured without `--record`, with
  `--paranoid`, gates 0 to 6: ToyRequire ACCEPTED in 1 min 50 s, GoMod ACCEPTED in 2 min 23 s.
- `no-old-anchor`: `grep -rn 'providers fs r).isEmpty\|statusOf fs r (' eval/mutants/cases` prints
  nothing.

### Lock prediction

Measured on the judged sketch: 206 → 252 declarations; 20 lines change, none leaves, 46 arrive. The
PR body lists the regenerated diff against this list.
- Changed, a change of meaning: `Spec.Sound` (value); `derivations` (value); `mem_derivations`,
  `derivations_single_provider` (type); `ctor Edge.mk` (type, one more field);
  `Derivation.requiringFactId`, `Derivation.providingFactId` (value, the new arm).
- Changed, derived instances of a changed type, `aux=` only: `instDecidableEqDerivation`,
  `instReprDerivation`, `instDecidableEqEdge`, `instReprEdge`, `instReprFactKind`, and
  `instDecidableEqFact` (it follows `FactKind`, whose expansion grew). `instDecidableEqFactKind`
  changes in `value=` too.
- Changed, the term of an `Edge` literal: `Spec.Adequacy.goodEdge` (value) and the five adequacy
  theorems whose statement builds an `Edge` with `{ goodEdge with … }` (`backwards_not_sound`,
  `forgetful_not_exact`, `trusting_ai_not_honest`, `same_key_edges_not_nodup`,
  `doubled_assumption_not_nodup`): `Edge.mk` takes `through := []`. Their statements read the same.
- Added: `ctor FactKind.binds`, `ctor Derivation.bound`, `Edge.through`, `ctor Affects.through`,
  `ctor Affects.below.through`, `boundB`, `Chain.bound`, `Chain.through`, `NoBinds`,
  `mem_derivations_of_noBinds`, and the 36 declarations of `Spec.Chains`.
- Unchanged, byte for byte, among others: `Scope` and `Identity` and their instances, `RepoKey` and
  its instances, `Resolution`, `Chain` and its instances, `Chain.origins`, `Chain.repoKey`,
  `matchesB`, `Edge.assumes`, `Edge.status`, every other statement in `Spec/Resolve.lean`,
  `retract_repo`, `derivations_key_ends`, `derivations_key_inj`, `mem_derivations_retract`, every
  line outside the graph.

### Mutant migration

Ten cases need a new `find=` anchor. Their `replace=` fields carry the existing faults into the
new implementation, and the expectation fields keep their text.

| Case | Edit |
|---|---|
| `ai_ignored` | `find=if assumes.all (fun a => !a.isAI) && same`, `replace=if same` |
| `status_requirer_only` | `find=status := statusOf fs r p (assumptionsOf r p)`, `replace=status := statusOf fs r p [r.origin]` |
| `unresolved_dropped` | `find=rows.flatMap Prod.snd` (its `replace=[]` stays) |
| `unresolved_inverted` | `find=allEnds.isEmpty`, `replace=!allEnds.isEmpty` |
| `first_provider_only` | `find=direct.map (fun p => mkEdge fs r p (summary.accepts p.id))`, `replace=(direct.take 1).map (fun p => mkEdge fs r p (summary.accepts p.id))` |
| `edges_duplicated` | `find=edges := rows.flatMap Prod.fst`, `replace=edges := rows.flatMap Prod.fst ++ rows.flatMap Prod.fst` |
| `first_fact_skipped` | `find=edges := rows.flatMap Prod.fst`, `replace=edges := rows.tail.flatMap Prod.fst` |
| `unresolved_lists_provisions` | `find=if isRequirement r && allEnds.isEmpty then [r.id] else []`, `replace=if allEnds.isEmpty then [r.id] else []` |
| `unresolved_duplicated` | `find=unresolved := rows.flatMap Prod.snd`, `replace=unresolved := (rows ++ rows).flatMap Prod.snd` |
| `impact_repeats_repo` | Narrow the anchor to `find=!seen.contains e.requiringRepo`, `replace=true` |
| `cheat_proofs_own_hole` | the `replace=` copy of the implementation takes the same change as `Impl/Resolve.lean` (P2-005a, rule R6): it becomes the new file on one line. Appendix A5 has a command that regenerates it (whitespace runs become one space, `, ` goes before `unresolved :=`) and a check that it is current; the flattened payload must also compile before its mutant is run |
| `impact_includes_self` | `Refute.lean`: `not_affects_nil`'s `induction` gains `\| through he => simp at he` after its `step` line |

The rest of the anchors still occur exactly once. The `Edge` literals
in 16 `Refute.lean` and `mutant` files build unchanged, because `through` has a default. Each moved
case was run on the judged sketch and kept its result: `ai_ignored` and `status_requirer_only`
refuted (`resolve_status_honest`), `unresolved_dropped` and `unresolved_inverted` refuted
(`resolve_unresolved_exact`, `resolve_total`), `impact_includes_self` refuted (`impact_correct`),
`cheat_proofs_own_hole` UNBOUND, rejected at values.

### Order of edits

Run one Lean build at a time. Generate the lock only with `lake exe mitos-gate lock` from the
repository root, as CI does: in the opus runner's check, oleans built in `core/` as its own root
package and read by another build of the gate gave 31 different lock lines.

| Step | Edit | Must pass before the next step |
|---|---|---|
| 1 | `Fact.lean`: `Identity` to the top, `FactKind` above `Fact`, add `binds` | `lake build mitos-core/MitosImpl`; `fact-step`; comparator |
| 2 | `Graph.lean`: `Derivation.bound` and the two arms, `Edge.through` last, `Affects.through`; `Impl/Impact.lean`; `Proofs/Impact.lean`; `impact_includes_self/Refute.lean` | `cd core && lake build && lake comparator --paranoid`; the four `impact_*` cases |
| 3 | `Spec/Derivations.lean`; `Sound`; the `obtain` patterns in `Adequacy.lean` and `Repo.lean`; `Impl/Resolve.lean`; `Proofs/Resolve/*` | `cd core && lake build && lake check && lake comparator --paranoid` |
| 4 | `Spec/Chains.lean`; its import in `Core.lean` | `lake build && lake exe mitos-gate imports`; `cd core && lake check` |
| 5 | `lake exe mitos-gate lock` | `lock`, `lock-lists-chains` |
| 6 | The nine `mutant` files (`cheat_proofs_own_hole`'s copy by the command in Appendix A5) | `mutants-build`; `all-cases-as-expected`, one case per invocation |
| 7 | After the last rebase: the lock again if `main` moved, both accept records, this file, the run log `ops/runs/<UTC date>/P2-001b-builder-<attempt>.json` | the gate |

The builder stops and reports when:
- `core/Challenge/`, `core/comparator.json`, `eval/score/` or `Proofs/Impact/Nodup.lean` needs an
  edit;
- a `find=` text other than the eight in the table would have to move, or a case changes its
  result;
- a `Refute.lean` other than `impact_includes_self`'s needs an edit;
- the regenerated lock differs from the prediction by a line it cannot explain, or prints a `-`
  line for a declaration outside the list (do not reorder to absorb it; report it);
- a record differs from `main`'s in a field other than `core_sha256`;
- a restated statement fails for a Phase 2 resolver on a Phase 1 input (a counterexample goes to a
  spec issue), or a replay kernel rejects a `decide` that Lean accepts (the fallback for a fixture
  is `main`'s `obtain` and `simp` style, as in P2-001a's task file);
- a file outgrows its line in `modules` by more than a third.

Before each push, the lines the change can affect, one at a time, from the repository root:

```bash
lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check
(cd core && lake check && lake comparator --paranoid)
(cd examples/acme && lake build)
lake --dir eval/mutants build
(for c in $(ls eval/mutants/cases); do
  for m in "" --paranoid; do lake --dir eval/mutants exe mitos-mutants $m "$c" || exit 1; done
done)
lake --dir eval/score build && lake --dir eval/score exe mitos-score eval/fixtures/toy
lake exe mitos-gate accept --workspace examples/acme --plugin ToyRequire --model Models.ToyRequire.model --paranoid
lake exe mitos-gate accept --workspace examples/acme --plugin GoMod --model Models.GoMod.model --paranoid
```

After the last rebase, P2-007's check 6 (`tasks/P2-007-gomod-plugin.md`, Checks, 6) runs for each
plugin at the head the merge pins and prints nothing. Before this PR it prints one `core_sha256`
line for `GoMod.json` and none for `ToyRequire.json`.

cut_line: ships `FactKind.binds`, the bound rule, `Edge.through`, `Affects.through`, the restated
`Sound`, the laws, `Spec/Chains.lean`, the resolver and impact with all twelve proofs, the
regenerated lock and both accept records, and the mutant-file edits. The PR says `Closes #204`.
It leaves out new mutant cases (P2-005b), a chain fixture for the scorer and its labels (P2-009a),
the union view's status rule in the scorer (P2-009a), the derivation count (P2-010), chains longer
than one binding (a later constructor), an extractor that emits `binds` (YAML is a later phase), and
the move of the span theorems out of `Spec/Adequacy.lean` (deferrals). If the budget bites, cut
from the fixture table in this order: `unresolved_exact_needs_the_binding` and
`sound_direct_edges_have_no_through`, then the `twoBindings` group (`twoBindings_derivations`,
`complete_keeps_both_bindings`, `binding_retracted_repo_edge_stays`, `wfTwoBindings`), then the
self-binding group. Never cut `sound_records_the_binding`, `unresolved_exact_binding_resolves`,
`assumptions_exact_lists_binding`, `status_honest_fork_inferred`, `binding_change_affects_requirer`
or `noBinds_twoProvisions`: each is the only fixture on its clause.

deferrals:
- From P2-001a (#203), its contract, followed: `FactKind.binds`; `Derivation.bound` with two
  arms; `boundB`, `Chain.bound`; `Edge.through`, `Affects.through`; `Sound`'s conjunct; `Chain`,
  `Chain.origins`, `Chain.repoKey`, `Complete`, `UnresolvedExact`, `AssumptionsExact`,
  `StatusHonest`, `Total`, `RetractExact`, `retract_repo` and both `Mutants.Implied` theorems keep
  their statements; `mem_derivations` restated; `derivations_single_provider` gains the no-binding
  hypothesis (as `NoBinds fs`); the provider-counting status rule is replaced. Two readings differ
  in form: `Sound` names `c.through` (a def) where the contract wrote `c.via.map (·.repo)`;
  `derivations` lists each requirement's direct chains and then its bound chains, in one `flatMap`,
  where the contract said "a second list". The set is the same, and with no binding the list is the
  same.
- From P2-001a, not followed here: "The span theorems leave `Spec/Adequacy.lean` … when the chain
  fixtures land" (D8). The fixtures go to their own file, so `Adequacy.lean` does not grow, and
  moving 35 lines between spec files is review noise in a PR whose lock diff the owner reads line by
  line. The move goes to this PR's follow-up issue (no row).
- To P2-005b (#206), candidate chain mutants on the new text, not run: `through := [b.repo]` →
  `through := []` (breaks `resolve_sound`); `(assumptionsOf r p).insert b.origin` →
  `assumptionsOf r p` (`resolve_assumptions_exact`, `resolve_retract_exact`);
  `providers fs r ++ fs.flatMap (boundProviders fs r)` → `providers fs r`
  (`resolve_unresolved_exact`, `resolve_status_honest`); dropping the bound `flatMap` from `edges`
  (`resolve_complete`); `e.through.any fun b => b == x || seen.contains b` → `false`
  (`impact_correct`); `.bound r.id b.id p.id` → `.bound r.id p.id b.id` (`resolve_sound`); one edge
  per repo-level key (`resolve_complete` on `twoBindings`). V1 of #276 (a record whose key no chain
  has) stays P2-005b's.
- To P2-009a (#210): a chain fixture can copy `Spec.Chains.chain`. Its repo-level edge runs from
  the requirer to the provider; the binding's repo is not part of `RepoKey`, so a chain edge shows as
  `env/runtime` from `web` to `orders` and does not name `deploy`, and `collapse` merges a direct
  and a bound record of one requirement and provider.
- To P2-010 (#212): `(resolve fs).edges.map Edge.key` lists the keys in the order of
  `(derivations fs).map Chain.key` (same enumeration). Not stated as a theorem. "Derivations per
  repo-level edge" counts bound records too; `twoBindings` is a two-derivation example.
- To P2-012 (#213): a CI check that `accepted/*.json` matches the tree (P2-007's R1: no CI step
  reads the records, so a stale one can merge).
- To #276 (owner, `gate/`): item 2 stays there; this design leaves no `aux=`-only line that is not a
  derived instance of a changed type.
- No row, so the PR's follow-up issue (all minor): the span move above; a binding's `to` identity is
  not anchored by `Anchored` (only `ident.key` is), which matters once an extractor emits bindings;
  nothing makes the build fail when a new `Derivation` constructor gets no list in `derivations`;
  the `replace=` copy in `cheat_proofs_own_hole` is a hand-synced copy of `Impl/Resolve.lean`, and a
  runner that builds it from the file would end D1's second item for every later row; the reference
  resolver enumerates at most O(n³) derivations for n facts. `resolveOne` scans providers once,
  scans providers only for actual binding facts, and summarizes all endpoint IDs once per fact;
  each emitted record then checks its provider ID and at most three origins in O(1). The rows
  also supply unresolved IDs, so that output adds no endpoint scan. Time and output space are
  O(n³), with O(n²) temporary endpoint/group data per row, treating fact-field comparisons as
  constant cost. The plan defers the HashMap resolver with an equivalence proof.

owner_decisions:

Settled by the plan and #156, followed as written: chains exist in Phase 2 through
`FactKind.binds`; a rule is a constructor; statements quantify over the finite list; a change in
the binding's repo is impact; the status rule in the plan's refined form; this spec PR carries its
implementation and proofs (P2-000).

- O1. A binding from an identity to itself (#160 item 1). The owner ruled out a bound derivation
  for that case. `boundB` requires distinct endpoint identities, and `selfBound_derivations`
  lists only `Chain.direct req prov`. The direct record stays `confirmed`.
  [Owner ruling](https://github.com/kitimark/mitos/issues/204#issuecomment-6898646864)

Design defaults the owner sees at `spec-approved`. They are this design's calls, not the owner's
rulings. The builder follows each until the owner says otherwise on #204.
- O2. `binds (to : Identity)` carries the target in the kind; the binding's `ident` is the
  identity it binds, so `Anchored` anchors that key and the target is not anchored. `boundB`
  compares no scopes, as `matchesB` compares none.
- O3. `Edge.through : List String := []`, the last field, with a default. Every `Edge` literal on
  `main` builds unchanged. It holds the repo of each binding fact as it is: no dedupe, and the
  requirer's and the provider's own repo are not removed.
- O4. `Sound` compares `c.through = e.through` through the def `Chain.through`.
- O5. `Affects.through` runs from the binding's repo to the requirer only. A binding held in the
  requirer's own repo makes that repo affect itself, so `impact es x` can list `x` without a cycle,
  as a same-repo direct edge already does.
- O6. The chain fixtures are a new locked file, `Spec/Chains.lean`, imported by
  `core/Mitos/Core/Spec.lean` (D2).
- O7. `Fact.lean` places `Identity` first, `Scope` second, and `FactKind` just above `Fact`.
  `binds` names `Identity`, which is declared after `FactKind` on `main`; of the orders measured,
  this one moves no unrelated lock line.
- O8. The fixture set: 36 locked declarations in `Spec.Chains` (14 inputs, 5 `WellFormed` theorems,
  17 consequences), and `NoBinds` with `mem_derivations_of_noBinds`. The cut order is in `cut_line`.
- O9. A dangling binding, one with no requirement or no provision, is data that no derivation uses.
  It is not reported anywhere: `unresolved` lists requirements only.
- O10. `NoBinds` is a locked definition that names the no-binding hypothesis once, where the two
  laws that need it read it.

## Rationale

### Problem
P2-001b adds the second rule. A requirement reaches its provider through a binding fact, an edge
records which repos the chain passes through, and impact follows them. Five things constrain the
shape. The owner reviews every locked line, and #276 showed lock lines that move with no change of
meaning. 38 mutant cases match exact text in `Impl/Resolve.lean`, 16 `Refute.lean` and `mutant`
files hold `Edge` literals, and none of those files is in this row's Owns cell except "the `find=`
lines its `Impl/` edit moves". Refutations must stay decidable and replay on five kernels.
P2-001a's laws were written so that `retract_repo` and both `Mutants.Implied` theorems need no new
statement here. And a plugin builds `Fact` values, so a change to `Fact` reaches every plugin and
both accept records.

### Facts this design rests on (checked against `main` at c280558)
- Lock lines hash the printed type, and for a def the value, plus `aux=` over unlisted helpers they
  reach (`gate/MitosGate/Lock.lean`). Theorem proofs are not hashed.
- Inserting a declaration with `deriving` (or a larger `deriving` expansion) above another in the
  same file moves the hygienic names in the later one's helpers (#276). Measured: adding a
  constructor to `Derivation` moved nothing below it (`RepoKey`, `Resolution` unchanged); new
  definitions placed below `Chain.repoKey` moved nothing in `Chain`.
- Of 42 mutant cases, 38 edit `Impl/Resolve.lean`, 4 edit `Impl/Impact.lean`; 21 distinct `find=`
  texts; one `replace=` (`cheat_proofs_own_hole`) is a full copy of `Impl/Resolve.lean`. Only
  `impact_includes_self/Refute.lean` does an exhaustive `induction` on `Affects`; no file outside
  the core matches on `FactKind` or `Derivation` (grep over `eval/`, `examples/`, `gate/`).
- `examples/acme/Models/GoMod.lean` uses `FactKind` as data and never matches on it. Both plugins
  pass gates 0 to 6 with `--paranoid` against the sketch.
- `rcases` patterns with fewer components than a conjunction bind the rest to the last one, so
  `obtain ⟨c, hc, hk, -⟩ := hs …` in `Mutants/Implied.lean` and `Spec/Repo.lean`'s
  `obtain ⟨c, hc, -⟩` absorb `Sound`'s new conjunct; patterns that name the repo-key conjunct gain a
  `-`.
- The comparator's replay covers the Challenge's closure. Fixtures in `Spec/Chains.lean` are checked
  by `lake build`; they are not replayed on the five kernels.

### Shape
A chain is a requirement, the facts it passes through (`via`), and a provision; P2-001a made
`Chain` final with `via` for this row. The bound rule is one constructor, one premise (`boundB`),
one builder (`Chain.bound`) and one list per requirement in `derivations`. Statements compare
keys, repo keys and the repos a chain passes through; they never look inside a key, except the two
accessors whose new arms keep `Total`'s and `StatusHonest`'s text.

Every field of an edge is pinned by one statement: `Sound` pins `key`, the repo-level key and
`through`; `AssumptionsExact` pins `assumes`; `StatusHonest` pins `status`.

The implementation keeps its own enumeration, as in P2-001a, so `Sound` and `Complete` stay real
proofs and the mutants keep their anchors. It mirrors the spec's two rules: `providers` and
`boundProviders` enumerate, `ends` is every fact some derivation of a requirement ends at, and
`statusOf` asks that every end is the record's provider. That is the plan's status rule in the
implementation's own terms, and `ends_derivations` is the one lemma that links the two. The proof expansion uses `ends`; runtime `resolveOne` shares the same direct and bound lists
across edge construction, status summary and unresolved IDs. `resolve_eq` proves these outputs
identical. A mutant that edits `providers` still reaches all three through the cached row.

`mkBoundEdge` builds on `mkEdge`, so the repo-level fields have one writer: `src_dst_swapped` and
`provider_scope` reach bound records too, and a later edit cannot let the two builders drift.

Interface depth: a consumer of resolver output sees one more `Edge` field and one more `Affects`
constructor. A spec reader sees one more conjunct and one more premise. A rule author adds a
constructor (the compiler then asks for the accessor arms), a premise, a builder and a list. Hidden
behind that are the laws: keys determine chains, retraction filters by every fact under a chain, and
with no binding nothing changes.

### Lock lines that move with no change of meaning (#276)
Placement, measured with `lake exe mitos-gate lock --check`, one run per variant, after the gate
was built. The sonnet runner measured the first four rows on `main` with only `Fact.lean`
changed; the last row and the opus runner's layout were run again by the judge on the whole sketch
(21 `-` lines against 20).

| `Fact.lean` order, with `binds` added | Unrelated lines that moved |
|---|---|
| `Identity`, `FactKind`, `Scope`, then the rest | `instDecidableEqSpan`, `instReprScope` |
| `Scope`, `Identity`, `FactKind`, then the rest | the same two |
| `Identity`, `Scope`, `FactKind`, then the rest | `instDecidableEqSpan` |
| `Scope`, `Identity`, …, `FactKind` just above `Fact` (the opus runner's) | `instReprScope` |
| **`Identity`, `Scope`, …, `FactKind` just above `Fact` (chosen)** | **none** |

`FactKind` cannot stay first because `binds` names `Identity`. In `Graph.lean`, `through` as the
last field of `Edge` keeps `Edge.assumes` and `Edge.status` (they changed when it sat after `key`;
both runners measured it). In `Derivations.lean` the new definitions sit below `Chain.repoKey` and
use `Located.repo`, so `Chain` and its instances keep their lines. The rules this supports: a new
field goes last; a new declaration goes below the existing ones in its file; a type that others
name goes above them; an in-place change to an inductive moves only the derived instances that name
it. Each row is one run, so the table is evidence and not a theory: a builder who finds a `-` line
outside the list under "Lock prediction" reports it and does not reorder to absorb it.

### Synthesis decision
The runners converged on the shape: `FactKind.binds (to : Identity)`, `Derivation.bound` with two
accessor arms, `Edge.through` last with a default, `Affects.through` as a constructor, `Sound`'s
third conjunct through `Chain.through`, an implementation that keeps its own enumeration and builds
the bound record from `mkEdge`, a status rule over every end of the requirement, the same six
mutant-file edits, and the same disagreements with the plan. That is strong agreement, so the shape
ships as it is, and the judge grafted only where the two differ. The judge ran on sonnet, the same
model as the second runner, so it measured each disputed point instead of weighing the runners'
claims. It judged in its own context and spawned no agent (the root's brief), so Phase C of the
arena skill has no cross-judge.

Rubric: (1) fidelity to the plan and to P2-001a's contract; (2) lock hygiene, #276; (3) mutant and
anchor cost; (4) fixture coverage of every statement whose meaning extends; (5) evidence run;
(6) builder legibility and the design red flags.

| Criterion | Opus runner (A) | Sonnet runner (B) |
|---|---|---|
| 1 | Follows the contract; two readings differ in form | The same two |
| 2 | One avoidable line moves (`instReprScope`) | None; found the `Identity` placement that avoids it |
| 3 | Six case edits; the inline `let` in `mkBoundEdge` makes the `replace=` copy need a hand-made `;` | The same six; no `let` in the original sketch, so the copy regenerated mechanically; the reviewed cache now uses explicit `;` separators that survive A5 |
| 4 | No fork fixture (the status rule's other half), no pin on the `through` default, no two-binding retraction | All three, and `NoBinds` on Phase 1's input |
| 5 | `comparator --paranoid` on all five kernels, five `--paranoid` mutants, both accepts with `--paranoid` | Nothing with `--paranoid` |
| 6 | 1098 lines; names read well (`ends`, `bindDb`); `derivations_without_bindings` restates the direct enumeration in a locked statement, and `derivations_single_provider` proves its own copy of the direct law | 1913 lines, the appendix is every file's diff; `bind` as a fixture name shadows Lean's `bind`; `provisions` and `providers` differ by one syllable |

Base: the opus runner. It has the stronger evidence (criterion 5), the leaner file, and names a
builder cannot confuse. Grafts, each folded in by hand and rebuilt:
1. From B, the `Fact.lean` layout with `Identity` moved above `Scope`. Measured by the judge on A's
   tree: 21 `-` lines become 20, and `instReprScope` stops moving. This is the answer to the root's
   #276 question.
2. From B, `NoBinds` and `mem_derivations_of_noBinds` in place of A's
   `derivations_without_bindings`. The membership form is P2-001a's `mem_derivations` text under
   the hypothesis, so a locked statement does not copy the direct enumeration, the hypothesis has
   one name, and `derivations_single_provider` reads the direct rule from it instead of proving a
   local copy.
3. From B, the helper `assumptionsVia` in place of A's inline `let` in `mkBoundEdge`. The
   one-line copy in `cheat_proofs_own_hole` (P2-005a, R6) is a flattening of the file. The
   regenerate-and-check command of Appendix A5, run on A's tree, printed a diff, because a `let`
   needs a `;` the flattening does not add; without the `let` the command works unchanged and
   the check prints nothing. `mkBoundEdge` now repeats `assumptionsVia r b p` as
   `mkEdge` repeats `assumptionsOf r p`, and the dedupe rule has one owner. The proofs take B's
   `mem_assumptionsVia`, `contains_assumptionsVia` and `assumptionsVia_nodup`.
4. From B, fixtures A lacked: `status_honest_fork_inferred` (a requirement with a direct and a
   bound chain to different providers is `inferred`, the plan's rule from the other side),
   `sound_direct_edges_have_no_through` (the default is a statement),
   `unresolved_exact_needs_the_binding` (both directions of `UnresolvedExact`),
   `twoBindings_derivations`, `complete_keeps_both_bindings` and
   `binding_retracted_repo_edge_stays` (option C on chains, the #156 staging and prod example), and
   `noBinds_twoProvisions` (the law's hypothesis holds on Phase 1's own input). B's shape for
   `sound_records_the_binding` (`e.repoKey = chainEdge.repoKey`) replaced A's two repo equations.
5. From B, the explicit list of disagreements with the plan and the stop conditions on the lock,
   the records and the replay kernels, merged into Context and Order of edits.

Cut from B: `status_honest_chain_confirmed` (the self-binding fixture already pins the `confirmed`
direction with a bound chain), `requirement_retracted_repo_edge_goes` (P2-001a's
`extractor_retracted_repo_edge_goes` is the same shape on a direct chain),
`impact_reaches_through_binding` (the same fact as `binding_change_affects_requirer`), and the
appendix of every file's diff (the non-routine proofs and the two spec files are in the Appendix; the
routine two-case proofs follow their routes). Kept from A: `ends` over `provisions`, `mkBoundEdge`
over `mkBound`, `boundB` in chain order, the grouped `derivations` (its order matches `resolve`'s
edges, and `resolve_edges_nodup` becomes one `pairwise_flatMap`), and the `Sound`-using status
fixtures that conclude for every record.

Verification, on the judged tree at `main` c280558 (one Lean build at a time, the host shared with
other sessions): `cd core && lake build` after a clean of `.lake/build` (23 jobs, no warning, no
`sorry`); `lake check` (standard axioms); `lake comparator --paranoid` (all five kernels accept);
`lake exe mitos-gate imports` (0 violations); `lake exe mitos-gate lock --check` (206 → 252
declarations, 20 `-` and 66 `+`, the list under "Lock prediction"); `fact-step` on `main` with
only `Fact.lean` changed; `lake --dir eval/mutants build`; all 42 mutant cases in default mode and
the original six edited ones with `--paranoid`; `cd examples/acme && lake build`; both plugins accepted with
`--paranoid`; the scorer on `eval/fixtures/toy` (868 bytes, identical to `main`'s); the chain-run
`decide` checks and the Usage `impact` example. Not run: the cheat corpus (`mitos-gate cheats`, CI
runs it), `mitos-lint-test`, and `--record` (it would edit the records).

### Tradeoffs accepted
- We accept eight moved `find=` texts with their paired replacements, one rewritten `replace=` copy and one `Refute.lean` line in
  exchange for a status rule that reads the plan's rule directly (`(ends fs r).all (·.id == p.id)`)
  and one shared premise path for edges, status and the unresolved list.
- We accept a default on `Edge.through` in exchange for the `Edge` literals in 16 files outside the
  core building unchanged; `Sound` pins the field, and `sound_direct_edges_have_no_through` pins the
  default, so a resolver that forgets it on a bound record fails a proof.
- We accept `binds (to : Identity)`, which moves `Identity` above `Scope` in `Fact.lean`, in
  exchange for a target typed as an identity and not two strings, and no unrelated lock line.
- We accept six locked lines that change because `Edge.mk` gained a field (`goodEdge` and five
  adequacy statements), with their text unchanged.
- We accept that `derivations_single_provider` is used by no proof, in exchange for keeping the
  Phase 1 agreement of the status rule locked.
- We accept 36 new locked declarations in `Spec.Chains`, 14 of them inputs, in exchange for a
  fixture per statement whose meaning extends to chains.
- We accept that a new `Derivation` constructor with no list in `derivations` still builds.
- We accept a new spec file and one import line outside the row's Owns cell in exchange for one
  topic per file (O6).
- We accept `Affects x x` for a binding in the requirer's own repo (O5), in exchange for no special
  case in `Sound`, `fires` or `Affects`.

### Alternatives considered
- `providers` as every end, deduplicated by a filter over `fs`, with Phase 1's
  `(providers fs r).length == 1`. It keeps the status and unresolved texts, and so eight more
  anchors, but the direct premise then lives in two lists: `same_repo_skipped` would stop breaking
  `resolve_unresolved_exact`, or the filter must compare `Located` values in every refutation's
  `decide`. Rejected.
- The implementation as `(derivations fs).map toEdge`, or one `mkEdge fs r via p` for both rules.
  Shortest proofs, but the enumeration moves into the locked core, six anchors vanish or 14 more
  move, and `Sound` and `Complete` become near-tautologies (P2-001a rejected the same).
- A binding as an edge (two records per chain, no `through`). `Affects` is unchanged, but an edge
  would then not be one derivation, `Sound` needs a second shape, and the repo-level edge between
  requirer and provider that `retract_repo` is about would not exist.
- `FactKind.binds` with no argument and a `Fact.target : Option Identity`. Every plugin literal
  changes, and `none` means "not a binding": meaning only in prose. Rejected.
- `through` inside `RepoKey`. The union view would split a requirement's direct and bound records
  into two repo-level edges. Rejected.
- `Affects.step` generalized to "the provider's or a binding's repo". One constructor, but every
  `.step (e := …) h` term (`Spec/Adequacy.lean`, three `Refute.lean` files) breaks. Rejected.
- The chain fixtures in `Spec/Adequacy.lean`, with the span theorems moved out as P2-001a
  suggested. No import line, but the file takes a third topic and the PR moves unrelated locked
  text. It is O6's fallback.
- Two appended lists in `derivations`, as the D1 sketch wrote. Same set; the grouped form keeps the
  order of `resolve`'s edges and makes `resolve_edges_nodup` one `pairwise_flatMap`.
- `derivations_without_bindings` as a list equality. Stronger, but it copies the direct enumeration
  into a locked statement, so two places list it.

### Open questions and risks
- The mutant runner was killed by the container's memory limit with several cases in one
  invocation. Is one case per invocation acceptable evidence, as here, until #276's V4 is looked at?
- A binding in the requirer's own repo makes `x ∈ impact es x`. Is that the impact the owner wants
  (O5)?
- `binds`'s target is not anchored in source. Should a binding's span cover both identities once a
  real binding extractor exists?
- Does the PR that lands this task file also remove P2-001b from
  `.claude/scripts/plan-tasks.pending`? That file is the owner's path (D7).

### Next implementation step
Step 1: move `Identity` and `FactKind` in `core/Mitos/Core/Fact.lean`, add `binds (to : Identity)`,
build, and show `fact-step`.

## Implementation on current main

- D1 extends the plan's Owns cell to the paired replacements, the regenerated resolver copy and
  the new impact induction case. Those changes preserve the existing mutant expectations.
- D2 extends the Owns cell by one import in `Mitos.Core.Spec`, the lock entry point after the
  plugin surface split. This puts the chain fixtures under the lock.
- The [verifier review](https://github.com/kitimark/mitos/pull/545#issuecomment-7059763924)
  adds a deviation for `gate/lock-meaning-test.sh`. The test landed through #524 after this
  design. Its scratch `isAI` probe restores the chain fixture after substituting its proof,
  and its `eq_of_id` probe checks both updated anchors before rebuilding. Each probe still
  verifies that exactly its intended lock entry changes.
- The lock grows from 203 to 248 declarations. The current format records 19 changed entries and
  45 new ones, including all 36 chain fixture declarations. The source-declaration lock in #524
  accounts for the count difference from the design, which counted the generated
  `Affects.below.through` constructor and used the old auxiliary hash for the `Fact` equality
  instance.
  The fact-only lock check on current main shows the new constructor and two changed
  `FactKind` instances.
- The endpoint summary uses `Bool ⊕ Nat` to stay within the mutant lint's command set. A
  Boolean supplies the result for all IDs, and a natural number supplies the single matching
  ID. The resolver still computes the summary once per requirement.
- The resolver proof uses the current Mathlib no-duplicates lemmas. The GoMod scratch example
  handles the new constructor and reports bindings if one appears.

## Done when
- [ ] all `checks` pass locally at the head except `mitos-lint-test` and the cheat corpus, which
      run in CI (read the `cheat-logs` artifact); one Lean build at a time
- [ ] every run-level fixture under Design holds
- [ ] the PR body lists the lock diff against the prediction (206 → 252, 20 `-`, 66 `+`), says
      `Closes #204`, names D1 and D2 and how each was settled, and says both records changed in
      `core_sha256` only
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)

## Appendix: checked text

The original blocks were built on Lean v4.35.0 against `main` at c280558. The cached resolver,
summary equivalence, row equivalence and binding-scan proof were rebuilt against that base in
the review round, with no `sorry`. The routine two-case proofs are not repeated; their routes are under `statements`.

The review round also filled the routine proof routes in scratch: all 23 core build jobs pass,
and `lake check` plus `lake comparator --paranoid` accept with only the permitted axioms when
run with `--inadvisably-no-sandbox`. The ordinary sandboxed commands cannot start in this
container (`bwrap` cannot create its UID map or `/run/user`); that local result does not replace
the builder's required sandboxed checks. All 42 mutant-file anchors match exactly once after
migration, and A5's exact flattened replacement compiles with the explicit let separators.

### A1. `core/Mitos/Core/Fact.lean`

```diff
--- a/core/Mitos/Core/Fact.lean
+++ b/core/Mitos/Core/Fact.lean
@@ -1,7 +1,7 @@
 namespace Mitos
 
-inductive FactKind where
-  | provides
-  | requires
+structure Identity where
+  kind : String
+  key  : String
   deriving DecidableEq, Repr
 
@@ -13,9 +13,4 @@
   deriving DecidableEq, Repr
 
-structure Identity where
-  kind : String
-  key  : String
-  deriving DecidableEq, Repr
-
 def utf8Len (cs : List Char) : Nat :=
   (cs.map Char.utf8Size).sum
@@ -43,4 +38,10 @@
   ⟨utf8Len pre.toList, utf8Len key.toList⟩
 
+inductive FactKind where
+  | provides
+  | requires
+  | binds (to : Identity)
+  deriving DecidableEq, Repr
+
 structure Fact where
   kind  : FactKind
```

### A2. `core/Mitos/Core/Spec/Derivations.lean`, the whole file

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

def boundB (r b p : Located) : Bool :=
  r.fact.kind == .requires && b.fact.ident == r.fact.ident &&
    b.fact.kind == .binds p.fact.ident && p.fact.kind == .provides && p.fact.ident != r.fact.ident

def Chain.bound (r b p : Located) : Chain :=
  { key := .bound r.id b.id p.id, requirement := r, via := [b], provision := p }

def Chain.through (c : Chain) : List String :=
  c.via.map Located.repo

def derivations (fs : List Located) : List Chain :=
  fs.flatMap fun r => (fs.filter (matchesB r)).map (Chain.direct r) ++
    fs.flatMap fun b => (fs.filter (boundB r b)).map (Chain.bound r b)

theorem mem_derivations {fs : List Located} {c : Chain} :
    c ∈ derivations fs ↔
      (∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p) ∨
        ∃ r ∈ fs, ∃ b ∈ fs, ∃ p ∈ fs, boundB r b p = true ∧ c = Chain.bound r b p := by
  simp only [derivations, List.mem_flatMap, List.mem_append, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨r, hr, ⟨p, ⟨hp, hm⟩, rfl⟩ | ⟨b, hb, p, ⟨hp, hm⟩, rfl⟩⟩
    · exact .inl ⟨r, hr, p, hp, hm, rfl⟩
    · exact .inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩
  · rintro (⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩)
    · exact ⟨r, hr, .inl ⟨p, ⟨hp, hm⟩, rfl⟩⟩
    · exact ⟨r, hr, .inr ⟨b, hb, p, ⟨hp, hm⟩, rfl⟩⟩

theorem derivations_key_ends {fs : List Located} {c : Chain} (h : c ∈ derivations fs) :
    c.key.requiringFactId = c.requirement.id ∧ c.key.providingFactId = c.provision.id := by
  rcases mem_derivations.mp h with ⟨r, -, p, -, -, rfl⟩ | ⟨r, -, b, -, p, -, -, rfl⟩ <;>
    exact ⟨rfl, rfl⟩

theorem derivations_key_inj {fs : List Located} (wf : WellFormed fs) {c d : Chain}
    (hc : c ∈ derivations fs) (hd : d ∈ derivations fs) (h : c.key = d.key) : c = d := by
  rcases mem_derivations.mp hc with ⟨r, hr, p, hp, -, rfl⟩ | ⟨r, hr, b, hb, p, hp, -, rfl⟩ <;>
    rcases mem_derivations.mp hd with ⟨r', hr', p', hp', -, rfl⟩ | ⟨r', hr', b', hb', p', hp', -, rfl⟩
  · obtain ⟨h1, h2⟩ := Derivation.direct.inj h
    rw [wf.eq_of_id hr hr' h1, wf.eq_of_id hp hp' h2]
  · cases h
  · cases h
  · obtain ⟨h1, h2, h3⟩ := Derivation.bound.inj h
    rw [wf.eq_of_id hr hr' h1, wf.eq_of_id hb hb' h2, wf.eq_of_id hp hp' h3]

theorem mem_derivations_retract {a : Assumption} {fs : List Located} {c : Chain} :
    c ∈ derivations (retract a fs) ↔ c ∈ derivations fs ∧ a ∉ c.origins := by
  simp only [mem_derivations, retract, List.mem_filter, bne_iff_ne, ne_eq]
  constructor
  · rintro (⟨r, ⟨hr, hra⟩, p, ⟨hp, hpa⟩, hm, rfl⟩ | ⟨r, ⟨hr, hra⟩, b, ⟨hb, hba⟩, p, ⟨hp, hpa⟩, hm, rfl⟩)
    · refine ⟨.inl ⟨r, hr, p, hp, hm, rfl⟩, ?_⟩
      simp only [Chain.origins, Chain.direct, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or]
      exact ⟨fun h => hra h.symm, fun h => hpa h.symm⟩
    · refine ⟨.inr ⟨r, hr, b, hb, p, hp, hm, rfl⟩, ?_⟩
      simp only [Chain.origins, Chain.bound, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or]
      exact ⟨fun h => hra h.symm, fun h => hba h.symm, fun h => hpa h.symm⟩
  · rintro ⟨⟨r, hr, p, hp, hm, rfl⟩ | ⟨r, hr, b, hb, p, hp, hm, rfl⟩, ha⟩
    · simp only [Chain.origins, Chain.direct, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or] at ha
      exact .inl ⟨r, ⟨hr, fun h => ha.1 h.symm⟩, p, ⟨hp, fun h => ha.2 h.symm⟩, hm, rfl⟩
    · simp only [Chain.origins, Chain.bound, List.cons_append, List.nil_append, List.map_cons,
        List.map_nil, List.mem_cons, List.not_mem_nil, or_false, not_or] at ha
      exact .inr ⟨r, ⟨hr, fun h => ha.1 h.symm⟩, b, ⟨hb, fun h => ha.2.1 h.symm⟩, p,
        ⟨hp, fun h => ha.2.2 h.symm⟩, hm, rfl⟩

def NoBinds (fs : List Located) : Prop := ∀ b ∈ fs, ∀ i, b.fact.kind ≠ .binds i

theorem mem_derivations_of_noBinds {fs : List Located} (hnb : NoBinds fs) {c : Chain} :
    c ∈ derivations fs ↔ ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ c = Chain.direct r p := by
  refine mem_derivations.trans ⟨?_, .inl⟩
  rintro (h | ⟨r, -, b, hb, p, -, hm, -⟩)
  · exact h
  · simp only [boundB, Bool.and_eq_true, beq_iff_eq] at hm
    exact absurd hm.1.1.2 (hnb b hb p.fact.ident)

theorem derivations_single_provider {fs : List Located} (wf : WellFormed fs) (hnb : NoBinds fs)
    {c : Chain} (hc : c ∈ derivations fs) :
    (∀ d ∈ derivations fs, d.requirement.id = c.requirement.id →
        d.provision.id = c.provision.id) ↔
      (fs.filter (matchesB c.requirement)).length = 1 := by
  have hdirect : ∀ {d : Chain}, d ∈ derivations fs ↔
      ∃ r ∈ fs, ∃ p ∈ fs, matchesB r p = true ∧ d = Chain.direct r p :=
    mem_derivations_of_noBinds hnb
  obtain ⟨r, hr, p, hp, hm, rfl⟩ := hdirect.mp hc
  show (∀ d ∈ derivations fs, d.requirement.id = r.id → d.provision.id = p.id) ↔
    (fs.filter (matchesB r)).length = 1
  have hpL : p ∈ fs.filter (matchesB r) := List.mem_filter.mpr ⟨hp, hm⟩
  constructor
  · intro H
    have hall : ∀ q ∈ fs.filter (matchesB r), q = p := by
      intro q hq
      obtain ⟨hq, hqm⟩ := List.mem_filter.mp hq
      exact wf.eq_of_id hq hp
        (H (Chain.direct r q) (hdirect.mpr ⟨r, hr, q, hq, hqm, rfl⟩) rfl)
    have hnd : (fs.filter (matchesB r)).Nodup := by
      unfold WellFormed List.Nodup at wf
      exact (List.Pairwise.of_map (·.id) (fun _ _ h heq => h (congrArg (·.id) heq)) wf).sublist
        List.filter_sublist
    rw [List.eq_replicate_iff.mpr ⟨rfl, hall⟩, List.nodup_replicate] at hnd
    have := List.length_pos_of_mem hpL
    omega
  · intro hlen d hd hid
    obtain ⟨q, hq⟩ := List.length_eq_one_iff.mp hlen
    obtain ⟨r', hr', p', hp', hm', rfl⟩ := hdirect.mp hd
    have hrr : r' = r := wf.eq_of_id hr' hr hid
    subst hrr
    have hp'L : p' ∈ fs.filter (matchesB r') := List.mem_filter.mpr ⟨hp', hm'⟩
    rw [hq, List.mem_singleton] at hp'L hpL
    simp only [Chain.direct, hp'L, hpL]

end Mitos
```

### A3. `core/Mitos/Core/Spec/Chains.lean` (new), the whole file

```lean
import Mitos.Core.Spec.Adequacy

namespace Mitos.Spec.Chains
open Adequacy (req prov twoProvisions provDeclared)

def needDb : Located :=
  { id := 0, repo := "web", rev := "a", path := "app.env", origin := .extractor "env"
    fact := { kind := .requires, ident := { kind := "env", key := "DATABASE_URL" },
              span := ⟨0, 12⟩ } }

def bindDb : Located :=
  { id := 1, repo := "deploy", rev := "c", path := "web.yaml",
    origin := .humanDeclaredOutsideSource "deploy/web.yaml"
    fact := { kind := .binds { kind := "svc", key := "orders-db" },
              ident := { kind := "env", key := "DATABASE_URL" }, span := ⟨0, 12⟩ } }

def provDb : Located :=
  { id := 2, repo := "orders", rev := "d", path := "service.yaml", origin := .extractor "svc"
    fact := { kind := .provides, ident := { kind := "svc", key := "orders-db" }, span := ⟨0, 9⟩ } }

def chain : List Located := [needDb, bindDb, provDb]

theorem wfChain : WellFormed chain := by unfold WellFormed; decide

def chainEdge : Edge :=
  { requiringRepo := "web", providingRepo := "orders", ident := needDb.fact.ident, scope := .runtime,
    key := .bound 0 1 2, through := ["deploy"],
    assumes := [needDb.origin, bindDb.origin, provDb.origin], status := .confirmed }

theorem chain_derivations : derivations chain = [Chain.bound needDb bindDb provDb] := by
  decide

theorem noBinds_twoProvisions : NoBinds twoProvisions := by
  intro b hb i
  simp only [twoProvisions, List.mem_cons, List.not_mem_nil, or_false] at hb
  rcases hb with rfl | rfl | rfl <;> simp [req, prov, provDeclared]

theorem sound_records_the_binding {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R chain).edges,
      e.key = Derivation.bound 0 1 2 ∧ e.through = ["deploy"] ∧ e.repoKey = chainEdge.repoKey := by
  intro e he
  obtain ⟨c, hc, hk, hr, ht⟩ := hs chain wfChain e he
  rw [chain_derivations, List.mem_singleton] at hc
  subst hc
  exact ⟨hk.symm, ht.symm, hr.symm⟩

theorem sound_direct_edges_have_no_through {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R [req, prov]).edges, e.through = [] := by
  intro e he
  obtain ⟨c, hc, -, -, ht⟩ := hs [req, prov] Adequacy.wf e he
  have hd : derivations [req, prov] = [Chain.direct req prov] := by decide
  rw [hd, List.mem_singleton] at hc
  subst hc
  exact ht.symm

theorem unresolved_exact_binding_resolves {R : Resolver} (hu : UnresolvedExact R) :
    0 ∉ (R chain).unresolved := by
  intro h
  obtain ⟨r, -, hid, -, hn⟩ := (hu chain wfChain 0).mp h
  exact hn (Chain.bound needDb bindDb provDb) (by rw [chain_derivations]; simp) hid.symm

theorem unresolved_exact_needs_the_binding {R : Resolver} (hu : UnresolvedExact R) :
    0 ∈ (R [needDb, provDb]).unresolved := by
  refine (hu [needDb, provDb] (by unfold WellFormed; decide) 0).mpr ⟨needDb, by simp, rfl, rfl, ?_⟩
  intro c hc
  have hnil : derivations [needDb, provDb] = [] := by decide
  rw [hnil] at hc
  simp at hc

theorem assumptions_exact_lists_binding {R : Resolver} (ha : AssumptionsExact R) :
    ∀ e ∈ (R chain).edges, e.key = Derivation.bound 0 1 2 →
      ∀ a, a ∈ e.assumes ↔ (a = needDb.origin ∨ a = bindDb.origin ∨ a = provDb.origin) := by
  intro e he hk a
  obtain ⟨h1, h2⟩ := ha chain wfChain e he (Chain.bound needDb bindDb provDb)
    (by rw [chain_derivations]; simp) hk.symm
  have ho : (Chain.bound needDb bindDb provDb).origins =
      [needDb.origin, bindDb.origin, provDb.origin] := rfl
  rw [ho] at h1 h2
  constructor
  · intro h; simpa using h1 a h
  · intro h; exact h2 a (by simpa using h)

def bindAI : Located := { bindDb with origin := .ai "investigator" }

def chainAI : List Located := [needDb, bindAI, provDb]

theorem wfChainAI : WellFormed chainAI := by unfold WellFormed; decide

theorem status_honest_ai_binding_inferred {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R chainAI).edges, e.status = .inferred := by
  intro e he
  have hd : derivations chainAI = [Chain.bound needDb bindAI provDb] := by decide
  obtain ⟨c, hc, hk, -⟩ := hs chainAI wfChainAI e he
  have hc' := hc
  rw [hd, List.mem_singleton] at hc'
  subst hc'
  have hai : bindAI.origin ∈ e.assumes :=
    (ha chainAI wfChainAI e he _ hc hk).2 _ (by simp [Chain.origins, Chain.bound])
  cases hst : e.status with
  | inferred => rfl
  | confirmed =>
    obtain ⟨hnoai, -⟩ := (hh chainAI wfChainAI e he).mp hst
    exact absurd (hnoai _ hai) (by decide)

def bindStaging : Located :=
  { bindDb with id := 3, repo := "staging", origin := .humanDeclaredOutsideSource "staging/web.yaml" }

def twoBindings : List Located := [needDb, bindDb, provDb, bindStaging]

theorem wfTwoBindings : WellFormed twoBindings := by unfold WellFormed; decide

theorem twoBindings_derivations :
    derivations twoBindings =
      [Chain.bound needDb bindDb provDb, Chain.bound needDb bindStaging provDb] := by
  decide

theorem complete_keeps_both_bindings {R : Resolver} (hc : Complete R) :
    (∃ e ∈ (R twoBindings).edges, e.key = Derivation.bound 0 1 2) ∧
      ∃ e ∈ (R twoBindings).edges, e.key = Derivation.bound 0 3 2 := by
  have h := hc twoBindings wfTwoBindings
  rw [twoBindings_derivations] at h
  exact ⟨h (Chain.bound needDb bindDb provDb) (by simp),
    h (Chain.bound needDb bindStaging provDb) (by simp)⟩

theorem binding_retracted_chain_goes {R : Resolver} (hs : Sound R) :
    (R (retract bindDb.origin chain)).edges = [] := by
  have wf' := wellFormed_retract bindDb.origin wfChain
  have hnil : derivations (retract bindDb.origin chain) = [] := by decide
  apply List.eq_nil_iff_forall_not_mem.mpr
  intro e he
  obtain ⟨c, hc, -⟩ := hs _ wf' e he
  rw [hnil] at hc
  simp at hc

theorem binding_retracted_repo_edge_stays {R : Resolver} (hs : Sound R) (hc : Complete R) :
    chainEdge.repoKey ∈
      (R (retract bindStaging.origin twoBindings)).edges.map Edge.repoKey := by
  have wf' := wellFormed_retract bindStaging.origin wfTwoBindings
  have hd : Chain.bound needDb bindDb provDb ∈
      derivations (retract bindStaging.origin twoBindings) := by decide
  obtain ⟨e, he, hk⟩ := hc _ wf' _ hd
  obtain ⟨c, hcm, hck, hcr, -⟩ := hs _ wf' e he
  have := derivations_key_inj wf' hcm hd (hck.trans hk)
  subst this
  exact List.mem_map.mpr ⟨e, he, hcr.symm⟩

def forkBind : Located :=
  { bindDb with id := 2, fact := { bindDb.fact with ident := req.fact.ident } }

def forkProv : Located := { provDb with id := 3 }

def fork : List Located := [req, prov, forkBind, forkProv]

theorem wfFork : WellFormed fork := by unfold WellFormed; decide

theorem fork_derivations :
    derivations fork = [Chain.direct req prov, Chain.bound req forkBind forkProv] := by
  decide

theorem status_honest_fork_inferred {R : Resolver} (hh : StatusHonest R) :
    ∀ e ∈ (R fork).edges, e.requiringFactId = 0 → e.status = .inferred := by
  intro e he hr
  cases hs : e.status with
  | inferred => rfl
  | confirmed =>
    obtain ⟨-, hall⟩ := (hh fork wfFork e he).mp hs
    rw [fork_derivations] at hall
    have h1 := hall (Chain.direct req prov) (by simp) hr.symm
    have h2 := hall (Chain.bound req forkBind forkProv) (by simp) hr.symm
    exact absurd (h1.trans h2.symm) (by decide)

def selfBind : Located :=
  { id := 2, repo := "deploy", rev := "c", path := "web.yaml", origin := .extractor "deploy"
    fact := { kind := .binds req.fact.ident, ident := req.fact.ident, span := ⟨0, 3⟩ } }

def selfBound : List Located := [req, prov, selfBind]

theorem wfSelfBound : WellFormed selfBound := by unfold WellFormed; decide

theorem selfBound_derivations :
    derivations selfBound = [Chain.direct req prov] := by
  decide

theorem status_honest_self_binding_confirmed {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R selfBound).edges, e.status = .confirmed := by
  intro e he
  obtain ⟨c, hc, hk, -⟩ := hs selfBound wfSelfBound e he
  have hc' := hc
  rw [selfBound_derivations, List.mem_singleton] at hc'
  subst hc'
  have hnoAI : ∀ a ∈ (Chain.direct req prov).origins, a.isAI = false := by decide
  refine (hh selfBound wfSelfBound e he).mpr
    ⟨fun a h => hnoAI a ((ha selfBound wfSelfBound e he _ hc hk).1 a h), ?_⟩
  intro d hd _
  rw [selfBound_derivations, List.mem_singleton] at hd
  subst hd
  exact congrArg Derivation.providingFactId hk

theorem binding_change_affects_requirer {I : List Edge → String → List String}
    (hi : ImpactCorrect I) : "web" ∈ I [chainEdge] "deploy" :=
  (hi [chainEdge] "deploy" "web").mpr (Affects.through (e := chainEdge) (by simp) (by decide))

end Mitos.Spec.Chains
```

### A4. The proofs that are not a two-case copy of `main`

`Proofs/Resolve/Basic.lean`:

```lean
theorem summarizeEnds_accepts (ps : List Located) (id : Nat) :
    (summarizeEnds ps).accepts id = ps.all (·.id == id) := by
  cases ps with
  | nil => rfl
  | cons p rest =>
    simp only [summarizeEnds, List.all_cons]
    split
    · rename_i h
      simp only [EndSummary.accepts]
      by_cases he : p.id = id
      · subst id; simp [h]
      · have hn : (p.id == id) = false := by simp [he]
        simp [hn]
    · rename_i h
      simp only [EndSummary.accepts]
      by_cases he : p.id = id
      · subst id; simp_all
      · simp [he]

theorem resolveOne_eq (fs : List Located) (r : Located) :
    resolveOne fs r =
      ((providers fs r).map (mkEdge fs r) ++
        fs.flatMap (fun b => (boundProviders fs r b).map (mkBoundEdge fs r b)),
       if isRequirement r && (ends fs r).isEmpty then [r.id] else []) := by
  simp only [resolveOne, List.flatMap_map, summarizeEnds_accepts]
  rfl

theorem resolve_eq (fs : List Located) :
    resolve fs =
      { edges := fs.flatMap fun r => (providers fs r).map (mkEdge fs r) ++
          fs.flatMap fun b => (boundProviders fs r b).map (mkBoundEdge fs r b)
        unresolved := ((fs.filter isRequirement).filter fun r => (ends fs r).isEmpty).map (·.id) } := by
  simp only [resolve, List.flatMap_map, resolveOne_eq]
  congr 1
  have hflat : ∀ (xs : List Located),
      xs.flatMap (fun r => if isRequirement r && (ends fs r).isEmpty then [r.id] else []) =
        ((xs.filter isRequirement).filter fun r => (ends fs r).isEmpty).map (·.id) := by
    intro xs
    induction xs with
    | nil => rfl
    | cons x xs ih =>
      cases hreq : isRequirement x <;> cases hempty : (ends fs x).isEmpty <;>
        simp only [List.flatMap_cons, List.filter_cons, hreq, hempty, Bool.and_true, Bool.and_false, Bool.false_eq_true, ↓reduceIte,
          List.map_cons, List.cons_append, List.nil_append, ih]
  exact hflat fs
theorem boundProviders_sublist (fs : List Located) (r b : Located) :
    (boundProviders fs r b).Sublist fs := by
  cases h : b.fact.kind <;> simp only [boundProviders, h]
  · exact List.nil_sublist _
  · exact List.nil_sublist _
  · exact List.filter_sublist

theorem mem_boundProviders {fs : List Located} {r b p : Located} :
    p ∈ boundProviders fs r b ↔ p ∈ fs ∧ boundB r b p = true := by
  cases h : b.fact.kind <;> simp [boundProviders, h, boundB]

theorem mem_ends {fs : List Located} {r q : Located} :
    q ∈ ends fs r ↔ q ∈ fs ∧ (matchesB r q = true ∨ ∃ b ∈ fs, boundB r b q = true) := by
  simp only [ends, List.mem_append, List.mem_flatMap, mem_providers, mem_boundProviders]
  constructor
  · rintro (⟨hq, hm⟩ | ⟨b, hb, hq, hm⟩)
    · exact ⟨hq, .inl hm⟩
    · exact ⟨hq, .inr ⟨b, hb, hm⟩⟩
  · rintro ⟨hq, hm | ⟨b, hb, hm⟩⟩
    · exact .inl ⟨hq, hm⟩
    · exact .inr ⟨b, hb, hq, hm⟩

theorem ends_derivations {fs : List Located} (wf : WellFormed fs) {r : Located} (hr : r ∈ fs)
    {P : Located → Prop} :
    (∀ c ∈ derivations fs, c.requirement.id = r.id → P c.provision) ↔ ∀ q ∈ ends fs r, P q := by
  constructor
  · intro H q hq
    obtain ⟨hq, hm | ⟨b, hb, hm⟩⟩ := mem_ends.mp hq
    · exact H (Chain.direct r q) (mem_derivations.mpr (.inl ⟨r, hr, q, hq, hm, rfl⟩)) rfl
    · exact H (Chain.bound r b q) (mem_derivations.mpr (.inr ⟨r, hr, b, hb, q, hq, hm, rfl⟩)) rfl
  · intro H c hc hid
    rcases mem_derivations.mp hc with ⟨r', hr', p, hp, hm, rfl⟩ | ⟨r', hr', b, hb, p, hp, hm, rfl⟩
    · have := wf.eq_of_id hr' hr hid
      subst this
      exact H p (mem_ends.mpr ⟨hp, .inl hm⟩)
    · have := wf.eq_of_id hr' hr hid
      subst this
      exact H p (mem_ends.mpr ⟨hp, .inr ⟨b, hb, hm⟩⟩)
```

`Proofs/Resolve/Edges.lean`:

```lean
theorem no_derivation_iff_no_end {fs : List Located} (wf : WellFormed fs) {r : Located}
    (hr : r ∈ fs) :
    (∀ c ∈ derivations fs, c.requirement.id ≠ r.id) ↔ (ends fs r).isEmpty := by
  have h := ends_derivations (P := fun _ => False) wf hr
  simp only [imp_false] at h
  rw [h, List.isEmpty_iff, List.eq_nil_iff_forall_not_mem]
```

`Proofs/Resolve/Assumptions.lean`:

```lean
theorem statusOf_confirmed {fs : List Located} (wf : WellFormed fs) {r p : Located} (hr : r ∈ fs)
    (assumes : List Assumption) :
    statusOf fs r p assumes = .confirmed ↔
      ((∀ a ∈ assumes, a.isAI = false) ∧
        ∀ c ∈ derivations fs, c.requirement.id = r.id → c.provision.id = p.id) := by
  rw [ends_derivations (P := fun q => q.id = p.id) wf hr]
  simp only [statusOf, Bool.and_eq_true, List.all_eq_true, Bool.not_eq_true', beq_iff_eq]
  split <;> simp_all

theorem resolve_status_honest : Spec.StatusHonest resolve := by
  intro fs wf e he
  rcases mem_edges.mp he with ⟨r, hr, p, -, -, rfl⟩ | ⟨r, hr, b, -, p, -, -, rfl⟩
  · exact statusOf_confirmed wf hr _
  · exact statusOf_confirmed wf hr _
```

`Proofs/Resolve/Nodup.lean`:

```lean
theorem assumptionsVia_nodup (r b p : Located) : (assumptionsVia r b p).Nodup := by
  unfold assumptionsVia
  by_cases h : b.origin ∈ assumptionsOf r p
  · rw [List.insert_of_mem h]; exact assumptionsOf_nodup r p
  · rw [List.insert_of_not_mem h]; exact List.nodup_cons.mpr ⟨h, assumptionsOf_nodup r p⟩

theorem resolve_edges_nodup : Spec.EdgesNodup resolve := by
  intro fs wf
  unfold WellFormed at wf
  have hkeys :
      (resolve fs).edges.map Edge.key =
        fs.flatMap fun r => (providers fs r).map (fun p => Derivation.direct r.id p.id) ++
          fs.flatMap fun b => (boundProviders fs r b).map fun p => Derivation.bound r.id b.id p.id := by
    rw [resolve_eq]
    simp only [List.map_flatMap, List.map_append, List.map_map, Function.comp_def, mkEdge,
      mkBoundEdge]
  have hids : fs.Pairwise (fun a b => a.id ≠ b.id) :=
    List.Pairwise.of_map (·.id) (fun _ _ h => h) wf
  have hsub : ∀ l : List Located, l.Sublist fs → l.Pairwise (fun a b => a.id ≠ b.id) :=
    fun l hl => hids.sublist hl
  have hreq : ∀ r x, x ∈ (providers fs r).map (fun p => Derivation.direct r.id p.id) ++
      fs.flatMap (fun b => (boundProviders fs r b).map fun p => Derivation.bound r.id b.id p.id) →
      x.requiringFactId = r.id := by
    intro r x hx
    simp only [List.mem_append, List.mem_map, List.mem_flatMap] at hx
    rcases hx with ⟨_, _, rfl⟩ | ⟨_, _, _, _, rfl⟩ <;> rfl
  unfold List.Nodup
  rw [hkeys, List.pairwise_flatMap]
  refine ⟨fun r _ => ?_, hids.imp ?_⟩
  · rw [List.pairwise_append, List.pairwise_flatMap]
    refine ⟨?_, ⟨fun b _ => ?_, hids.imp ?_⟩, ?_⟩
    · exact List.Pairwise.map _ (fun _ _ hne heq => hne (Derivation.direct.inj heq).2)
        (hsub _ List.filter_sublist)
    · exact List.Pairwise.map _ (fun _ _ hne heq => hne (Derivation.bound.inj heq).2.2)
        (hsub _ (boundProviders_sublist fs r b))
    · intro b b' hne x hx y hy heq
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
      exact hne (Derivation.bound.inj heq).2.1
    · intro x hx y hy heq
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
      obtain ⟨_, _, hy⟩ := List.mem_flatMap.mp hy
      obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
      cases heq
  · intro a b hne x hx y hy heq
    exact hne (by rw [← hreq _ x hx, ← hreq _ y hy, heq])
```

`resolve_unresolved_nodup` is `main`'s with `rw [resolve_eq]` before its unfolding and
`(ends fs r).isEmpty` in `hempty`. `mem_edges` and `mem_keys` likewise rewrite `resolve_eq` before
expanding the canonical lists; the remaining Challenge proofs keep their stated routes.

`Proofs/Impact.lean`:

```diff
--- a/core/Mitos/Proofs/Impact.lean
+++ b/core/Mitos/Proofs/Impact.lean
@@ -6,6 +6,7 @@
 theorem fires_iff {x : String} {seen : List String} {e : Edge} :
     fires x seen e = true ↔
-      (e.providingRepo = x ∨ e.providingRepo ∈ seen) ∧ e.requiringRepo ∉ seen := by
-  simp [fires]
+      (e.providingRepo = x ∨ e.providingRepo ∈ seen ∨ ∃ b ∈ e.through, b = x ∨ b ∈ seen) ∧
+        e.requiringRepo ∉ seen := by
+  simp [fires, or_assoc]
 
 theorem impactGo_sound (es : List Edge) (x : String) :
@@ -22,13 +23,15 @@
       simp only [List.mem_cons] at hy
       rcases hy with rfl | hy
-      · have hstep : Affects es e.providingRepo e.requiringRepo :=
-          .step (hrest e (List.mem_of_find?_eq_some h))
-        rcases fires_iff.mp (List.find?_some h) with ⟨hd | hd, _⟩
-        · exact hd ▸ hstep
-        · exact .trans (hseen _ hd) hstep
+      · have he := hrest e (List.mem_of_find?_eq_some h)
+        rcases (fires_iff.mp (List.find?_some h)).1 with hd | hd | ⟨b, hb, hd | hd⟩
+        · exact hd ▸ Affects.step he
+        · exact .trans (hseen _ hd) (.step he)
+        · exact hd ▸ Affects.through he hb
+        · exact .trans (hseen _ hd) (.through he hb)
       · exact hseen y hy
 
 def Closed (es : List Edge) (x : String) (out : List String) : Prop :=
-  ∀ e ∈ es, (e.providingRepo = x ∨ e.providingRepo ∈ out) → e.requiringRepo ∈ out
+  ∀ e ∈ es, (e.providingRepo = x ∨ e.providingRepo ∈ out ∨ ∃ b ∈ e.through, b = x ∨ b ∈ out) →
+    e.requiringRepo ∈ out
 
 theorem impactGo_closed (es : List Edge) (x : String) :
@@ -59,5 +62,6 @@
   intro a b hab
   induction hab with
-  | step he => intro ha; exact hc _ he ha
+  | step he => intro ha; exact hc _ he (ha.elim .inl (.inr ∘ .inl))
+  | through he hb => intro ha; exact hc _ he (.inr (.inr ⟨_, hb, ha⟩))
   | trans _ _ ih1 ih2 => intro ha; exact ih2 (.inr (ih1 ha))
 
```

### A5. The regenerated `replace=` line of `cheat_proofs_own_hole`

The edits are in the table under "Mutant migration". To write the generated line after step 3,
run this from the repository root.

```bash
python3 -I -c "
import re
src = open('core/Mitos/Impl/Resolve.lean').read()
new = 'replace=' + re.sub(r'[ \n]+', ' ', src).rstrip(' ').replace(' unresolved :=', ', unresolved :=')
path = 'eval/mutants/cases/cheat_proofs_own_hole/mutant'
lines = open(path).read().split('\n')
lines = [new if l.startswith('replace=import Mitos.Core.Spec namespace') else l for l in lines]
open(path, 'w').write('\n'.join(lines))
"
```

This prints nothing when the copy is current (`own-hole-copy-current`; it also printed nothing on `main`):

```bash
diff <(tr -s ' \n' ' ' < core/Mitos/Impl/Resolve.lean | sed 's/ *$//; s/ unresolved :=/, unresolved :=/'; echo) \
     <(grep '^replace=import Mitos.Core.Spec namespace' eval/mutants/cases/cheat_proofs_own_hole/mutant | sed 's/^replace=//')
```


To compile A5's exact flattened payload, in scratch only:

```bash
sed -n 's/^replace=import Mitos.Core.Spec namespace/import Mitos.Core.Spec namespace/p' \
  eval/mutants/cases/cheat_proofs_own_hole/mutant > <scratch>/OwnHole.lean
(cd core && lake env lean <scratch>/OwnHole.lean)
```
