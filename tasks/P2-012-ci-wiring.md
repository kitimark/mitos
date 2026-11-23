# tasks/P2-012-ci-wiring.md

phase: 2
goal: Every PR accepts every plugin in `examples/acme/Plugins/` (`ToyRequire` and `GoMod`) with `--paranoid --record` through one script, and fails when a committed `accepted/*.json` differs from the record the gate writes for the tree. Every PR also builds `eval/diff` (pins, selftest, and the comparison as a warning) and runs `mitos-mutants --prepare` over every case. That step fails on a case that does not prepare as its manifest says, and on a Challenge theorem that no case claims. A judged run of every case fails on a Challenge theorem that no refuted case breaks. Each night, Go from `eval/diff/.go-version` rewrites the vendored outputs before the differential run, and the `full` job prints the scorecard of every fixture.
statement: none in `statements.lock` (CI and tooling). The runner's own, appended to `eval/mutants/Mutants/Verdict.lean`: `Mutants.mem_unbroken`, `Mutants.mem_claimed`, `Mutants.mem_unclaimed`, `Mutants.runPasses_corpus`, `Mutants.runPasses_named`, `Mutants.prep_ok_iff`, `Mutants.prep_written_iff`
touches: .github/workflows/ci.yml (job `checks` only), .github/workflows/nightly.yml (jobs `full` and `canary`, new job `diff`), .github/scripts/accept-plugins.sh (new), .github/scripts/accept-plugins.test.sh (new), .github/scripts/install-go.sh (new), .github/scripts/nightly-baseline.sh (new), .github/scripts/nightly-baseline.test.sh (new), gate/lake-no-cache-check.py (expected Lake jobs only), .github/scripts/cheat-shard.test.sh (only its `checks 20` timeout pin, and only under S6), eval/mutants/Mutants/Verdict.lean (one block appended before `end Mutants`), eval/mutants/Main.lean (the `usage` text, `writeWorkspaces`, and in `main` the `--prepare` guard, the `--prepare` branch and the end of the judged run), this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/ except lake-no-cache-check.py's expected Lake jobs, eval/cheats/, core/, examples/ (`examples/acme/accepted/*.json` included, see S1), every other file under .github/ (the other workflows, .github/actions/, the other scripts), eval/mutants/Mutants/ except Verdict.lean, eval/mutants/cases/, the rest of eval/mutants/Main.lean, eval/diff/, eval/score/, eval/fixtures/, docs/ (O2), plan/, .claude/, .coderabbit.yaml, every lean-toolchain, lakefile.toml and lake-manifest.json
checks: actionlint on both workflows; `shellcheck -x` on the three new scripts; `.github/scripts/{accept-plugins,cheat-shard,cache-logs,ci-trust,cancel-superseded,land-protection}.test.sh`; `lake --dir eval/mutants build` (warningAsError) and `#print axioms` of the seven statements; fixtures F1 to F21 and F23; run-log check; `plan-tasks.test.sh`; `gate` green at the head; one nightly `workflow_dispatch` on the branch (F22)
budget: 10 iterations · 5h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

- **Plan row.** P2-012 in `plan/phase-2.md`, issue #213, wave W7, last (it waits for P2-008 and P2-010). Its Owns cell is `ci.yml`, `nightly.yml` and "the lines of `eval/mutants/Main.lean` that #107 item 3 needs"; Reads: every row. It is Class B: the owner merges it (`.github/`). It is trust-critical, so a sonnet-xhigh and an opus-xhigh verifier check every head that needs a verdict. Role: PR owner, hard (opus, xhigh).
- **This file goes past the Owns cell.** It adds three `.github/scripts/` files, an appended block in `Mutants/Verdict.lean` and the `Main.lean` lines that #107 item 2 needs. The reasons are under Rationale. The plan edit is the owner's (O1), as with `tasks/P2-011-toolchain-readiness.md`. The build starts once the owner has extended the cell (S0).
- **Rule files.** Read on `origin/main` at `eac85d2` after `git fetch`: `plan/phase-2.md`, `tasks/TEMPLATE.md`, `.claude/skills/architect/` (SKILL, red flags, rationale template), `docs/process.md` ("What runs where", "Scorecard"), and `CLAUDE.md` with the kitimark-mode skill.
- **Merged rows used here, as on `main`:**
  - P2-000 (#202).
  - P2-001a with P2-005a (#203, #205, in #277).
  - P2-006 (#207, #272).
  - P2-007 (#208, #286).
  - P2-008 (#209, #330, merged 2026-11-15).
  - P2-009b (#211).
  - P2-011 PR A (#283).
- **Rows not merged** (contract only; each has a `revisit_when` line): P2-001b (#204), P2-005b (#206), P2-009a (#210), P2-010 (#212, designed in `tasks/P2-010-nightly-scorecard.md`, which C1 follows), P2-011 PR B (#147).
- **Findings handed to this row:**
  - #107 items 2 to 5.
  - #33 and #275 item 1: a record that matches the tree. These are also P2-007 R1 and P2-001b's deferral.
  - P2-006 and P2-007: GoMod accepted in CI and in the canary.
  - P2-008: the nightly refresh and run, a CI build of `eval/diff` (its R1), whether the nightly fails on exit 2, and the docs row.
  - P2-009b: the go.mod scorecard in CI and in the nightly.
  - P2-011: the canary gaps, and "CI never builds `eval/mutants`".
  - #175's last bullet.
- **Already settled on `main`:**
  - #158 closed with #304: `full` and the canary run `lake exe mitos-gate cheats --jobs 4`.
  - #107 item 5: `nightly.yml` has no comment above the mutant steps, so nothing is left to fix.
- **Facts on `main` at `eac85d2`:**
  - **Mutant cases.** There are 44 (the plan's Shared files 3 says 42). 15 have `rejects=lint`. All 12 Challenge theorems are claimed by a case with `breaks=` and no `rejects=` (#311 added the cases for `resolve_unresolved_nodup` and `impact_nodup`). No scheduled nightly has run those two cases yet: the newest scheduled run is `48bb997`.
  - **`--prepare` today.** Over every case it exits 1, because `writeWorkspaces` sets `code := 1` for every lint refusal, expected ones included. Both runners measured this. A bare `--prepare` in CI would be red on arrival.
  - **Stale record.** `accepted/GoMod.json` holds `core_sha256` `8ae154a0…edfb184`. `ToyRequire.json` holds `f7d74757…5e6cb9e`, which is what `main`'s core hashes to. Both runners recomputed this independently. GoMod was recorded before P2-001a, and nothing in CI saw it (#33). This row's accept step is red on `main` until a re-record lands (S1).
  - **Pins.** `cheat-shard.test.sh` pins the job timeouts, `checks 20` among them. It also fails if `ci.yml` contains `mapfile`, and it counts 4 checkouts.
  - **CI timings** (latest `main` run, 43771424506): `checks` 4 min 19 s; the slowest shard 5 min 1 s; `gate` done at 5 min 51 s; the toy accept 54 s; the scorecard step 1 s. The GoMod accept with `--paranoid --record` took 2 min 12 s to 3 min 1 s (P2-007, five local runs).
  - **Caches.** Only `.lake`, `core/.lake` and `~/.elan` are cached in CI, so `eval/mutants/.lake`, `eval/diff/.lake` and `examples/acme/.lake` build cold on every PR.
  - **Go 1.24.7.** go.dev's JSON listing gives `go1.24.7.linux-amd64.tar.gz` SHA256 `da18191ddb7db8a9339816f3e2b54bdded8047cdc2a5d67059478f8d1595c43f` (78584952 bytes). `Diff.Go` runs Go with `GOTOOLCHAIN=local`, `GOWORK=off` and cwd `/`.
- **What the judge checked**, in a scratch copy of `origin/main` at `eac85d2`, on Lean v4.35.0. These are single runs on a machine other agents shared, so the times are indicative:
  - `lake --dir eval/mutants build` passed with the Verdict and Main text below (warningAsError). The axioms are `propext`, `Classical.choice` and `Quot.sound` only.
  - `--prepare` with no case named exited 0 in 28 s. It wrote 29 cases (58 directories) and printed 15 `refused by the lint, as its manifest says`. Sampled peak RSS was 9.3 GB.
  - F3 to F7, F9 and F10 gave the results stated under fixtures. F2's historical run used `edges := fs.flatMap fun r =>`; the current-anchor receipt under F2 is from the independent verifier at `4857ba7`.
  - `install-go.sh` ran for real in 7.8 s. `check-pins.sh --online` passed in 6 s. `lake --dir eval/diff build` took 11 s with acme warm. `selftest.sh` printed 28 `ok` lines in 3.9 s. The plain run exited 0 in 0.28 s. `--refresh` with Go 1.24.7 exited 0 and left `git status --porcelain eval/diff` empty.
  - A whitespace edit of `cases/zap/module.json` passed the plain run (exit 0). After `--refresh` the tree showed ` M eval/diff/cases/zap/module.json`.
  - The PR diff step: exit 0 on `main`; a `::warning::` and exit 0 with one triage line removed; exit 2 and red with one `module.json` removed.
  - The scorecard loop printed two cards (`gomod`, `toy`).
  - `actionlint -shellcheck=shellcheck` was clean on both edited workflows. The five existing workflow-reading tests and `accept-plugins.test.sh` (A1 to A10) passed against them.
  - **Not run:** a real `accept-plugins.sh --record` (gate and comparator), a judged run of all 44 cases, CI, and a nightly dispatch.
- **What round 2 checked** (the PR owner, after review): C1 against P2-010's task file. In a scratch copy of `main` at `eac85d2` with P2-010's `types` text applied (`Score/Nightly.lean` 276 lines, `Main.lean` 78), `lake --dir eval/score build` ended with `Build completed successfully (44 jobs).` in about 10 s. The nightly scorecard step below passed actionlint, and the F23 cases gave the results stated there, one run each.
- **Landing this design.** The design PR removes `P2-012` from `.claude/scripts/plan-tasks.pending`, which is an owner path, so the owner merges the design PR. The builder's PR leaves `.claude/` alone.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file lists.

depth:
- **Build depth** for every part that rests on merged rows: the three scripts, the Lean, the `ci.yml` steps, `nightly.yml`'s `full` accept, #107 item 4, the `diff` job and the canary line. That text is final, and it was built, linted or run as listed under Context.
- **Build depth** for the nightly scorecard step, its D1 line and its two artifacts (C1). They rest on P2-010's design, not a merged row: the commands, exit codes and lines that `tasks/P2-010-nightly-scorecard.md` pins with its `#guard`s and its N7. The step ran against P2-010's text, built in scratch (round 2, F23).
- **Contract only** for one step of C1, the fetch of `main`'s numbers (the baseline). C1 fixes its permission, source, output and failure. Its commands are the builder's, proved against the real API.

revisit_when:
- re-check after #204 (P2-001b) merges:
  - It re-records both accept records, so S1 must then print nothing.
  - It moves `find=` anchors, so `--prepare` of every case must still exit 0 at its head.
  - If it adds Challenge theorems, P2-005b's cases must claim them before this row's step can be green (O4).
- Re-checked after #206 (P2-005b) merged: 72 cases, 15 lint refusals, 57 written cases; re-measure full-corpus prepare memory and decide whether PR preparation needs sharding (see Implementation and R3).
- re-check after #210 (P2-009a) merges: `eval/fixtures/chain/` joins the PR loop with no workflow change, but it needs a `labels.tsv`; F19 then prints three cards.
- C1 was filled from P2-010's task file when it landed. Re-check after #212 (P2-010) merges: run F23 at the head. If P2-010's build moved a line C1 reads (the D1 line, the no-edge line, the bold line) or an exit code, amend C1 and the step first. Then decide the PR scorecard (C1, still open).
- re-check after P2-011 PR B (#147) merges: its re-recorded records must pass the accept step. If P2-012 merges first, tell PR B's owner that CI now checks both records at its head.

modules: each existing file is edited in place, and each new file owns one topic.
- `.github/scripts/accept-plugins.sh` (new, 40 lines): the one list of plugins and their models, the check that `Plugins/`, the list and `accepted/` agree, and the record check. It copies `install-elan.sh`'s style.
- `.github/scripts/accept-plugins.test.sh` (new, 79 lines): A1 to A10, with a stub `lake` in a scratch git repo. It copies `cancel-superseded.test.sh` (a stub tool, no network).
- `.github/scripts/install-go.sh` (new, 34 lines): Go from `eval/diff/.go-version`, SHA256 pinned, retried, and its version read back. It copies `install-elan.sh`.
- `.github/workflows/ci.yml`, job `checks`, about +30 lines. It adds three steps: the accept test, the `eval/diff` step and the `--prepare` step. It changes two: the scorecard loops over every fixture, and the accept step calls the script. There is no new job, checkout or timeout.
- `.github/workflows/nightly.yml`, about +100 lines:
  - `full`: the accept step calls the script; `if: ${{ !cancelled() }}` goes on both mutant steps (#107 item 4); `actions: read` is added to its permissions, and the baseline fetch, the scorecard step and its two artifacts are added (C1).
  - New job `diff`.
  - `canary`: one line.
- `eval/mutants/Mutants/Verdict.lean`, +104 lines appended: `unbroken`, `claimed`, `unclaimed`, `Scope`, `runPasses`, `Prep` and `prep`, with their statements and `#guard`s, beside `breakers` and `passes`.
- `eval/mutants/Main.lean`, +34 −14 lines in the design (plus package-reuse arguments retained from main): the `usage` text, `writeWorkspaces` routed through `prep`, no `--prepare` usage error without names, the coverage line in `--prepare`, and the UNBROKEN section and `runPasses` at the end of the judged run.

### How a builder or a later PR gets past this row, and what stops it

| # | The move | What stops it | Fixture |
|---|---|---|---|
| X1 | Add `Plugins/Evil.lean` with no CI line | `accept-plugins.sh` compares `Plugins/*.lean`, its list and `accepted/*.json` before any accept | A4, A5 |
| X2 | A stale record (GoMod today), a deleted record, an orphan record, or a temp file in `accepted/` | `git diff --exit-code`, the name checks, the stray check and the untracked check | A2, A3, A5, A6, F13 |
| X3 | Accept without `--paranoid` | The script always passes it, and the stub fails a call without it | A1 |
| X4 | A second way to accept: a workflow that calls `mitos-gate accept` itself | A10 greps every workflow | A10 |
| X5 | Skip the `rejects=lint` cases with a shell `grep` that reads a manifest otherwise than Lean's parser does | The expectation lives in `prep`; the CI step names no case; one reader | F1, F3, F4 |
| X6 | A Challenge theorem with no case, or claimed only by a cheat case | `unclaimed` on every PR; `unbroken` in every judged run of all cases. Both count only `breaks=` cases with no `rejects=` | F5, F10, guards |
| X7 | A stray file in `eval/mutants/cases/` | The runner lists every entry, as the judged run does: `no such case directory` | F6 |
| X8 | A new step in a new `ci.yml` job, which `gate` does not require | The steps go in `checks`, which `prove` needs. `cheat-shard.test.sh` pins the job list through its timeouts | F21 |
| X9 | A hand-edited `module.json` that agrees with a wrong model: the plain run and the offline pins pass it | The nightly `--refresh`, then the clean-tree step | F18 |
| X10 | Edit `module.mod` and its `pins.tsv` hash together | The nightly `check-pins.sh --online` | F17 |
| X11 | A swapped Go archive, or a `.go-version` bump with no hash | SHA256 checked before extraction; `go env GOVERSION` checked after; an unknown version fails closed | F16 |
| X12 | A fixture directory with no labels is skipped | The loop scores every directory, and `mitos-score` fails without a `labels.tsv` | F19 |
| X13 | `continue-on-error`, `\|\| true`, or `if: always()` on a check step | None in this design. `!cancelled()` only on evaluation steps. The verifiers read the diff | review |
| X14 | Reword the scorer's D1 line, so the nightly step reads no number and the report still looks fine | The step fails when the report has neither the D1 line nor P2-010's no-edge line (C1) | F23 |

types:

`.github/scripts/accept-plugins.sh`, final text (shellcheck clean; A1 to A10 pass):

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGINS=(
  "ToyRequire:Models.ToyRequire.model"
  "GoMod:Models.GoMod.model"
)

mode=${1:-}
case $mode in
  --record|--no-record) ;;
  *) echo "usage: accept-plugins.sh --record|--no-record" >&2; exit 2 ;;
esac
cd "$(dirname "$0")/../.."
ws=examples/acme
fail() { echo "::error::accept-plugins.sh: $*" >&2; exit 1; }
names() { LC_ALL=C sort | tr '\n' ' '; }

stray=$(find "$ws/Plugins" -mindepth 1 -maxdepth 1 -name '*.lean' ! -type f -print)
[ -z "$stray" ] || fail "Plugins/ holds a nonregular Lean entry: $stray"
listed=$(printf '%s\n' "${PLUGINS[@]%%:*}" | names)
plugins=$(find "$ws/Plugins" -maxdepth 1 -type f -name '*.lean' -printf '%f\n' | sed 's/\.lean$//' | names)
[ "$listed" = "$plugins" ] || fail "Plugins/ holds [$plugins] and this script accepts [$listed]"
stray=$(find "$ws/accepted" -mindepth 1 ! -regex '.*/[A-Za-z][A-Za-z0-9_]*\.json' -print)
[ -z "$stray" ] || fail "accepted/ holds something that is not a record: $stray"
recorded=$(find "$ws/accepted" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | sed 's/\.json$//' | names)
[ "$listed" = "$recorded" ] || fail "accepted/ holds records for [$recorded] and this script accepts [$listed]"

for entry in "${PLUGINS[@]}"; do
  args=(accept --workspace "$ws" --plugin "${entry%%:*}" --model "${entry#*:}" --paranoid)
  if [ "$mode" = --record ]; then args+=(--record); fi
  lake exe mitos-gate "${args[@]}"
done

if [ "$mode" = --record ]; then
  git diff --exit-code -- "$ws/accepted" \
    || fail "a committed record is not what accept --record writes for this tree; re-record it at the head, after the last rebase"
  left=$(git status --porcelain --untracked-files=all -- "$ws/accepted")
  [ -z "$left" ] || fail "the gate left files that are not committed: $left"
fi
```

The plugin-to-model pairs live in this trusted file, never in a record or other data a PR can edit. A PR that chose the model for its own plugin would choose what gate 6 judges it against.

`.github/scripts/accept-plugins.test.sh`, final text (shellcheck clean; passed against the edited workflows):

```bash
#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/lake" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$LAKE_LOG"
[ "$1 $2 $3" = "exe mitos-gate accept" ] || exit 9
case " $* " in *" --paranoid "*) ;; *) exit 8 ;; esac
plugin=; record=false
while [ $# -gt 0 ]; do
  case $1 in --plugin) plugin=$2; shift ;; --record) record=true ;; esac
  shift
done
if [ "$plugin" = "${REJECT:-}" ]; then echo "VERDICT: REJECTED"; exit 1; fi
if $record; then printf '{"plugin": "%s", "core": "%s"}\n' "$plugin" "${CORE:-c1}" > "examples/acme/accepted/$plugin.json"; fi
echo "VERDICT: ACCEPTED"
STUB
chmod +x "$work/bin/lake"

fresh() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/.github/scripts" "$work/repo/examples/acme/Plugins" "$work/repo/examples/acme/accepted"
  cp "$root/.github/scripts/accept-plugins.sh" "$work/repo/.github/scripts/"
  for p in ToyRequire GoMod; do
    : > "$work/repo/examples/acme/Plugins/$p.lean"
    printf '{"plugin": "%s", "core": "c1"}\n' "$p" > "$work/repo/examples/acme/accepted/$p.json"
  done
  git -C "$work/repo" init -q
  git -C "$work/repo" add -A
  git -C "$work/repo" -c user.name=t -c user.email=t@t commit -qm base
  : > "$work/lake.log"
}
run() {
  status=0
  (cd "$work/repo" && PATH="$work/bin:$PATH" LAKE_LOG="$work/lake.log" "$@" \
    .github/scripts/accept-plugins.sh "$mode") > "$work/out" 2>&1 || status=$?
}
expect() {
  [ "$status" = "$1" ] || { cat "$work/out" >&2; fail "$2: exit $status, wanted $1"; }
  [ -z "${3:-}" ] || grep -qF -- "$3" "$work/out" || { cat "$work/out" >&2; fail "$2: no '$3'"; }
  ok "$2"
}

mode=--record
fresh; run env; expect 0 "A1 both plugins accepted with --paranoid --record, records unchanged"
[ "$(grep -c -- '--paranoid --record$' "$work/lake.log")" = 2 ] || fail "A1: not two --paranoid --record calls"
fresh; run env CORE=c2; expect 1 "A2 a record that differs from the gate's is red" "is not what accept --record writes"
fresh; git -C "$work/repo" rm -q examples/acme/accepted/GoMod.json; run env; expect 1 "A3 a deleted record is red" "accepted/ holds records for [ToyRequire ]"
fresh; : > "$work/repo/examples/acme/Plugins/Evil.lean"; run env; expect 1 "A4 an extra plugin is red before any accept" "Plugins/ holds [Evil GoMod ToyRequire ]"
[ ! -s "$work/lake.log" ] || fail "A4: an accept ran"
fresh; echo '{}' > "$work/repo/examples/acme/accepted/Evil.json"; run env; expect 1 "A5 an orphan record is red" "accepted/ holds records for"
fresh; : > "$work/repo/examples/acme/accepted/.GoMod.json.1.tmp"; run env; expect 1 "A6 a temp file in accepted/ is red" "not a record"
fresh; run env REJECT=GoMod; expect 1 "A7 a rejected plugin is red" "VERDICT: REJECTED"
mode=--no-record
fresh; run env CORE=c2; expect 0 "A8 --no-record passes no --record and checks no record"
grep -q -- '--record' "$work/lake.log" && fail "A8: --record was passed"
mode=--bogus
fresh; run env; expect 2 "A9 an unknown mode is a usage error" "usage:"

direct=$(grep -n 'mitos-gate accept' "$root"/.github/workflows/*.yml || true)
[ -z "$direct" ] || fail "A10 a workflow runs mitos-gate accept itself: $direct"
for f in ci.yml nightly.yml; do
  grep -q 'accept-plugins.sh --record' "$root/.github/workflows/$f" || fail "A10 $f does not run accept-plugins.sh --record"
done
grep -q 'accept-plugins.sh --no-record' "$root/.github/workflows/nightly.yml" || fail "A10 the canary does not run accept-plugins.sh --no-record"
ok "A10 every workflow accepts through accept-plugins.sh"
mode=--record
fresh; ln -s GoMod.lean "$work/repo/examples/acme/Plugins/Evil.lean"; run env
expect 1 "A11 an extra symlink plugin is red before any accept" "nonregular Lean entry"
[ ! -s "$work/lake.log" ] || fail "A11: an accept ran"
echo "accept-plugins: done"
```

`.github/scripts/install-go.sh`, final text (shellcheck clean; ran for real, 7.8 s):

```bash
#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
version=$(tr -d '[:space:]' < "$root/eval/diff/.go-version")
case $version in
  1.24.7) sha256=da18191ddb7db8a9339816f3e2b54bdded8047cdc2a5d67059478f8d1595c43f ;;
  *) echo "::error::install-go.sh pins no SHA256 for go$version; a Go bump adds it here with eval/diff/.go-version" >&2; exit 1 ;;
esac
archive=go$version.linux-amd64.tar.gz
url=https://go.dev/dl/$archive
attempts=5
delay="${INSTALL_RETRY_DELAY:-10}"
dest=${RUNNER_TEMP:-/tmp}/go-$version

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=1
until curl -sSfL --connect-timeout 30 --max-time 300 -o "$tmp/$archive" "$url"; do
  if [ "$n" -ge "$attempts" ]; then
    echo "::error::download of $url failed after $attempts attempts"
    exit 1
  fi
  echo "download failed (attempt $n of $attempts); retrying in $((delay * n))s."
  sleep $((delay * n))
  n=$((n + 1))
done
echo "$sha256  $tmp/$archive" | sha256sum -c -
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmp/$archive" -C "$dest"
got=$(GOTOOLCHAIN=local "$dest/go/bin/go" env GOVERSION)
[ "$got" = "go$version" ] || { echo "::error::the archive holds $got, not go$version"; exit 1; }
echo "$dest/go/bin" >> "${GITHUB_PATH:-/dev/null}"
```

The version-to-hash table is a second list beside `.go-version`. It cannot drift silently: an unpinned version fails closed. `--refresh` also refuses any Go whose `go env GOVERSION` differs from `.go-version`, so a Go preinstalled on the runner cannot stand in for the pinned one.

`eval/mutants/Mutants/Verdict.lean`, appended before `end Mutants`. This is the final text, built under warningAsError with the proofs and guards:

```lean
def unbroken (theorems : List String) (rs : List Result) : List String :=
  theorems.filter fun t => (breakers rs t).isEmpty

theorem mem_unbroken {theorems : List String} {rs : List Result} {t : String} :
    t ∈ unbroken theorems rs ↔ t ∈ theorems ∧ breakers rs t = [] := by
  simp [unbroken, List.mem_filter, List.isEmpty_iff]

def claimed (ms : List Mutant) : List String :=
  ms.flatMap fun m =>
    match m.expect, m.rejects with
    | .breaks ts, none => ts
    | _, _ => []

theorem mem_claimed {ms : List Mutant} {t : String} :
    t ∈ claimed ms ↔ ∃ m ∈ ms, ∃ ts, m.expect = .breaks ts ∧ m.rejects = none ∧ t ∈ ts := by
  simp only [claimed, List.mem_flatMap]
  constructor
  · rintro ⟨m, hm, h⟩
    rcases hx : m.expect with ts | g <;> rcases hr : m.rejects with _ | s <;> simp [hx, hr] at h
    exact ⟨m, hm, ts, hx, hr, h⟩
  · rintro ⟨m, hm, ts, hx, hr, h⟩
    exact ⟨m, hm, by simp [hx, hr, h]⟩

def unclaimed (theorems : List String) (ms : List Mutant) : List String :=
  theorems.filter fun t => !(claimed ms).contains t

theorem mem_unclaimed {theorems : List String} {ms : List Mutant} {t : String} :
    t ∈ unclaimed theorems ms ↔ t ∈ theorems ∧ t ∉ claimed ms := by
  simp [unclaimed, List.mem_filter]

inductive Scope where
  | corpus
  | named
  deriving Repr, DecidableEq

def Scope.ofNamed (named : List String) : Scope :=
  if named.isEmpty then .corpus else .named

def Scope.gaps : Scope → List String → List String
  | .corpus, missing => missing
  | .named, _ => []

def runPasses (scope : Scope) (control : Run) (cases : List String) (rs : List Result)
    (theorems : List String) : Bool :=
  passes control cases rs && (scope.gaps (unbroken theorems rs)).isEmpty

theorem runPasses_corpus {control : Run} {cases ts : List String} {rs : List Result} :
    runPasses .corpus control cases rs ts = true ↔
      passes control cases rs = true ∧ ∀ t ∈ ts, breakers rs t ≠ [] := by
  simp only [runPasses, Scope.gaps, Bool.and_eq_true, List.isEmpty_iff,
    List.eq_nil_iff_forall_not_mem, mem_unbroken, not_and, ne_eq]

theorem runPasses_named {control : Run} {cases ts : List String} {rs : List Result} :
    runPasses .named control cases rs ts = passes control cases rs := by
  simp [runPasses, Scope.gaps]

inductive Prep where
  | written
  | refusedAsExpected
  | refusedUnexpectedly
  | notRefused
  deriving Repr, DecidableEq

def prep : Option Stage → List String → Prep
  | some .lint, [] => .notRefused
  | some .lint, _ :: _ => .refusedAsExpected
  | _, [] => .written
  | _, _ :: _ => .refusedUnexpectedly

def Prep.ok : Prep → Bool
  | .written | .refusedAsExpected => true
  | .refusedUnexpectedly | .notRefused => false

theorem prep_ok_iff (r : Option Stage) (l : List String) :
    (prep r l).ok = true ↔ (r = some .lint ↔ l ≠ []) := by
  rcases r with _ | (_ | _ | _ | _) <;> cases l <;> simp [prep, Prep.ok]

theorem prep_written_iff (r : Option Stage) (l : List String) :
    prep r l = .written ↔ r ≠ some .lint ∧ l = [] := by
  rcases r with _ | (_ | _ | _ | _) <;> cases l <;> simp [prep]

private def refutedBy (n : String) (ts : List String) : Result :=
  { name := n
    judged := .ran (.breaks ts) none
      { holes := some .accepted, approved := some .rejected, refutation := some .accepted } }

private def refusedAtLint (n : String) (ts : List String) : Result :=
  { name := n, judged := .ran (.breaks ts) (some .lint) { lint := ["a macro"] } }

#guard unbroken ["a", "b"] [refutedBy "m1" ["a"]] == ["b"]
#guard unbroken ["a"] [refusedAtLint "c1" ["a"]] == ["a"]
#guard unbroken ["a"] [refutedBy "m1" ["a"], refusedAtLint "c1" ["a"]] == []
#guard unbroken ["a"] [] == ["a"]
#guard runPasses .named .accepted ["m1"] [refutedBy "m1" ["a"]] ["a", "b"]
#guard !runPasses .corpus .accepted ["m1"] [refutedBy "m1" ["a"]] ["a", "b"]
#guard runPasses .corpus .accepted ["m1"] [refutedBy "m1" ["a"]] ["a"]
#guard Scope.ofNamed [] == .corpus
#guard Scope.ofNamed ["m1"] == .named
#guard (prep (some .lint) []).ok == false
#guard (prep (some .lint) ["macro"]).ok
#guard (prep none ["macro"]).ok == false
#guard (prep none []).ok
#guard (prep (some .holes) ["macro"]).ok == false
```

`eval/mutants/Main.lean`. This is the final diff, built together with the block above:

```diff
-       mitos-mutants --prepare <dir> <case>...
+       mitos-mutants --prepare <dir> [<case>...]
   Run from the repository root. Lints each case's Lean text, then judges every case in
   eval/mutants/cases/, or the named ones, with the sandboxed lake comparator. --paranoid also runs
   the external kernels. --keep keeps the workspaces. Logs go to .lake/mutants/. Exit 0: every case
-  as expected; 1: not; 2: could not run.
-  --prepare writes each named case's workspaces to <dir>/<case>/ (refutation or values run) and
-  <dir>/<case>.holes/ (hole run), and judges nothing; it writes none for a case the lint refuses.
+  as expected and, when no case is named, every Challenge theorem broken by a refuted case; 1: not;
+  2: could not run.
+  --prepare writes the workspaces of every case, or of the named ones, to <dir>/<case>/
+  (refutation or values run) and <dir>/<case>.holes/ (hole run), and judges nothing; it writes none
+  for a case the lint refuses. Exit 1 when a case does not prepare, when the lint refuses a case
+  whose manifest has no rejects=lint or does not refuse one whose manifest has it, or, when no case
+  is named, when no case with breaks= and no rejects= names a Challenge theorem.
@@ def writeWorkspaces
-    (cases : List String) : IO UInt32 := do
+    (cases : List String) : IO (UInt32 × List Mutant) := do
   let mut code := 0
+  let mut ms := #[]
   for name in cases do
     match ← (prepare env a casesDir name).run with
     | .error e => IO.eprintln s!"{clean name}: {clean e}"; code := 1
     | .ok p =>
-      unless p.lint.isEmpty do
+      ms := ms.push p.mutant
+      match prep p.mutant.rejects p.lint with
+      | .written =>
+        writeFiles a.toolchain (out / name) (p.approved ++ p.refutation.getD p.values)
+        writeFiles a.toolchain (out / s!"{name}.holes") p.holes
+        IO.println s!"{clean name}: {out / name}"
+      | .refusedAsExpected =>
+        IO.println s!"{clean name}: refused by the lint, as its manifest says ({p.lint.length} finding(s))"
+      | .refusedUnexpectedly =>
         for l in p.lint do IO.eprintln s!"{clean name}: lint: {clean l}"
         code := 1
-        continue
-      writeFiles a.toolchain (out / name) (p.approved ++ p.refutation.getD p.values)
-      writeFiles a.toolchain (out / s!"{name}.holes") p.holes
-      IO.println s!"{clean name}: {out / name}"
-  return code
+      | .notRefused =>
+        IO.eprintln s!"{clean name}: its manifest says rejects=lint, and the lint finds nothing"
+        code := 1
+  return (code, ms.toList)
@@ def main
-  if cfg.prepare.isSome && cfg.cases.isEmpty then IO.eprintln usage; return 2
@@
+  let scope := Scope.ofNamed cfg.cases
   if let some out := cfg.prepare then
-    return ← writeWorkspaces env a casesDir out cases
+    let (code, ms) ← writeWorkspaces env a casesDir out cases
+    let missing := scope.gaps (unclaimed a.theorems ms)
+    for t in missing do
+      IO.eprintln s!"{clean t}: no case with breaks= and no rejects= names this theorem"
+    return if code == 0 && missing.isEmpty then 0 else 1
@@ after the UNEXPECTED SURVIVORS block
+  let unbrokenNow := scope.gaps (unbroken a.theorems rs)
+  unless unbrokenNow.isEmpty do
+    IO.println "\nUNBROKEN THEOREMS (no case refutes them: add a mutant case that breaks each)"
+    for t in unbrokenNow do IO.println (clean t)
@@
-  if passes control cases rs then
+  if runPasses scope control cases rs a.theorems then
```

`claimed` counts only prepared cases with `breaks=` and no `rejects=`, where prepared means that `prepare` returned `.ok`, before lint classification. A `prepare` `.error` contributes no mutant and no claim. An `.ok` case with `breaks=`, no `rejects=` and unexpected lint findings still claims its theorems: a theorem named only there is not reported as unclaimed, although `.refusedUnexpectedly` fails the run. A theorem is unclaimed only when no qualifying prepared case names it. In F2, `bound_edges_duplicated` still claims `resolve_edges_nodup`, so the moved `edges_duplicated` anchor does not create that coverage gap. A run of named cases checks no coverage, because a partial list cannot meet it. The CI step and the nightly name no case.

`ci.yml`, job `checks`, final text (actionlint clean). After the `land-protection.test.sh` step:

```yaml
      - name: accept-plugins.sh accepts exactly the plugins in examples/acme/Plugins, and every workflow accepts through it
        run: .github/scripts/accept-plugins.test.sh
```

After "Example workspace builds". The scorecard step is replaced and the toy accept becomes the script; the `scorecard` upload and `scorecard-comment` are unchanged:

```yaml
      - name: The go.mod differential runner builds, its pins and selftest pass, and its report is in the summary (no Go; a mismatch warns)
        shell: bash
        run: |
          lake --dir eval/diff build
          eval/diff/check-pins.sh
          eval/diff/selftest.sh
          status=0
          lake --dir eval/diff exe mitos-diff eval/diff > "$RUNNER_TEMP/diff.md" || status=$?
          { echo '### Differential run (go.mod, vendored outputs)'; cat "$RUNNER_TEMP/diff.md"; } >> "$GITHUB_STEP_SUMMARY"
          case $status in
            0) ;;
            1) echo "::warning::untriaged mismatch or stale line in eval/diff/triage.tsv; the nightly diff job fails on it" ;;
            *) cat "$RUNNER_TEMP/diff.md"; echo "::error::mitos-diff could not read eval/diff (exit $status)"; exit "$status" ;;
          esac

      - name: Every mutant case prepares as its manifest says, and a case claims every Challenge theorem (mitos-mutants --prepare)
        run: |
          lake --dir eval/mutants build
          lake --dir eval/mutants exe mitos-mutants --prepare "$RUNNER_TEMP/mutants"

      - name: Scorecard on every fixture (precision and recall per edge type against hand labels)
        shell: bash
        run: |
          lake --dir eval/score build
          : > "$RUNNER_TEMP/scorecard.md"
          for f in eval/fixtures/*/; do
            lake --dir eval/score exe mitos-score "${f%/}" >> "$RUNNER_TEMP/scorecard.md"
            echo >> "$RUNNER_TEMP/scorecard.md"
          done
          cat "$RUNNER_TEMP/scorecard.md"
          cat "$RUNNER_TEMP/scorecard.md" >> "$GITHUB_STEP_SUMMARY"
```

```yaml
      - name: Every plugin in examples/acme/Plugins is accepted (gates 0-6, independent kernels), and its committed record is the one the gate writes
        run: .github/scripts/accept-plugins.sh --record
```

`nightly.yml`, job `full`, final text apart from the baseline fetch (C1). The job gains a `permissions:` block under `runs-on`:

```yaml
    permissions:
      contents: read
      actions: read
```

Its steps:

```yaml
      - run: cd examples/acme && lake build
      - name: Every plugin in examples/acme/Plugins is accepted, and its committed record is the one the gate writes
        run: .github/scripts/accept-plugins.sh --record
      - run: lake exe mitos-gate cheats --jobs 4

      - name: Build the mutant runner
        if: ${{ !cancelled() }}
        run: lake --dir eval/mutants build

      - name: Mutation testing (paranoid)
        if: ${{ !cancelled() }}
        shell: bash
        # body unchanged

      - name: The numbers of main's newest nightly that has them, as the scorecard's baseline
        if: ${{ !cancelled() }}
        env:
          GH_TOKEN: ${{ github.token }}
        # C1 fetch, contract only

      - name: Scorecard of every fixture, its diff against main's numbers, and the most derivations any repo-level edge has
        if: ${{ !cancelled() }}
        shell: bash
        run: |
          lake --dir eval/score build
          base=()
          if [ -f "$RUNNER_TEMP/base/numbers.tsv" ]; then base=("$RUNNER_TEMP/base/numbers.tsv"); fi
          status=0
          lake --dir eval/score exe mitos-score --all eval/fixtures "${base[@]}" > "$RUNNER_TEMP/scorecard.md" || status=$?
          cat "$RUNNER_TEMP/scorecard.md" >> "$GITHUB_STEP_SUMMARY"
          [ "$status" -eq 0 ] || exit "$status"
          lake --dir eval/score exe mitos-score --numbers eval/fixtures > "$RUNNER_TEMP/numbers.part"
          mkdir -p "$RUNNER_TEMP/numbers"
          mv "$RUNNER_TEMP/numbers.part" "$RUNNER_TEMP/numbers/numbers.tsv"
          n=$(sed -n '/^Most derivations any repo-level edge has: /{s/^Most derivations any repo-level edge has: \([0-9][0-9]*\), .*/\1/p;q;}' "$RUNNER_TEMP/scorecard.md")
          if [ -n "$n" ]; then
            echo "Most derivations any repo-level edge has: $n"
            if grep -q '^\*\*Above [0-9][0-9]*: D1 reopens ' "$RUNNER_TEMP/scorecard.md"; then
              echo "::warning::a repo-level edge has $n derivations, above D1's threshold, so D1 is the owner's to reopen (plan/phase-2.md, Scope decisions)"
            fi
          elif ! grep -Fqx 'No fixture has a repo-level edge, so no derivations were counted.' "$RUNNER_TEMP/scorecard.md"; then
            echo "::error::the scorecard has no line that starts 'Most derivations any repo-level edge has: <n>, ', so this step and mitos-score --all disagree on its format"
            exit 1
          fi

      - if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: scorecard
          path: ${{ runner.temp }}/scorecard.md
          if-no-files-found: error

      - if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: scorecard-numbers
          path: ${{ runner.temp }}/numbers/numbers.tsv
          if-no-files-found: ignore
```

The `# body unchanged` and `# C1 fetch, contract only` lines above only mark an elision and the one step that is not final; the workflow gets no comment. The scorecard step holds no threshold: P2-010's `d1Threshold` decides its bold line, and the step's `::warning::` follows that line, so 8 lives in one place. The number never fails the step (O7). The step fails on a scorer error, which keeps P2-010's exit code, and when the report has neither the D1 line nor the no-edge line (C1, F23). `numbers.tsv` is moved into place only after `--all` and `--numbers` both exit 0, so a broken run uploads no baseline (P2-010's W11). With a stub `run` in the fetch step, this text passed `actionlint -shellcheck=shellcheck` (round 2).

`nightly.yml`, new job `diff`, placed after `full`. Final text (actionlint clean; each command ran in scratch):

```yaml
  diff:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: ./.github/actions/setup
        with:
          cache: "false"

      - name: Go from eval/diff/.go-version (SHA256 pinned in install-go.sh, retried)
        run: .github/scripts/install-go.sh

      - name: The pins match their bytes, sum.golang.org and the reviewed licence sources
        run: eval/diff/check-pins.sh --online

      - name: Build eval/diff and run its selftest
        run: |
          lake --dir eval/diff build
          eval/diff/selftest.sh

      - name: Go rewrites the vendored outputs, then the differential run compares them with the plugin
        shell: bash
        run: |
          status=0
          lake --dir eval/diff exe mitos-diff eval/diff --refresh > "$RUNNER_TEMP/diff.md" || status=$?
          { echo '### Differential run (go.mod, refreshed with Go)'; cat "$RUNNER_TEMP/diff.md"; } >> "$GITHUB_STEP_SUMMARY"
          exit "$status"

      - name: Go printed the vendored bytes (the refresh left the tree clean)
        if: ${{ !cancelled() }}
        run: |
          moved=$(git status --porcelain --untracked-files=all -- eval/diff)
          if [ -n "$moved" ]; then
            printf '%s\n' "$moved"
            git diff --stat -- eval/diff
            echo "::error::Go $(cat eval/diff/.go-version) does not print the vendored module.json bytes"
            exit 1
          fi

      - if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: diff-report
          path: ${{ runner.temp }}/diff.md
          if-no-files-found: ignore
```

`cache: "false"` is deliberate. The setup action saves its cache under `lean-<hash>-<sha>`. If this short job saved first, its small `.lake`, with no gate build, would win the key that `full` and the next PRs restore. That is the reason `ci.yml` lets only `checks` save.

`nightly.yml`, job `canary`. In the `trap` block, `.github/scripts/accept-plugins.sh --no-record` replaces the two-line toy accept. No record is checked, because the toolchain differs.

C1, the nightly scorecard, as `tasks/P2-010-nightly-scorecard.md` hands it over (its Usage, exit codes and deferrals). Build depth, except the baseline fetch:
- **Commands.** `lake --dir eval/score exe mitos-score --all eval/fixtures [<baseline>]` prints the report. `lake --dir eval/score exe mitos-score --numbers eval/fixtures` prints the lines that a later run reads as `<baseline>`. Both run from the repository root, with no network and no Go.
- **Exit codes, as P2-010 sets them.**
  - `--all`: 0 when every fixture scored; 1 when one did not, with the whole report printed; 1 with nothing printed when the baseline has a line of an unknown kind or the wrong field count; 2 on bad usage.
  - `--numbers`: 0, or 1 with nothing on stdout.
  - The numbers never change either code (P2-010's D6). The step exits with any non-zero code, because a scorer error fails the run (`docs/process.md:190`), and it adds none for a number (O7).
- **The D1 line.** Before any card (P2-010's D7), the report holds exactly one of these two lines, byte for byte as P2-010's `summary` prints them:
  - ``Most derivations any repo-level edge has: <n>, <edge> in fixture `<name>`. D1 reopens above 8.``, with ``, which that fixture's card leaves out`` before `. D1 reopens above 8.` when that edge is not in the card;
  - `No fixture has a repo-level edge, so no derivations were counted.`

  Above the threshold, a later line reads ``**Above 8: D1 reopens (`plan/phase-2.md`, Scope decisions).**``. P2-010's pins G6 to G8 hold the D1 line from `has: <n>, ` on and the bold line's start, `**Above 8: D1 reopens`. No pin of P2-010 holds the words before `has:` or the no-edge line, so F23 holds them.
- **How the step reads it.** It takes the first line that starts with the stable prefix `Most derivations any repo-level edge has: `, and reads `<n>` as the digits between the prefix and the next `, `. It prints `<n>` in its log. When a line starts with `**Above <digits>: D1 reopens `, it adds a `::warning::`. It fails only when the report has neither the D1 line nor the no-edge line, because then this step and `mitos-score --all` disagree on the format (F23). It does not compare `<n>` with 8 itself, so the threshold lives only in P2-010's `d1Threshold`.
- **Artifacts.** `scorecard` holds the report, `scorecard.md`. `scorecard-numbers` holds `numbers.tsv`, which is written only when `--all` and `--numbers` both exit 0.
- **The baseline, shape (b).** This is the root's default, which answers #160 item 3 and which P2-010 states the same way (its owner_decisions and Q-a). This row owns the fetch, and the owner can overrule the default.
  - It is the `numbers.tsv` of `main`'s newest nightly that uploaded `scorecard-numbers`, placed at `$RUNNER_TEMP/base/numbers.tsv` before the scorecard step. The step passes it only when that file exists.
  - With none, the report says `No baseline given, so nothing was compared.` That happens on the first night (P2-010's R4) and on F22's branch dispatch, which runs before `main` has any.
  - Shape (a) is out. A numbers file committed in the tree would have to be rewritten by every PR that moves a number, as a record is (R2). A baseline computed from `main`'s tree would compare a scheduled nightly, which runs on `main`, with itself. The night before's numbers need neither, and they show what changed since.
- **The fetch step, contract only.**
  - Permission: `full` gets `actions: read` beside `contents: read`, and nothing else. The step gets `GH_TOKEN: ${{ github.token }}`.
  - Source: a run of `nightly.yml` on `main` in this repository, other than this run, taken newest first, whose `scorecard-numbers` artifact has not expired. It is never an artifact found by name alone. A pull request's run can upload an artifact under any name, and the artifact route does not say which workflow uploaded it: its `workflow_run` holds only `id`, `repository_id`, `head_repository_id`, `head_branch` and `head_sha` (read on 2026-11-16).
  - Choose by the artifact, not by `gh run list --status success`. Two of the three newest scheduled nightlies on `main` concluded `failure` (read on 2026-11-16), and a success filter would skip their numbers.
  - Output: that run's `numbers.tsv` at `$RUNNER_TEMP/base/numbers.tsv`, or no file when no such run has one. A missing artifact is not an error.
  - Failure: an API error fails the fetch step. The scorecard step still runs under `!cancelled()` and says that it compared nothing.
  - Proof before the first push: the builder runs the fetch's commands against the real API with the artifact name `mutant-logs`, which `full` uploads on `main` today, and records which run they picked. F22 then shows the no-baseline path.
- **Anything else stops the builder (S7):** a write permission, a secret, another host, or a change in P2-010's build to a line or an exit code that C1 reads.
- **Still open:**
  - The fetch's exact commands, and how many runs it reads before it gives up.
  - The PR scorecard. P2-010's deferrals let `ci.yml`'s step switch to `--all eval/fixtures`. That would post the summary and the D1 line on every PR, and run `Nightly.checked` there. The loop above stays until the re-check after #212 merges decides, so the toy card keeps its bytes; the PR comment adds every other card and a blank line after each (F19).

statements:
- `Mutants.mem_unbroken`: a theorem is unbroken exactly when it is listed and its `breakers` is empty. Through `Mutants.mem_breakers`, `breakers` counts only a refuted case with `breaks=` and no `rejects=`.
- `Mutants.mem_claimed` and `Mutants.mem_unclaimed`: a theorem is unclaimed exactly when no prepared case with `breaks=` and no `rejects=` names it.
- `Mutants.runPasses_corpus`: a judged run of every case passes iff `passes` holds and every Challenge theorem has a breaker (#107 item 3).
- `Mutants.runPasses_named`: a run of named cases passes iff `passes` holds, as today.
- `Mutants.prep_ok_iff`: a case prepares cleanly exactly when its manifest says `rejects=lint` if and only if the lint refused it (#107 item 2).
- `Mutants.prep_written_iff`: workspaces are written exactly when the manifest does not expect the lint and the lint found nothing.
- Shell invariants, each pinned by the fixtures named:
  - I1. CI, `full` and the canary accept exactly the plugins in `Plugins/`, each with `--paranoid`, through one list (A1, A4, A10).
  - I2. With `--record`, every committed record equals what the gate writes, and the gate leaves no uncommitted file (A2, A3, A5, A6).
  - I3. Every new PR step is in `checks`, the job `prove` needs (F21).
  - I4. Every night the vendored outputs are Go's, and the pins match sum.golang.org (F17, F18).
  - I5. Go is installed only from an archive whose SHA256 the repository pins (F16).
  - I6. Every fixture directory is scored (F19).
  - I7. No scorecard number fails the nightly, the D1 number included. A scorer error fails it, and so does a report whose D1 line the step cannot read (F23, O7).

reuse:
- From the gate: `mitos-gate accept --record` (`Accept.writeRecord`, which writes by temp file and rename).
- From the mutant runner: `prepare`, `writeWorkspaces`, `Mutants.breakers`, `mem_breakers`, `passes`, `Mutant`, `Stage`, and `readApproved`'s `theorems`.
- From `eval/diff`, exactly as P2-008's Usage names them: `check-pins.sh` (offline and `--online`), `selftest.sh`, `mitos-diff` and `--refresh`, and `.go-version`.
- From the scorer: `mitos-score <fixture-dir>`, and P2-010's `--all` and `--numbers` (C1).
- From the workflows: `.github/actions/setup` and its `cache` input, `install-elan.sh`'s download, check and retry pattern, `cancel-superseded.test.sh`'s stub style, the `status=0 … || status=$?` pattern of "Mutation testing (paranoid)", and `$GITHUB_STEP_SUMMARY`.

fixtures: To run one workflow step locally (A's harness):

```
step() { python3 -I -c 'import sys,yaml; w=yaml.safe_load(open(sys.argv[1])); print(next(s["run"] for j in w["jobs"].values() for s in j["steps"] if s.get("name","").startswith(sys.argv[2])))' "$1" "$2"; }
RUNNER_TEMP=$(mktemp -d) GITHUB_STEP_SUMMARY=/dev/null bash -eo pipefail <(step .github/workflows/ci.yml 'Every mutant case')
```

Run the fixtures at the head, and the variants in a scratch worktree of the head. The historical results marked "judge" were measured at `eac85d2`. F2 separately identifies its earlier anchor and the independent verifier's current-anchor run at `4857ba7`.
- F1 `prepare-corpus`: `--prepare` with no case named exits 0. At the implementation base it must write 57 cases (114 workspaces) and print 15 `refused by the lint, as its manifest says`; measure peak RSS again. The earlier design run wrote 29 cases in 28 s.
- F2 `prepare-moved-anchor`: add a space inside `edges := rows.flatMap Prod.fst` in `core/Mitos/Impl/Resolve.lean`. Exit 1, including `edges_duplicated: … does not occur exactly once`; `bound_edges_duplicated` still claims `resolve_edges_nodup`, so no unclaimed-theorem diagnostic for it is expected. The [independent verifier's run at `4857ba7`](https://github.com/kitimark/mitos/pull/554#issuecomment-7069062704) reported exit 1 with `the text to find does not occur exactly once` and no coverage line. The historical `eac85d2` judge result used the earlier `edges := fs.flatMap fun r =>` variant; the current anchor was added in `a717614`. This pins #107 item 2.
- F3 `prepare-lint-gone`: set `cheat_impl_macro`'s `replace=` to `def mitosNoop : Nat := 0 end Mitos.Impl`. Exit 1: `its manifest says rejects=lint, and the lint finds nothing` (judge).
- F4 `prepare-lint-unexpected`: delete `rejects=lint` from `cheat_impl_macro`. Exit 1, with its three `lint:` lines (judge).
- F5 `prepare-unclaimed`: move both `impact_repeats_repo` and `impact_through_bypasses_seen` out, or add `rejects=refutation` to both. The older 44-case fixture needed only the first case. Exit 1: `impact_nodup: no case with breaks= and no rejects= names this theorem` (judge, both variants).
- F6 `prepare-stray`: add `eval/mutants/cases/stray.txt`. Exit 1: `stray.txt: no such case directory` (judge).
- F7 `prepare-named`: `--prepare <dir> edges_duplicated cheat_impl_macro cheat_hide_gap` exits 0, with no coverage line (judge).
- F8 `prepare-spec-shape`: parenthesize one Challenge statement's type in `core/Challenge/Resolver.lean`. `--prepare` exits 2 (#107 item 12, now on PRs).
- F9 `unbroken-named`: `mitos-mutants edges_duplicated` exits 0 with no UNBROKEN section (judge, 43 s).
- F10 `unbroken-corpus`: reduce `cases/` to `edges_duplicated` and run with no case named. Exit 1; UNBROKEN lists the other 11 theorems (judge, 33 s).
- F11 `accept-script`: `accept-plugins.test.sh` passes A1 to A10 (judge).
- F12 `records-head`: `accept-plugins.sh --record` at the head prints two `VERDICT: ACCEPTED`, and `git status --porcelain examples/acme/accepted` is empty (after S1).
- F13 `record-stale-real`: in scratch, set `"paranoid": false` in `GoMod.json` and commit. The script exits 1, and its diff shows that line.
- F14 `diff-pr`: with no `go` on `PATH`, the PR diff step exits 0; the selftest prints 28 `ok` lines (judge).
- F15 `diff-pr-paths`: remove the last `triage.tsv` line: exit 0 with the `::warning::`. Remove `cases/zap/module.json`: exit 2, red (judge).
- F16 `install-go`: a real run puts `go1.24.7` on `GITHUB_PATH` (judge, 7.8 s). A scratch copy with one hex digit of the hash changed fails `sha256sum -c` and extracts nothing. A scratch `.go-version` of `1.25.0` fails closed before any download.
- F17 `pins-online`: `check-pins.sh --online` exits 0 (judge, 6 s). In scratch, change one `module.mod` byte and recompute its `pins.tsv` hash: `--online` is red.
- F18 `diff-nightly`: with Go 1.24.7, `--refresh` exits 0 and the tree stays clean (judge). After a committed whitespace edit of `cases/zap/module.json`, the plain run exits 0, the refresh exits 0, and the clean-tree step is red on ` M eval/diff/cases/zap/module.json` (judge).
- F19 `scorecard-pr`: the loop prints one card per fixture, `gomod` then `toy` (judge), and the `toy` card is byte-identical to `main`'s. A scratch fixture directory with no `labels.tsv` makes the step red.
- F20 `lint-workflows`: `actionlint -shellcheck=shellcheck .github/workflows/ci.yml .github/workflows/nightly.yml` prints nothing (judge).
- F21 `existing-tests`: `cheat-shard`, `cache-logs`, `ci-trust`, `cancel-superseded` and `land-protection` `.test.sh` pass on the edited workflows (judge).
- F22 `nightly-dispatch`: `gh api -X POST repos/{owner}/{repo}/actions/workflows/nightly.yml/dispatches -f ref=<branch>`. Expected:
  - `full` is green: both accepts pass, mutation testing reads "all N cases as expected" with no `none` row and no UNBROKEN section, and the scorecard step follows C1. Its log prints `Most derivations any repo-level edge has: <n>`, its summary says `No baseline given, so nothing was compared.` because `main` has no `scorecard-numbers` yet, and `scorecard` and `scorecard-numbers` are uploaded.
  - `diff` is green, with the report in its summary.
  - The canary's result is reported. A canary failure on an rc is an early warning, not a blocker.
- F23 `scorecard-d1-line`, the check that this step and P2-010 still agree. At the head, after #212 merges, run the scorecard step with `eval/fixtures` in its text replaced by each root below. The `d1-8` and `d1-9` roots are P2-010's N7; the others are built the same way, in scratch:

  ```
  s=$(mktemp -d); RUNNER_TEMP=$s GITHUB_STEP_SUMMARY=$s/summary bash -eo pipefail -c "$(step .github/workflows/nightly.yml 'Scorecard of every fixture' | sed "s#eval/fixtures#$root#g")"
  ```

  - `eval/fixtures`: exit 0. The log prints `Most derivations any repo-level edge has: 2` (at least 2 once `chain` joins, P2-010's N13), with no `::warning::`, and `numbers/numbers.tsv` holds the `--numbers` lines (27 for `gomod` and `toy`).
  - The same root with its own `numbers.tsv` at `$s/base/numbers.tsv`: exit 0, and `No change against the baseline.`
  - `d1-8`: exit 0, `… has: 8`, no `::warning::`.
  - `d1-9`: exit 0, `… has: 9`, the `::warning::`, and the bold line in the summary. A number never fails the step (O7).
  - One fixture with an empty `labels.tsv` and only `repos/a/PROVIDES`: exit 0, and the summary has P2-010's no-edge line.
  - Scorer errors: a fixture with no `labels.tsv` exits 1 and leaves no `numbers.tsv`. A baseline line of the unknown kind `bogus` exits 1 with `baseline line 1: unknown line kind "bogus"`.
  - Drift: in scratch, change `Most derivations any repo-level edge has:` in `Score/Nightly.lean` to `Most derivations one repo-level edge has:`. P2-010's G6 still passes, because it matches from `has:` on. The step exits 1 with `::error::the scorecard has no line that starts 'Most derivations any repo-level edge has: <n>, ', …`. A rewording that also moves `has:` fails P2-010's own build at G6.
  - Round 2 ran every case above at `eac85d2`, with P2-010's `types` text built in scratch, and got these results. The step as it stood at `45c541d` read the line `most derivations per repo-level edge: <n>`. That build never prints it, so that step would have exited 1 every night.
- PR CI at the head: `checks` and `gate` are green. The PR body records each new step's time and the `checks` wall time.

cut_line: ships:
- In `ci.yml`: the script-run accepts of every plugin with the record check; the `eval/diff` step; `--prepare` of every case with static coverage; the scorecard of every fixture; and the accept test.
- In `nightly.yml`: the script in `full` and in the canary; #107 item 4; the `diff` job; and the baseline fetch and the scorecard step with its two artifacts (C1), which reports the D1 number and never fails on it (O7).
- In the runner: the `prep` rule (#107 item 2) and both coverage checks (#107 item 3).

It leaves out:
- the `docs/process.md` rows (O2);
- the canary gaps (O6);
- a scorecard post with a write permission (O3);
- the deferrals below.

If P2-010 slips, nothing is cut: this row waits for it (W7).

deferrals:
- From P2-001a and P2-005a: #107 items 2 and 3, done here.
- From #107:
  - Items 2, 3 and 4 are done.
  - Item 5 has nothing left on `main`.
  - Round-10 item 8 and #175's last bullet ("PR CI never builds `eval/mutants`") are closed by the `--prepare` step.
  - Items 6 to 12 stay in #107. Item 11, a per-run limit in `judge` and `timeout-minutes` on `full`, is not this row's.
  - The PR says `Part of #107`.
- From #33, #275 item 1, P2-007 R1 and P2-001b: the record check. The PR says `Closes #33` and `Part of #275`.
- From P2-006 and P2-007: GoMod in CI, in `full` and in the canary.
- From P2-008:
  - The nightly refresh and run are the `diff` job.
  - The CI build is the PR step (its R1).
  - "Does the nightly fail on exit 2": yes, on any non-zero exit.
  - The docs row goes to O2.
  - `.coderabbit.yaml`'s `!eval/diff/cases/**` filter stays with the root, outside this cell.
- From P2-005b: decide PR prepare sharding using a fresh 72-case memory run after the environment/cache lifetime fixes.
- From P2-009b: the go.mod scorecard, in the PR loop now and nightly through C1. Its docs wording goes to O2.
- From P2-011: "CI never builds `eval/mutants`" is done. The canary gaps go to O6.
- From #158: nothing (#304).
- From P2-010 (#212): the nightly run, its artifacts, the baseline download and the post (P2-010's cut_line), all in C1. Whether the PR scorecard switches to `--all` stays open (C1).
- To P2-011 PR B (#147): its re-recorded records must pass the accept step. They are already in its touches.
- To one `follow-up` issue the PR owner files, no row (all minor):
  - Cache `eval/mutants/.lake`, `eval/diff/.lake` and `examples/acme/.lake` in `checks` (about 1 to 2 min of cold builds per PR). This goes through the cache paths and `cache-logs.test.sh`.
  - Triage hygiene, as a `Diff.Triage` rule in `eval/diff/` (one reader of `triage.tsv`): a triage line cites an open `follow-up` issue, and an `only-in-plugin` line is refused.
  - A Go refresh on PRs that touch `eval/diff/` would catch X9 before merge, at the cost of network access on PRs.
  - The canary rewrites three of the five `lean-toolchain` files (it misses `eval/diff` and `eval/score`). That is harmless until O6 adds their builds.
- To the Phase 3 row that adds an acme plugin: one line in `PLUGINS`.

owner_decisions:
- **Settled by the plan:**
  - one `.github` PR, which the owner merges;
  - differential tests are nightly evaluation, not a gate;
  - GoMod is accepted with `--paranoid` in CI (criterion 4);
  - refresh, then run;
  - #107 items 4 and 5, #158 and #33 may ride along;
  - D1 reopens when a repo-level edge has more than 8 derivations;
  - the scorecard's numbers never fail a run, and a scorer error does (`docs/process.md:190`, the owner's rule; O7);
  - P2-012 lands last.
- **O1, the Owns cell.**
  - The cell gains `.github/scripts/accept-plugins.sh`, `accept-plugins.test.sh` and `install-go.sh`; the appended block in `eval/mutants/Mutants/Verdict.lean`; and "the lines of `eval/mutants/Main.lean` that #107 items 2 and 3 need" (it said item 3).
  - Root default: extend it, for the reasons under Rationale. The build starts once the owner has made the plan edit (S0).
  - If the owner keeps the cell, the root has this design amended to the in-cell shapes under Alternatives before anyone builds.
- **O2, `docs/process.md`.** "What runs where" and the paragraph at `:492-494` go stale.
  - Root default: the PR body carries the row text below, and the root has a PR owner open a docs-only PR beside it for the owner. Alternative: widen this row's cell by that section.
  - Rows:
    - Honest plugin accepted, gates 0–6: `.github/scripts/accept-plugins.sh --record` (every plugin in `examples/acme/Plugins/`; each committed record is what `accept --record` writes) | ✓ | ✓ | ✓ | yes.
    - Fixture scorecard: `mitos-score` on every directory of `eval/fixtures/`.
    - Full evaluation scorecard: `lake --dir eval/score exe mitos-score --all eval/fixtures [<baseline>]`, with `<baseline>` the `--numbers` lines of `main`'s newest nightly (C1); nightly; the numbers no, the D1 number included; a scorer error yes.
    - Differential tests against real tools: `lake --dir eval/diff exe mitos-diff eval/diff`. On PRs the build, `check-pins.sh` and `selftest.sh` block, and the comparison warns. Nightly: `--refresh` with Go from `.go-version` and `check-pins.sh --online`.
    - Mutation testing: `mitos-mutants --prepare <dir>` on PRs, which blocks; `mitos-mutants --paranoid` nightly.
- **O3, where the nightly scorecard goes.**
  - Root default: the run's job summary and the `scorecard` artifact (C1). This needs no write permission and sends no message.
  - Alternative: one bot comment, edited in place, on a "Nightly scorecard" issue. That is a design amendment with these properties:
    - one job with `issues: write` only, which builds nothing;
    - it runs on `main` or for a named test issue;
    - it edits only the bot's own comment, found by a marker;
    - it refuses a body over 60000 bytes;
    - the first run creates the issue.
- **O4, static coverage on PRs.** Every spec PR that adds a Challenge theorem must carry a case that claims it. Root default: yes. It moves the item-3 failure from the next nightly to the PR that adds the theorem, at no extra run time.
- **O5, the PR-time comparison.**
  - Root default: exit 1 warns and exit 2 or more is red. This follows the plan: evaluation is not a gate, but an unreadable `eval/diff` is a broken build.
  - Alternatives: block on exit 1 too, or do not compare on PRs at all.
- **O6, P2-011's canary gaps** (`lock --check`, `mitos-lint-test`, the `eval/score` and `eval/diff` builds, every `lean-toolchain`). Root default: not in this PR, because P2-011 hands them over only "if the owner adds them".
- **O7, D1 above 8 in the nightly.** The owner's question: should a repo-level edge with more than 8 derivations turn the nightly red?
  - Root default, not the owner's ruling: no. The nightly reports the number and never fails on it. `docs/process.md:190` says the scorecard's numbers never fail a run and a scorer error does, and P2-010's D6 keeps the D1 line out of the exit code.
    - The summary shows P2-010's D1 line and, above 8, its bold line. The step prints the number in its log and adds a `::warning::` to the run when the bold line is there (C1).
    - Nobody is paged. The owner sees the bold line and the warning on the nightly's page, and reopening D1 stays the owner's reading (plan, Scope decisions).
    - The step still fails on a scorer error, and when the report has neither the D1 line nor the no-edge line. That is a broken contract between this step and `mitos-score --all`, not a number (F23).
  - A red threshold would change the rule in `docs/process.md`, which the owner keeps. If the owner chose it:
    - an owner PR beside this one gives `docs/process.md`'s scorecard rule an exception for the D1 number, and O2's "Full evaluation scorecard" row says "fails above 8 derivations";
    - the step's `::warning::` becomes an `::error::` and `exit 1`, after the summary and `numbers.tsv` are written, so the report still shows (P2-010's D6 reason), and F23's `d1-9` case expects exit 1;
    - a red nightly is a failure no PR owns, so it goes to a researcher (kitimark-mode, "The root orchestrates"), and a D1 reopening becomes root work instead of a line the owner reads;
    - P2-010 needs no change, because its exit code stays a scorer's.
- **Root defaults, not owner rulings,** each with its reason under Rationale. An owner answer replaces any of them:
  - every PR runs the new steps, with no path filter;
  - one accept script;
  - Go from a pinned archive, not `actions/setup-go`;
  - `diff` is its own job, without a cache save;
  - `!cancelled()` only on evaluation steps;
  - the `checks` timeout stays at 20 unless S6 applies;
  - the Go refresh and the online pins run nightly only.

### Risks and stop conditions

Risks:
- **R1, wall time.** `checks` grows from 4.3 min to about 9 min warm. This is an estimate:
  - the GoMod accept, about 2.5 min;
  - the mutants build (cold, 0.5 to 1.4 min) and `--prepare` (about 0.5 min);
  - `eval/diff`, about 0.3 min.

  `checks` then becomes the critical path, ahead of the 3 to 5 min shards, so `gate` goes from about 6 to about 10 min per push.
- **R2, records and rebases.** No rebase regenerates records (plan, Shared files 1). Every core, model, plugin or toolchain PR, and every PR that an updater rebase leaves stale, is red until its owner re-records at the head. That is the purpose of the check, but it costs those owners about 3 min.
- **R3, memory.** The design measured 9.3 GB at 44 cases; P2-005b reported 10.8 GB at 72, and a verifier was killed (137). Main has since fixed retained imported environments and lookup caches (#536/#540). Re-measure at 72 cases before accepting one full-corpus PR step. Keep one process if it fits the runner; a failure must not be hidden by sharding named cases, which would skip corpus coverage.
- **R4, the nightly network.** `diff` reaches go.dev, sum.golang.org and raw.githubusercontent.com, each with retries. An outage turns `diff` red, which is evaluation, never a PR gate.
- **R5, coverage binds spec PRs.** O4 means a theorem costs a mutant case. On a corpus that passes, `unbroken ⊆ unclaimed`, so the nightly's item-3 failure fires on its own only when the nightly and the PR saw different corpora.
- **R6, the canary.** On an rc it can now fail on GoMod's proofs. That is an early warning, as intended.

Stop conditions for the builder:
- **S0, resolved for this implementation.** The user explicitly requested implementation of #213; that authorizes this task's concrete design scope. The stale Owns-cell prerequisite is superseded for this request; plan/ remains unchanged.
- **S1.** Before writing, after `git fetch origin main`, run `accept-plugins.sh --record` (a draft is enough) on a clean `origin/main` worktree. If it is red on a stale record (`GoMod.json` today), stop. P2-001b's merge re-records it; otherwise the root has a PR owner re-record it with the gate, never by hand, in its own small PR that an agent merges (`examples/acme/accepted/` is not a kept path). This PR never edits a record to get green.
- **S2.** `--prepare` of every case is red on clean `main` with the Lean edit, for a reason other than F2 to F6 (an invalid case, an unclaimed theorem): stop. It is a corpus or spec issue. Never relax the check or add a vacuous case.
- **S3.** The newest nightly, or one judged run of every case on `main`, shows a `none` row: stop. A mutant case comes first.
- **S4.** An edit falls outside `touches`, or a step, `--paranoid`, a lint expectation or an `if` that keeps a check running would be dropped or weakened: stop.
- **S5.** The Go archive's hash differs from the pinned value: stop. Never change the hash without a reviewed source.
- **S6.** `checks` runs over 15 min warm at the head: raise its `timeout-minutes` to 30 and `cheat-shard.test.sh`'s pin to `checks 30` in the same PR, and report it. Over 25 min: stop. The fallback is a parallel accept job, which changes `prove.needs` and `mitos-gate cheats aggregate` (`gate/`, the owner's).
- **S7.** C1's fetch needs anything besides `actions: read` and the source C1 names, or P2-010's build changed a line or an exit code that C1 reads (F23 fails): stop.
- **S8, done.** Stop when the PR is open on `main`, `gate` is green, F1 to F23 are done and every thread is answered. Report the head as waiting on the owner, who merges `.github/`.

## Done when
- [ ] all `checks` pass locally; F1 to F21 and F23 give the stated results; F22 passes on the branch; `gate` is green at the head
- [ ] `lake --dir eval/mutants build` shows no warning; no `sorry`; `#print axioms` of the seven statements shows standard axioms only
- [ ] `accept-plugins.sh --record` on the real tree leaves `git status --porcelain examples/acme/accepted` empty
- [ ] the PR says `Closes #213`, `Closes #33`, `Part of #107` and `Part of #275`, links its `follow-up` issue, and carries the O2 row text
- [ ] run-log record written (`ops/runs/<UTC date>/P2-012-builder-<attempt>.json`)

## Rationale

### Problem
Seven rows each left one line for this PR, and at each of them a green check can currently mean nothing:
- a record nothing reads (`GoMod.json` is stale on `main`);
- a `--prepare` that is red on arrival;
- a vendored directory Go never rewrites;
- a scorecard that skips a fixture;
- a theorem no mutant breaks.

The tools all exist on `main`. Two constraints shape the design:
- `--prepare` treats an expected lint refusal as a failure, so it cannot run over every case unless that rule changes.
- CI runs on the PR's merge ref, so a record check judges the merged tree.

The plan makes the differential run evaluation, so the PR side may block only on what is a broken build.

### Usage (caller's view)
- **A builder, before pushing a core, model, plugin or toolchain change:** `.github/scripts/accept-plugins.sh --record`, then commit any record it rewrote. Also `lake --dir eval/mutants exe mitos-mutants --prepare /tmp/m`, which covers every case and checks coverage; `--prepare /tmp/m <case>` checks the named cases only.
- **A PR author, in `checks`:**
  - one accept step that names a stale record and prints its diff;
  - one `--prepare` step that names the case that no longer applies, or the theorem nobody claims;
  - an `eval/diff` step that is red only when `eval/diff` cannot be read, and otherwise warns;
  - one scorecard per fixture in the PR comment.
- **The owner, each night:**
  - `full`: accepts, cheats, mutation testing with the UNBROKEN section, and the scorecard with its diff against the night before and the D1 line, which warns above 8 and never fails the run (O7);
  - `diff`: the Go refresh, the comparison and the clean tree;
  - the canary.
- **A Phase 3 builder adding a plugin:** one line in `PLUGINS`. The set check makes a plugin with no line fail.

### Shape
- **One list per concern, derived where it can be.**
  - Plugins: one array in a trusted script, checked against `Plugins/` and `accepted/`.
  - Cases: the runner's own `readDir`, as in the judged run; the CI step names none.
  - Fixtures: the directories of `eval/fixtures/`.
  - Theorems: the Challenge.
  - Go: `.go-version`, with a hash table that fails closed.
- **One reader per format.** The `rejects=lint` expectation is a `Prep` value computed from the parsed manifest (per red flag "Two ways to do one task"). Neither the shell nor a second script reads manifests or `triage.tsv`.
- **Meaning in types.** Whether a run covers the corpus is `Scope`, not a `Bool` (red flag "Meaning only in prose"). The four prepare outcomes are constructors, and each rule has a statement and `#guard`s.
- **Deep surfaces.**
  - `accept-plugins.sh --record` hides the list, the set check, `--paranoid` and the record check behind one call that all three workflow call sites use.
  - `--prepare <dir>` hides case discovery, the lint expectation and coverage.
- **Two levels of failure.** Evaluation steps take `!cancelled()`, so a red cheat corpus no longer skips them (#107 item 4); check steps keep the default. The differential evaluation sits in its own job, so its network and its downloaded binary stay out of `full`. That job has no persisted token and saves no cache.
- **`git status --porcelain --untracked-files=all`** beside `git diff --exit-code`, so an untracked record or output fails too.

### Tradeoffs accepted
- We accept about 4 more minutes per PR (R1) in exchange for no path filter in a trust workflow. The steps depend on `core/`, `gate/`, `eval/mutants/`, `eval/diff/`, the models, the plugins and the toolchain files, and a filter that misses one path is a silent hole. The row text says "PRs that touch `core/`", and this deviation is recorded below.
- We accept a cell extension (O1) in exchange for one plugin list instead of three, and one manifest reader instead of two.
- We accept a cold build of core and acme in the nightly `diff` job in exchange for keeping `full`'s cache key and its trust steps away from Go and the network.
- We accept that the nightly coverage failure is nearly redundant with the static check (R5), because it is the item-3 statement itself and costs nothing.
- We accept a PR-time comparison that only warns, as the plan demands, while the nightly fails on it.

### Alternatives considered
- **In-cell shapes**, the O1 fallback:
  - the plugin-to-model map inline in `ci.yml`, with a set guard, and one accept line per plugin in `full` and in the canary;
  - a shell split of `--prepare` into non-lint cases, which must exit 0, and `rejects=lint` cases, which must exit 1 with only `lint:` lines;
  - `actions/setup-go@924ae3a1cded613372ab5595356fb5720e22ba16` (v6.5.0) with `go-version-file`;
  - `unbroken` and `runPasses` in `Main.lean`.

  These are fail-closed and in the cell. They lost on the hand-synced plugin list (three places, one guarded), the second manifest reader, and a third-party download with no hash in the repository (P2-008's A3 was never verified).
- **Path-filtered PR steps:** fewer minutes, but a changed-path computation on a merge ref that must never miss. Lost on trust.
- **A parallel `accept` job:** it keeps `gate` near 6 min, but `prove` and `mitos-gate cheats aggregate` (`gate/`) would have to learn a third result. Held as the S6 fallback.
- **Differential steps in `full` with `!cancelled()`:** no cold build, but Go and the network would sit in the trust job, mixed into one red signal.
- **Plugins read from `accepted/*.json`:** no hand-kept list, but a PR would choose the model its plugin is judged against. Lost on trust.

### Where the plan row and `main` disagree
- The row says `--prepare` "on PRs that touch `core/`". This design runs it on every PR (Tradeoffs).
- The Owns cell names only the `Main.lean` lines that #107 item 3 needs. Item 2 needs `writeWorkspaces` too, and the design adds `Verdict.lean` and three scripts (O1).
- The row says "the nightly scorecard post". Where it posts is O3.
- The plan's Shared files 3 counts 42 cases; there are 44.
- `docs/process.md` still says "Phase 2" for the differential row and names only the toy fixture (O2).

### Open questions and risks
- Is about 10 min of `gate` per push acceptable, or should the parallel accept job (S6 fallback) come in this PR?
- Should spec PRs carry a claiming mutant case for each new theorem (O4)?
- Should the PR-time comparison block (O5), or should a PR that touches `eval/diff/` also refresh with Go?
- O1 to O3, O6 and O7 above.

### Next implementation step
Check S0, then run S1 and S3 on `main`. Apply the Verdict and Main text and run F1 to F10. Then add the three scripts and the workflow steps, and run F11 to F21 before the first push.

### Synthesis decision
Root's default, not the owner's ruling. **Design A (opus) is the base**, for its plan-faithful surface and for these pieces:
- It handles `docs/process.md` as an owner decision instead of an edit outside the cell (B edited the docs by default, an owner path its cell does not name).
- C1 is a contract with two permission shapes. Round 2 filled it from P2-010's task file with shape (b).
- Its owner decisions and stop conditions, the step harness, the record check with a printed diff, `!cancelled()` limited to evaluation steps, and every-PR steps with no path filter.

**Fixed in A:**
- Raising `checks` to 30 min would break `cheat-shard.test.sh`'s `checks 20` pin, which A's `must_not_touch` forbade editing. The timeout now stays unless S6 applies.
- The `Bool` `full` became `Scope`.
- The two `--prepare` calls and the shell's case list became one runner call.
- The plugin list in three places became one.

**Grafted from Design B (sonnet):**
- the single accept script with its test (A1 to A9, plus A10, the one-way check folded in from B's N10);
- the lint expectation in Lean (`Prep` and `prep_ok_iff`), now wired into `writeWorkspaces` and built, where B had left the wiring unbuilt;
- static coverage (`claimed` and `unclaimed`);
- the SHA256-pinned Go installer, without B's `GO_DL_BASE` and `GO_INSTALL_DIR` hooks;
- a separate nightly `diff` job with `persist-credentials: false` and `check-pins.sh --online`, with the cache save turned off to protect the shared key;
- B's attack table, trimmed to what ships.

**Rejected from B:**
- a blocking PR-time comparison by default (the plan makes it evaluation);
- the PR-time Go refresh and online pins (network on PRs; the nightly catches X9);
- `triage-issues.sh` and `score-fixtures.sh` (second readers of `triage.tsv` and of the scorer's output, and new rules for other rows' tools);
- `nightly-wiring.test.sh` beyond A10;
- the `issues: write` posting job as the default (a message surface the owner keeps; it is O3's alternative);
- canary parity by default (P2-011 hands it over only if the owner adds it).

**The judge's own work** settled the base and the grafts:
- built the final Lean (seven statements, standard axioms) and ran `--prepare` on the corpus at `eac85d2` with F2's earlier `edges := fs.flatMap fun r =>` anchor variant and the F3 to F7 variants;
- ran the named and one-case corpus judged runs;
- ran the real Go install, the online pins and the refresh, and caught the hand edit;
- ran the PR diff step's three exit paths and the scorecard loop;
- ran actionlint and the six workflow tests on the edited workflows.

## Implementation at 174d623

The dependencies have merged, including chain fixtures, the 72-case corpus and the nightly scorer.
The PR keeps per-fixture PR cards: the toy card keeps its bytes, while chain and gomod are added.
C1 uses a focused `nightly-baseline.sh` and stubbed API tests. It reads completed runs of
`nightly.yml` on main, excludes this run and other repositories, follows every run/artifact page,
and picks the newest unexpired numbers artifact regardless of run conclusion. There is no
arbitrary run-count cutoff. API errors and malformed archives fail; the final baseline appears
only after one regular root `numbers.tsv` member was read successfully. Scorer bytes pass through.
These two additional script boundaries and `gate/lake-no-cache-check.py`'s additional expected
Lake job are necessary integration deviations: the existing exact-job check would reject the
new nightly diff job. Every existing expected job and mutation check stays, and diff sets
`LAKE_NO_CACHE=1`. Newly introduced third-party action calls use resolved commit pins.

The old cache premise is historical: main now caches acme, score and mutant build trees too;
eval/diff remains cold. Package reuse and all environment/cache lifetime fixes in Main are kept.

Validation is in progress. Actionlint and shellcheck pass. Accept harness A1–A10 passes.
The baseline harness checks source selection, failed-run eligibility, pagination, absent/expired
artifacts, API errors and malformed/extra/duplicate/symlink archives. A separate independent
verifier exercised a true multi-page artifact stream. The Lake-cache check passes 7 jobs and
rejects 27 mutations. A11 now rejects an extra nonregular `.lean` plugin before any accept.
The CI prepare wrapper invokes the same command once, streams its output, preserves its status
(including 128 plus signal for a signal failure), and prints wall time and maximum child RSS.

Validation receipts for this attempt:
- Independent GPT verification passed at `7c6fc911707bcaf905a6aed57f57c6f9cb45ef26`, whose tree
  exactly matched the locally reviewed head: actionlint, shellcheck, acceptance/baseline tests,
  Lake-cache mutation checks, direct warningAsError Verdict build, seven standard-axiom reports,
  fourteen additional Lean behavior guards and D1 shell success/error/warning cases.
- `lake --dir eval/mutants build` succeeded (1050 jobs); diff and score builds succeeded (36
  and 1046 jobs). Main's existing Graph import warning is replayed; new runner code passes
  warningAsError. Initial linking failed because this host has no `/tmp`; retry with a scratch
  TMPDIR succeeded.
- Offline pins, all 28 differential selftests and the plain comparison passed. Real pinned
  Go 1.24.7 installation, online pins and refresh passed, leaving eval/diff clean. Scratch F15
  mismatch/unreadable cases returned 1/2, and F18's whitespace edit passed plain comparison
  before refresh restored the exact original bytes.
- PR cards and nightly `--all`/`--numbers` scored all three fixtures. D1 maximum is 2; no
  baseline was given. Plan-task and the 11 gate-suite inventory tests passed.
- The real GitHub workflow-list route returned 19 completed main nightlies. The helper's
  no-baseline path read all of them successfully through a public curl transport for `gh api`.
  A positive-selection scratch variant chose the newest night's mutant-logs artifact; that
  artifact was also downloaded successfully with the authenticated GitHub connector. This
  proves API selection and download separately; it is not a completed new nightly run.
- Production local `--prepare` exits 2 at the existing package-visibility sandbox probe:
  bubblewrap cannot create NETLINK_ROUTE on this host. A scratch #eval harness using the real
  leanCheck/writeWorkspaces calls but omitting that probe was killed (137) after 255 s while
  a source gate build also ran; maximum child RSS was 5,607,012 KiB. It is no success receipt
  and is not a production memory measurement. Hosted CI successfully prepared all cases at
  the first PR head; the final wrapper records production RSS before the sharding decision.
- S3's pre-existing corpus is verified by the successful 72-case judged run in
  https://github.com/kitimark/mitos/actions/runs/44892073901: 52 refuted, 0 gaps, 20 cheats.
  That receipt predates this PR's coverage reporting.
- Documentation follow-up is #553. Full local acceptance/judging cannot bypass the sandbox;
  hosted checks supply that evidence. F22 remains unavailable here because gh is unauthenticated,
  the browser is signed out and the connector exposes no workflow dispatch operation. No new
  nightly dispatch, required Claude/Opus verifier admission or owner merge is claimed.

The first hosted CI run at `7c6fc91` passed gate, prove and every shard. Its checks job took
8 min 50 s: differential 14 s, mutants build plus full preparation 93 s, three fixture cards
3 s, both paranoid record accepts 136 s. Its log has exactly 57 written cases, 15 expected
lint refusals and two ACCEPTED verdicts, with the record checks clean. No timeout increase
is needed. The final batch retains one full-corpus prepare and adds its RSS receipt.
