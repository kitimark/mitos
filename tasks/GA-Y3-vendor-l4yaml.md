# GA-Y3 vendor L4YAML

phase: gate architecture
goal: Build the upstream parser closure offline and verify its bytes against its pinned revision.
statement: none (tooling task)
touches: gate/vendor/l4yaml/**, gate/vendor-test.sh, .github/scripts/vendor-provenance.sh, .github/scripts/vendor-provenance.test.sh, .github/workflows/ci.yml, lakefile.toml, tasks/GA-Y3-*, ops/runs/
must_not_touch: lean-toolchain, lake-manifest.json, statements.lock, models.lock, core/, plan/
checks: vendor-test, vendor-provenance, build, imports, lock, core-check, comparator-paranoid, accept-toy, cheats, lint-test, affected-workflow-tests
budget: 40 iterations, 2 hours wall
escalation: hint, automation, stronger model, pair, split, revisit statement

## Context

The user wants [#397](https://github.com/kitimark/mitos/issues/397) implemented and reviewed, ready for the owner to merge.
The issue's default revision is the working choice. The owner still reviews the pin, license, library entry, nine startup lines, and provenance step.
The work uses the inherited GPT model after the requested Opus model was unavailable. It makes no Opus verification claim. The repository still requires an Opus verdict before the owner receives a merge command.

## Design

depth: build
revisit_when: Review the startup inventory and closure again whenever the upstream pin changes.
modules:
- `gate/vendor/l4yaml/` holds only the 19 parser modules, upstream license, five-field pin, and 20-row blob manifest.
- `gate/vendor-test.sh` checks local bytes, real file types, closure, metadata, startup inventory, and the library build.
- `.github/scripts/vendor-provenance.sh` compares local bytes and modes with the immutable upstream revision. Its optional CI mode skips upstream access for an unchanged vendor tree.
- `.github/scripts/vendor-provenance.test.sh` exercises both commands on copied files and a real local git upstream fixture. A stub replaces only the repeated library build.
- `.github/workflows/ci.yml` runs those behavior tests and calls provenance with event data in environment variables.
- `lakefile.toml` adds the issue's library entry. The existing default targets stay the same.
types: PIN is exactly five ordered key-value lines. MANIFEST is a sorted, unique table of raw git blob hashes and safe relative paths. Neither file is executed.
statements: Local bytes equal MANIFEST. Its 19 Lean files equal the entry module's import closure. Online checks also require upstream mode 100644, blob identity, and the pinned toolchain.
reuse: bash, awk, find, git hash-object --no-filters, git ls-tree, and the existing gate shell-test loop.
fixtures: byte change; byte change with updated manifest; license change; missing and extra files; FIFO; symlink; added public meta import; nested header comments; unsupported import form; changed or added startup command; forbidden build metadata; unsafe, duplicate, and unterminated manifest rows; PIN text injection; unavailable transport; unchanged PR and push; changed PR and push; zero push base; invalid commit.
cut_line: Vendor the parser and prove provenance. The workflow reader, import fence, view, and oracle retirement belong to separate issues.
deferrals: The parser seam stays with #354, the fence with #398, the view with #399, and oracle retirement with #400.
owner_decisions: The issue default chooses revision 742f7186f59e9c8f7d6ea5bc83518ee55011e110 on v4.35.0. Final pin and license approval remains with the owner.

Two designs were compared. The selected design keeps the two required shell commands self-contained and parses only the observed import-header subset. The alternative shared PIN and MANIFEST validation in one Python standard-library verifier. The two direct shell commands kept this fixed-pin change smaller. The selected design takes the alternative's checks for path attacks, metadata links, public meta imports, and rehashed tampering.

The header reader handles nested block comments, line comments, module headers, ordinary imports, public imports, and meta imports. It refuses other header forms. The startup inventory is a review aid for this fixed pin, not a complete Lean parser. The online check compares every upstream byte. A pin change needs a new startup review.

The library is unused by the gate until #354 imports it. Its three initialization blocks therefore do not run in the current gate executable. Their eventual startup reach is an inference from the import design. Judged code still uses the gate's existing separate parser environment and lake subprocesses.

## Throughput checkpoint

- Blocking first steps. Read the issue and trust rules, install Lean outside the checkout, and preserve three sequential clean baseline builds before the library entry changes.
- Independent workstreams. The root compares design candidates. This owner writes the branch and runs its builds. Reviewers inspect the authored scripts while measurements continue.
- Shared mutable state. Only this owner edits this branch. The benchmark removes only this worktree's root and core build directories.
- Smallest safe decomposition. One owner carries the coupled vendor, tests, CI step, and PR. Independent reviewers provide separation.

## Verification evidence

The committed closure contains 19 Lean files, 9,746 lines, and 431,542 bytes. LICENSE is the twentieth manifest row by file count. Its bytes retain the upstream Caltech BSD-3 and Apache-2.0 notices.

The real upstream provenance command exited 0 against the pinned GitHub revision. After appending one byte to LICENSE without changing MANIFEST, the same command exited 1 and named `gate/vendor/l4yaml/LICENSE`. The file was then restored from the checked-out upstream revision.

The behavior suite passed against a local git fixture. It verifies refusal of modified source and license bytes even after the manifest is updated. It also checks the listed file, header, startup, metadata, manifest, transport, and CI cases. Both commands reject symlinks and nonregular entries. Unrelated PR and push commits skip the fetch even when transport is disabled.

Raw successful samples are in [GA-Y3-builds.tsv](GA-Y3-builds.tsv). The three clean baseline builds took 593.201, 587.893, and 564.010 seconds. The median was 587.893 seconds and the range was 564.010 to 593.201 seconds. Each produced 297,407,518 root `.lake` bytes, 2,882,822 core `.lake` bytes, and 64 olean files.

The separate clean parser-library builds took 18.050, 18.099, and 18.423 seconds. The median was 18.099 seconds and the range was 18.050 to 18.423 seconds. Each produced 22,175,833 `.lake` bytes and 19 olean files. There were 19 built modules, plus two Lake target jobs.

The baseline graph is commit `391789f47e5bd64571658f2cc83d9294fecec91c`. Authored shell files and unused vendor sources were placed during its sequential trials, without changing the Lake configuration. Parser trials use that graph plus this PR's exact library entry. Their lakefile SHA-256 is `d55f59713bbd5d99a555d9e629fc8af1610791bfd2fa4b5dd6536cbfea218e31`. The after set is pending. No unrelated Lean source changes enter these graphs.

Each plain run deletes the root and core `.lake` directories, then times `lake build` and counts both directories in bytes. Parser-only runs delete the root `.lake` and time `lake build L4YAML`; they do not use core outputs. The plain build outputs were parked and restored between sets. Default targets are identical before and after. Plain `lake build` does not request the parser library yet. These are three descriptive runs per configuration, not a performance adoption verdict. The machine exposes five CPUs with a four-CPU cgroup quota. A process sample identified the existing `Snapshot/Fixtures.lean` compilation on one fully used core as the baseline's long critical step. Its first build reported 386 seconds.

The real vendor check, mutation suite, imports, lock, runlog, bash syntax, REST wrapper, cache-logs, cheat-shard, ci-trust, land-protection, and cancel-superseded tests passed. The gate binary remained byte-identical after adding and building the unused library. Local core replay is pending an environment-only sandbox workaround because this container lacks `/run/user`. The temporary wrapper adds a private `/run` tmpfs and retains the existing isolation flags. Normal CI still runs every required core, acceptance, and cheat check.

## Done when

- [x] Local mutation and upstream-fixture tests pass.
- [x] Real upstream comparison succeeds and a one-byte change fails.
- [ ] Three clean before and after measurements are recorded with their spread.
- [x] The real 19-module library build passes.
- [ ] Affected local process checks pass.
- [ ] CI shows that the upstream provenance step ran.
- [ ] Root no-comments review and independent verification cover the final head.
- [x] The run-log record is written.

## Principles applied

Model the Domain made PIN and MANIFEST data tables rather than executable shell. Build the Lever made the mutation checks rerunnable. Boundary Discipline keeps upstream failures distinct from byte mismatches. Test Behavior, Not Implementation checks command exits and named files. Explain the Number separates plain builds from parser builds and records the long critical step. Laziness Protocol kept the issue's library configuration and the two standalone commands.
