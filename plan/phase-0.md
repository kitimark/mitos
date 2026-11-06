# Phase 0: foundations and red team

**Exit criteria:** every known cheat is rejected; a clean toy plugin is accepted end to end.

**Status: exit criteria met** on Lean v4.35.0, locally. CI runs the same checks on every push.

| # | Task | Status |
|---|---|---|
| P0-001 | Pin the toolchain (`lean-toolchain`: v4.35.0) | done |
| P0-002 | Lake layout: `core/` (trusted, Std only), root package with `gate/` | done |
| P0-003 | Core types: `Fact`, `Identity`, `Span`, `Extractor`, `Model` | done |
| P0-004 | Line layer `Mitos.lines` with proven anchoring (`Mitos.mem_lines`) | done |
| P0-005 | Obligations `Anchored`, `SoundWrt`, `CompleteWrt` | done |
| P0-006 | `statements.lock` (SHA-256 of compiled types and definition values) + `--check` | done |
| P0-007 | Import rule for `core/` | done |
| P0-008 | Gate 1 lint | done |
| P0-009 | `mitos-gate accept`: gates 0–5 via generated Challenge + `lake comparator` | done |
| P0-010 | Example workspace `examples/acme` with a reviewed model, `models.lock`, toy plugin | done |
| P0-011 | Cheat corpus (13 cases) and runner | done |
| P0-012 | CI workflow, CODEOWNERS, `spec-approved` label check | done (not yet run on GitHub) |
| P0-013 | Process doc, task template, run-log schema | done |
| P0-014 | Scorer and PR scorecard comment on the fixture | moved to Phase 1 (needs the resolver) |
| P0-015 | Nightly scheduled job | moved to Phase 1 (nothing nightly-only yet) |

## Results

Cheat corpus, full gate and comparator alone (lint skipped):

| Case | Full gate | Comparator alone |
|---|---|---|
| sorry, admit, fake_axiom, native_decide | rejected at 1 | rejected at 4 (axioms) |
| partial_extractor | rejected at 1 | rejected at 4 |
| local_notation | rejected at 1 | rejected at 3 (statements) |
| weakened_statement, swapped_model | rejected at 3 | rejected at 3 |
| env_hack (`debug.skipKernelTC` + `addDecl`) | rejected at 1 | rejected at 5 (kernel replay) |
| model_tamper | rejected at 0 (`models.lock`) | rejected at 0 |
| implemented_by, extern, eval_command | rejected at 1 | **accepted**: only the lint stops these |

Honest toy plugin with `--paranoid`: accepted in about 32 s (5 independent kernels).

## Carried into Phase 1

- Checked UTF-8 byte spans in place of character offsets.
- Gate 6 (model adequacy: examples, vacuity, mutation, counterexample search).
- Statement mutation testing for the core's own theorems.
- Scorer, PR scorecard comment, nightly job, next-toolchain canary.
- Turn on branch protection with code-owner review and create the `spec-approved` label.
