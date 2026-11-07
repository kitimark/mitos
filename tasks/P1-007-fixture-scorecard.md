# tasks/P1-007-fixture-scorecard.md

phase: 1
goal: The scorer prints precision and recall per edge type for the fixture against hand labels,
  and CI posts it on PRs (Phase 1 exit criterion 4).
statement: none (tooling task)
touches: eval/fixtures/toy/, eval/score/, .github/workflows/ci.yml, docs/process.md,
  plan/phase-1.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, gate/, eval/cheats/, examples/acme/
checks: build, imports, lock, core lake check, comparator --paranoid, acme build, accept-toy,
  cheats, scorer on the fixture, actionlint
budget: 15 iterations · 2h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- `docs/process.md`, "Scorecard": graph quality is precision and recall per edge type and trust
  level. Phase 0 moved the scorer here because it needs the resolver (P0-014).
- No spec change: everything is outside `core/`, so there is no spec PR.

## Design

**Fixture.** `eval/fixtures/toy/repos/<repo>/…`: six small repos checked in as plain
directories. `eval/` because the fixture is evaluation data, like the cheat corpus; not
`examples/`, which is a workspace the gate judges. A `.gitattributes` (`* -text`) keeps the bytes
exact, so the CRLF file stays CRLF on every checkout.

| Repo | Content | Exercises |
|---|---|---|
| app | requires `left-pad`, `ui-kit`, `naïve-date`, `analytics-sdk` | non-ASCII key (byte spans), an external requirement that stays unresolved |
| ui-kit | provides `ui-kit`, requires `left-pad` | a provider that also requires |
| lib-pad, pad-fork | both provide `left-pad` | two providers: `inferred` edges, one of them wrong |
| date-lib | provides `naïve-date` | `confirmed` edges |
| web | `deps.toy` with CRLF line endings requires `ui-kit`; `src/main.toy` requires `naïve-date` | a file the toy convention reads wrongly (key `ui-kit\r`): a miss |

The two imperfect cases are there on purpose: a fixture where every number is 1.00 cannot show
that the scorer measures anything. They mark the difference the scorecard exists to measure.
The proofs say the extractor agrees with its model and the resolver with its spec; only labels
say whether the model agrees with what a reader of the repos sees.

**Provisions.** The only accepted plugin (`ToyRequire`) emits requirements, and nothing provides
toy packages. A provision is therefore a human declaration (`Assumption.declaration`), written
in the providing repo as a `PROVIDES` file with lines `provide <name>`. A toy `provide` plugin
was considered and rejected: it needs a new reviewed model, so a `models.lock` change with
`spec-approved`, for no gain in what this task measures. The scorer re-checks every fact's span
against its file (`Span.text … = some key`) and stops on one that is not anchored, so the
unproved declaration reader cannot cite the wrong bytes unnoticed.

**Hand labels.** `labels.tsv`, one repo-level edge per line, five tab-separated fields:
requiring repo, providing repo, identity kind, identity key, scope. `#` lines are comments, and
the comments record the judgements behind the labels. Repo level because that is what a person
can label by reading the repos; fact-level labels would mean writing byte spans by hand. Tabs
because a key may contain a space. Labels carry no trust level: status is the resolver's claim
about an edge, not a fact about the world, so it is scored, not labelled.

**Scoring.** An edge type is `kind/scope` (today only `toy/runtime`: the toy plugin is the only
extractor and every fact it emits is `runtime`). Fact-level edges collapse to repo level; a
repo-level edge is `inferred` when any edge under it is. Per edge type: predicted, labelled, TP,
FP, FN, precision, recall. Per edge type and trust level: predicted, TP, FP, precision, which is
the calibration check behind the tripwire "precision of checked edges below 1.0". Then the false
positives, the misses and the unresolved requirements with their byte spans, so a number can be
traced to a file.

**Runtime.** Lean, as a small Lake package `eval/score/` (`lean_exe mitos-score`) that requires
the example workspace, so it runs the accepted plugin and `Mitos.Impl.resolve` as compiled code,
with no second language. It is outside the root package so `lakefile.toml` and the trusted build
are unchanged. Lake writes `eval/score/lean-toolchain` on the first build; it is checked in and
equal to the root pin, like `examples/acme/lean-toolchain`. The scorer exits 1 on an unanchored
fact or a malformed label line, 2 on bad usage, 0 otherwise: the numbers never fail CI, a broken
scorer does.

**CI.** The `gate` job builds and runs the scorer after the example workspace, prints the
scorecard to the log and the job summary, and uploads it as the `scorecard` artifact. A separate
job, `scorecard-comment`, needs `gate`, runs only on `pull_request` events from this repository,
and is the only job with `pull-requests: write`. It runs no code from the PR: it downloads the
artifact and posts it as one comment marked `<!-- mitos-scorecard -->`, updating that comment on
later runs instead of adding one per push. A fork's token is read-only, so fork PRs keep the
scorecard in the job summary only.

**Not in this task.** The scorecard diff against `main` and the nightly scorecard; trust-level
calibration beyond precision per status; more fixtures and edge types, which arrive with real
extractors (npm `dependencies` versus `devDependencies` give the first `dev` edges).

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms (no Lean in `core/` changed)
- [x] the scorer prints precision and recall per edge type for the fixture
- [ ] CI posts the scorecard on the PR (needs the `.github/` change merged by the owner to run
      on other PRs; it runs on this PR's own head)
- [x] run-log record written (ops/runs/)
