# Phase 1: the trusted resolver

**Goal:** a reference resolver and impact analysis whose properties are proven against
owner-approved statements, plus the measurement loop (scorecard, nightly checks) that every
later phase relies on.

**Exit criteria**

1. `cd core && lake comparator` accepts `Mitos.Proofs.Resolver` against
   `core/Challenge/Resolver.lean`: all eight theorems, standard axioms only, also with
   `--paranoid`.
2. `cd core && lake check` passes: no `sorry` anywhere in the core.
3. Mutation testing: each mutant of the resolver in `eval/mutants/` breaks at least one theorem.
4. The scorer prints precision and recall per edge type for the fixture against hand labels,
   and CI posts it on PRs.
5. The nightly job runs the full checks and a next-toolchain canary.

## Scope decisions

- **One resolution rule in this phase:** a requirement matches a provision of the same
  identity. Each edge therefore has exactly one derivation (its requirement and provision), and
  "retracting an assumption removes exactly the edges that rest on it" is a true theorem
  (`Spec.RetractExact`).
- **Deferred to Phase 2:** multi-step chains (config key → deployment → service → repo). Those
  give an edge several possible derivations, and the single- versus all-derivations decision
  (research report, "One product decision…") has to be made in that phase's spec PR.
- **Status rule:** an edge is `confirmed` only when nothing under it is AI-proposed and its
  requirement has exactly one provider; otherwise `inferred` (`Spec.StatusHonest`).

## Tasks

| # | Task | Kind | Status |
|---|---|---|---|
| P1-001 | Resolver vocabulary, statements, adequacy theorems, Challenge; spec-PR mechanics; docs for solo-owner review | spec | in review |
| P1-002 | Reference resolver: `Mitos.Impl.resolve`; prove sound, complete, unresolved-exact, total | impl | waiting on P1-001 |
| P1-003 | Prove assumptions-exact, status-honest, retract-exact | impl | waiting on P1-002 |
| P1-004 | Impact analysis `Mitos.Impl.impact` (worklist reverse reachability); prove impact-correct | impl | waiting on P1-001 |
| P1-005 | Checked UTF-8 byte spans in `Span` and the line layer; migrate obligations and the toy plugin | spec, then impl | not started |
| P1-006 | Mutation testing: `eval/mutants/` + runner; each mutant must break a theorem | tooling | not started |
| P1-007 | Fixture repos + hand labels; scorer; PR scorecard comment | tooling | not started |
| P1-008 | Nightly scheduled job; next-toolchain canary | tooling | not started |
| P1-009 | Gate 6 for models: examples, vacuity checks (empty / emit-everything extractors) | gate | not started |

P1-002 and P1-004 can run in parallel; P1-003 follows P1-002 because both edit
`Mitos/Impl/Resolve.lean`.
