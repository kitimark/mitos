# Mitos

*Follow the thread across your codebase.*

Mitos maps how repositories relate (package dependencies, API calls, deployment wiring) as a
graph in which every edge carries its evidence and the assumptions it rests on. The trusted core
is written in Lean 4, and extractors, including ones AI agents write for your own conventions,
are accepted only with machine-checked proofs of Mitos-owned obligations.

**Status:** Phase 0 complete (`plan/phase-0.md`); Phase 1, the trusted resolver, in progress (`plan/phase-1.md`).

| Path | What it is |
|---|---|
| `core/` | trusted core (Lean, `Init`/`Std` only): facts, the line layer, extractor obligations |
| `gate/` | `mitos-gate`: lint, import rule, `statements.lock`, the acceptance pipeline |
| `examples/acme/` | an example user workspace: a reviewed model and an agent-written plugin |
| `eval/cheats/` | cheat corpus the gate must reject |
| `docs/process.md` | how work is done, verified and observed |
| `plan/`, `tasks/`, `ops/` | phase plans, task files, run logs |
| `reports/`, `research_notes/` | the research behind the design |

Quick start: see `docs/process.md`, section 6.
