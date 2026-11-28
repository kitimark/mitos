# Mitos

*Follow the thread across your codebase.*

Mitos maps how repositories relate (package dependencies, API calls, deployment wiring) as a
graph in which every edge carries its evidence and the assumptions it rests on. The trusted core
is written in Lean 4, and extractors, including ones AI agents write for your own conventions,
are accepted only with machine-checked proofs of Mitos-owned obligations.

## Status

As of 28 Nov 2026. The live view is the [milestones](https://github.com/kitimark/mitos/milestones):
each open plan row is an issue in its milestone.

| Track | State | Plan |
|---|---|---|
| Phase 0 and Phase 1 | Complete. | `plan/phase-0.md`, `plan/phase-1.md` |
| Phase 2: chains and the first real extractor | Closing. Every task is merged except P2-011's toolchain bump ([#147](https://github.com/kitimark/mitos/issues/147)): the chain resolver with its proofs, the chain mutants, the go.mod model and plugin, the differential run against `go mod edit -json`, and the nightly scorecard. The nightly has been green since 21 Nov. The milestone stays open for #147, the follow-up issues and the owner's phase review. | `plan/phase-2.md` |
| Phase 3: agent-written extractors on real repos | In planning. The draft plan and its open decisions are in [#610](https://github.com/kitimark/mitos/issues/610), and the plan PR is [#616](https://github.com/kitimark/mitos/pull/616). The scope is not approved yet. | none yet |
| Land: merges on the owner's `/land` | In progress. The land planner, the owner-speech parser, the approval rules and the `land` workflow are merged, and PRs have landed on a typed `/land`. Open: the shadow report ([#191](https://github.com/kitimark/mitos/issues/191)), the workflow's real runs ([#297](https://github.com/kitimark/mitos/issues/297)), the Claude and Grok connectors, the process rules and the protocol draft (P1-013 to P1-017, P1-021). | `plan/land.md` |
| Watch: one Lean waiter for GitHub ([#502](https://github.com/kitimark/mitos/issues/502)) | Started. The design is merged (`tasks/502-watch/`), and the first module, P2-013, is in review ([#618](https://github.com/kitimark/mitos/pull/618)). P2-014 to P2-029 follow. | `plan/phase-2.md` |
| Mathlib adoption | In progress. Mathlib v4.35.0 is pinned in `core/`, and the proofs and the resolver spec may import it. Two files do so now: a resolver proof and the spec's `Graph.lean`. Open: the first spec statement on a Mathlib definition ([#394](https://github.com/kitimark/mitos/issues/394)) and more Mathlib in the spec and proofs ([#595](https://github.com/kitimark/mitos/issues/595)). | Gate architecture milestone |

| Path | What it is |
|---|---|
| `core/` | trusted core (Lean): facts, the line layer, extractor obligations; the plugin surface imports only `Init`/`Std`, and the proofs and the resolver spec may use Mathlib |
| `gate/` | `mitos-gate`: lint, import rule, `statements.lock`, the acceptance pipeline |
| `examples/acme/` | an example user workspace: a reviewed model and an agent-written plugin |
| `eval/cheats/` | cheat corpus the gate must reject |
| `docs/process.md` | how work is done, verified and observed |
| `plan/`, `tasks/`, `ops/` | phase plans, task files, run logs |
| `reports/`, `research_notes/` | the research behind the design |

Quick start: see `docs/process.md`, section 6.
