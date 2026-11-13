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

| # | Task | Kind | Issue |
|---|---|---|---|
| P1-001 | Resolver vocabulary, statements, adequacy theorems, Challenge; spec-PR mechanics; docs for solo-owner review | spec | none, landed in [#1](https://github.com/kitimark/mitos/pull/1) |
| P1-002 | Reference resolver: `Mitos.Impl.resolve`; prove sound, complete, unresolved-exact, total | impl | none, landed in [#2](https://github.com/kitimark/mitos/pull/2) |
| P1-003 | Prove assumptions-exact, status-honest, retract-exact | impl | none, landed in [#2](https://github.com/kitimark/mitos/pull/2) |
| P1-004 | Impact analysis `Mitos.Impl.impact` (worklist reverse reachability); prove impact-correct | impl | none, landed in [#2](https://github.com/kitimark/mitos/pull/2) |
| P1-005 | Checked UTF-8 byte spans in `Span` and the line layer; migrate obligations and the toy plugin | spec, then impl | none, landed in [#7](https://github.com/kitimark/mitos/pull/7) |
| P1-006 | Mutation testing: `eval/mutants/` + runner; each mutant must break a theorem | tooling | [#30](https://github.com/kitimark/mitos/issues/30) |
| P1-007 | Fixture repos + hand labels; scorer; PR scorecard comment | tooling | none, landed in [#18](https://github.com/kitimark/mitos/pull/18) |
| P1-008 | Nightly scheduled job; next-toolchain canary | tooling | none, landed in [#5](https://github.com/kitimark/mitos/pull/5) |
| P1-009 | Gate 6 for models: examples, vacuity checks (empty / emit-everything extractors) | gate | none, landed in [#21](https://github.com/kitimark/mitos/pull/21) and [#26](https://github.com/kitimark/mitos/pull/26) |

Each open row has an issue in the [Phase 1 milestone](https://github.com/kitimark/mitos/milestone/1),
and its status lives in that issue and its PRs. Rows that landed before issues were used have
none.

P1-002 and P1-004 can run in parallel; P1-003 follows P1-002 because both edit
`Mitos/Impl/Resolve.lean`. In practice P1-002, P1-003 and P1-004 landed in one implementation PR,
which also added the solution module `Mitos/Proofs/Resolver.lean`; exit criteria 1 and 2 are met
there (`lake comparator --paranoid` accepts; `lake check` passes).

## Land track (#179)

The land / auto-rebase migration. It replaces the updater that rebases every open PR on each move
of `main` with a planner that pushes only the PR that lands next, so rebase churn stops costing CI
runs, paid bot reviews and agent tokens. The design is [#178](https://github.com/kitimark/mitos/issues/178)
and the tracker is [#179](https://github.com/kitimark/mitos/issues/179). Step numbers are the
tracker's.

| # | Task | Kind | Issue |
|---|---|---|---|
| (step 0) | Bind admins on `main`, so a behind PR cannot merge (405) | setting | none, owner setting, done |
| P1-010 | Step 1. `Land.lean` with its proofs; `mitos-gate land` over fixed JSON (owner-gated: `gate/`) | gate | [#189](https://github.com/kitimark/mitos/issues/189) |
| P1-011 | Step 2. Owner-speech parser with its statements; the one snapshot producer (owner-gated: `gate/`) | gate | [#190](https://github.com/kitimark/mitos/issues/190) |
| P1-012 | Step 3. Shadow run: `decide` only prints its plan (owner-gated: `.github/`) | ci | [#191](https://github.com/kitimark/mitos/issues/191) |
| P1-013 | Step 4. Claude connector: `land.sh`, wake rules, the `bot-review.sh` cover rule (owner-gated: `.claude/`) | tooling | [#192](https://github.com/kitimark/mitos/issues/192) |
| P1-014 | Step 5. The switch: `apply` pushes only the planned PR; `report` is added; the old loop is deleted (owner-gated: `.github/`) | ci | [#193](https://github.com/kitimark/mitos/issues/193) |
| P1-015 | Step 6. Process rules: merge means `land`; hand-overs give `/land <commit>` (owner-gated: `.claude/`, `docs/process.md`, `.cursor/`) | process | [#194](https://github.com/kitimark/mitos/issues/194) |
| P1-016 | Step 7. Grok connector: the relay applies the wake table (owner-gated: `.github/`, `.cursor/`) | tooling | [#195](https://github.com/kitimark/mitos/issues/195) |
| P1-017 | Step 8. Fold `/land`, `/hold` and `land` into the protocol draft; add a `behind` flag to the TLA+ model | process | [#196](https://github.com/kitimark/mitos/issues/196) |

Steps 1 and 2 can start now. Steps 3 and 4 follow them. Step 5, the switch, needs steps 0 to 4,
and [PR #149](https://github.com/kitimark/mitos/pull/149) and issue
[#171](https://github.com/kitimark/mitos/issues/171) must land first. To roll back step 5,
revert it. Step 6 follows step 5 at once. Steps 7 and 8 follow step 1.

These rows are not Phase 1 exit criteria. If the exit criteria are met first, the rows still open
move to the next phase's plan in that plan's PR.
