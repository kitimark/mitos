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
| P1-013 | Step 4. Claude connector: `land.sh`, which treats `present` on a kept path as nothing to do, wake rules, the `bot-review.sh` cover rule (owner-gated: `.claude/`) | tooling | [#192](https://github.com/kitimark/mitos/issues/192) |
| P1-014 | Step 5. The switch: the push joins P1-020's `apply`, which pushes only the planned PR; the old loop is deleted (owner-gated: `.github/`) | ci | [#193](https://github.com/kitimark/mitos/issues/193) |
| P1-015 | Step 6. Process rules, the rest after P1-021: merge means `land`; the old updater's rules go (owner-gated: `.claude/`, `docs/process.md`, `.cursor/`) | process | [#194](https://github.com/kitimark/mitos/issues/194) |
| P1-016 | Step 7. Grok connector: the relay applies the wake table (owner-gated: `.github/`, `.cursor/`) | tooling | [#195](https://github.com/kitimark/mitos/issues/195) |
| P1-017 | Step 8. Fold `/land`, `/hold`, `land`, the approval and the later-comment rule into the protocol draft; add them and a `behind` flag to the TLA+ model | process | [#196](https://github.com/kitimark/mitos/issues/196) |
| P1-018 | A1. `Land.lean`: the owner's approval (`approves`), a later owner comment (`ownerSpoke`) and the `merge` plan, with statements 15 to 18; `LandCli` reads and prints them, and `Shadow`'s assumed word approves (owner-gated: `gate/`) | gate | [#295](https://github.com/kitimark/mitos/issues/295) |
| P1-019 | A2. The reader: only a typed comment that holds just `/land <commit>` approves, and any later typed owner comment or review post retires it; its statements and the JSON cases (owner-gated: `gate/`) | gate | [#296](https://github.com/kitimark/mitos/issues/296) |
| P1-020 | A3. `land.yml`: `decide`'s outputs, `apply` that only merges the planned PR on the owner's approval, and `report`; `land-apply.sh` and its test (owner-gated: `.github/`, the last kept PR the owner merges by hand) | ci | [#297](https://github.com/kitimark/mitos/issues/297) |
| P1-021 | A4. Rules: the owner lands a kept PR by typing `/land <commit>`, and no agent calls its merge; `land-ready` in `pr-state.sh`; no agent deletes a comment. Closes #270 (owner-gated: `CLAUDE.md`, `.claude/`, `docs/process.md`, `.cursor/`; landed with `/land`) | process | [#298](https://github.com/kitimark/mitos/issues/298) |

Steps 1 and 2 can start now. Steps 3 and 4 follow them. Step 5, the switch, needs steps 0 to 4,
issue [#171](https://github.com/kitimark/mitos/issues/171) must land first, and holder `push`
records must have started ([amendment](https://github.com/kitimark/mitos/issues/178#issuecomment-6832011164),
asked of #172 in round 3). To roll back step 5, revert it, and if step 6 has landed, revert step 6's
rules too. Step 6 follows step 5 at once. Step 7 follows steps 1 and 2 (it reads the one snapshot
and the parser) and is best after step 5. Step 8 follows step 1.

Rows P1-018 to P1-021 are A1 to A4 of the [auto-merge amendment](https://github.com/kitimark/mitos/issues/178#issuecomment-6890739593), which the owner accepted on 15 Nov: the owner's typed `/land <commit>` makes the land workflow merge a PR they keep. They ship before step 5, in order. P1-018 can start now; it needs steps 1 and 2. P1-019 needs P1-018. P1-020 needs P1-018, P1-019, the protection reader of [#245](https://github.com/kitimark/mitos/issues/245) ([#278](https://github.com/kitimark/mitos/pull/278)) and the shadow evidence on #191: every kept PR the owner merged in the window reads `agrees`. P1-021 follows P1-020 at once, after P1-020's real runs. Step 5 then adds its push to P1-020's `apply`. To roll them back, lightest first: `/hold` on one PR; then the owner disables the `land` workflow (`gh workflow disable land.yml`), or merges by hand a one-line PR that sets `LAND_MERGE` off; then revert P1-021 and P1-020. P1-018 and P1-019 stay, because nothing acts on a `merge` plan then. The owner can merge by hand at any time.

These rows are not Phase 1 exit criteria. If the exit criteria are met first, the rows still open
move to the next phase's plan in that plan's PR.
