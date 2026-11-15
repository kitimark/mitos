# tasks/P1-013-claude-connector.md

phase: 1
goal: A Claude agent lands a pull request by repeating one call, `.claude/scripts/land.sh <pr>`, which does only what `mitos-gate land` answers; `bot-review.sh` counts a review that `carry` covers; and the monitor can stay quiet after a rebase.
statement: none locked (tooling task). PR 2 restates one gate statement, `Snapshot.OnlyTheOwnerQueues`, as `OnlyTheOwnerOrADelegateQueues` (under Design, statements)
touches: PR 1 (the cover rule): .claude/scripts/lib/main-tool.sh, .claude/scripts/main-tool.test.sh, .claude/scripts/carry.sh, .claude/scripts/carry.test.sh, .claude/scripts/bot-review.sh, .claude/scripts/bot-review.test.sh, .claude/scripts/sourced-bash.test.sh · PR 2 (the delegate): gate/MitosGate/Speech/Comment.lean, gate/MitosGate/Speech.lean, gate/MitosGate/Snapshot/Obs.lean, gate/MitosGate/Snapshot.lean, gate/snapshot-test.sh, gate/snapshot-fetch.sh only under revisit_when, and one case of .claude/scripts/land.test.sh if PR 3 merged first · PR 3 (`land`): .claude/scripts/lib/land-snapshot.sh, .claude/scripts/land.sh, .claude/scripts/land.test.sh, .claude/scripts/sourced-bash.test.sh · PR 4 (the wake rules): .claude/scripts/lib/wake.sh, .claude/scripts/watch-github.sh, .claude/scripts/watch-github.test.sh, and one sentence each of .claude/skills/kitimark-mode/SKILL.md and of the "Waiting on GitHub" row of docs/process.md (O6) · PRs 1, 3 and 4: their rows of .claude/README.md and of the check matrix in docs/process.md · each PR: this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/MitosGate/Land.lean, gate/MitosGate/LandCli.lean, gate/MitosGate/Shadow*, gate/MitosGate/Snapshot/Fixtures.lean, .github/, eval/cheats/, models, CLAUDE.md, .claude/hooks/, .cursor/, plan/, and the rest of .claude/skills/
checks: PRs 1, 3 and 4: shellcheck 0.11.0 -x on each new or changed script, each .claude/scripts/*.test.sh the PR adds or changes, gh-api-rest.test.sh, sourced-bash.test.sh, plan-tasks.test.sh, build (land.test.sh and watch-github.test.sh run the real mitos-gate) · PR 2: build, the axiom checks (standard axioms only), every gate/*-test.sh, mitos-lint-test, cheats (in ci)
budget: PR 1 8 iterations · 3h wall · 1M tokens; PR 2 6 iterations · 2h wall · 0.6M tokens; PR 3 10 iterations · 3h wall · 1.2M tokens; PR 4 12 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-013 in `plan/phase-1.md` (Land track), issue #192: step 4 of the land / auto-rebase
  migration, tracker #179. Proof it works: tests, and one real agent landing.
- The design: #178, comment 6821317899 (Decision 5: callers repeat one intent, `land`, until it
  answers `merged` or `stopped`; Decision 3: the wake table; the connector table: `merge`, `wake`
  as "two rules in `watch-github.sh`", `nudge`), its `covered` amendment 6832011164, and its
  auto-merge amendment 6890739593. The owner accepted the last one on 15 Nov (#179, typed comment
  6890996353, recorded in 6891010165) and asked that this row go on once it was accepted (#192,
  comment 6890023661).
- What the auto-merge amendment changes here is one line: "`land.sh` treats `present` on a kept
  path as nothing to do." `step` does not change. On a kept path the owner types `/land <commit>`
  and the land workflow merges. No Claude session calls a merge route for such a pull request,
  asked or not (#270, #271).
- Built before this row, all on `main`: step 1 (#198: `Land.lean`, `mitos-gate land`), step 2
  (#233, #244, #246: `Speech`, `Snapshot`, `mitos-gate speech` and `snapshot`,
  `gate/snapshot-fetch.sh`), step 3 (#260, #262: `land.yml`'s `decide`, `mitos-gate shadow`).
- Not built: the amendment's rows A1 to A4, which get their plan ids in the plan PR that adds this
  file, and steps 5 to 8. #278 (#245, the protection reader) is open.
- The plan PR that adds this file also removes `P1-013` from `.claude/scripts/plan-tasks.pending`,
  or `plan-tasks.test.sh` fails.
- P1-010 and P1-011 have no task file (both are in the pending list), so
  `tasks/P1-012-shadow-decide.md` is the shape this file follows.
- Design written at plan time: an arena of two runners, one on Claude Opus and one on Claude
  Fable, and a judge on Claude Fable. The base is the Opus runner's. "Synthesis decision" lists
  the grafts and the fixes, and "What was checked" lists the runs. Checked against `main` at
  a222e99. `main` moved to a7a666d while the judge ran; of the files this design reads, only three
  proof lines of `gate/MitosGate/ContentId.lean` changed.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build for PRs 1, 2 and 3 and for `lib/wake.sh`. Their sketches are below in full, and each
ran here (What was checked). Contract only for three parts: the `land:` line of
`watch-github.sh`; `gate/snapshot-fetch.sh` outside a workflow once #278 merges; and every line
that names A1 to A4.

revisit_when: three re-checks, each by the Architect.
- After #278 merges: main's protection outside a workflow (the contract below), and `land.sh`'s
  read-only run against the fetch that landed.
- After A1 merges: `land.sh` reads `.step` of the decision and, of its own pull request, `head`,
  `gate` and the fields of `as_read`. Check that they keep their names, and replace `as_read` by
  the tool's own "why an owner word does not stand". Also, once A1 has merged, PR 2's fixture for
  a bare `/land` on a kept path expects `.stop .noEntry`, not `.present hC`, because A1 reads that
  `/land` with `approves := false` and it is no entry. Its name becomes
  `bareOwnerLandOnAKeptPathIsNoEntryForTheOrchestrator`. If PR 2 is still open, it writes that
  value; if PR 2 merged first, A1 changes the fixture (P1-018, revisit_when). Either may merge
  first.
- After A2 merges, if PR 2 is still open: A2 edits `Speech/Comment.lean` and `Snapshot/Obs.lean`
  too.

modules: one topic per file (`.claude/skills/principle-split-by-topic/SKILL.md`). Line counts are
rough budgets; the sketched files are at their sketch's size.
- PR 1, the cover rule:
  - `.claude/scripts/lib/main-tool.sh`: main's tool, the `mitos-gate` built in a checkout of
    `origin/main` that the clone keeps, and when that build is fresh; 65 lines; copies
    `lib/origin-repo.sh` (a sourced function file with a bash shebang).
  - `.claude/scripts/main-tool.test.sh`: the library against a real scratch clone and a stub
    `lake`; 130 lines; copies `bot-review.test.sh` (a scratch repository, `ok` and `FAIL` lines).
  - `.claude/scripts/carry.sh`: whether one commit covers a pull request's head; 70 lines; copies
    `bot-review.sh` (usage header, `say` and `die`, an `api` wrapper under `timeout`, one answer
    line, exits 0, 1 and 2).
  - `.claude/scripts/carry.test.sh`: `carry.sh` against a stub `gh`, a stub gate and a local bare
    remote; 130 lines; copies `bot-review.test.sh`.
  - `.claude/scripts/bot-review.sh`: one more answer, `reviewed <head> (carried from <sha>)`, and
    one suffix, `; carry not checked: <why>`; 12 lines added.
  - `.claude/scripts/bot-review.test.sh`: its pull request gains a branch and a repository, and
    its environment a stub main tool whose `carry` answers "no carry", so the 46 cases of today
    keep their text; plus the cover cases; 90 lines added.
  - `.claude/scripts/sourced-bash.test.sh`: checks every `lib/*.sh` instead of naming
    `origin-repo.sh`, and follows `carry.sh` with `-x` (PR 3 adds `land.sh`).
- PR 2, the delegate:
  - `gate/MitosGate/Speech/Comment.lean`: `delegates` names `claude/orchestrator`; 1 line.
  - `gate/MitosGate/Speech.lean`: eight fixtures for the delegate, and one for the record
    `land.sh` posts; 35 lines added.
  - `gate/MitosGate/Snapshot/Obs.lean`: `OnlyTheOwnerOrADelegateQueues` replaces
    `OnlyTheOwnerQueues`; 10 lines changed.
  - `gate/MitosGate/Snapshot.lean`: the axiom-check list names the new theorem.
  - `gate/snapshot-test.sh`: one case steps as an undelegated teammate; two cases added.
- PR 3, `land`:
  - `.claude/scripts/lib/land-snapshot.sh`: one landing snapshot taken with main's tool; 14
    lines; copies `lib/origin-repo.sh`.
  - `.claude/scripts/land.sh`: one step of `land` for one pull request, and its one write; 197
    lines; copies `bot-review.sh`.
  - `.claude/scripts/land.test.sh`: `land.sh` against a stub `gh`, a stub fetch and snapshot, and
    the real `mitos-gate land` and `speech`; 320 lines; copies
    `.github/scripts/land-decide.test.sh` (`lake build mitos-gate`, a gate wrapper whose
    `snapshot` prints a file and whose `land` is the real one).
- PR 4, the wake rules:
  - `.claude/scripts/lib/wake.sh`: who a monitor line wakes, by the wake table; 138 lines; copies
    `watch-github.sh`'s own `own_filter` (a filter over the poll's lines).
  - `.claude/scripts/watch-github.sh`: sources the three libraries and calls `wake_filter` in
    `report` when `WATCH_WAKE=1` (7 lines, below), and prints the `land:` line (25 lines,
    contract).
  - `.claude/scripts/watch-github.test.sh`: the wake cases and the `land:` cases; 200 lines
    added.
- PRs 1, 3 and 4 each update their rows of `.claude/README.md` and add one check-matrix row per
  new test to `docs/process.md` (L1 local, not blocking, as `usage-sum.test.sh`). PR 1 also
  rewords the `sourced-bash.test.sh` row, which names `origin-repo.sh` today. CI runs none of the
  new tests (deferrals).
- `gh-api-rest.test.sh` scans every `lib/*.sh` against an exact list of `gh` uses. The three
  libraries hold no `gh` in a code line, so its list does not change (run here).

### Usage (caller's view)

One command lands a pull request. The caller repeats it until it answers `merged` or `stopped`.
The numbers in these examples are made up, except #124's.

```
$ .claude/scripts/land.sh 281
land #281: entered 4c2d9e1, record 6893312040
$ .claude/scripts/land.sh 281 && .claude/scripts/watch-own.sh <state-dir> merge 281
land #281: merged 4c2d9e1
```

| Answer | Exit | What the caller does |
|---|---|---|
| `merged <head>` | 0 | done; the root records its own merge for the monitor, as above |
| `stopped: <why>` | 1 | done; it reports the line. `<why>` is `held`, `unenforced`, `notEligible`, `stuck <conflict \| contentChanged \| red \| historyError \| unread>`, `noEntry`, `closed`, `present <head>, the merge is not this caller's`, or a land record that is no word |
| `entered <head>, record <id>` | 3 | calls again now; the record's id goes in its report, as every post's id does |
| `waiting: <for what>` | 3 | calls again when the monitor shows the change the line names |
| `land: <error>` on standard error | 2 | retries once, then reports the line |

On a path the owner keeps, the same command never merges. A stop also prints what was read:

```
$ .claude/scripts/land.sh 282
land: #282 as read: updatable=true enforced=true rest=true base=current gate=success author=opus verdicts=2 botAt=3f1eba7 words=0
land #282: stopped: noEntry
```

After the owner types `/land 3f1eba7…` it answers
`land #282: stopped: present 3f1eba7, the merge is not this caller's`. That is the amendment's
"nothing to do": the owner's word stands, the head is green on main's tip, and the merge is the
land workflow's once A3 is on `main`, and the owner's by hand until then (#270, fix b).

A caller does not poll `land.sh`: one call is 7 + 6N REST reads for N open pull requests. The
root waits on its Monitor (the kitimark-mode skill, Watchers). A PR owner waits with its bounded
loop on one cheap read, then calls once.

| Answer | Call again when the Monitor prints |
|---|---|
| `entered <head>, record <id>` | at once |
| `waiting: gate <result> at <head>` | `pr #N head <head> checks gate=<result>` |
| `waiting: the replay of <head> onto main` | `pr #N head <new head> …` |
| `waiting: #M lands first` | `pr #M merged at …` or `closed at …` |
| `waiting: #N changed since the read` | at once, one time |
| `waiting: GitHub refused the merge (405 or 409): …` | at once, one time; then as the new answer says |

The first call in a clone builds main's tool, about ten minutes, and so does the first call
after `main` changes a file the tool is built from. Every other call takes about 22 s (What was
checked). A call that would build goes to an agent, not the root's foreground.

The cover rule needs no new command at a hand-over. These are the sketch's real answers today;
`bot-review.sh` on `main` reads #124 as `behind`:

```
$ .claude/scripts/bot-review.sh 124
coderabbit #124: reviewed 8d6f6bf (carried from f90677d)
$ .claude/scripts/carry.sh 124 f90677d34af1c7baf26fc884e593ab31ce7c133f
carry #124: f90677d covers 8d6f6bf
```

`bot-review.sh` never builds. When main's tool is not fresh it answers as today and says so:
`coderabbit #124: behind: last reviewed f90677d, head 8d6f6bf; carry not checked: main's tool is
not built at a7a666d`. The root then gives `carry.sh 124 <commit>` to an agent, which builds, and
runs `bot-review.sh` again.

With the wake rules on (`WATCH_WAKE=1`), the root's Monitor prints nothing for a move of `main`,
an updater push, or a green `gate` on work that is covered and not in line. A line that wakes
someone says whom:

```
pr #281 head 4c1d2e3 checks gate=success,prove=success wake=lander
pr #277 head 83361a9 checks gate=failure,prove=failure wake=holder
land: run 43700000001 failed on main a222e99
```

In Claude Code every wake goes through the root's Monitor. On `wake=lander` the root, or the
agent it gave the landing to, calls `land.sh` again. On `wake=holder` the root resumes the pull
request's owner. `wake=orchestrator` is for the root itself. A `land:` line is a failure no PR
owns, so it goes to a researcher, as a `ci:` line does.

### The answer (the one data structure)

`land.sh` prints one line on standard output, `land #<pr>: <answer>`. Everything else is a
`land:` line on standard error. Exit 2 is an error and has no answer line.

| `step` of `mitos-gate land` | Answer | Exit | What this call wrote |
|---|---|---|---|
| none: the pull request is merged | `merged <head>` | 0 | nothing; one read, no fetch |
| none: it is closed | `stopped: closed` | 1 | nothing; one read, no fetch |
| `enter about` | `entered <about>, record <id>` | 3 | one land record, after the read again |
| `enter about`, the record carries no `claude` app | `stopped: the land record in comment <id> carries no claude app, so it is no word` | 1 | that record |
| `enter about` again, and the record this clone posted about that commit is in the read | `stopped: the land record in comment <id> is read and is no word` | 1 | nothing |
| `merge head` | `merged <head>` | 0 | one rebase merge pinned to `head`, after the read again, then one read that it merged |
| `merge head`, GitHub answers 405 or 409 | `waiting: GitHub refused the merge (<code>): <its message>` | 3 | the one merge call |
| `enter` or `merge`, and the head or the conversation differs from the snapshot's reads | `waiting: #<pr> changed since the read` | 3 | nothing |
| `present head` | `stopped: present <head>, the merge is not this caller's` | 1 | nothing |
| `wait ahead` | `waiting: #<ahead> lands first` | 3 | nothing |
| `awaitPush head` | `waiting: the replay of <head> onto main` | 3 | nothing |
| `awaitGate head` | `waiting: gate <result> at <head>`, or `waiting: gate cancelled at <head>, re-ran the failed jobs of run <id>` | 3 | a re-run of the failed jobs, only when the snapshot reads the gate as `cancelled`, the run of the newest gate check is over and it is below its third attempt |
| `stop held` | `stopped: held` | 1 | nothing; it also prints the fetch's and the snapshot's own lines, which name a failed read |
| `stop unenforced`, `notEligible`, `noEntry` | `stopped: <why>` | 1 | nothing |
| `stop stuck <how>` | `stopped: stuck <how>` | 1 | nothing |

- **Three writes exist,** each at most once per call: the record's `POST issues/<pr>/comments`,
  the merge's `PUT pulls/<pr>/merge` with `merge_method=rebase` and `sha=<head>`, and the re-run's
  `POST actions/runs/<id>/rerun-failed-jobs`. There is no `merge-async`, no retry, no push, no
  label, no assignment and no dispatch.
- **`present` is always "nothing to do".** `land.sh` cannot tell a kept path without a copy of
  `keptPath`, and off the kept paths `present` means the caller is no delegate. In both cases the
  merge is someone else's, so no path list is copied and no caller merges on `present`. Once PR 2
  names the delegate, `land.sh` gets `present` only on a kept path, or on paths that were not read,
  which count as kept.
- **The land record** is one comment, posted through the session's `gh`, so it carries the
  `claude` app under the owner's login. Its body is one `mitos-protocol` fence that holds
  `{"v":1,"kind":"land","task":<pr>,"as":{"provider":"claude","teammate":"orchestrator"},"head":"<40-hex head>"}`,
  a blank line and the footer. `mitos-gate speech` reads that body as `agentLand` with the app
  and as `ignored footer` without it (run here).
- **One record per commit.** The clone remembers the record it posted (`<head> <comment id>`).
  When `step` says `enter` again for that commit and the comment is in the read, a second record
  would be no word either, so the call stops. When the read lacks the comment (it was deleted, or
  the list lagged), the call posts again. This is a safety net against drift between this script's
  record and `Speech.record?`: within the Lean model, a record that is read as this caller's word
  about the head always ends `enter`.
- **The caller is `claude/orchestrator`,** the one teammate PR 2 delegates. A teammate's name
  inside one provider is self-declared (`AgentNeedsSlugProviderTaskHead` proves the app and the
  provider, not the name), so the name is a constant of the connector, not an argument.
- **Knob,** for tests: `MITOS_MAIN_TOOL` names another folder for main's tool. `land.sh` and
  `carry.sh` say on standard error when it is set.

### `lib/main-tool.sh` (PR 1 starts from this file)

Ran here: shellcheck is clean on the file alone, with no directive. The plan-time cases (15, a
real scratch clone, a real `git worktree add` into the git directory and a stub `lake`) ran on the
sketch before its answers left the globals; the sketch as it stands passed the round-2 cases
(What was checked).

```bash
#!/usr/bin/env bash

main_tool_inputs=(gate core lakefile.toml lake-manifest.json lean-toolchain .github/workflows/land.yml)

main_tool_dir() {
  local common
  common=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || return 1
  printf '%s\n' "${MITOS_MAIN_TOOL:-$common/mitos-main-tool}"
}

main_tool_bin() { printf '%s\n' "$1/.lake/build/bin/mitos-gate"; }

main_tool_why() { printf '%s\n' "$1" >&2; }

main_tool_fresh() {
  local proj=$1 stamp=$2 at=$3 bin=$4 built
  built=$(cat "$stamp" 2>/dev/null) || return 1
  [[ $built =~ ^[0-9a-f]{40}$ ]] && [ -x "$bin" ] || return 1
  [ "$built" = "$at" ] \
    || git -C "$proj" diff --quiet "$built" "$at" -- "${main_tool_inputs[@]}" 2>/dev/null
}

main_tool() {
  local mode=$1 dir=${2:-} at=${3:-} proj=${CLAUDE_PROJECT_DIR:-.} bin stamp
  case $mode in
    ensure | ready) ;;
    *) main_tool_why "main_tool takes ensure or ready"; return 1 ;;
  esac
  [ -n "$dir" ] || { main_tool_why "main_tool takes the folder main_tool_dir prints"; return 1; }
  bin=$(main_tool_bin "$dir")
  stamp=$dir/.lake/main-tool.built
  if [ "$mode" = ensure ] || [ -z "$at" ]; then
    timeout -k 5 60 git -C "$proj" fetch -q origin main </dev/null 2>/dev/null \
      || { main_tool_why "cannot fetch origin main"; return 1; }
    at=$(git -C "$proj" rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}') \
      || { main_tool_why "no origin/main"; return 1; }
  fi
  [[ $at =~ ^[0-9a-f]{40}$ ]] || { main_tool_why "main is not a commit"; return 1; }
  if [ -z "${MAIN_TOOL_FD:-}" ]; then
    exec {MAIN_TOOL_FD}>>"$dir.lock" || { main_tool_why "cannot open the lock"; return 1; }
  fi
  flock -s -w 30 "$MAIN_TOOL_FD" || { main_tool_why "the checkout is busy"; return 1; }
  main_tool_fresh "$proj" "$stamp" "$at" "$bin" && return 0
  if [ "$mode" = ready ]; then
    main_tool_why "main's tool is not built at ${at:0:7}"
    return 1
  fi
  command -v lake >/dev/null 2>&1 || { main_tool_why "lake is not installed"; return 1; }
  flock -x -w 1800 "$MAIN_TOOL_FD" || { main_tool_why "the checkout stayed busy"; return 1; }
  if ! main_tool_fresh "$proj" "$stamp" "$at" "$bin"; then
    rm -f -- "$stamp"
    if [ -e "$dir/.git" ]; then
      git -C "$dir" checkout -q --force --detach "$at" 2>/dev/null \
        || { main_tool_why "cannot move the checkout to ${at:0:7}"; return 1; }
    else
      git -C "$proj" worktree add -q --detach "$dir" "$at" 2>/dev/null \
        || { main_tool_why "cannot add the checkout"; return 1; }
    fi
    (cd "$dir" && lake build mitos-gate) >"$dir.build.log" 2>&1 </dev/null \
      || { main_tool_why "the build at ${at:0:7} failed, see $dir.build.log"; return 1; }
    printf '%s\n' "$at" >"$stamp" || { main_tool_why "cannot write the stamp"; return 1; }
  fi
  flock -s "$MAIN_TOOL_FD" || { main_tool_why "cannot take the shared lock back"; return 1; }
}
```

- **How the answers come back.** No value crosses a function's edge in a global. `main_tool_dir`
  prints the checkout's folder and `main_tool_bin <dir>` the binary in it, and a caller reads
  each with `$(…)`. `main_tool` prints nothing on standard output: it returns 1 with the reason as
  the last line on standard error, and the caller sends that to a file,
  `main_tool ensure "$tool_dir" 2>"$w/main-tool.err" || die "… $(tail -n 1 "$w/main-tool.err")"`.
  The reason is not read with `$(…)`, because `main_tool` opens the shared lock in its caller's
  process, and a subshell would close it on return; a redirection keeps the call in the caller's
  shell. `land_snapshot` answers the same way. The other shape was a nameref the caller passes
  (`local -n`), and it lost because shellcheck 0.11.0 reads every write through a nameref as an
  unused variable (SC2034), so the directive would come back (run here, What was checked).
  `MAIN_TOOL_FD` stays a global: it is the process's own lock, and only this file reads it. No
  caller read `MAIN_TOOL_AT`, so it is gone.
- The checkout lives in the git directory (`<git-common-dir>/mitos-main-tool`), so `git status`
  never shows it and every worktree of the clone shares it.
- The build is fresh when its stamp names a commit whose `main_tool_inputs` equal main's. So a
  move of `main` that touches no tool input needs no build and no checkout, and `ready` keeps
  passing. `lakefile.toml` is in the list, so a new source root makes the build stale.
- A caller holds a shared lock until its process exits, so no build replaces the binary under it.
  A caller that lives long, the monitor, calls `main_tool` in a subshell.

### `carry.sh` and the cover rule (PR 1)

`carry.sh` is the recipe of the kitimark-mode skill, Verdicts, as one command: the head and the
branch from REST, the pushes from the activity route, the fetch of the branch and the commit,
then `mitos-gate carry origin/main <commit> <head>` in main's checkout.

```bash
#!/usr/bin/env bash
# Usage: carry.sh [--no-build] <pr> <commit>
#
# Whether <commit> covers the head of pull request <pr>: `mitos-gate carry origin/main <commit>
# <head>` of main's tool, over the pushes of the branch. It prints one line:
#   carry #<pr>: <commit> covers <head>          exit 0
#   carry #<pr>: <commit> does not cover <head>  exit 1
# An error prints one `carry:` line on standard error and exits 2. With --no-build it never builds
# main's tool, and a tool that is not built at main is an error.
set -u

say() { printf 'carry: %s\n' "$1" >&2; }
die() { say "$1"; exit 2; }
usage() { die "usage: carry.sh [--no-build] <pr> <commit>"; }

mode=ensure
if [ "${1:-}" = --no-build ]; then mode=ready; shift; fi
[ $# = 2 ] || usage
pr=$1 from=$2
[[ $pr =~ ^[1-9][0-9]{0,6}$ ]] || usage
[[ $from =~ ^[0-9a-f]{40}$ ]] || usage
for tool in gh jq git flock timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR source=lib/origin-repo.sh
source "$here/lib/origin-repo.sh"
# shellcheck source-path=SCRIPTDIR source=lib/main-tool.sh
source "$here/lib/main-tool.sh"
origin_repo
[ -z "${MITOS_MAIN_TOOL:-}" ] || say "MITOS_MAIN_TOOL is set, so the tool is not the one this clone keeps"

w=$(mktemp -d 2>/dev/null) || die "cannot make a temp dir"
trap 'rm -rf "$w"' EXIT
api() {
  local file=$1
  shift
  timeout -k 5 60 gh api "$@" >"$w/$file" 2>/dev/null </dev/null
}

api pr.json "repos/$repo/pulls/$pr" || die "cannot read PR #$pr"
IFS=$'\t' read -r head ref from_repo < <(jq -r \
  '[.head.sha, .head.ref, (.head.repo.full_name // "-")] | @tsv' "$w/pr.json" 2>/dev/null)
[[ ${head:-} =~ ^[0-9a-f]{40}$ ]] || die "PR #$pr has no head commit"
[[ ${ref:-} =~ ^[A-Za-z0-9._/-]+$ && $ref != -* && $ref != *..* ]] \
  || die "PR #$pr has a branch name this script does not put in a route"
[ "$from_repo" = "$repo" ] || die "PR #$pr is from another repository"
pushes="repos/$repo/activity?ref=refs/heads/$ref&direction=desc&per_page=100"
if ! api activity.json --paginate --slurp "$pushes" \
  || ! jq -r '.[][] | [.timestamp, .activity_type, .actor.login, .before, .after] | @tsv' \
    "$w/activity.json" >"$w/activity.tsv" 2>/dev/null; then
  die "cannot read the pushes of PR #$pr"
fi

tool_dir=$(main_tool_dir) || die "not in a clone"
tool_bin=$(main_tool_bin "$tool_dir")
main_tool "$mode" "$tool_dir" 2>"$w/main-tool.err" || die "$(tail -n 1 "$w/main-tool.err")"
timeout -k 5 60 git -C "$tool_dir" fetch -q origin "$ref" "$from" </dev/null 2>/dev/null \
  || die "cannot fetch $ref and ${from:0:7}"
(cd "$tool_dir" && timeout -k 5 120 "$tool_bin" carry origin/main "$from" "$head") \
  <"$w/activity.tsv" >/dev/null 2>"$w/carry.err"
case $? in
  0) echo "carry #$pr: ${from:0:7} covers ${head:0:7}"; exit 0 ;;
  1)
    sed 's/^/carry: /' "$w/carry.err" | head -n 3 >&2
    echo "carry #$pr: ${from:0:7} does not cover ${head:0:7}"
    exit 1 ;;
  *) die "mitos-gate carry did not answer" ;;
esac
```

`bot-review.sh` gains these lines (the diff against `main`):

```diff
+carried='' unchecked=''
+if [[ $state == paused || $state == behind || $state == pending ]] && [ -n "$last" ] && [ "$last" != "$head" ]; then
+  timeout -k 5 120 "$(dirname "${BASH_SOURCE[0]}")/carry.sh" --no-build "$pr" "$last" >/dev/null 2>"$w/carry.err"
+  case $? in
+    0) state=reviewed carried=" (carried from ${last:0:7})" ;;
+    1) ;;
+    *)
+      why=$(head -n 1 "$w/carry.err" | sed 's/^carry: //' | tr -c "A-Za-z0-9 .,:;()/#_'\n-" ' ' | cut -c1-80)
+      unchecked="; carry not checked: ${why:-carry.sh gave no reason}" ;;
+  esac
+fi
+
 h=${head:0:7}
 l=${last:0:7}
@@
-  reviewed) echo "coderabbit #$pr: reviewed $h"; exit 0 ;;
+  reviewed) echo "coderabbit #$pr: reviewed $h$carried"; exit 0 ;;
@@
-  paused | behind | pending) echo "coderabbit #$pr: $state: last reviewed $l, head $h" ;;
+  paused | behind | pending) echo "coderabbit #$pr: $state: last reviewed $l, head $h$unchecked" ;;
```

- The rule is the reader's, and the commit it starts from is not yet. `Obs.reviewed` asks
  `carries` from `Snapshot.botAt`, whatever CodeRabbit's run at the head is doing, and this
  sketch asks `carry.sh` from `last`. So `paused`, `behind` and `pending` all read `reviewed`
  when `carry` covers the head. But `last` prefers the paused summary's commit, while `botAt`
  takes the head when CodeRabbit's check there passed, and else the newest CodeRabbit review with
  a body (deferrals, #245). If the summary names A and the newest review names B, and only A
  carries to the head, `bot-review.sh` reads `reviewed` and asks for no review, while `land`
  reads the head as not reviewed. PR 1 settles one selection and pins that case (#290, item 4).
- A carried head posts no `@coderabbitai review` request, with or without `--request`. That is
  where the rule saves a paid review.
- When the cover check cannot run, the answer is today's, with the suffix. That side costs one
  bot review and hides nothing.
- The header comment's state table gains the carried answer and the suffix.

### `land.sh` and `lib/land-snapshot.sh` (PR 3 starts from these files)

Ran here, on the sketches before their answers left the globals: 59 cases pass against the real
`mitos-gate land` and `speech` of a222e99; 24 mutants each fail a case; and three read-only runs
against GitHub. As they stand, shellcheck is clean on `lib/land-snapshot.sh` alone with no
directive and on `land.sh` with `-x`, and `land_snapshot` passed the round-2 cases (What was
checked).

```bash
#!/usr/bin/env bash
# Usage: land.sh <pr>
#
# One step of `land` for pull request <pr>, as claude/orchestrator. It prints one line,
# `land #<pr>: <answer>`:
#   merged <head>                exit 0
#   stopped: <why>               exit 1: held, unenforced, notEligible, stuck <how>, noEntry, closed,
#                                present <head> (the merge is not this caller's), or a land record
#                                that is no word
#   entered <head>, record <id>  exit 3: the land record is posted; call again now
#   waiting: <for what>          exit 3: call again when the monitor shows this pull request
# An error prints one `land:` line on standard error and exits 2.
set -u

say() { printf 'land: %s\n' "$1" >&2; }
die() { say "$1"; exit 2; }
pr=${1:-}
[ $# = 1 ] && [[ $pr =~ ^[1-9][0-9]{0,6}$ ]] || die "usage: land.sh <pr>"
answer() { printf 'land #%s: %s\n' "$pr" "$1"; exit "$2"; }
for tool in gh jq git flock timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR source=lib/origin-repo.sh
source "$here/lib/origin-repo.sh"
# shellcheck source-path=SCRIPTDIR source=lib/main-tool.sh
source "$here/lib/main-tool.sh"
# shellcheck source-path=SCRIPTDIR source=lib/land-snapshot.sh
source "$here/lib/land-snapshot.sh"
origin_repo
provider=claude teammate=orchestrator app=claude
[ -z "${MITOS_MAIN_TOOL:-}" ] || say "MITOS_MAIN_TOOL is set, so the tool is not the one this clone keeps"

w=$(mktemp -d 2>/dev/null) || die "cannot make a temp dir"
trap 'rm -rf "$w"' EXIT
common=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "not in a clone"
exec {pr_lock}>>"$common/mitos-land-$pr.lock" || die "cannot open the lock for #$pr"
flock -n "$pr_lock" || die "another land.sh runs for #$pr"
posted=$common/mitos-land-$pr.record

api() { timeout -k 5 60 gh api "$@" 2>"$w/api.err" </dev/null; }
short() { printf '%s' "${1:0:7}"; }
sha() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
clean() { tr -c 'A-Za-z0-9 .,:;()/#_-' ' ' | sed 's/ *$//' | cut -c1-80; }

settled() {
  local state head
  api "repos/$repo/pulls/$pr" >"$w/pr.json" || die "cannot read #$pr"
  IFS=$'\t' read -r state head < <(jq -r \
    '[(if .merged_at != null then "merged" else .state end), .head.sha] | @tsv' "$w/pr.json" 2>/dev/null)
  case ${state:-} in
    merged)
      sha "${head:-}" || die "#$pr has no head commit"
      answer "merged $(short "$head")" 0 ;;
    closed) answer "stopped: closed" 1 ;;
    open) ;;
    *) die "cannot read the state of #$pr" ;;
  esac
}

settled
tool_dir=$(main_tool_dir) || die "not in a clone"
tool_bin=$(main_tool_bin "$tool_dir")
main_tool ensure "$tool_dir" 2>"$w/main-tool.err" || die "main's tool: $(tail -n 1 "$w/main-tool.err")"
land_snapshot "$repo" "$w" "$tool_dir" "$tool_bin" 2>"$w/land-snapshot.err" \
  || die "$(tail -n 1 "$w/land-snapshot.err")"
if ! jq -e --argjson n "$pr" 'any(.prs[]; .pr == $n)' "$w/snapshot.json" >/dev/null 2>&1; then
  settled
  die "#$pr is open but not in the snapshot"
fi

jq -c --arg p "$provider" --arg t "$teammate" --argjson n "$pr" \
  '. + {me: {provider: $p, name: $t}, pr: $n}' "$w/snapshot.json" >"$w/input.json" \
  || die "cannot name the caller in the snapshot"
"$tool_bin" land "$w/input.json" >"$w/decision.json" 2>"$w/land.err" \
  || die "the decision is refused: $(head -n 1 "$w/land.err" | clean)"
step=$(jq -c '.step | objects' "$w/decision.json" 2>/dev/null)
[ -n "$step" ] || die "the decision has no step"
field() { jq -r --arg k "$1" '.[$k] | tostring' <<<"$step"; }
obs() {
  jq -r --argjson n "$pr" --arg k "$1" '.prs[] | select(.pr == $n) | .[$k] | tostring' "$w/snapshot.json"
}

as_read() {
  jq -r --argjson n "$pr" '.prs[] | select(.pr == $n) | . as $o
    | ($o.author.model // "none" | if test("^[a-z0-9.-]{1,20}$") then . else "?" end) as $author
    | ["updatable=\($o.updatable)", "enforced=\($o.enforced)", "rest=\($o.rest)",
       "base=\($o.base.kind)", "gate=\($o.gate)", "author=\($author)",
       "verdicts=\($o.verdicts | length)", "botAt=\(($o.botAt // "none")[0:7])",
       "words=\($o.words | length)"]
    | "#\($o.pr) as read: " + join(" ")' "$w/snapshot.json" 2>/dev/null \
    | while IFS= read -r line; do say "$line"; done
}

digest() { jq -c '[.[][] | [.id, (.updated_at // .submitted_at)]] | sort' "$1" 2>/dev/null; }
unchanged() {
  local f route
  api "repos/$repo/pulls/$pr" >"$w/now-pr.json" || return 1
  [ "$(jq -r .head.sha "$w/now-pr.json")" = "$(obs head)" ] || return 1
  for f in comments review-comments reviews; do
    case $f in
      comments) route="repos/$repo/issues/$pr/comments?per_page=100" ;;
      review-comments) route="repos/$repo/pulls/$pr/comments?per_page=100" ;;
      reviews) route="repos/$repo/pulls/$pr/reviews?per_page=100" ;;
    esac
    api --paginate --slurp "$route" >"$w/now-$f.json" || return 1
    [ "$(digest "$w/now-$f.json")" = "$(digest "$w/reads/$f-$pr.json")" ] || return 1
  done
}

record() {
  # shellcheck disable=SC2016
  printf '```mitos-protocol\n%s\n```\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_' \
    "$(jq -cn --argjson n "$pr" --arg p "$provider" --arg t "$teammate" --arg h "$1" \
      '{v: 1, kind: "land", task: $n, as: {provider: $p, teammate: $t}, head: $h}')"
}

gate_run() {
  jq -r --arg h "$1" '[.[].check_runs[]? | select(.name == "gate" and .app.slug == "github-actions"
      and .head_sha == $h)] | max_by(.id) | .details_url // ""
    | capture("/actions/runs/(?<r>[0-9]+)/").r // empty' "$w/reads/checks-$pr.json" 2>/dev/null
}

case $(field kind) in
  merge)
    head=$(field head)
    sha "$head" || die "the step names no full commit"
    unchanged || answer "waiting: #$pr changed since the read" 3
    if api -X PUT "repos/$repo/pulls/$pr/merge" -f merge_method=rebase -f "sha=$head" >"$w/merge.json"; then
      if ! api "repos/$repo/pulls/$pr" >"$w/after.json" \
        || ! jq -e '.merged_at != null' "$w/after.json" >/dev/null; then
        die "the merge call answered, but #$pr does not read merged"
      fi
      answer "merged $(short "$head")" 0
    fi
    code=$(grep -o 'HTTP [0-9][0-9][0-9]' "$w/api.err" | tail -n 1)
    case $code in
      "HTTP 405" | "HTTP 409")
        said=$(jq -r '.message // ""' "$w/merge.json" 2>/dev/null | clean)
        answer "waiting: GitHub refused the merge (${code#HTTP }): $said" 3 ;;
      *) die "the merge call failed: ${code:-no HTTP status}" ;;
    esac ;;
  enter)
    about=$(field about)
    sha "$about" || die "the step names no full commit"
    if read -r was id <"$posted" 2>/dev/null && [ "$was" = "$about" ] && [[ ${id:-} =~ ^[1-9][0-9]*$ ]] \
      && jq -e --argjson id "$id" 'any(.[][]; .id == $id)' "$w/reads/comments-$pr.json" >/dev/null 2>&1; then
      as_read
      answer "stopped: the land record in comment $id is read and is no word" 1
    fi
    unchanged || answer "waiting: #$pr changed since the read" 3
    api -X POST "repos/$repo/issues/$pr/comments" -f "body=$(record "$about")" >"$w/posted.json" \
      || die "cannot post the land record"
    IFS=$'\t' read -r id slug < <(jq -r '[(.id | numbers), (.performed_via_github_app.slug // "-")] | @tsv' \
      "$w/posted.json" 2>/dev/null)
    [[ ${id:-} =~ ^[1-9][0-9]*$ ]] || die "GitHub returned no id for the land record"
    printf '%s %s\n' "$about" "$id" >"$posted" || say "cannot keep the id of the land record, comment $id"
    [ "$slug" = "$app" ] \
      || answer "stopped: the land record in comment $id carries no $app app, so it is no word" 1
    answer "entered $(short "$about"), record $id" 3 ;;
  wait)
    ahead=$(field ahead)
    [[ $ahead =~ ^[1-9][0-9]*$ ]] || die "the step names no pull request"
    answer "waiting: #$ahead lands first" 3 ;;
  awaitPush) answer "waiting: the replay of $(short "$(field head)") onto main" 3 ;;
  awaitGate)
    head=$(field head) gate=$(obs gate)
    if [ "$gate" = cancelled ] && run=$(gate_run "$head") && [[ $run =~ ^[1-9][0-9]*$ ]] \
      && api "repos/$repo/actions/runs/$run" >"$w/run.json" \
      && jq -e '.status == "completed" and .run_attempt < 3' "$w/run.json" >/dev/null; then
      api -X POST "repos/$repo/actions/runs/$run/rerun-failed-jobs" >/dev/null \
        || die "cannot re-run the failed jobs of run $run"
      answer "waiting: gate cancelled at $(short "$head"), re-ran the failed jobs of run $run" 3
    fi
    case $gate in
      success | failure | cancelled | skipped | pending | missing) ;;
      *) gate=unread ;;
    esac
    answer "waiting: gate $gate at $(short "$head")" 3 ;;
  present) answer "stopped: present $(short "$(field head)"), the merge is not this caller's" 1 ;;
  stop)
    why=$(field why)
    as_read
    case $why in
      held)
        sed 's/^/land: /' "$w/fetch.err" "$w/snapshot.err" 2>/dev/null | head -n 20 >&2
        answer "stopped: held" 1 ;;
      unenforced | notEligible | noEntry) answer "stopped: $why" 1 ;;
      stuck)
        how=$(field stuck)
        case $how in
          conflict | contentChanged | red | historyError | unread) answer "stopped: stuck $how" 1 ;;
        esac ;;
    esac ;;
esac
die "the decision names a step this script does not know"
```

`.claude/scripts/lib/land-snapshot.sh`:

```bash
#!/usr/bin/env bash

land_snapshot() {
  local repo=$1 out=$2 tool_dir=$3 tool_bin=$4 dash
  dash=$(sed -n 's/^ *LAND_DASHBOARD: \([1-9][0-9]\{0,6\}\)$/\1/p' \
    "$tool_dir/.github/workflows/land.yml" 2>/dev/null)
  [[ $dash =~ ^[1-9][0-9]{0,6}$ ]] \
    || { echo "main's land.yml does not name one LAND_DASHBOARD" >&2; return 1; }
  "$tool_dir/gate/snapshot-fetch.sh" "$repo" "$dash" "$out/reads" 2>"$out/fetch.err" </dev/null \
    || { echo "the fetch refused: $(tail -n 1 "$out/fetch.err")" >&2; return 1; }
  (cd "$tool_dir" && "$tool_bin" snapshot "$out/reads") >"$out/snapshot.json" \
    2>"$out/snapshot.err" </dev/null \
    || { echo "the snapshot refused: $(tail -n 1 "$out/snapshot.err")" >&2; return 1; }
}
```

The fetch script, the snapshot command and the dashboard number all come from main's checkout,
not the caller's tree, so a pull request that edits them does not judge itself.

### The wake rules (PR 4)

The design's connector table gives Claude Code's `wake` as "two rules in `watch-github.sh`". In
Claude Code a printed line wakes the root, which then resumes the lander or the holder, or acts
itself. So the script decides two things for a line: whether it prints, and whom it names.

1. **No snapshot needed.** A move of `main` and an updater push wake nobody: `Land.wake`'s first
   arm answers `nobody` for every input, and statement 14 (`QuietAfterRebase`) names it. So does
   a change of checks that finishes no `gate` and no `CodeRabbit`, such as `prove` or
   `gate=pending`, which today's rules already treat as no news ("a check still running").
2. **One snapshot per poll.** A finished `gate`, a finished `CodeRabbit` run and a new
   `needs-rebase` label are asked of main's `mitos-gate land` as `gateDone`, `botReviewed` and
   `conflictFound`, over one snapshot taken with `land_snapshot`, the same one `land.sh` reads. A
   line whose every event answers `nobody` is dropped. Any other line prints, and ends with
   ` wake=<lander|holder|orchestrator>`.

| A line that is new in this poll | What the filter does |
|---|---|
| `main <sha>` | drops it |
| `pr #N head H checks …`, H is new, and every push from the last printed head to H is a force-push by `mitos-pr-updater[bot]` | an updater push: wakes nobody by itself; the checks on H are judged as the next rows say |
| the same line, H is new by any other push | prints as today (a holder's push) |
| `gate=` newly finished | asks `gateDone N <gate>`, with the gate as the snapshot reads it (`Snapshot.gateOf`), not as the line shows it |
| `CodeRabbit=` newly finished, whatever its result | asks `botReviewed N` |
| any other change of checks (a check that starts, `prove`, `scorecard-comment`, `unlisted=`) | drops it |
| `pr #N labels=… assignees=…` whose only change is `needs-rebase` added | asks `conflictFound N` |
| every other line: other labels, assignees, merges, closes, a new or an outside pull request, the owner's comments and reviews, `ci:` and `land:` lines, `coderabbit skipped` | prints as today |

- When rule 2 cannot decide, its lines print as today, with no `wake=`. That is when main's tool
  is not fresh at the poll's `main`, the snapshot or a decision is refused, the snapshot read
  another head than the line's, or fewer than 1,000 REST calls are left. So the filter can wake
  more than the table, never less. When the tool is not fresh it also prints
  `watch-github: wake rules: main's tool is not built at <main>`, once per commit of `main`.
- The updater-push test only names the event: which actor made each push between two heads the
  monitor printed. It copies the shape of `Carry.walk` on the 7-character heads of the monitor's
  lines. It decides nothing: `updaterPushed` wakes nobody for every input, and when the push
  changed the content, the `gate` line that follows wakes the holder, because the work is then
  not covered.
- It ships off. `wake_filter` runs only when `WATCH_WAKE=1` (O3).

`.claude/scripts/lib/wake.sh`. Ran here, on the sketch before its functions took their folders as
arguments: 44 cases pass over fixed poll files, a stub activity route and the real
`mitos-gate land`. As it stands, shellcheck is clean on the file alone with no directive, and the
wake filter passed the round-2 cases (What was checked). Each function takes the folders and the
repository it reads as arguments, and `watch-github.sh` passes its own:
`wake_filter "$dir" "$w" "$repo"`. It still calls functions by name, `watch-github.sh`'s `api`,
`say` and `drop_lock_fd` and the two other libraries', but reads none of their variables.

```bash
#!/usr/bin/env bash

wake_updater='mitos-pr-updater[bot]'

wake_by_updater() {
  local poll_dir=$1 repo=$2 n=$3 old=$4 new=$5 ref
  ref=$(jq -r --argjson n "$n" '.[] | select(.number == $n) | .head.ref // ""' "$poll_dir/open.json" 2>/dev/null)
  [[ $ref =~ ^[A-Za-z0-9._/-]+$ && $ref != -* && $ref != *..* ]] || return 1
  api "activity-$n.json" "repos/$repo/activity?ref=refs/heads/$ref&direction=desc&per_page=30" || return 1
  jq -e --arg v "$old" --arg c "$new" --arg u "$wake_updater" '
    def walk($cur): if $cur == $v then true
      elif length == 0 then false
      else .[0] as $p
        | ($p.after[0:7] == $cur and $p.activity_type == "force_push" and $p.actor.login == $u)
          and (.[1:] | walk($p.before[0:7])) end;
    walk($c)' "$poll_dir/activity-$n.json" >/dev/null 2>&1
}

wake_head_events() {
  local state_dir=$1 poll_dir=$2 repo=$3 n=$4 h=$5 c=$6 prev h0 c0
  prev=$(grep -m1 "^pr #$n head " "$state_dir/snapshot" 2>/dev/null) || { echo keep; return; }
  h0=$(awk '{print $4}' <<<"$prev")
  c0=${prev#* checks }
  if [ "$h" != "$h0" ]; then
    wake_by_updater "$poll_dir" "$repo" "$n" "$h0" "$h" || { echo keep; return; }
    c0=-
  fi
  jq -nc --argjson n "$n" --arg c "$c" --arg c0 "$c0" '
    def checks: split(",") | map(split("=") | {(.[0]): .[1]}) | add // {};
    def done: . != null and . != "pending";
    ($c | sub(" unlisted=.*$"; "") | checks) as $now | ($c0 | sub(" unlisted=.*$"; "") | checks) as $was
    | (if ($now.gate | done) and $now.gate != $was.gate then {kind: "gateDone", pr: $n} else empty end),
      (if ($now.CodeRabbit | done) and $now.CodeRabbit != $was.CodeRabbit
       then {kind: "botReviewed", pr: $n} else empty end)'
}

wake_label_events() {
  local state_dir=$1 n=$2 l=$3 a=$4 prev l0 a0
  prev=$(grep -m1 "^pr #$n labels=" "$state_dir/snapshot" 2>/dev/null) || { echo keep; return; }
  l0=$(awk '{print substr($3, 8)}' <<<"$prev")
  a0=$(awk '{print substr($4, 11)}' <<<"$prev")
  if [ "$a" = "$a0" ] && jq -ne --arg l "$l" --arg l0 "$l0" '
      def set: if . == "-" then [] else split(",") end;
      (($l | set) - ($l0 | set)) == ["needs-rebase"] and (($l0 | set) - ($l | set)) == []' >/dev/null; then
    jq -nc --argjson n "$n" '{kind: "conflictFound", pr: $n}'
  else
    echo keep
  fi
}

wake_of() {
  local land_dir=$1 tool_bin=$2 ev=$3 n
  n=$(jq -r .pr <<<"$ev")
  if [ "$(jq -r .kind <<<"$ev")" = gateDone ]; then
    ev=$(jq -c --argjson n "$n" --slurpfile s "$land_dir/snapshot.json" \
      '($s[0].prs[] | select(.pr == $n) | .gate) as $g
       | if $g == null or ($g | IN("pending", "missing")) then error("no result") else . + {gate: $g} end' \
      <<<"$ev" 2>/dev/null) || return 1
  fi
  jq -c --argjson e "$ev" '{prs, event: $e}' "$land_dir/snapshot.json" >"$land_dir/event.json" 2>/dev/null \
    && "$tool_bin" land "$land_dir/event.json" 2>/dev/null | jq -er '.wake.kind'
}

wake_decide() {
  local poll_dir=$1 repo=$2 main tool_dir tool_bin tier text ev one kind who keep n h
  main=$(jq -r '.commit.sha // ""' "$poll_dir/main.json" 2>/dev/null)
  mkdir -p "$poll_dir/land"
  api rate.json rate_limit || return 1
  [ "$(jq -r '.resources.core.remaining // 0' "$poll_dir/rate.json" 2>/dev/null)" -ge "${WATCH_WAKE_FLOOR:-1000}" ] \
    2>/dev/null || return 1
  tool_dir=$(main_tool_dir) || { echo "not in a clone" >"$poll_dir/wake-why"; return 1; }
  tool_bin=$(main_tool_bin "$tool_dir")
  main_tool ready "$tool_dir" "$main" 2>"$poll_dir/main-tool.err" \
    || { tail -n 1 "$poll_dir/main-tool.err" >"$poll_dir/wake-why"; return 1; }
  drop_lock_fd land_snapshot "$repo" "$poll_dir/land" "$tool_dir" "$tool_bin" 2>/dev/null || return 1
  while IFS=$'\t' read -r tier text ev; do
    keep=0 who=
    case $text in
      "pr #"*" head "*)
        n=${text#pr #}; n=${n%% *}
        h=$(awk '{print $4}' <<<"$text")
        jq -e --argjson n "$n" --arg h "$h" 'any(.prs[]; .pr == $n and (.head | startswith($h)))' \
          "$poll_dir/land/snapshot.json" >/dev/null 2>&1 || ev='[]' keep=1 ;;
    esac
    while read -r one; do
      kind=$(wake_of "$poll_dir/land" "$tool_bin" "$one") || kind=
      case $kind in
        nobody) ;;
        lander | holder | orchestrator)
          keep=1
          case ",$who," in *",$kind,"*) ;; *) who=${who:+$who,}$kind ;; esac ;;
        *) keep=1 ;;
      esac
    done < <(jq -c '.[]' <<<"$ev")
    [ "$keep" = 0 ] || printf '%s\t%s%s\n' "$tier" "$text" "${who:+ wake=$who}"
  done <"$poll_dir/wake-pending" >"$poll_dir/lines.decided"
}

wake_filter() {
  local state_dir=$1 poll_dir=$2 repo=$3 tier text n h c l a ev any=0
  : >"$poll_dir/lines.wake"
  : >"$poll_dir/wake-pending"
  while IFS=$'\t' read -r tier text; do
    case $text in
      "main "*) continue ;;
      "pr #"*" head "*" checks "*)
        n=${text#pr #}; n=${n%% *}
        h=$(awk '{print $4}' <<<"$text")
        c=${text#* checks }
        ev=$(wake_head_events "$state_dir" "$poll_dir" "$repo" "$n" "$h" "$c") ;;
      "pr #"*" labels="*" assignees="*)
        case $text in *" outside "*) printf '%s\t%s\n' "$tier" "$text" >>"$poll_dir/lines.wake"; continue ;; esac
        n=${text#pr #}; n=${n%% *}
        l=$(awk '{print substr($3, 8)}' <<<"$text")
        a=$(awk '{print substr($4, 11)}' <<<"$text")
        ev=$(wake_label_events "$state_dir" "$n" "$l" "$a") ;;
      *) printf '%s\t%s\n' "$tier" "$text" >>"$poll_dir/lines.wake"; continue ;;
    esac
    if [ "$ev" = keep ]; then
      printf '%s\t%s\n' "$tier" "$text" >>"$poll_dir/lines.wake"
    elif [ -n "$ev" ]; then
      printf '%s\t%s\t%s\n' "$tier" "$text" "$(jq -sc . <<<"$ev")" >>"$poll_dir/wake-pending"
      any=1
    fi
  done <"$poll_dir/lines"
  if [ "$any" = 1 ]; then
    if (wake_decide "$poll_dir" "$repo"); then
      cat "$poll_dir/lines.decided" >>"$poll_dir/lines.wake"
    else
      cut -f1,2 "$poll_dir/wake-pending" >>"$poll_dir/lines.wake"
      if [ -s "$poll_dir/wake-why" ] && ! cmp -s "$poll_dir/wake-why" "$state_dir/wake-said"; then
        say "wake rules: $(cat "$poll_dir/wake-why")"
        cp "$poll_dir/wake-why" "$state_dir/wake-said"
      fi
    fi
  fi
  mv "$poll_dir/lines.wake" "$poll_dir/lines"
}
```

The hook in `watch-github.sh` (the diff against `main`). With it, and with `WATCH_WAKE` unset,
`main`'s own `watch-github.test.sh` passes unchanged in a scratch tree (145 cases):

```diff
 # shellcheck source-path=SCRIPTDIR source=lib/origin-repo.sh
 source "$(dirname "${BASH_SOURCE[0]}")/lib/origin-repo.sh"
+# shellcheck source-path=SCRIPTDIR source=lib/main-tool.sh
+source "$(dirname "${BASH_SOURCE[0]}")/lib/main-tool.sh"
+# shellcheck source-path=SCRIPTDIR source=lib/land-snapshot.sh
+source "$(dirname "${BASH_SOURCE[0]}")/lib/land-snapshot.sh"
+# shellcheck source-path=SCRIPTDIR source=lib/wake.sh
+source "$(dirname "${BASH_SOURCE[0]}")/lib/wake.sh"
 origin_repo
@@ report()
   } >"$w/lines"
+  [ "${WATCH_WAKE:-0}" != 1 ] || wake_filter "$dir" "$w" "$repo"
   drop_own_echoes | LC_ALL=C sort -s -t "$(printf '\t')" -k1,1 | cut -f2- >"$w/out"
```

The `land:` line, contract only (a deferral from P1-012). `poll()` reads
`actions/workflows/land.yml/runs?branch=main&status=failure&per_page=5` through `api` and adds one
event per run, `land: run <id> failed on main <sha>`, keyed by the run's id, as it adds the
`coderabbit skipped` events. So each run prints once, and a new state folder's first poll prints
none. A failed read of that route leaves the poll as it is. The line does not depend on
`WATCH_WAKE`. PR 4 adds the line's name to the one sentence of the kitimark-mode skill, Watchers,
that lists what the monitor prints, and to the "Waiting on GitHub" row of `docs/process.md` (O6).

### PR 2, the delegate (built at a222e99)

On `main` no agent can land: `Speech.delegates = []`, so `Obs.mayMerge` is false for everyone and
`step` answers an agent `noEntry` or `present`, never `enter` or `merge`.
`Snapshot.OnlyTheOwnerQueues` proves it. The plan row's proof needs one delegate. The default
(O1) names the teammate `land.sh` acts as.

The sketch spans three files, in this order. `delegates` goes in
`gate/MitosGate/Speech/Comment.lean`. `OnlyTheOwnerOrADelegateQueues` and its proof go in
`gate/MitosGate/Snapshot/Obs.lean`, where they replace `OnlyTheOwnerQueues` and its proof.
`orchestrator`, `stepAs` and the eight fixtures go in `Speech.Fixture` of
`gate/MitosGate/Speech.lean`, before `agentLandAfterAnEditHolds`.

```lean
def delegates : List Teammate := [⟨"claude", "orchestrator"⟩]

def OnlyTheOwnerOrADelegateQueues : Prop :=
  ∀ g p r x, ∀ e ∈ (obs g p r x).entries, e.lander = .owner ∨
    ∃ t, e.lander = .agent t ∧ t ∈ Speech.delegates ∧ (obs g p r x).kept = false

theorem onlyTheOwnerOrADelegateQueues : OnlyTheOwnerOrADelegateQueues := by
  intro g p r x e he
  cases hl : e.lander with
  | owner => exact .inl rfl
  | agent t =>
    obtain ⟨hk, hd⟩ := Land.onlyMergersQueue _ e t he hl
    exact .inr ⟨t, rfl, hd, hk⟩

def orchestrator : Teammate := ⟨"claude", "orchestrator"⟩

def stepAs (who : Teammate) (cs : List Comment) (paths : List String := ["README.md"]) : Step :=
  let o := { obs (words ctx cs pushes true).1 with paths := some paths }
  step who (queueOf [o]) o

theorem theOrchestratorIsTheDelegate : delegates = [orchestrator] := rfl
theorem orchestratorRecordOffKeptPathsMerges :
    stepAs orchestrator [app "claude" 111 11 (fence (landBy "claude" "orchestrator" 7 hC))] =
      .merge hC := by decide +kernel
theorem orchestratorEntersWithNoRecord : stepAs orchestrator [] = .enter hC := by decide +kernel
theorem undelegatedRecordIsNoEntry :
    stepAs worker [app "claude" 111 11 (fence (landBy "claude" "worker" 7 hC))] =
      .stop .noEntry := by decide +kernel
theorem orchestratorRecordOnAKeptPathIsNoEntry :
    stepAs orchestrator [app "claude" 111 11 (fence (landBy "claude" "orchestrator" 7 hC))]
      [".claude/scripts/land.sh"] = .stop .noEntry := by decide +kernel
theorem grokRecordAsTheOrchestratorIsNoEntry :
    stepAs worker [app "cursor" 111 11 ("```mitos-protocol\n" ++
      landBy "grok" "orchestrator" 7 hC ++ "\n```")] = .stop .noEntry := by decide +kernel
theorem ownerLandOffKeptPathsMergesForTheOrchestrator :
    stepAs orchestrator [typed 112 12 "/land"] = .merge hC := by decide +kernel
theorem ownerLandOnAKeptPathIsPresentedToTheOrchestrator :
    stepAs orchestrator [typed 112 12 "/land"] [".claude/scripts/land.sh"] = .present hC := by
  decide +kernel
```

- `ownerLandOnAKeptPathIsPresentedToTheOrchestrator` assumes that A1 has not merged: on `main`
  today a bare `/land` on a kept path is the owner's entry, so `step` presents it. Once A1 has
  merged, the same `/land` is no entry, and the fixture is
  `bareOwnerLandOnAKeptPathIsNoEntryForTheOrchestrator`, `= .stop .noEntry`, under revisit_when.
  Both values were checked with `decide +kernel` in round 3 of the plan PR
  (`tasks/P1-018-land-approval.md`, Build notes at plan time). The other seven fixtures hold
  either way.
- `gate/MitosGate/Snapshot.lean`'s axiom-check list names `onlyTheOwnerOrADelegateQueues` in
  place of `onlyTheOwnerQueues`.
- The statement keeps what the old one gave the owner: on a kept path, or with the paths unread,
  nothing but the owner's entry stands, because `OnlyMergersQueue` needs `kept = false`. A1's
  statement 17 (`KeptEntryIsTheOwners`) says the same in `Land`.
- `Shadow` is not touched: its reader steps as `outsider o`, whose name no delegate has
  (`Shadow/Reading.lean` 16), and `gate/shadow-test.sh` passes with the delegate named.
- `gate/snapshot-test.sh`: the case "an app's /land is no entry" steps as `claude/orchestrator`
  today and answers `enter` once the delegate is named, so it steps as `claude/worker`. Two cases
  are added: "the orchestrator with no record is told to enter" and "the orchestrator's record
  lands off kept paths".

### Contract only: main's protection outside a workflow (re-check after #278)

`land.sh`, `carry.sh` and the wake filter run in a session, not in a workflow. On `main` today
`gate/snapshot-fetch.sh` reads `branches/main/protection` with the caller's token, and the
session's token can read it (What was checked). PR #278 changes that: protection comes only from
the reader's artifact for the run that `GITHUB_RUN_ID` names, and with no run id the script saves
no `protection.json`, so every pull request holds and `land.sh` answers `stopped: held` for all.

The contract: with `GITHUB_RUN_ID` unset, `snapshot-fetch.sh` reads the route itself, as `main`
does now; with it set, #278's freshness rule. A direct read is fresh by its nature. In a workflow
the run id is always set, and a workflow that unset it would fail closed, because the workflow
token cannot read the route.

- Preferred: #278 keeps that branch, one `if` in its `protection()`. Its case "no run id holds"
  becomes "no run id reads the route" and "no run id and a failed route holds". The root asks
  #278's PR owner.
- Otherwise PR 2 adds it after #278 merges, in `gate/snapshot-fetch.sh` and `gate/snapshot-test.sh`.
- Until one of the two is on `main`, PR 3's real runs after #278 all read `held`.

types: shell, no new Lean type.
- `land.sh <pr>`: `<pr>` is `^[1-9][0-9]{0,6}$`. The answer grammar and the exits are the table
  above: one line with a fixed first word (`merged`, `stopped:`, `entered`, `waiting:`) and an
  exit code that carries the same split (0, 1, 3, and 2 for an error). A caller branches on the
  code and reads the line only to report it. The step it reads is `LandCli.stepJson` of
  `Land.Step`, one `kind` per constructor, which A1 does not change ("`step` does not change").
- `carry.sh [--no-build] <pr> <commit>`: `<commit>` is 40 hex digits. `carry #<pr>: <commit>
  covers <head>` with exit 0, `… does not cover <head>` with exit 1 and the tool's reason on
  standard error, one `carry:` line and exit 2 on an error. With `--no-build` a tool that is not
  fresh is an error.
- `bot-review.sh`: one more answer, `coderabbit #<pr>: reviewed <head> (carried from <sha>)`,
  exit 0; and the suffix `; carry not checked: <why>` on a `paused`, `behind` or `pending` line.
- `lib/main-tool.sh`: `main_tool_dir`, `main_tool_bin <dir>` and
  `main_tool ensure|ready <dir> [<main>]`, where `<dir>` is what `main_tool_dir` printed.
  - `main_tool_dir` prints the checkout's folder, `<git-common-dir>/mitos-main-tool` or
    `MITOS_MAIN_TOOL`, and returns 1 outside a clone. `main_tool_bin` prints the binary in it.
  - `main_tool` prints nothing on standard output. It returns 0 when the build in `<dir>` is
    fresh, and 1 with the reason as the last line on standard error. A caller sends standard
    error to a file, never through `$(…)` (How the answers come back).
  - `ensure` fetches `main`. When the build is not fresh it moves the checkout to `main`, or adds
    it, builds, and writes the stamp `.lake/main-tool.built`.
  - `ready` never builds. With `<main>` it does not fetch either.
  - Both leave a shared lock on `<checkout>.lock` held until the calling process exits. A build
    takes it exclusively, for up to 30 minutes of waiting.
- `lib/land-snapshot.sh`: `land_snapshot <owner/name> <dir> <tool-dir> <tool-bin>`, after
  `main_tool`, with what `main_tool_dir` and `main_tool_bin` printed. It writes `<dir>/reads/`,
  `<dir>/snapshot.json`, `<dir>/fetch.err` and `<dir>/snapshot.err`, and returns 1 with the
  reason as the last line on standard error. The dashboard issue is the one main's `land.yml`
  names.
- `lib/wake.sh`: `wake_filter <state-dir> <poll-dir> <owner/name>`, called by `watch-github.sh` as
  `wake_filter "$dir" "$w" "$repo"`. It rewrites `<poll-dir>/lines` (`<tier>\t<line>`). It calls
  `watch-github.sh`'s `api`, `say` and `drop_lock_fd`. `api <file>` writes `$w/<file>`, so the
  poll folder it is passed must be `$w`.
- State in the git directory, shared by every worktree of the clone: `mitos-main-tool/` (the
  checkout), `mitos-main-tool.lock`, `mitos-main-tool.build.log`, `mitos-land-<pr>.lock` (one
  `land.sh` per pull request at a time) and `mitos-land-<pr>.record` (`<head> <comment id>` of
  the land record this clone posted last).

statements: none new in PRs 1, 3 and 4; every decision is `mitos-gate land`'s or `carry`'s.
- PR 2: `Snapshot.OnlyTheOwnerOrADelegateQueues` replaces `Snapshot.OnlyTheOwnerQueues` (a gate
  statement, not in `statements.lock`; the owner accepts the change with O1). Proved above from
  `Land.onlyMergersQueue`, on the three standard axioms.
- The shell rests on proved statements: the merge on `MergeIsGated` (6), `present` and the stops
  on `UnenforcedLandsNothing` (7) and `HoldWins` (8), the record on `OnlyMergersQueue` (10) and
  `AgentNeedsSlugProviderTaskHead`, wake rule 1 on `QuietAfterRebase` (14), the cover rule on
  `Carry`'s.
- What this row adds is pinned by tests, each a fixture below:
  - `holds-no-rule`: `land.sh` names no kept path, label, verdict or model, and reads the decision
    only at `.step`.
  - `three-writes-only`: the only write calls are the record, the merge and the re-run, and the
    stub `gh` saw at most one of each in every case.
  - `present-never-merges`: no write follows `present`, on a kept path or with the paths unread.
  - `merge-is-pinned`: the merge call has exactly `merge_method=rebase` and `sha=<head of the
    step>`.
  - `one-answer-line`: standard output is one line in every case that exits 0, 1 or 3, and empty
    on exit 2.
  - `rule-one-is-leans`: the real `mitos-gate land` answers `nobody` to `mainMoved` and to
    `updaterPushed` for each pull request of `gate/land-fixtures/queue.json`.
  - `cover-is-carry`: `bot-review.sh` answers `(carried from …)` only when `carry.sh` exits 0.

reuse:
- `mitos-gate land` (`LandCli.run`) for every step and every wake; `mitos-gate snapshot` and
  `gate/snapshot-fetch.sh` from main's checkout for the one snapshot; `mitos-gate carry` for the
  cover rule; `mitos-gate speech` in `land.test.sh` to read the record back.
- `lib/origin-repo.sh` (`origin_repo`), `watch-own.sh` (the caller records its merge), and the
  rule of the kitimark-mode skill, Verdicts, for running main's tool in a checkout of
  `origin/main`.
- `gate/land-fixtures/queue.json`, which already names `claude/orchestrator` as a delegate; the
  record shape of `Speech.Fixture.landBy` and `fence`.
- `bot-review.test.sh`'s stub `gh`, `watch-github.test.sh`'s fixture poll files, and the gate
  wrapper of `.github/scripts/land-decide.test.sh`.

fixtures: the names are the cases that passed here on the sketches, unless a line says "to add".
- `.claude/scripts/main-tool.test.sh` (a real scratch clone, a stub `lake`), 15 cases: ready
  never builds, and names main when nothing is built; ensure adds the checkout in the git
  directory, builds once and stamps; `git status` of the clone does not show the checkout; ensure
  at the same commit does not build; a move of main that touches no tool input leaves the build
  fresh; ensure after that move does not build or move the checkout; a move of main that touches
  `gate/` makes the build stale; a failed build leaves no stamp; ready fails after the failed
  build, though an old binary is there; ensure after main moves builds again, at main; ready with
  a commit does not fetch; ready with no commit fetches, and says so when it cannot; another
  worktree of the clone shares the checkout; a second call in one process reuses the lock; a
  build waits for a caller that still runs the binary. To add: each refusal's reason is the last
  line on standard error, and standard output stays empty.
- `.claude/scripts/carry.test.sh` and the cover cases of `bot-review.test.sh` (a stub `gh`, main's
  tool as the library really makes it, a stub gate), 19 checks: with main's tool not built, the
  answer is today's and says the carry was not checked; `bot-review.sh` never builds main's tool;
  `carry.sh` builds main's tool on first use and answers; carry is asked in main's checkout, from
  the commit to the head, with the pushes as TSV; `carry.sh` says when the commit does not cover
  the head, and passes the tool's reason on standard error; a tool that does not answer is an
  error; a short commit is usage; a paused, a behind and a pending head that carry covers each
  read reviewed, and no request is posted; a head CodeRabbit passed asks no carry; a pending head
  that carry does not cover stays pending; a cover check that cannot answer keeps today's line and
  says so; a fork is not carried; one build after every case; the origin URL is never printed.
  To add: a branch name with two dots is refused; a failed fetch is an error; a timeout says so.
- `.claude/scripts/land.test.sh` (a stub `gh`, a stub fetch and snapshot, the real `land` and
  `speech`), 59 checks:
  - the record: no record, the delegate enters; the land record is one fence and the footer; the
    record reads as the orchestrator's land word; the same body without the app is no word; the
    clone remembers the record's head and id; a record posted without the app stops; a remembered
    record that is read and is still no word stops, and posts nothing; a remembered record that
    the read lacks is posted again; a record remembered for another head does not stop a new one;
    a changed conversation posts no record;
  - the merge: the delegate's record on main, green, merges; the merge is a rebase merge pinned
    to the head; the owner's `/land` off kept paths merges for the delegate; a 405 waits; a 409
    waits; another merge failure is an error, and names the status; a merge call that answers but
    does not merge is an error;
  - the read again: a new, an edited and a deleted comment, a new review, a new review comment
    and a moved head since the read each merge nothing;
  - the amendment: present on a kept path is nothing to do; present with unread paths is nothing
    to do; a kept path without a word is `noEntry`;
  - stops: a stop prints what was read; a hold stops, with the fetch's and the snapshot's lines;
    unenforced, not eligible, a conflict, a red gate and a replay that changes content each stop;
  - waits: behind main waits for the replay; a cancelled gate is re-run, the newest gate run; a
    third attempt is not re-run; a run that is not over is not re-run; a pending gate waits, and
    is not re-run; another pull request lands first;
  - not open: merged elsewhere is merged, with one read and no fetch; closed is stopped; open but
    missing from the snapshot is an error;
  - errors: a refused fetch, a refused snapshot, a refused decision, an unknown step and an
    unknown stop are each an error; usage is an error with no answer line; a second run for the
    same pull request is refused; zero or two `LAND_DASHBOARD` lines are an error;
  - pins: every `gh` call is `gh api`; `holds-no-rule`; `three-writes-only`.
  - To add: `the-caller-is-the-delegate` (the one teammate of `Speech.delegates` in the tree is
    the one `land.sh` names; added by the later of PR 2 and PR 3); a list with a second page holds
    and says which read failed; every call has a timeout; the knob is said on standard error; the
    origin URL is never printed.
- Mutants of `land.sh`, each failing at least one case (all 24 do here): the merge is not pinned;
  the merge is a squash; the merge does not read again; the read again ignores edits, skips the
  reviews, or ignores the head; a record without the app counts; a record that is read and no word
  is posted again; a record of another head stops a new one; the record names another task; the
  record has no footer; a pending gate is re-run; a third attempt is re-run; a run that is not
  over is re-run; the oldest gate run is re-run; `present` merges; `awaitPush` merges; a 422 only
  waits; a merge that did not merge is called merged; a closed pull request is decided; a merged
  pull request is fetched; the caller is another teammate; a second run is not refused; `held`
  prints no read line.
- `.claude/scripts/watch-github.test.sh` with `WATCH_WAKE=1` (the 44 checks of the sketch's test):
  - rule 1: a move of main wakes nobody, and costs no read and no snapshot; an updater push wakes
    nobody, and takes no snapshot; two updater pushes in one poll wake nobody; the holder's push
    is kept; a holder's push under an updater push is kept; an updater push from a head the
    monitor never printed is kept; a check still running wakes nobody; a change of the unlisted
    count wakes nobody;
  - rule 2: a green gate on covered work out of line wakes nobody, and takes one snapshot; a green
    gate on uncovered work wakes the holder; a red gate wakes the holder; a green gate on an
    agent's entry wakes its lander; a green gate on the owner's entry alone wakes nobody; a
    cancelled gate on the owner's entry alone wakes the orchestrator; the gate's value is the
    snapshot's, not the line's; a gate the snapshot still reads as pending keeps the line; a head
    the snapshot did not read keeps the line; a CodeRabbit pass on covered work wakes nobody, and
    on uncovered work wakes the holder; a CodeRabbit run that ends without a review does the
    same; a gate and a bot result in one line name each wake once; a conflict on covered work
    wakes the holder, and on uncovered work nobody;
  - kept as today: an assignment; another label; an outside pull request's line; a new pull
    request; an owner comment; a merge, a `ci:` line and a skipped bot line;
  - cannot decide: a low REST budget keeps the gate line, and takes no snapshot; a refused
    snapshot keeps it; without main's tool a green gate is kept, and a move of main still wakes
    nobody; the not-built line prints once for one commit of main; after a poll the monitor holds
    no lock on main's tool;
  - `rule-one-is-leans`, three checks.
  - To add: wake off prints as today (the whole existing file, unchanged, 145 cases); a red land
    run prints once; old red land runs are quiet on the first poll; a failed read of the land runs
    keeps the poll; a whole poll of `watch-github.sh` with `WATCH_WAKE=1` against the stub `gh`.
- PR 2, Lean (`decide +kernel`, in `Speech.Fixture`, all built): the eight theorems above. To
  add: `landShRecordIsTheOrchestratorsWord`, `readOf` of the exact body `land.sh` posts (the
  fence, a blank line, then the footer) is `.agent orchestrator hC`.
- PR 2, `gate/snapshot-test.sh`: the three cases under "PR 2, the delegate".
- Live, in each PR's body: see cut_line.

cut_line: four PRs, each `Part of #192`, each merged by the owner. The report of the real landing
closes #192.
- PR 1, the cover rule (`.claude/`), starts at once. It is live at its merge and needs no switch:
  today's rule already keeps a verdict on a head that `carry` covers, and this gives the bot
  review the same reading. Real runs, reads only: `carry.sh` and `bot-review.sh` on every open
  pull request. Then the first hand-over that reads `reviewed … (carried from …)`.
- PR 2, the delegate (`gate/`, trust-critical), starts at once, beside PR 1. Its body names the
  one statement that changes. It carries the protection branch if #278 merged without it.
- PR 3, `land` (`.claude/`), opens after PR 1 merges, because it sources its library. It changes
  no rule: until P1-015 the only landing through it is this row's proof. Real runs, reads only,
  through a `gh` wrapper that refuses a write: `land.sh` on every open pull request, with each
  answer and the call count in the body.
- PR 4, the wake rules (`.claude/`), opens after PR 3 merges, because it sources
  `lib/land-snapshot.sh`. The filter ships off; the `land:` line is live at its merge. Real runs:
  a second monitor with `WATCH_WAKE=1` and its own state folder beside the root's, over at least
  one merge, with each line that only one printed named in the body. And the replay (a deferral
  from P1-012): for each decided record of the shadow window (`gate/shadow-fetch.sh`), ask
  `mitos-gate land` with the record's snapshot and its trigger as the event, and count the
  answers. `mainMoved` is itself; `gateDone` is asked for the pull request whose head is the
  trigger's, with the gate the record read; `comment` is asked as `ownerSpoke`, an upper bound.
  The count is the number of root turns the rules would have left.
- The real landing (the plan row's proof): after PR 2 and PR 3 merge, the root runs `land.sh` on
  the first pull request off kept paths that is covered, reviewed and green, such as this file's
  build-notes PR (`tasks/` and `ops/runs/` only). It answers `entered`, then `merged`. The report
  names the record's id and the merge commit on `main`. The landing also proves the three writes
  against the real API; the re-run is proved by the first cancelled gate, or by a verifier told
  to break its call.
- Left out: the rules (P1-015), turning the wake rules on (O3), `nudge`, CI for the new tests,
  and naming the clauses a `notEligible` answer lacks (deferrals).

deferrals:
- Into this row:
  - from the auto-merge amendment: "`land.sh` treats `present` on a kept path as nothing to do".
    Done here: `stopped: present`, no write;
  - from P1-012: `wake` replayed over the recorded triggers (an evidence step of PR 4), and a red
    `decide` reaching the root (the `land:` line).
- To P1-015 (#194): make `land.sh` the only way an agent merges ("merge means `land`"), with
  `land.sh N && watch-own.sh <dir> merge N`; turn `WATCH_WAKE` on in the arming command, with the
  rules that make it right (the root enters `land` when a verdict passes, and no catch-up follows
  a rebase, which is A4's); point the carry recipe of the kitimark-mode skill, Verdicts, at
  `carry.sh`; send a call that would build main's tool to an agent; the rule for the
  `coderabbit skipped … while assigned` line.
- To P1-014 (#193): `nudge`. It is left out: before step 5 the old loop keeps every branch on
  main's tip, and after it the land record itself starts `decide` (`land.yml` runs on any comment
  under the owner's login, which the record is). Also to step 5, which edits `.github/` anyway:
  run the new tests in `ci.yml`'s `checks` job, and `conflictFound` once the `needs-rebase` label
  goes.
- To A1, or a follow-up issue if A1 has merged: `mitos-gate land` names the clauses a
  `notEligible` pull request lacks (`Shadow.lacks` exists), so `as_read` goes. Today all five open
  pull requests answer `notEligible`.
- To P1-016 (#195): the answer vocabulary, for the Grok connector.
- To #245 (its follow-up list):
  - `bot-review.sh`'s last reviewed commit prefers the paused summary's commit, while
    `Snapshot.botAt` prefers a passed check at the head, then the newest review with a body. They
    agreed on #124, #125 and #126;
  - `gh api --paginate` fails in a session on a list's second page, because the session proxy
    refuses the `repositories/<id>` route of the `Link` header (run here). So in a session a pull
    request with over 100 comments, files, pushes or check runs at its head holds, and `land.sh`
    answers `stopped: held` with the failed read named. #245 lists this for the fetch already;
  - a fetch of named pull requests only: a wake needs one pull request's reads, and the fetch
    reads all.
- To a follow-up issue: a `lean_lib` target without the fixture modules, so main's tool rebuilds
  in seconds after a `gate/` change (`MitosGate.Snapshot.Fixtures` alone took 338 s). It edits
  `lakefile.toml`, which the owner keeps.
- From #278: main's protection outside a workflow (the contract above).

owner_decisions: O1 to O6. The plan PR settles them: each has a default that the build follows
unless the owner says otherwise on #192.
- **O1. Delegate `claude/orchestrator`** (PR 2, `gate/`). Default: yes. The proof needs one
  delegate, and so does step 6. It adds no power: agents already merge pull requests off kept
  paths through the same route, protection asks 0 approvals, and Lean keeps every kept or unread
  path from any agent (`OnlyMergersQueue`). A name inside one provider is self-declared, so this
  delegates any Claude session that posts through the Claude app, which is who merges today. If
  no: PR 2 drops, and the proof becomes `land.sh`'s real answers plus one owner `/land` off a kept
  path. The other choice the protocol draft names, a typed `delegate-merge` line per task (#172),
  is narrower and needs a parser.
- **O2. The row gains `gate/`,** where the plan says "(owner-gated: `.claude/`)". Default: yes,
  as its PR 2, with the plan text unchanged. The other choice is a row of its own before the real
  landing.
- **O3. The wake rules ship off, and P1-015 turns them on.** Default: yes. Under today's rules
  the root must see each updater push and each green `gate`: a merge command in a catch-up is
  pinned to a head, and the root merges a pull request the owner does not keep when its `gate`
  turns green. Quiet lines would hide both until A4 and step 6 change those rules.
- **O4. The wake filter never drops an owner comment,** so a `/land` or `/hold` that the table
  says wakes nobody still wakes the root. Default: yes. A misread there would hide the owner's
  words; a kept line costs one root turn.
- **O5. Outside a workflow, `gate/snapshot-fetch.sh` reads main's protection itself** (the
  contract above), in #278 or in PR 2. Default: yes. The other choice, `land.sh` writing
  `protection.json` after the fetch, needs no `gate/` change but gives one snapshot input two
  writers.
- **O6. The row edits two sentences of the rules** for the `land:` line: the list of monitor
  lines in the kitimark-mode skill, Watchers, and the "Waiting on GitHub" row of
  `docs/process.md`. Default: yes, and only those. The rules themselves stay with P1-015.

### What was checked (15 Nov, `main` at a222e99, Lean 4.35.0, shellcheck 0.11.0, git 2.43.0)

Nothing in the repository was edited, pushed or posted. Every number is from one run.

- **By the judge, on the sketches as they were at plan time,** when `main_tool` and
  `land_snapshot` answered in globals and `lib/wake.sh` read `watch-github.sh`'s variables.
  - shellcheck `-x` is clean on `land.sh`, `carry.sh`, the patched `bot-review.sh` and the three
    libraries, with SC2034 turned off in `lib/main-tool.sh` and `lib/land-snapshot.sh` and SC2154
    in `lib/wake.sh`.
  - `lib/main-tool.sh`: 15 of 15, against a real scratch clone, a real `git worktree add` into
    the git directory, and a stub `lake`.
  - `land.sh`: 59 of 59, with the real `mitos-gate land` and `speech` of a222e99. 24 of 24
    mutants each fail a case.
  - The cover rule: 19 of 19. `main`'s own `bot-review.test.sh` against the patched script: 30
    of its 46 cases pass, and the other 16 differ only by the `carry not checked` suffix, because
    its fixture pull request has no branch.
  - `lib/wake.sh`: 44 of 44, with the real `mitos-gate land`.
  - In a scratch copy of `main`'s `.claude` tree with the libraries, `land.sh`, `carry.sh`, the
    patched `bot-review.sh` and the hook: `gh-api-rest.test.sh` passes with its list unchanged,
    `sourced-bash.test.sh` passes over every `lib/*.sh`, and `watch-github.test.sh` passes
    unchanged with `WATCH_WAKE` unset (145 cases).
  - Live, reads only, through a `gh` wrapper that refuses every write, with the a222e99 binary as
    main's tool: `land.sh` on #278 and #124 answered `stopped: notEligible` in 22 s and 24 s, with
    43 `gh` calls each, which fits 7 + 6N for six open pull requests; on #300, which does not
    exist, `land: cannot read #300`, exit 2, one call. `carry.sh --no-build`: f90677d covers
    8d6f6bf (#124), 2bf6750 covers fe8c218 (#126), and 39c5313 does not cover ae14195 (#125:
    `cursor[bot]` pushed after the review), 2 to 3 s each. `bot-review.sh`: #124 and #126 read
    `reviewed … (carried from …)`, #125 and #278 stay `behind`, 4 to 5 s each.
  - `gh api --paginate --slurp` on a list with three pages fails at the second page with HTTP 403
    from the session proxy.
- **By the Opus runner, checked by the judge from its scratch copy and logs.** PR 2's Lean: the
  copy differs from `main` in the four files above and nothing else; `lake build mitos-gate`
  built all 95 jobs, with every module's axiom check (8 min 10 s); `gate/land-test.sh` 55 of 55,
  `speech-test.sh` 39 of 39, `shadow-test.sh` 49 of 49, `snapshot-test.sh` 50 of 51, the one case
  named above. A cold `lake build mitos-gate` at a222e99: 9 min 37 s wall on 4 cores, beside
  another agent's build; `MitosGate.Snapshot.Fixtures` alone 338 s. A build with nothing to do:
  0.3 s.
- **By the Fable runner.** A comment from a session carries the `claude` app. The id of a `gate`
  check run is the id of its Actions job. The judge read the check runs of #278's head: a gate
  check's `details_url` is `…/actions/runs/<run>/job/<job>`, which `gate_run` parses.
- **In round 2 of the plan PR (#288), on the sketches as they stand** (`main` at a7a666d,
  shellcheck 0.11.0, bash 5.2.21, git 2.43.0, util-linux `flock` 2.39.3). The `/no-comments` pass
  took out the SC2034 and SC2154 directives, and the sketches were reshaped so that no answer
  crosses a function's edge in a global.
  - shellcheck, with no directive but `record`'s SC2016: clean on `lib/main-tool.sh`,
    `lib/land-snapshot.sh` and `lib/wake.sh` each alone, and on `carry.sh` and `land.sh` with
    `-x`. With the hook and the `bot-review.sh` lines applied to `main`'s two files,
    `shellcheck -x -S warning` on `watch-github.sh`, `bot-review.sh`, `carry.sh` and `land.sh`
    is clean, as `sourced-bash.test.sh` runs it.
  - Before the reshape, with the directives gone: SC2034 on `MAIN_TOOL_AT` and `MAIN_TOOL_WHY`,
    and on `LAND_SNAPSHOT_WHY`; SC2154 on `w`, `repo` and `dir` in `lib/wake.sh`. No caller read
    `MAIN_TOOL_AT`. A nameref (`local -n` or `declare -n`) draws SC2034 on each write through it.
  - 31 of 31 cases of the new shape, against a real scratch clone with a bare origin, a stub
    `lake`, a stub `mitos-gate` and a stub fetch. `main_tool_dir` and `main_tool_bin`. `ready`
    with nothing built, and after a failed build. `ensure` builds once and stamps, needs no build
    after a move of `main` off the tool inputs, and builds again after a `gate/` change. Each
    refusal's reason is the last line on standard error, with standard output empty. A caller
    that sends standard error to a file holds the shared lock until it exits and reuses it on a
    second call, while the same call inside `$(…)` leaves no lock. `land_snapshot`'s answer and
    its three refusals. The wake filter, with stubs of `api`, `say` and `drop_lock_fd`: a move of
    `main`, a `needs-rebase` label, a line with no earlier line, the tool not built (said once
    per commit of `main`, and no lock left after the poll), and a green gate that the tool
    answers `nobody` or `holder` for. Two mutants of `lib/wake.sh` (`wake_of` ignores the tool
    it is passed; `wake_filter` passes the poll folder as the state folder) fail 2 and 4 cases.
  - Not run again on the new shape: the plan-time cases above (15, 59, 19 and 44), the 24
    mutants of `land.sh`, `main`'s own test files, and the live reads.
- **Not run:** a real `entered` or `merged`, which no agent can get on `main`; the re-run call;
  `land.sh` against #278's `snapshot-fetch.sh`; a real build through `main_tool ensure` (the
  tests use a stub `lake`); `watch-github.sh` end to end with `WATCH_WAKE=1` (the filter was
  tested as a library, and the hook only with the variable unset); the `land:` line; the replay
  over the shadow window; PR 2's `landShRecordIsTheOrchestratorsWord` and its three
  `snapshot-test.sh` cases; and anything on `main` after A1 or #278.

## Rationale

### Problem

Steps 1 to 3 put the decision in Lean and a recorder in CI. Nothing yet lets a Claude agent act
on that decision: agents still merge with a hand-typed call pinned to a head, still ask for a bot
review after each updater push, and the root still wakes for every push. The connector must turn
one decision into at most one write, for a caller that repeats one call. Five facts make the
shape non-obvious:
- On `main` no agent can enter or merge at all (`delegates = []`), so the row's proof needs a
  delegate, which is a `gate/` change.
- On a kept path the merge is never an agent's (#270, #271, the accepted amendment). The connector
  must make that the path of least effort, not a rule to remember.
- The decision must come from main's tool, never from the tree being judged, and a cold build of
  it takes about ten minutes.
- The session reads protection today, but #278 takes that read away from every caller outside a
  workflow.
- The quiet the design wants after a rebase is wrong until the rules change: today the root must
  see a waiting pull request's head move, and a `gate` turn green.

### Facts this design rests on (checked against `main` at a222e99)

- `Speech.delegates = []` (`gate/MitosGate/Speech/Comment.lean` 23), so `Obs.mayMerge` is false
  for every teammate, and `Snapshot.onlyTheOwnerQueues` proves every snapshot entry is the
  owner's. `Land.Fixture` and `gate/land-fixtures/queue.json` already name `claude/orchestrator`
  as the delegate; `Land.Fixture.root` is the judge of a `wordingOnly` verdict, not a lander.
- `step` answers `present` when an entry stands, the head is green on main's tip, and the caller
  may not merge: a kept or unread path, or a caller that is no delegate (`Land.lean` 257). With
  unread paths the work is also trust-critical, so it needs a `verifier-opus` pass to be covered.
- `mitos-gate land` refuses a snapshot whose `pr` is not listed (`LandCli.lean`,
  `Snapshot.check`), so `land.sh` answers a merged or closed pull request itself, from one read.
- `agentRead` takes one top-level `mitos-protocol` fence and does not refuse a footer
  (`Speech/Comment.lean`), and `apps` maps the `claude` app to the provider `claude`. A comment
  the session posts carries that app under the owner's login.
- `Snapshot.gateOf` takes the newest `gate` check of `github-actions` at the head by id, and reads
  any conclusion but `success`, `cancelled` and `skipped` as a failure (`Snapshot/Fields.lean`).
- `mitos-gate carry` exits 0 when the verdict carries, 1 when it does not or it could not check,
  and 2 on a usage error (`Carry.lean`, `cli`).
- `mitos-gate snapshot` takes its commits from git objects in the current clone and moves no
  ref (`SnapshotCli.lean`), so a checkout whose tool inputs equal main's serves as main's tool
  even when its own `HEAD` is an older commit.
- `mitos-gate` is built from `gate/`, with `core/` through `mitos-core/+Mitos.Core:olean`
  (`lakefile.toml`). `main_tool_inputs` is a superset of that, plus `land.yml` for the dashboard
  number.
- `land.yml`'s `decide` starts on any `issue_comment` from the owner's login, so each land record
  starts one shadow run now and a planned push after step 5.
- The design's sample: 141 updater pushes and 32 moves of `main` in 3 days, each a monitor line
  today, and 140 CodeRabbit checks at updater heads.
- While the judge ran, `main` moved by two merges, and one touched a tool input
  (`gate/MitosGate/ContentId.lean`, three proof lines). The freshness rule calls the build stale
  after such a move, so the next `carry.sh` or `land.sh` rebuilds every module that imports it.

### Synthesis decision

Base: the Opus runner's. It was the only candidate whose every part existed and ran: the
connector's sketches with a stub run against the real `land` and `speech`, the wake filter as
code, and PR 2's Lean built whole. It also keeps the row closable: it names the delegate inside
the row, where the Fable runner left the plan row's proof to a row that does not exist.

Both candidates converged on these, so they ship as consensus: the shell holds no rule and reads
only `.step`; main's tool is a checkout of `origin/main` that the clone keeps; the dashboard
number is read from main's `land.yml`; the record's body; the three writes; the wake rules ask
`mitos-gate land` and ship off; an owner comment is never dropped; `nudge` waits for step 5; and
no agent can land on `main` today.

Grafts from the Fable runner:
1. `carry.sh`, the Verdicts recipe as one command, which `bot-review.sh` asks. The base had the
   recipe inline in `bot-review.sh`, where a verdict's carry could not use it.
2. The cut into one PR per concern: the cover rule, `land`, the wake rules. The base had one
   `.claude/` PR of twelve files.
3. The build is fresh by its inputs, not by main's exact commit. With the base's rule, `ready`
   failed after every merge, so the cover rule would rarely run.
4. One read of the pull request first, so a merged or closed one costs no fetch.
5. The check that the posted record carries the `claude` app, and a stop when a record is read
   and is no word. The base posted a new record on every call in that case.
6. The `as read` line on a stop, and the fetch's and snapshot's lines on `held`.
7. The target on a wake line (`wake=lander`), and a finished CodeRabbit run asked as
   `botReviewed` whatever its result.
8. The two deferrals from P1-012 that the base missed: the `land:` line and the replay.
9. The static pins and the mutants as named fixtures.

The judge's own fixes:
- `main_tool` took the exclusive lock on every `ensure`, and the monitor held its shared lock for
  life, so with the wake rules on no `land.sh` could ever run. Now `ensure` takes the shared lock
  first and upgrades only to build, a process reuses its lock, and the wake filter decides in a
  subshell (a test pins that the monitor holds no lock after a poll).
- The remembered record, by comment id, so a record whose comment was deleted is posted again and
  a list that lags costs at most one duplicate.
- The wake filter keeps a line whose head the snapshot did not read.
- `carry.sh --no-build`, so `bot-review.sh` never starts a build in the root's foreground.
- The count of PR 2's fixtures (eight, where the base said seven).
- The session's pagination limit, which neither candidate named.

Rejected from the Opus runner: one PR for all of `.claude/`; the `carry` call inline in
`bot-review.sh`; a wake line that says only "someone"; a build stamp that must equal main's
commit.

Rejected from the Fable runner:
- `present` as `waiting`. A PR owner would wait on the owner's merge with no end, and the
  amendment says "nothing to do".
- `--as <teammate>`. The name is self-declared, and only the delegate's name does anything.
- The `MITOS_GATE` knob and "proof A", a landing through a wrapper that adds a delegate to the
  snapshot. It moves "who may merge" into shell and proves nothing about main's rules.
- `land.sh` writing `protection.json` (two writers of one snapshot input).
- A copy of the caller's `.lake` as the seed of main's tool: the judged tree's build output
  would feed the tool that judges it.
- One exclusive lock for a whole call, and a freshness test with no stamp, which passes with a
  stale binary after a failed build.
- "The newest push is the updater's" as the updater-push test: it hides a holder's push that an
  updater push follows within one poll (a test pins the case).
- The delegate as a row of its own, with `claude/root` as its name. `Land.Fixture` and the land
  fixtures already call the lander `orchestrator`.

### Tradeoffs accepted

- We accept a ten-minute first call in each clone, and minutes after each change to a tool input
  on `main`, in exchange for never running a tool that the judged tree built.
- We accept 7 + 6N REST reads and about 22 s a call in exchange for a decision on fresh reads,
  rather than on the last `decide` record, which no verdict edit or bot review restarts.
- We accept a hand-kept list of the tool's inputs in exchange for a build that stays fresh across
  the merges that do not touch it. The list holds `lakefile.toml`, so a new source root makes the
  build stale.
- We accept a re-read of the head and three comment routes before each write (4 calls) in
  exchange for no record or merge landing on a conversation it did not read. A comment in the
  second between the re-read and the write can still slip by, as in A3's `apply`.
- We accept `land.sh` re-running a cancelled `gate` itself, up to the run's third attempt, because
  the wake table wakes the lander for exactly that, and otherwise it would answer `waiting` with
  no end.
- We accept that the wake filter takes one snapshot in each poll that has a candidate line, in
  exchange for the table being Lean's.
- We accept that an owner's `/land` or `/hold` still prints a line with the wake rules on, where
  the table says nobody wakes (O4).
- We accept a copy of `Carry.walk`'s shape in `jq`, on 7-character heads, to name the
  updater-push event. It decides nothing, and its cases are pinned.
- We accept `MITOS_MAIN_TOOL`, which lets a caller name another tool, in exchange for tests with a
  stub tool. The script says so on standard error, `land-decide.sh` has the same kind of knob, and
  GitHub's protection is the enforcement, not this script.
- We accept dormant code (the wake rules, off) in exchange for tests and a side-by-side run before
  the rules flip.
- We accept four owner-merged PRs where the plan row names one path, in exchange for one concern
  per PR and a round budget each.

### Alternatives considered

- **Read the last `decide` record instead of a fresh snapshot.** No local Lean build and no
  protection problem, but a verdict cell edit or a bot review starts no `decide` run, so `land.sh`
  would answer `notEligible` on stale reads and stop. Lost on correctness.
- **A loop inside `land.sh` that waits until merged.** One call, no protocol. It lost because an
  agent must not wait on GitHub in a shell (the kitimark-mode skill, Watchers), and it would spend
  7 + 6N reads per poll.
- **`land.sh` adds `delegates` to the snapshot it passes to `land`.** No `gate/` change, but the
  rule "who may merge" would move into shell, and the updater would read another snapshot than
  the lander. Lost on the design's own rule ("the updater and every lander read one snapshot").
- **The wake table copied into shell.** Cheap, but a second copy of statement 14's table, which
  needs `covered` and "in line" in shell: the dashboard parser, `carry` and the queue. Lost on
  the hand-synced list.
- **`bot-review.sh` reading `Obs.reviewed` from a snapshot.** One source for "reviewed". It lost
  because the snapshot does not print derived fields, and one `carry` call costs 2 reads where a
  snapshot costs 6 + 6N.
- **A `--kept` answer for `present`, from a copy of `keptPath`.** It follows the amendment's
  words more closely. It lost because the list would live in a third place.
- **The wake rules on by default.** Saves root turns at once, but hides the lines today's rules
  need. Lost on ordering (O3).

### Open questions and risks (for the builder to measure)

- Does `git worktree add` into the git directory work in every agent's sandbox? It works on git
  2.43.0 in a scratch clone (run here); the harness refuses some git forms in isolated worktrees.
  If it does not, the default moves next to the clone.
- How much memory does a cold build of main's tool take beside other agents' builds? The
  amendment's author saw `Snapshot/Fixtures` killed for memory; the Opus runner's build passed in
  15 GB beside another build.
- How often is the tool stale when `bot-review.sh` runs? Every `gate/` or `core/` merge makes it
  so, and the land track merges there often this month.
- Does GitHub return a land record's comment in the list at once? The remembered record bounds a
  lag to one duplicate.
- Does "re-run failed jobs" on a run whose `gate` was cancelled re-run that job, and what does
  GitHub answer for a run that is not over? `land.sh` asks only for a finished run.
- Does the session's permission check allow the merge call inside `land.sh`? The real landing
  answers that.
- A session with a shallow clone may read `base` as `unread`. That fails closed, as
  `stopped: stuck unread`.
- How many root turns would the wake rules have left? PR 4's replay counts it.

### Next implementation step

PR 1: add `lib/main-tool.sh` with `main-tool.test.sh` first, because every other part runs main's
tool; then `carry.sh` and the cover lines. PR 2 starts beside it.

## Done when
- [ ] PR 1 merged: `bot-review.sh` answers `reviewed … (carried from …)` on a real head that
      `carry` covers, and posts no request there
- [ ] PR 2 merged: `lake build` with every axiom check, and every `gate/*-test.sh`
- [ ] PR 3 merged: `land.test.sh` passes with its mutants, and the body holds `land.sh`'s real
      read-only answer on each open pull request
- [ ] PR 4 merged: the side-by-side run and the replay's counts are in the body
- [ ] the real landing: `land.sh` answers `entered`, then `merged`, on a pull request off kept
      paths, and its merge commit is on `main`
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
