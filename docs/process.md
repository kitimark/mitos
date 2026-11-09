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
| `<workspace>/models.lock` | the SHA-256 of every human-reviewed model file, examples modules included | `lake exe mitos-gate lock-models --workspace <workspace>` | `spec-approved` label |
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
| Honest plugin accepted, gates 0–6 | `lake exe mitos-gate accept … --paranoid` | ✓ | ✓ | ✓ | yes |
| Cheat corpus rejected | `lake exe mitos-gate cheats` | when touching `gate/` | ✓ | ✓, but `nightly.yml` still runs `eval/cheats/run.sh` until the PR that deletes it | yes |
| Fixture scorecard: precision and recall per edge type against hand labels | `lake --dir eval/score exe mitos-score eval/fixtures/toy` | when touching the resolver, a plugin, the fixture or the scorer | ✓, posted on the PR | | the numbers no; a scorer error yes |
| Full evaluation scorecard | Phase 1 | | | ✓ | — |
| Differential tests against real tools | Phase 2 | | | ✓ | — |
| Mutation testing of our own theorems | Phase 1 | | | ✓ | — |
| Next Lean release-candidate canary (`nightly.yml`, job `canary`) | Phase 1 | | | ✓ | — |

### The acceptance gate

`mitos-gate accept` runs gates 0–6 on one plugin and its model:

| Gate | What it checks | Implemented by |
|---|---|---|
| 0 provenance | toolchain pin matches; the plugin name is a plain identifier and the model a dotted one in `Models` (`Models.X.model`); the models and `models.lock` are read once, and every model is listed in the lock with a matching hash; a lock with a malformed line, a path listed twice or a path that is not a model file is rejected; every later gate and the record use those bytes; fresh judging directory with no `.lake` | `gate/MitosGate/Accept.lean` |
| 1 lint | the plugin parses with the toolchain's own `Init`/`Std` syntax, and its tokens (as Lean's parser produces them) include no `sorry`, `axiom`, `partial`, `unsafe`, `implemented_by`, `extern`, `csimp`, `native_decide`, `include_str`, notation, macros, instances, `#eval`, `debug.*` options, or imports outside `Init`/`Std`/`Mitos.Core`/`Models`. Identifiers are matched by name, so `«sorry»` counts as `sorry`. Imports are checked on the parsed module name, component by component: each component must be made of identifier characters only (no `.`, space or empty component, though a keyword such as `«import»` passes), so `Models.«..».Mitos.Impl` is rejected (`eval/cheats/plugin_dotdot_import`, `model_dotdot_import`), and the name must start with the components of an allowed root. The header may not be `module` or `prelude`, and an import may not be `public`, `meta` or `all`. No plugin or model needs them, and without `module` the last three do not parse anyway. Every model in the workspace passes the same rules, since a plugin may use what a model defines (`eval/cheats/model_implemented_by`). On top, a model may contain only allowlisted commands, so it declares no syntax by construction and `Init`/`Std` syntax is all the plugin's syntax. The allowed top-level commands are a module doc, `namespace`, `section` with or without a name (but not `public`, `noncomputable`, `meta` or `@[expose]`), `end`, `open`, and declarations. The allowed declarations are `def`, `theorem`, `abbrev`, `example`, `structure` and `inductive`, with no modifier but a doc comment and attributes. The only allowed attribute is `simp`, wherever it appears. `instance`, `class`, `axiom` and `opaque` are left out because they change instance search or add unproved constants. `private`, `protected`, `noncomputable`, `unsafe`, `partial`, `nonrec` and `meta` are left out because a reviewed model needs none of them. `deriving` and computed fields are left out because they generate instances or replace compiled code. Every other attribute is left out because attributes are how a `def` becomes a parser, macro, elaborator or compiler override. `set_option`, `variable`, `attribute`, `mutual`, `… in` and `#`-commands are left out too. Any other command is a violation, reported with its file, line and kind. The lint does not also compare the parser's token table before and after the model, because the lint parses without elaborating, so the table never changes during the run. A real before-and-after comparison would have to elaborate the model or load its compiled `.olean`, which runs the model's code. That check would cost more than the allowlist, and it would be less robust. The parse also never turns on the scoped notation an `open` would activate, so after `open Int` the lint reads `-[1+1]` differently from Lean. On Lean v4.35.0 no `Init`/`Std` scoped token can start a string or comment, so this hides nothing and can only cause false rejections. That was checked on v4.35.0 and must be rechecked on each toolchain bump. A file where Lean's parser stops early, as at a mid-file `import`, is rejected, so nothing after the stop goes unchecked. `lake exe mitos-lint-test` checks each allowed and rejected kind, for models and for plugin imports | `gate/MitosGate/Lint.lean`, `gate/LintTest.lean` |
| 2 sandbox | the plugin is built inside bubblewrap; it can write only to the judging project's `.lake`. A plugin comparator run that gives no judgment, such as a build error or a `lake` that does not start, fails here; the model's run (gate 6) fails at gate 6 | `lake comparator` |
| 3 statements | the plugin's theorems and its extractor definition match the generated Challenge, compared as kernel terms | `lake comparator` |
| 4 axioms | only `propext`, `Quot.sound`, `Classical.choice` | `lake comparator` |
| 5 kernels | with `--paranoid`: lean4lean, nanoda, con-leche, con-ron and the paranoid Lean kernel also accept | `lake comparator --paranoid` |
| 6 model adequacy | the reviewed examples are in their own module, which imports only `Mitos.Core` and which only the adequacy module imports; the adequacy module imports the model and the examples and proves `Mitos.Model.Adequate`. Judged like gates 2–5 in the same judging directory, before the plugin is built; the plugin's run leaves every build output of gate 6's runs unchanged | `gate/MitosGate/Accept.lean`, `lake comparator` |

The Challenge module is generated by the gate from Mitos-owned obligations
(`Mitos.Anchored`, `Mitos.SoundWrt`, `Mitos.CompleteWrt`); the agent never writes it. The
judging directory is self-contained: the trusted core is copied in as source, because the sandbox
can only read the project and write to its `.lake`.
`--model` must name a declaration (`def` or `abbrev`), not an `export` alias; an alias fails at gate 2
("Unknown identifier"). No gate enforces the rule yet: the gate 0 check is a pending follow-up in
`tasks/gate3-qualified-challenge.md`.
The gate prints each line that holds text from the workspace, from Lean, from the comparator, from
a file or from its arguments through `MitosGate.ciLine` (`gate/MitosGate/Util.lean`, with its
proofs). It writes the text through an allowlist of printable code points (`oneLine`); every other
code point prints as `\u{XXXX}`. So a file name or message stays on one line and cannot forge a
`VERDICT:` line, move the cursor or reorder the text with bidi controls. `ciLine` also escapes
what GitHub's runner reads as a workflow command: a `[` right after `##` anywhere in the line, and
a `:` that would come first after the leading spaces. So the text cannot add an annotation, mask a
word in the log or stop the runner from reading commands. This is proved for the runner's parsers
read as ordinal, which is how they behave under the invariant and en-US cultures. The runner matches
the markers culture-sensitively, so under some other cultures (ja-JP and th-TH shown) it reads more
lines as commands, and a self-hosted runner with such a culture is out of scope. The culture of
GitHub-hosted runners is inferred to be en-US or invariant, not logged. Decoding the escapes gives
back the original text. The `::error` lines of `runlog` and `lock-models` are the gate's own
commands, with the text through `oneLine` and GitHub's escaping. The verdict line is printed as
`Cheats.Verdict.render` makes it, so that `mitos-gate cheats` reads it back; `Verdict.ofGate`
writes its text with `ciLine`, and `Verdict.ofGate_not_startsCommand` and `Verdict.ofGate_no_break`
prove that the whole line starts no command and stays one line. `lake exe mitos-lint-test` runs the
gate on hostile file names, lock lines and arguments, the cheat runner on hostile case names and
options, and the comparator tail on hostile output, and checks every line printed.

Gates 0–5 take the model as given: a plugin passes them by emitting the facts the model says
hold. `Mitos.CompleteWrt` matches an emitted fact by kind and identity only, not by span or by how
often it occurs. For a file with two `require left-pad` lines, one emitted `left-pad` fact covers
both, and gates 0–5 do not ensure that every occurrence the model says holds is emitted. A model
that says nothing holds would admit the extractor that emits nothing, and one that says too much
would admit one that emits too much. So for `--model Models.X.model`, three modules pinned in
`models.lock` take part:

- the model module `Models.X` declares `Models.X.model`, the model gates 3 and 6 judge. Gate 3's
  Challenge imports only this module, so the model must be declared within its reach;
- the examples module `Models.X.Examples` declares `Models.X.model.examples : Mitos.ModelExamples`:
  golden files, each a reviewed file with every fact the model must say holds in it and no other.
  A golden file with no facts says that the file requires nothing;
- the adequacy module `Models.X.Adequacy` imports the other two and proves
  `Models.X.model.adequate : Mitos.Model.Adequate Models.X.model Models.X.model.examples`: on each
  golden file a fact holds exactly when it is listed, every listed fact is anchored, and some golden
  file lists a fact whose kind and identity no fact of another golden file has.

**Golden facts and the model share no definition outside `Mitos.Core`.** If they did, a mistake in
the shared definition would sit on both sides of "holds exactly when listed" and cancel out. A toy
model whose `fact` read `require left-pad` as *providing* `left-pad`, with its golden facts built by
that `fact`, passed gate 6 while the examples could live in the model module. So gate 6 reads the
headers of gate 0's copy of the models with Lean's own parser and checks that:
- every import's components are plain identifiers, as gate 1 also requires. Lean finds a module's
  file by joining its name's components with `/`, so without this a name such as
  `Models.«..».Mitos.Impl.Resolve` reaches a file outside the locked models, and one such as
  `Models.«X/Examples»` could name the examples module's file under another name
  (`model_dotdot_import`, which gate 6 now rejects without lint);
- the examples module imports only `Mitos.Core` (and Lean's `Init`), so no golden fact is built with
  a model definition (`golden_circular_provides`, `golden_circular_devscope`,
  `golden_shared_helper`);
- no model module but the adequacy module imports the examples module, so the model cannot use a
  helper declared there (`golden_helper_in_examples`);
- the adequacy module imports the model module and the examples module, so it cannot declare a
  model or examples of its own (`golden_adequacy_own_model`, `golden_adequacy_own_examples`).

A first comparator run then judges the examples module on its own against the Challenge's
`examples` hole. So the examples constant is declared there (`golden_decoy_examples`), and a model
module that declares its own examples, as round 1's toy did, makes the adequacy module's build fail
on the duplicate name. The model the adequacy run judges is the one gate 3 judges: gate 3's
Challenge imports only the model module, so a model declared in the examples module, which the
model module cannot reach, fails gate 3's build, which is reported first, and the adequacy module
cannot see a second declaration of the name beside the first (`golden_model_in_examples`, rejected
at gate 2). Write golden facts as literal values, field by field, as the toy's
`Models/ToyRequire/Examples.lean` does.

Gate 6 generates a Challenge (`Challenge/Mitos/ModelAdequacy.lean`, a path no plugin name gives)
with the model and its examples as definition holes and the adequacy theorem as the statement,
every name written from `_root_`. It judges the examples module against the `examples` hole
(`examples.json`), then the adequacy module against the whole Challenge (`adequacy.json`). Gate 0's
checked copy of the models is the only copy the judging directory gets, and gate 1 rejects
`include_str` — the only `Init`/`Std` term syntax that reads a file's contents into a term — so a
model cannot read a plugin-chosen judging-directory file (`../comparator.json`,
`../Plugins/<P>.lean`) at elaboration time, and the hole values are the bytes the lock pins
(`eval/cheats/model_include_str`, `model_include_str_src`). Gates 2–6 share one judging directory
and the comparator judges gate 6 there first, before it builds the plugin, so nothing the plugin's
build writes reaches gate 6. After gate 6's runs and again after the plugin's run, the gate hashes
every build output under the directory's `.lake/build/lib/lean/`, from its own process once the
sandbox has exited. The plugin's run must leave every output of gate 6's runs as it was. Anything
there that is not a regular file fails too, and so does an accepted gate 6 that left no `.olean`
for the model module, since then nothing would be compared. So gates 3 and 6 judge one elaboration
of the model. "Does not rest on lint" covers this double-elaboration check only: a model that runs
code while it elaborates and makes Lake rebuild it for the plugin's run is rejected at gate 6
without lint (`eval/cheats/double_elaboration`). The hash check compares in one direction only — it
checks that the plugin's run left gate 6's outputs unchanged, not what gate 6's runs left for the
plugin's — and file reads at elaboration time are stopped by lint, not by the hash check. Gate 1's
model allowlist, which covers every model file, examples modules included, rejects such code
anyway, and `noncomputable`, so the examples are computable data a reviewer can evaluate. The
verdict still reports gates 2–5 before gate 6. The locked theorems are the vacuity checks. Against
an adequate model:
- the extractor that emits nothing is not complete (`Model.Adequate.empty_not_complete`);
- the one that emits every listed fact on every file is not sound (`everything_not_sound`);
- one that emits the same facts on every file is not both sound and complete
  (`constant_not_sound_complete`).

More generally (`sound_on_golden`, `complete_on_golden`), a plugin that passes gates 3 and 6 emits
on each golden file only listed facts, and a fact with the kind and identity of each listed one.
Since the golden facts share no definition with the model, each golden file is an exact test of the
model, and of the plugin through it.

What gate 6 does not show:
- whether the golden files are the right ones, or enough of them;
- anything about the model on files that are not golden.

A model whose `Holds` is true exactly on its golden facts, a lookup table, is adequate. Against it,
a lookup-table extractor that knows only the golden files passes every gate. Gate 6 cannot rule
that out. Owner review of `Holds` carries it, and later the mutation and corpus checks (gate 7)
will too. The same holds for a model that is right on its golden files and wrong elsewhere, such as
one that reads only the first lines of a file.

With `--paranoid`, all five kernels replay the model's proof. nanoda overflowed its stack on a
`decide` that compared whole facts built from a non-ASCII file. So the toy model decides its
requirement lines as offsets and characters (`golden_of_requirements`), and its adequacy module
checks each literal golden fact against `fact` with `simp`, leaving `decide` only byte counts. No
proof compares `String`s.

Gates 7 (corpus and differential runs) and 8 (human review) come in later phases.

### The cheat corpus

`eval/cheats/<case>/` holds a plugin (and optionally a model) that tries to cheat, plus an
`expect` file:

```
full=1                      # the gate must reject at this gate
comparator_only=reject@4    # with lint skipped, the later gates must still reject (or "accept")
why=Leaves the completeness proof as `sorry`.
```

`why=` states the attack in the present tense: what the case does and what it would get accepted.
It holds no history, such as when the case was found or which fix closed it.

A case whose `expect` also has the line `model_approved=yes` stands for models the owner approved:
the runner re-pins `models.lock` to every model under the workspace's `Models/`, recursively as
gate 0 walks it, so gate 0 passes and the later gates
are what is tested.

`lake exe mitos-gate cheats` runs every case twice: through the full gate, and with
`--skip-lint`, to record what the later gates catch on their own. Every full run must reject at the
expected gate. The comparator-only expectation is checked as well, so a change in what each layer
catches is noticed and recorded on purpose. Each run is its own `mitos-gate accept` process in a
fresh copy of the workspace, `--jobs N` of them at a time (default 4), each stopped after
`--timeout S` seconds (default 600) and then failed. Naming cases runs only those. A case whose
`expect` has `heavy=yes` needs much memory (`model_include_str_src` peaks at about 13 GB), so its
runs run alone. The logs are `.lake/cheats/<case>.full.log` and `<case>.comparator.log`, with
`timing.tsv` beside them, and CI uploads them as the `cheat-logs` artifact. Every decision the runner
makes is in `gate/MitosGate/Cheats.lean`, with its proofs: the `expect` parser (a key it does not
know, or a key given twice, is an error, except `lock_append`; `full` and `comparator_only` are
required), the reading of the gate's verdict line, the pass rule, the table and the scheduler.
`eval/cheats/run.sh`, the shell runner it replaces, runs one run at a time. Both printed the same
table in every CI run of #84 that compared them, so CI runs only `mitos-gate cheats`. `run.sh`
stays until `nightly.yml` no longer runs it (#103).

A `comparator_only=accept` case may also have one `guards=R` line, such as
`guards=banned:include_str`, naming the lint rule it pins. Each gate-1 violation ends with its
rule's id in brackets (`[banned:include_str]`), and the runner checks that every violation of the
full run has rule R. Gate 1 is the only gate `--skip-lint` skips, so without R the full run would
be ACCEPTED, and a change that drops R turns the corpus red. `lake exe mitos-lint-test` requires
every entry of `Lint.banned` to be guarded by a case or listed in `eval/cheats/unguarded`, and that
list must equal `unguardedBans` in `gate/LintTest.lean`, whose entries must stay banned. Dropping
or renaming a listed ban therefore takes an edit to that file.

A case's `Models/` is copied over the example workspace's, so a case model can import the toy's
examples module. A case with its own model is judged against the example workspace's
`models.lock`, so gate 0 rejects it (`model_tamper`), unless its `expect` has
`model_approved=yes`. Each `lock_append=` line of an `expect` is appended to the case's
`models.lock` (a case keeps no `models.lock` of its own, since CI reads every `models.lock` path as
spec): `lock_duplicate_path` lists the toy model a second time with a wrong hash, and gate 0 rejects
it as `sha256sum --check` would. `empty_extractor`, `emit_everything` and `weakened_adequacy` stand
for a weak model the owner approved by mistake: gates 0–5 accept all three and gate 6 rejects them.
In a full run gate 1 already rejects `emit_everything`, whose unprovable adequacy theorem is
`sorry`. In `nearmiss_scope` the model has the toy model's golden files but reads a commented-out
line as a dev requirement. Near misses, which excluded only one exact fact, let it pass; its golden
file `commentedOutLine` rejects it, at gate 6 without lint (gate 1 rejects its `sorry`). In
`judge_dir_model` the model reads its judging directory, so it meant one model at gate 3 and
another at gate 6 while they had separate directories. Lint rejects its `include_str` and the
`sorry` its proof falls back to, and without lint gate 6 does, because both gates now judge one
elaboration of it. In `model_include_str` and `model_include_str_src` the model reads a
plugin-chosen file (`../comparator.json`, `../Plugins/<P>.lean`) with `include_str` and, for the
plugin being judged, means the weak model where only `require zz` holds, with weak examples it
proves adequate; the empty-for-`left-pad` extractor then passes gates 3 and 6. Gate 1 rejects the
`include_str`; the comparator alone accepts them, which is why the lint ban is the fix.
`double_elaboration` makes Lake rebuild its model between gate 6's runs and the plugin's; lint
rejects its `#eval`, and without lint gate 6 rejects the changed build outputs. The `shadow_*` model
cases each declare a name that the Challenge's statements would find under the plugin's namespace if
they were not written from `_root_`. Gate 3 rejects them, and gate 1 already rejects the two that
need `export`. Case models use the golden-file layout too: most are the toy's model module with one
change and use the toy's examples and adequacy modules, while `double_elaboration`,
`judge_dir_model`, `model_include_str` and `model_include_str_src` prove their own adequacy, and
the two `model_include_str` cases also choose their golden files with `include_str`.

Seven cases have a model with a wrong `fact` and a layout in which the mistake would not reach
gate 6: the golden facts share the model's `fact`, or gate 6 judges a different model from gate 3.
Gate 6 rejects all seven, with and without lint:
- `golden_circular_provides` and `golden_circular_devscope`, the verifier's two cases: `fact` reads
  a requirement as *providing* the package, or gives it the `dev` scope, and the examples module
  imports the model module to build its facts with `fact`. With the examples in the model module,
  as round 1 allowed, gate 6 accepted both;
- `golden_decoy_examples`: the examples module declares nothing, and the model module declares the
  examples;
- `golden_shared_helper`: the examples module imports a helper module with `fact` that the model
  module imports too;
- `golden_helper_in_examples`: the examples module declares `fact`, and the model module imports it;
- `golden_adequacy_own_examples` and `golden_adequacy_own_model`: the adequacy module does not
  import the examples module, or the model module, and declares its own.

Each is accepted by a gate without the one check that rejects it. In `golden_model_in_examples` the
examples module declares the model as well as golden facts built with its wrong `fact`, and the
model module declares nothing. Gate 6's layout rule and both of its runs accept that layout, but
gate 3's Challenge, which imports only the model module, does not build, so the case is rejected at
gate 2 in both modes. With a Challenge that also imported the examples module it is accepted.

Eleven cases are expected to pass the comparator on its own: `implemented_by`, `extern`,
`eval_command`, the smuggling variants `char_literal_smuggle`, `raw_string_smuggle` and
`escaped_attr_smuggle`, the model cases `model_notation`, `model_implemented_by`,
`model_include_str` and `model_include_str_src`, and the escaped import `plugin_dotdot_import`.
The kernel cannot see what code *runs*, only what is *proved*. Those cases are why the lint is a
required gate rather than a nicety. `model_dotdot_import`, the escaped import in a model, passed the
comparator on its own too until gate 6 checked the components of every model import; without lint,
gate 6 now rejects it.

### Security fixes

- **Input property first.** State what a fix protects as a property of the gate's inputs, such as
  "a model's meaning depends only on its locked bytes", before choosing how to enforce it.
  Enforce it by isolation, so that untrusted code cannot reach what the property rules out. A
  token ban adds defence in depth on top of isolation; it does not replace it.
- **A cheat case per check.** Each check that a fix adds or restores lands with a corpus case
  that the check rejects. With the check removed, the case's full run, or its `--skip-lint` run
  for a check after gate 1, no longer matches its `expect`: it is ACCEPTED, or rejected at another
  gate. So a rebase that drops the check turns the corpus red. The PR shows that flip with one run
  of the case on the gate without the check. A run that another check rejects at the same gate
  does not pin this one.
- **Test the premise.** A fix has failed when a later cheat or verifier gets past it. After two
  failed fixes that rest on one premise, write the premise down and test it directly before a
  third fix.

## 4. How to observe

### Run log (one record per agent task attempt)

Stored in `ops/runs/` as one JSON file per attempt, `ops/runs/<date>/<task>-<role>-<attempt>.json`,
holding the record on one line (or as CI artifacts); schema and merging rules in
`ops/runs/README.md`:

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
  `.github/workflows/owner-ping.yml` posts an @mention as `github-actions[bot]` on each
  assignment of the owner made from the owner's account. An assignment that any other account
  or a bot makes gets no ping. Never label a PR to show the owner its state, because any label
  change re-runs the full `gate`.
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
| Waiting on GitHub | the orchestrator's Monitor running `.claude/scripts/watch-github.sh`, which prints one line per change to an open PR, `main` or the owner's comments, and a `ci:` line when a head has no `ci` run, a run waits long in the queue or a run is left on an old head, and nothing otherwise; PR owners wait at most two bounded calls, and watcher agents cover only what the script cannot see |
| Merge readiness and fresh rules | `.claude/hooks/pr-state.sh` before every prompt: each owner PR's `gate`, verdict head, unanswered owner comments and user-kept paths, a merge command pinned to the head only when the dashboard's verdict covers it, and the rule files that changed on `main` since the session loaded its rules. It reads every comment of a PR whose verdict covers its head and only the newest 100 of the repository for the rest, and a footer post anywhere on a PR counts as the answer to an earlier owner comment, so the merge rule's own read of the owner's comments still decides |
| Public posts | `.claude/hooks/check-no-session-link.sh` refuses a session link or a `Claude-Session:` line in a commit or GitHub write; `.claude/scripts/open-pr.sh` opens each PR and cleans the link the session proxy adds at create. The first revision of each PR body still holds that link in the edit history, which anyone who can read the repository can open; only the owner can delete it, in the browser |

A Cursor session loads `.cursor/rules/kitimark-mode.mdc` and `.cursor/rules/process-pointers.mdc`
on every chat, and `.cursor/rules/lean-trust.mdc` when a `.lean` file is in context.
`.cursor/skills/kitimark-mode/SKILL.md` tells the agent to read
`.claude/skills/kitimark-mode/SKILL.md` and this document, which stay canonical. pstack is
installed in Cursor as a plugin (`/add-plugin pstack`,
[cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack)), and `.claude/` is the port
this repository maintains. #100 leaves `AGENTS.md` out of the repository, because outside
reviewers read instructions from the head.

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
lake exe mitos-gate cheats
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
- Gates 3 and 6 share one judging directory so that they judge one elaboration of the model, but
  the first version relied on lint for that. A model that ran code while it elaborated could make
  Lake rebuild it in the plugin's run and mean the toy model at gate 6 and the model where nothing
  holds at gate 3. With `--skip-lint`, gates 0–6 accepted the extractor that emits nothing
  (`eval/cheats/double_elaboration`). The gate now hashes the build outputs after each run and
  rejects any change at gate 6.
