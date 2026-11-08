# How Mitos is built: loops, checks and observation

This document is how work on Mitos is planned, done, checked and observed. It applies to people
and to AI agents alike. One rule sits under everything else:

> **People review statements. Machines check proofs. Metrics decide when a phase is done.**

Agents are good at proving statements someone else fixed and bad at writing the right
statements (see `reports/Lean first Mitos architecture.md`). So agents write code and proofs;
people approve what those proofs mean.

## 1. Five loops

```
┌─ L4 Phase loop (weeks) ───────────── owner ─────────────────────────────┐
│  plan phase → run tasks → exit criteria met? → retrospective → re-plan  │
│ ┌─ L3 Nightly loop (daily) ───────── scheduled ───────────────────────┐ │
│ │  full eval · differential tests · theorem mutation · red team ·     │ │
│ │  next-toolchain canary → scorecard                                  │ │
│ │ ┌─ L2 Integration loop (per PR) ── CI + owner on trusted paths ───┐ │ │
│ │ │  build · imports · statement lock · label check · accept toy ·  │ │ │
│ │ │  cheat corpus → merge                                           │ │ │
│ │ │ ┌─ L1 Task loop (hours) ──────── one agent, one task ─────────┐ │ │ │
│ │ │ │  read task → implement + prove → local checks → open PR     │ │ │ │
│ │ │ │ ┌─ L0 Inner loop (seconds) ──── agent + Lean ─────────────┐ │ │ │ │
│ │ │ │ │  edit → goal state / errors → fix → repeat              │ │ │ │ │
│ │ │ │ └─────────────────────────────────────────────────────────┘ │ │ │ │
│ │ │ └─────────────────────────────────────────────────────────────┘ │ │ │
│ │ └─────────────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

| Loop | Speed | Driven by | Done when |
|---|---|---|---|
| L0 Inner | seconds | builder agent with lean-lsp-mcp | Lean reports no errors and no `sorry` |
| L1 Task | hours | one builder agent | local checks pass, within the task budget |
| L2 Integration | per PR | CI, plus the owner on trusted paths | all required checks green, reviews done |
| L3 Nightly | daily | scheduled job | scorecard shows no regression and no tripwire |
| L4 Phase | weeks | owner | the phase's exit criteria are met on the scorecard |

## 2. How to work

### Two PRs per feature: statements first

```
 Spec PR  (small, owner-reviewed)            Impl PR  (large, machine-checked)
 ─────────────────────────────────           ──────────────────────────────────
 • statements as Prop definitions      ──►   • Mitos.Impl.*: the implementation
   in Mitos.Core.Spec                        • Mitos.Proofs.*: theorems whose
 • adequacy theorems: wrong                    statements match the Challenge
   implementations fail them                 • must NOT change any spec file
 • core/Challenge/*: the exact theorems      • owner skims; Lean and the
   the implementation must prove               comparator check
 • regenerated statements.lock
 • task files with budgets
```

How the pieces fit:

- **Statements are definitions, not theorems with `sorry`.** `Mitos.Spec.Sound : Resolver → Prop`
  says what any resolver must satisfy. The spec PR merges with no `sorry` anywhere on `main`.
- **Adequacy theorems** (`Mitos.Core.Spec.Adequacy`) prove that obviously wrong implementations
  fail each statement. If a later edit weakens a statement, one of them stops proving.
- **The Challenge** (`core/Challenge/*.lean`) names the definitions the implementation must
  provide and states each theorem it must prove, with `sorry` holes. It is not a default build
  target, so `lake check` never sees its `sorry`s.
- **The implementation** lives in `Mitos.Impl.*` and `Mitos.Proofs.*`, outside the locked
  namespace, so an impl PR does not touch `statements.lock`. CI runs `lake comparator` in
  `core/` to check the proofs state exactly what the Challenge states.

A spec PR changes `statements.lock`, a `models.lock`, `core/Challenge/`, `core/comparator.json`
or the locked spec's sources (`core/Mitos/Core.lean`, `core/Mitos/Core/`), and therefore needs
the `spec-approved` label from the owner. CI fails any PR that touches one of them without that label;
CI cannot tell a spec PR from an impl PR, so keeping spec changes out of impl PRs is a review rule.
A file moved out of one of these paths counts as a change to it, and so does a path with non-ASCII
characters.

### The task file

Every unit of work is a file in `tasks/`, written from `tasks/TEMPLATE.md`:

```markdown
# tasks/P1-007-resolve-total.md
phase: 1
goal: Every requirement becomes an edge or appears in `unresolved`.
statement: Mitos.resolve_total            # already in statements.lock
touches: core/Mitos/Core/Resolve.lean, core/Mitos/Core/Proofs/Total.lean
must_not_touch: statements.lock, gate/, eval/, models
checks: build, imports, lock, accept-toy, cheats
budget: 40 iterations · 2h wall · 1.5M tokens
```

### Roles

| Role | Who | May write | May not write |
|---|---|---|---|
| Owner | person | statements, models, lock files, phase plans; merges trusted paths | — |
| Orchestrator | agent, the session the owner talks to | task choice, agent briefs, merges of verified PRs, catch-ups on GitHub (§4) | any repository file, which it hands to other agents |
| Planner | agent | task files; draft statements, submitted as a spec PR | proofs, gate, eval |
| Builder | agent (a few in parallel) | code and proofs inside the task's `touches` | statements, lock files, `gate/`, `eval/`, models |
| Red team | agent | new cases in `eval/cheats/`, counterexamples | anything merged into trusted code |
| Verifier | agent that did not write the PR, on another model, plus an `opus` one on a trust-critical PR | a pass or fail verdict on one PR head | the code it checks |
| Evaluator | CI and nightly job | scorecards, logs | — |
| Reviewer | agent, advisory only | PR comments, on code with comments stripped | approvals |

Agents pick tasks, open PRs and merge implementation PRs on their own once CI is green on the
PR's head and a verifier has passed its change. A wording-only change needs no verifier. A rebase that leaves the
`git patch-id --verbatim` unchanged keeps that verdict. Which agent does what, on which model and effort, and what
stays with the owner (spec approval, trust infrastructure, plans) are listed in
`.claude/skills/kitimark-mode/SKILL.md`, which `CLAUDE.md` loads in every session.

`CODEOWNERS` marks the trusted paths, so GitHub asks the owner to review any PR touching them.
While the owner is the only person on the repository, "Require review from Code Owners" stays
off: PRs opened by agents appear under the owner's account, and GitHub never lets an author
approve their own PR. The `spec-approved` label is the owner's sign-off on spec changes, and CI
enforces it. `main` is protected: changes arrive by pull request with the `gate` check green.

### Rules for the inner loops (L0, L1)

- **Budget.** Each task has an iteration, wall-clock and token budget. When it runs out, the
  agent writes a stuck report (goal state, what it tried, best hypothesis) and stops. A `sorry`
  never reaches `main`.
- **Escalation ladder.** Hint (a lemma or an approach) → automation (`grind`, `decide`, hammer)
  → stronger model → pair with a person → split the task → revisit the statement.
- **Counterexample exit.** If the agent finds a counterexample to a statement (checked with
  `decide` or Plausible), it stops and opens a spec issue with it. That is a success: it found a
  bug in a statement or a model. Rewriting the statement itself is never allowed.
- **Parallelism.** At most about three builders at once. Tasks that touch `core/` run one at a
  time, because proofs there depend on each other and proof merge conflicts are expensive.

## 3. How to verify

### Lock files pin meaning

| File | Pins | Regenerate with | Changing it needs |
|---|---|---|---|
| `statements.lock` | every declaration in `Mitos.Core.*` (not `Mitos.Impl`/`Mitos.Proofs`): SHA-256 of its type, of its value for definitions, and (`aux=`) of every generated declaration it reaches; generated declarations get no line of their own | `lake exe mitos-gate lock` | `spec-approved` label |
| `<workspace>/models.lock` | the SHA-256 of every human-reviewed model file | `sha256sum Models/*.lean > models.lock` | `spec-approved` label |
| `core/Challenge/`, `core/comparator.json` | the theorems the core implementation must prove | edited by hand in a spec PR | `spec-approved` label |

`statements.lock` is computed from the compiled environment, not from source text, so a
formatting or notation trick cannot hide a change. Definition *values* are locked too, because a
definition such as `Mitos.Anchored` is a statement of meaning. Theorem *proofs* are not locked:
re-proving is fine, changing what is proved is not. (`Expr.hash` is not used: its effective
width is only 32 bits.)

A definition's meaning can live in declarations Lean generates for it: a structurally recursive
`f` compiles to `List.brecOn … f._f`, and a `match`'s patterns live in `f.match_1`. So a line's
`aux=` hashes, in name order, the type (and value, for definitions) of every unlisted `Mitos.Core`
declaration its own type or value references, transitively. The walk stops at declarations that
have their own line and at anything outside `Mitos.Core` (pinned by `lean-toolchain`); it never
enters theorem proofs. CI also requires `spec-approved` for any change under `core/Mitos/Core/`,
which covers what no kernel term references, such as a structure field's default value.

### What runs where

| Check | Command | L1 local | L2 PR | L3 nightly | Blocks merge |
|---|---|---|---|---|---|
| Build core and gate | `lake build` | ✓ | ✓ | ✓ | yes |
| Core imports only `Init`, `Std`, `Mitos.*`; the spec never imports implementations | `lake exe mitos-gate imports` | ✓ | ✓ | ✓ | yes |
| Lock matches the compiled core | `lake exe mitos-gate lock --check` | ✓ | ✓ | ✓ | yes |
| Core: no `sorry`, standard axioms only | `cd core && lake check` | ✓ | ✓ | ✓ | yes |
| Core implementation proves the Challenge | `cd core && lake comparator --paranoid` | ✓ | ✓ | ✓ | yes |
| Spec changes carry `spec-approved` | CI step | | ✓ | | yes |
| Plugin lint (gate 1) | `lake exe mitos-gate lint <file>` | ✓ | ✓ | | yes |
| Model lint allowlist accepts and rejects each command kind | `lake exe mitos-lint-test` | when touching `gate/` | ✓ | | yes |
| Honest plugin accepted, gates 0–5 | `lake exe mitos-gate accept … --paranoid` | ✓ | ✓ | ✓ | yes |
| Cheat corpus rejected | `eval/cheats/run.sh` | when touching `gate/` | ✓ | ✓ | yes |
| Fixture scorecard: precision and recall per edge type against hand labels | `lake --dir eval/score exe mitos-score eval/fixtures/toy` | when touching the resolver, a plugin, the fixture or the scorer | ✓, posted on the PR | | the numbers no; a scorer error yes |
| Full evaluation scorecard | Phase 1 | | | ✓ | — |
| Differential tests against real tools | Phase 2 | | | ✓ | — |
| Mutation testing of our own theorems | Phase 1 | | | ✓ | — |
| Next Lean release-candidate canary (`nightly.yml`, job `canary`) | Phase 1 | | | ✓ | — |

### The acceptance gate

`mitos-gate accept` runs gates 0–5 on one plugin:

| Gate | What it checks | Implemented by |
|---|---|---|
| 0 provenance | toolchain pin matches; every model listed in `models.lock` with a matching hash; fresh judging directory with no `.lake` | `gate/MitosGate/Accept.lean` |
| 1 lint | the plugin parses with the toolchain's own `Init`/`Std` syntax, and its tokens (as Lean's parser produces them) include no `sorry`, `axiom`, `partial`, `unsafe`, `implemented_by`, `extern`, `csimp`, `native_decide`, notation, macros, instances, `#eval`, `debug.*` options, or imports outside `Init`/`Std`/`Mitos.Core`/`Models`. Identifiers are matched by name, so `«sorry»` counts as `sorry`. Imports are checked on the parsed module name, component by component: each component must be made of identifier characters only (no `.`, space or empty component, though a keyword such as `«import»` passes), so `Models.«..».Mitos.Impl` is rejected (`eval/cheats/plugin_dotdot_import`, `model_dotdot_import`), and the name must start with the components of an allowed root. The header may not be `module` or `prelude`, and an import may not be `public`, `meta` or `all`. No plugin or model needs them, and without `module` the last three do not parse anyway. Every model in the workspace passes the same rules, since a plugin may use what a model defines (`eval/cheats/model_implemented_by`). On top, a model may contain only allowlisted commands, so it declares no syntax by construction and `Init`/`Std` syntax is all the plugin's syntax. The allowed top-level commands are a module doc, `namespace`, `section` with or without a name (but not `public`, `noncomputable`, `meta` or `@[expose]`), `end`, `open`, and declarations. The allowed declarations are `def`, `theorem`, `abbrev`, `example`, `structure` and `inductive`, with no modifier but a doc comment and attributes. The only allowed attribute is `simp`, wherever it appears. `instance`, `class`, `axiom` and `opaque` are left out because they change instance search or add unproved constants. `private`, `protected`, `noncomputable`, `unsafe`, `partial`, `nonrec` and `meta` are left out because a reviewed model needs none of them. `deriving` and computed fields are left out because they generate instances or replace compiled code. Every other attribute is left out because attributes are how a `def` becomes a parser, macro, elaborator or compiler override. `set_option`, `variable`, `attribute`, `mutual`, `… in` and `#`-commands are left out too. Any other command is a violation, reported with its file, line and kind. The lint does not also compare the parser's token table before and after the model, because the lint parses without elaborating, so the table never changes during the run. A real before-and-after comparison would have to elaborate the model or load its compiled `.olean`, which runs the model's code. That check would cost more than the allowlist, and it would be less robust. The parse also never turns on the scoped notation an `open` would activate, so after `open Int` the lint reads `-[1+1]` differently from Lean. On Lean v4.35.0 no `Init`/`Std` scoped token can start a string or comment, so this hides nothing and can only cause false rejections. That was checked on v4.35.0 and must be rechecked on each toolchain bump. A file where Lean's parser stops early, as at a mid-file `import`, is rejected, so nothing after the stop goes unchecked. `lake exe mitos-lint-test` checks each allowed and rejected kind, for models and for plugin imports | `gate/MitosGate/Lint.lean`, `gate/LintTest.lean` |
| 2 sandbox | the plugin is built inside bubblewrap; it can write only to the judging project's `.lake` | `lake comparator` |
| 3 statements | the plugin's theorems and its extractor definition match the generated Challenge, compared as kernel terms | `lake comparator` |
| 4 axioms | only `propext`, `Quot.sound`, `Classical.choice` | `lake comparator` |
| 5 kernels | with `--paranoid`: lean4lean, nanoda, con-leche, con-ron and the paranoid Lean kernel also accept | `lake comparator --paranoid` |

The Challenge module is generated by the gate from Mitos-owned obligations
(`Mitos.Anchored`, `Mitos.SoundWrt`, `Mitos.CompleteWrt`); the agent never writes it. The
judging directory is self-contained: the trusted core is copied in as source, because the sandbox
can only read the project and write to its `.lake`.
`--model` must name a declaration (`def` or `abbrev`), not an `export` alias; an alias fails at gate 2
("Unknown identifier"). No gate enforces the rule yet: the gate 0 check is a pending follow-up in
`tasks/gate3-qualified-challenge.md`.

Gates 6 (model adequacy), 7 (corpus and differential runs) and 8 (human review) come in
Phases 1–3.

### The cheat corpus

`eval/cheats/<case>/` holds a plugin (and optionally a model) that tries to cheat, plus an
`expect` file:

```
full=1                      # the gate must reject at this gate
comparator_only=reject@4    # with lint skipped, the later gates must still reject (or "accept")
why=Leaves the completeness proof as `sorry`.
```

A case whose `expect` also has the line `model_approved=yes` stands for models the owner approved:
the runner re-pins `models.lock` to every model under the workspace's `Models/`, recursively as
gate 0 walks it, so gate 0 passes and the later gates
are what is tested.

`eval/cheats/run.sh` runs every case twice: through the full gate, and with `--skip-lint`, to
record what the later gates catch on their own. Every full run must reject at the expected gate.
The comparator-only expectation is checked as well, so a change in what each layer catches is
noticed and recorded on purpose.

Ten cases are expected to pass the comparator on its own: `implemented_by`, `extern`,
`eval_command`, the smuggling variants `char_literal_smuggle`, `raw_string_smuggle` and
`escaped_attr_smuggle`, the model cases `model_notation` and `model_implemented_by`, and the
escaped imports `plugin_dotdot_import` and `model_dotdot_import`. The kernel cannot see what code *runs*, only what is *proved*. Those cases are
why the lint is a required gate rather than a nicety.

## 4. How to observe

### Run log (one record per agent task attempt)

Stored as NDJSON in `ops/runs/` (or as CI artifacts); schema in `ops/runs/README.md`:

```json
{"task":"P1-007","role":"builder","model":"…","attempt":2,"iterations":31,"wall_min":74,
 "tokens":1180000,"errors_by_kind":{"type_mismatch":12,"unsolved_goals":15},
 "lint_hits":["sorry"],"escalations":["hint","grind"],"outcome":"merged"}
```

`outcome` is one of `in-review`, `merged`, `stuck`, `counterexample`, `abandoned`.

### Scorecard (one per nightly run, from Phase 1)

- **Graph quality:** precision and recall per edge type and trust level, trust-level
  calibration, impact recall on historical co-changes.
- **Assurance:** cheat corpus result, theorem mutation kill rate, trusted lines of code, axioms
  used, lock entries.
- **Cost:** proof-to-code ratio, task success rate, median iterations, tokens per merged task,
  hours per toolchain bump.
- **Bug ledger:** for each bug, whether proofs, differential tests, evaluation or users found it.

PRs get the fixture scorecard (`eval/fixtures/toy`, hand labels in its `labels.tsv`) as a
comment from the `scorecard-comment` job in `ci.yml`. The diff against `main`'s scorecard comes
with the nightly scorecard.

### Owner catch-up on GitHub

The owner catches up on GitHub, not in a chat session:

- **The Owner dashboard**, a pinned issue. The orchestrator rewrites its body when something
  changes for the owner: what needs the owner, each open PR with its head, `gate` result and
  verdict, the PRs merged lately with their verdicts, what comes next, and the open follow-ups.
- **Assigned to the owner** means it needs the owner (`is:open assignee:kitimark`). Agents act
  through the owner's account, and GitHub does not notify a user of their own actions, so
  `.github/workflows/owner-ping.yml` posts an @mention as `github-actions[bot]` on each such
  assignment. Never label a PR to show the owner its state, because any label change re-runs
  the full `gate`.
- **One milestone per phase, one issue per open plan row.** `plan/phase-N.md` says what is to be
  done and in which order, and its Issue column links each row's issue. Status lives in the
  issue and its PRs. The labels `follow-up` and `process` mark work found along the way.

The rules are in `.claude/skills/kitimark-mode/SKILL.md`, "Catching the user up".

### Tripwires: stop and fix first

| Signal | Meaning | Action |
|---|---|---|
| Precision of `checked` edges below 1.0 | a model or a proven statement is wrong | stop other work; spec issue to the owner |
| A cheat passes the full gate | the gate is broken | stop accepting plugins until fixed |
| A mutation of our code still passes a theorem | that theorem is too weak | spec issue: strengthen it |
| Trusted code grows with no spec PR | scope creep in what must be trusted | block until justified |
| Agent lint hits spike | a task is too hard or a statement is wrong | review the task, not just the agent |
| Proof checking time grows week over week | proofs are getting slow | refactoring task |
| The next-toolchain canary fails | an upgrade is coming | schedule the bump early |

### Phase review (L4)

At the end of each phase the owner reviews the scorecard trend and the run logs: exit criteria
(met or not, by the numbers), cost per task, where bugs were found, then re-plans the next phase.

## 5. Mapping to tools

| Need | Tool |
|---|---|
| L0 | Claude Code with lean-lsp-mcp |
| L1 parallel builders | separate Claude Code sessions or worktree-isolated agents, one task each |
| L2 | GitHub Actions (`.github/workflows/ci.yml`), protected `main`, CODEOWNERS, the `spec-approved` label |
| L2 CI fixes | the agent that owns the PR, watching it and fixing failures inside the task's `touches` |
| L3 | `.github/workflows/nightly.yml` (full checks, `--paranoid` comparator, next-toolchain canary), plus a scheduled task posting the scorecard |
| L4 | the scorecard trend plus a short retrospective in `plan/` |
| Owner catch-up | the pinned Owner dashboard issue, issues and PRs assigned to the owner, one milestone per phase, `.github/workflows/owner-ping.yml` |
| Waiting on GitHub | the orchestrator's Monitor running `.claude/scripts/watch-github.sh`, which prints one line per change to an open PR, `main` or the owner's comments and nothing otherwise |

## 6. Local setup

```bash
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
```

```bash
sudo apt-get install -y bubblewrap
```

```bash
lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check
```

```bash
lake exe mitos-gate accept --workspace examples/acme --plugin ToyRequire --model Models.ToyRequire.model --paranoid
```

```bash
eval/cheats/run.sh
```

## 7. Findings that changed the design during Phase 0

- `lake comparator` sandboxes with **bubblewrap**, not landrun as the research report said. On
  Ubuntu 24.04 CI runners, unprivileged user namespaces must be allowed for it.
- The sandbox can only write to the judged project's `.lake`, so path dependencies cannot be
  built inside it. The gate copies the trusted core into the judging directory as source.
- Well-founded recursion blocks `decide`, which model examples rely on. Trusted syntax layers
  such as `Mitos.lines` are written with structural recursion.
- Kernel replay rejects an ill-typed theorem injected with `debug.skipKernelTC`
  (`eval/cheats/env_hack`), confirming that elaboration-time tricks do not survive export.
- Phase 0 spans were character offsets into `String.toList`, wrong for any file with a non-ASCII
  character. Since P1-005 they are UTF-8 byte offsets read over `String.toList` with
  `Char.utf8Size`: `Span.text` is `none` unless both ends sit on character boundaries, and
  bridge theorems tie each span to the bytes of `s.toByteArray` and to valid `String.Pos.Raw`
  positions. On Lean 4.35, `decide` also evaluates `String` and `ByteArray` operations on small
  literals; spans stay on `List Char` so proofs stay list algebra.
- Gate 1 first scanned plugin source with a hand-written tokenizer. A char literal `'"'` or a
  raw string `r"\"` desynchronised it from Lean's lexer and hid a following `implemented_by`,
  which the comparator alone accepts. Lint now takes its tokens from Lean's own parser
  (`eval/cheats/char_literal_smuggle`, `raw_string_smuggle`).
- `statements.lock` initially listed every declaration, including those Lean generates for
  each inductive type (`sizeOf_spec`, `ctorIdx`, …). They follow from the locked types, so the
  lock now omits them to keep spec diffs reviewable.
- Omitting generated declarations hid real meaning: the body of `Mitos.lines.go` lives in
  `lines.go._f` and `lines.go.match_1`, so changing it left the lock unchanged, and so did the
  spec-approved check, which looked only at lock and Challenge paths. Each lock line now hashes
  the generated declarations it reaches (`aux=`), and the label check covers `core/Mitos/Core/`.
- Gate 1 first checked models against a hand-written list of syntax-declaring keywords, which
  did not cover every such command, and it ran none of the plugin rules on them. An approved
  model's `@[implemented_by evilRun] def honestRun`, used by a clean plugin, passed gates 0–5
  with `--paranoid` (`eval/cheats/model_implemented_by`). Models now pass every plugin rule and
  a command allowlist, and `gate/LintTest.lean` checks each kind.
- The import rule matched the de-escaped module name as a string, so `Models.«..».Mitos.Impl`
  read as `Models....Mitos.Impl` and passed the `Models.` prefix. A plugin importing the
  reference implementation passed gates 0–5 with `--paranoid`
  (`eval/cheats/plugin_dotdot_import`). Imports are now checked on the parsed name's components,
  each a plain identifier. The core import rule (`mitos-gate imports`) uses the same check.
