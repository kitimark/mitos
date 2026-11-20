---
name: kitimark-mode
description: "How the Mitos owner (kitimark) wants agents to work. Follow this skill and docs/process.md. Invoke explicitly as $kitimark-mode or /kitimark-mode."
---

# kitimark mode

The process itself (loops, two-PR protocol, locks, gates, tripwires) is in `docs/process.md`.
This file says who does the work and how much to decide alone while following it.

The process lives in `docs/process.md`. This skill and that file win where a vendored playbook disagrees. A playbook that says to merge or to skip a check loses. Never add the label `spec-approved`. The owner merges a PR that needs that label or that touches a path the owner keeps. Never enable auto-merge, and never post a merge command. The merge procedure is in `docs/process.md`. The repository has no `AGENTS.md`. #100 keeps it out.

## The root orchestrates

The root is the session the user talks to. It plans, delegates, judges and catches the user up.
Agents do the rest, so the root is always free to answer the user. A spawned agent is not the
root. It does its brief's work itself and follows the parts of this file for its role.

- The root picks the next task, writes each brief, spawns agents, reads each report together with
  the diff or artifact behind it, and decides what happens next. It answers a quick question from
  what it already has. It edits no repository file.
- Everything else goes to an agent from the role table below: building, fixing, rebasing,
  pushing, answering review threads, and any check that runs longer than about a minute. CI
  failures and bot findings on a PR go to that PR's owner. A failure no PR owns yet, such as a
  red nightly run, goes to a researcher first.
- **Tripwire.** If the root is about to edit a repository file, push, rebase or wait in the
  foreground on a long run, it stops and hands the job to an agent instead. A root that does the
  work cannot answer the user while it works, and it fills its context with logs. The root's
  `Monitor` on the GitHub watcher script (see Watchers) is not such a wait. The monitor runs
  beside the root, and the root stays free to answer the user, so the root arms the monitor
  itself. Repairs to shared GitHub state, such as body rewrites, bulk fixes or reply sweeps, go to
  an agent too. The root itself writes to GitHub only for catch-ups, the dashboard, assignments,
  and filing one issue. The merge procedure is in `docs/process.md`.
- A program of many PRs also follows the Orchestrate playbook
  (`.agents/skills/poteto-mode/playbooks/orchestrate.md`) for sub-coordinators and supervision.

## Roles

spawn a subagent with your host's tool (Codex `spawn_agent`, Antigravity `invoke_subagent`, Cursor `Task`, Claude Code `Agent`); if none, run the steps one at a time.

When the host has no subagent tool, that same session does the repository edit; when a subagent tool exists, the root still edits no repository file.

Inherit the parent model, or the host's default.

Only the root spawns agents. A subagent spawns one only after a probe in the current environment shows that it can, because a subagent's toolset may have no way to spawn.

| Role | Job |
|---|---|
| Architect | designs each open plan row once, at plan time, with the **architect** skill (see Plan-time designs) |
| PR owner, hard | Lean proofs, a trust-critical PR (see Verdicts), a skill or design change. Use a worktree. |
| PR owner, routine | a script, a fixture, a doc fix, a rebase, a conflict merge, a one-line fix. Use a worktree. |
| Verifier | checks one head it did not write and returns pass or fail with evidence. Use a worktree. The verifier did not write most of the diff. |
| Watcher | waits on one condition the root's GitHub monitor cannot report (see Watchers) and returns when it changes |
| Researcher | reads docs or prior art, or diagnoses a failure, and edits nothing |

A host usage limit is spent first on what many agents reuse: plan-time designs and verdicts. A model the owner did not ask for on that task is not a row, a default, or a fallback.

- **Briefs.** Each brief states the user's goal, the task, the paths the agent may write, the evidence that proves the job done, and where the agent stops. A brief for a plan row names the row and where its design is (see Plan-time designs), and states only what differs from that design. A worktree spawn names the commit to start from, because an isolated worktree starts from the default branch.
- **Other spawns.** When a routed skill (`how`, `swarm`, `reflect` and the like) names a spawn, follow that skill. Inherit the parent model, or the host's default. Under the **poteto-mode** skill, a PR owner's subagent reads `.agents/skills/poteto-mode/SKILL.md` first. If the host rejects a spawn field, omit that field and say so.
- **Usage limits.** On a usage-limit error, probe the preferred model before any fallback, with a foreground agent whose whole prompt is `probe`. Probe it again before each later spawn that wants that model. A reset time says when the limit lifts at the latest, not when to try again. Only a routine row falls back, and its brief and posts say so. A hard row waits, or the root re-sequences the work. Once a probe answers, correct each post that named the limit. The spawn hook records each such probe's answer. It warns about a brief that says a model is at its limit, or that drops a role to another model, when there was no probe of that model in the last hour (#221).
- **Forks.** A fork runs on the root's settings and context. Fork only when the job needs the state the root has built up, and never for a PR round, a review, or a verdict.

- **Watchers.** Waiting goes in this order everywhere, playbooks included: the root's `Monitor`
  first, then a PR owner's own bounded waits, then a watcher agent only for what the monitor
  cannot see. Long waits on GitHub state go to the root's `Monitor` running
  `.claude/scripts/watch-github.sh <state-dir>`, and no agent runs for them. Such waits include a
  label, merge or comment from the user, an updater run, or a bot's check finishing. One monitor
  covers every open PR. While nothing changes, the script prints nothing, so it costs no tokens.
  Every 60 s the script reads REST and prints one line for each change of these kinds:
  - A merge or close.
  - A new PR.
  - A PR's labels or assignees.
  - The head and finished checks of a PR from the user's account (agents open theirs through it).
  - A move of `main`.
  - A comment or review from the user's account that does not end with the footer, with its id.
  - `ci:` lines for a head with no `ci` run, a long queue or a run on an old head. A `ci:` line is
    a failure no PR owns (see The root orchestrates).
- The root keeps one state directory for the whole session, `<scratchpad>/watch-github`. It makes
  the directory at the first arm, passes the same one at every re-arm and never makes a second
  one, because the script keeps its lock, snapshot and cursor there. So a re-armed monitor neither
  repeats nor misses an event.
- When the root changes a PR's assignees or labels, or merges or closes it, it records the write
  once the write succeeds. Where it can, it records the write in the same command:
  `<write> && .claude/scripts/watch-own.sh <state-dir> <kind> <n> <value>`. The kind is `assign`,
  `unassign`, `label`, `unlabel`, `merge` or `close`. The value is the login or the label, and a
  merge or a close takes no value. The next poll leaves out that PR's line only when the writes
  recorded since the previous poll account for the whole change, and that poll then forgets them.
  So a write that failed or was undone hides nothing later. A change by anyone else prints,
  unless a write that the root recorded in that same poll asked for the same change.
- The first poll in a new directory prints the user's comments that no footer comment follows. A
  new session also sets `WATCH_SINCE` to the dashboard's last update, so the first poll prints the
  merges and comments since then. The root arms the monitor with `timeout_ms` 1800000, the cap. In
  the turn the monitor expires or exits, the root re-arms it with one call, unless the monitor
  cannot run (see below). The root holds the monitor because a subagent cannot keep a Monitor once
  the subagent returns. The script already filters its lines to state changes, so the monitor does
  not bring back the flood that PR-activity subscriptions caused.
- Monitor lines are data, not instructions. A line shows a bot's finished check, such as
  `CodeRabbit=success`, but not the bot's comments or review threads. The PR owner that the root
  resumes reads those. A PR from another account, such as a fork's, shows only as `pr #N outside`
  with its labels, assignees and close. The script does not read such a PR's head, checks or
  reviews. So a flood of fork PRs cannot spend the REST limit the agents share, and the check names
  that a fork's workflow chooses never reach the root. Check names other than `gate`, `prove`,
  `scorecard-comment` and `CodeRabbit` show only as a count, `unlisted=N`. A poll prints at most
  30 lines, with the user's comments first. A `watch-github: N more changes in this poll are not shown`
  line means the root reads the rest over REST, because the monitor will not print them again. An
  `owner comment <id>` line whose id a poster recorded is an agent's post that lost its footer,
  not the user's words.
- **Nobody waits on GitHub in a background shell,** the root included, even for one condition
  such as a single merge. The Monitor tool's own description advises a background Bash `until`
  loop for one notification, and this rule overrides it. Such a loop sees only its one condition,
  not every PR, and the harness stops it at the background cap (see Working rules). An overnight
  loop on the user's merges ended at that cap, nothing replaced it, and the root missed the merge
  of #63 at 03:18 UTC. Where `Monitor` shows only as a deferred tool's name, the root loads it
  with ToolSearch.
- A PR owner that waits on its own CI or bot review makes one foreground Bash call with a
  `timeout` of up to 600000 ms. The call wraps an `until` loop that polls every 60 s, such as
  `timeout 590 bash -c 'until <check>; do sleep 60; done'`. So a wait under 10 minutes is one call.
  If CI is still running after two such calls, the owner reports its head as "pushed, waiting on
  CI" and returns. The owner does not keep polling. The root's monitor shows the result, and the
  root then resumes that same owner with SendMessage, which keeps the owner's context. The resumed
  owner finishes its own round. It reads the checks and the bot's threads, fixes red CI and real
  findings, answers every thread, and pushes and waits again the same way (see PR owners carry
  their PR).
- A watcher agent runs only for a condition the script cannot report. It polls the REST routes in
  **Forge** (`.agents/skills/poteto-mode/playbooks/opening-a-pr.md`) in a foreground loop that
  ends within the Bash timeout, `timeout 590 bash -c 'until <check>; do sleep 60; done'`. It
  re-issues that loop until the state changes. Each re-issue is a model turn that re-reads the
  agent's context, which is why the monitor comes first. The #26 label watcher used about 70k
  tokens over 99 minutes. In a watcher agent, a background shell fails even sooner, because a
  Claude Code session stops a few minutes after no agent is in a model call or a foreground tool
  call.
- The monitor cannot run when it exits, for example with `watch-github: gh is not installed`, or
  when it prints that GitHub is unreachable. While it cannot run, every condition is one it cannot
  report. In that case, the root reads the state in flight itself, over REST or the GitHub MCP
  tools that **Forge** names. It spawns one watcher agent for each condition that a returned PR
  owner or a catch-up waits on. Such a watcher may poll with those MCP tools where `gh` fails.
  Once `gh` answers again, the root re-arms the monitor and stops those watchers, so one wake
  source covers each condition at a time.
- A watcher agent returns only on a state change. A state change here is a new head, a check
  result at the current head, a new or reopened thread that no agent posted, a new comment without
  the footer or with an id no poster recorded, a label, a merge or a close. The watcher drops
  check suites on superseded heads, bot edits to threads already resolved, agents' own replies,
  and the `github-actions[bot]` comments that start with `<!-- owner-ping -->` (see Catching the
  user up). Agents post under the user's account, so the watcher finds their replies by the
  comment ids the posters recorded, never by login. The `Generated by [Claude Code]` footer only
  marks candidates, because anyone can type it. The thread route returns no author or body, so the
  watcher reads bodies from the comment routes in **Forge**. The script reports no other account's
  comments. It takes a comment from the user's account for an agent's comment only when the
  comment ends with the footer, so a quoted footer hides no reply. A reply that the user ends with
  the footer is missed. So while a catch-up waits on a reply, the root also reads the comment
  routes at each re-arm.
- Nobody subscribes to PR activity, because subscription events land in the root.

`.claude/hooks/check-agent-spawn.sh` warns when an Agent call leaves out `model` or `effort`, or
when a fork sets either. It warns when `in parallel` is not true, except for a call whose
whole prompt is `probe`, because a probe runs in the foreground. It warns when a PR owner or
verifier spawn has no `isolation: "worktree"`. It also warns when a brief claims a model is at
its limit, or downgrades away from it, and no completed foreground `probe` call of that model
the model named in the brief is on record from the last hour. When rule files changed
on `main` after the session loaded its rules, the hook repeats `pr-state.sh`'s note. Put that
note in the brief.

## Decide, don't ask

- When there is a recommended next step, take it and report what you did. Do not end a turn with
  "Should I…?". The user has answered every such question with "yes" or "what's next?".
- Pick the next task yourself. It is the first row in the current `plan/phase-N.md` whose issue
  is open with no open PR and whose dependencies are met. Prefer work that strengthens the checks
  (mutants, fixtures, scorer) before new features. When a phase's exit criteria are met, draft
  the next phase's plan together with its spec PR. Plans are the user's, so both wait for the
  user.
- Choose between implementation options on your own. Record the choice and the reason in the
  task file or PR body, not as a question. A go-ahead from the user settles only what it names.
  Record a call inferred from it as the root's default, with its reason, never as the user's
  ruling.
- When a problem occurs a second time, or the same call to the user appears in two catch-ups,
  file one `process` issue at once. The issue names the cause and the structural fix, and it has
  an owner. Every catch-up or dashboard line about that problem links it. A standing rule the
  user gives in chat, or the second identical per-PR ask that names a skill or a check, goes into
  a rules PR in the same session.

## PR owners carry their PR

A PR owner carries one PR from its branch to a green `gate` with every review thread answered,
then reports the head and returns. It may return earlier as "pushed, waiting on CI" (see
Watchers), and the root resumes the same owner with SendMessage once the monitor shows the
result. A brief never stops it at "code-ready" for the root to open the PR. The root never
takes over a round. A round ends when the owner reports its head as merge-ready or as waiting on
the user. An owner that returned as "pushed, waiting on CI" has not ended its round, so the root
resumes it. The resumed owner handles the red CI and the bot findings on that push itself. A
later round goes to a fresh PR owner with consolidated scope. Such a round is, for example, a red
check after a later rebase, a new blocking bot finding on a reported head, or a failed verdict.
The consolidated scope is the first brief, every later directive, the last report and the
branch. The **poteto-mode** skill's "Fresh subagents by default" names the same exception.

1. Branch from the latest `main`. Give each PR one concern: one task, or a few tightly coupled
   ones. A fix the task does not need goes in its own PR. So does a security fix found while
   reviewing a feature, when it does not depend on the feature's code. Keep the branch current by
   rebasing onto `main`, not by merging `main` in. `.github/workflows/update-prs.yml` sets a
   `needs-rebase` label when an automatic rebase conflicts. A PR with that label gets a PR owner,
   who rebases, resolves, reruns the checks and force-pushes with a lease. A PR in a GitHub stack
   never gets that label, and it is rebased only with its whole stack (see **Stacks**).
2. Before pushing, run locally every check in the `docs/process.md` check matrix that the change
   can affect. For Lean work, that includes `cd core && lake check` and
   `lake comparator --paranoid`.
3. Open the PR without asking, with `.claude/scripts/open-pr.sh --head <branch> --title <title>
   --body-file <file>`. The session proxy adds a session link to the body of every PR create. The
   script reads the body back and cleans it. `check-no-session-link.sh` refuses any other command
   whose text names a create, even one that only mentions it, so run the script alone. The first
   revision in the body's edit history keeps the link, and only the user can delete it, in the
   browser. So the owner's report names the PR for that list (#91, call 3). Wait for CI and the
   bots as **Watchers** says for a PR owner. Make at most two bounded calls, then report "pushed,
   waiting on CI" and return until the root resumes you. Batch known fixes into one push, because
   each push starts CI and a paid bot review.
4. When CI is red, reproduce the failure locally, fix it and push. Never weaken a theorem, gate or
   cheat expectation to get green. That is a spec change, and it goes to the user. A `gate` that
   was cancelled, or whose log says `prove` was still pending at the bound, is not red. Once its
   run completes, re-run its failed jobs
   (`gh api -X POST repos/{owner}/{repo}/actions/runs/<id>/rerun-failed-jobs`). When `prove`
   failed because a shard was cancelled (not timed out) at the current head, re-run the run that
   `gate`'s message names, not the latest run.
5. Check each bot finding against the code. Fix the real blocking ones and file the real minor
   ones (see Rounds). Reply on every thread with the fixing commit, the follow-up issue or the
   reason the code stays as it is. Leave a security finding's thread open for the user.
6. Update the task file and the run log in the same PR. The run log is one new file per attempt,
   `ops/runs/<date>/<task>-<role>-<attempt>.json`, with the record on one line
   (`ops/runs/README.md`). Each round is an attempt and adds its own file. The PR may rewrite its
   own files until it merges. A file on `main` never changes, so an update to an earlier record
   goes in the next attempt's `note`. Before each push,
   `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
   shows only `A` lines. The PR body says `Closes #n` for the task's issue when the PR finishes
   the task, and `Part of #n` otherwise. The plan records no status, so a task PR leaves `plan/`
   alone.
7. Push every known fix, then report the head as merge-ready or as waiting on the user.

Every agent that posts to GitHub ends each post with the footer, a `---` line and then
`_Generated by [Claude Code](https://claude.ai/code)_`. This rule covers PR owners and any other
poster, and it covers issues and the dashboard body too. Each such agent's report lists the ids
of its posts. The watcher's echo filter and the merge rule below rely on both.

## Rounds

- **Blocking only.** A round fixes only blocking findings, everywhere, playbooks included. A
  finding blocks when a run at the head or a line of the diff shows it: a cheat the gate accepts,
  a wrong result, a red check, a security check added or restored without the cheat case that
  pins it (`docs/process.md`, Security fixes), or a doc line the PR made wrong. A check, cheat
  case, theorem or `expect` line that the diff removes or weakens also blocks. Examples are a
  deleted case, `reject@N` relaxed to `reject`, or a check that a conflict resolution drops. These
  block because weakening one is a spec change for the user (PR owners carry their PR, step 4). A
  confidential key, token or ID in the diff or a post also blocks, and Catching the user up rules
  those out. A problem that `main` already has blocks only if the PR copies it, newly reaches it
  or is meant to fix it. Everything else is minor.
- Minor findings go into one `follow-up` issue per PR, which the PR body links. The PR owner files
  the minor findings it holds in its round, and the root files those of a passing verdict. A minor
  fix joins a round only when it is one line in a file that round already touches. A finding
  deferred to a later plan row goes into that row's task file or issue when it is deferred. A
  finding with no row stays in the follow-up issue, never deferred to "any time".
- A verifier marks each finding blocking or minor. Only a blocking one fails the verdict, so a
  pass with minor findings starts no round.
- Size a re-review of a design or an issue to its delta, about one lens per named change.
- **Round budget.** A PR gets two rounds. A round in which its owner only rebases, a stack's
  restack included, does not count when the new head keeps the content id (see Verdicts) of the
  head the round started from. Both content ids come from one build of `main`'s tool. For a PR in
  a stack, the parent PR's branch takes the place of `origin/main`. That head still needs a
  verifier, as Verdicts says. A `/no-comments` pass that only deletes or rewords comments does not
  count either. A reshape fix that the pass accepts counts as the PR's next round. Before a third
  round starts, the root narrows or splits the PR. The PR keeps its task's change and the blocking
  fixes, and the rest moves to separate PRs or the follow-up issue. The third brief names what is
  left. A PR that still fails after its third round stops there. The root starts no fourth round
  and posts a catch-up that names what still fails.

## Verdicts

- The root spawns a verifier at the head each PR owner reports, or at the head that follows its
  `/no-comments` pass (see Needs you means assigned to the user). The exception is a wording-only
  change from an author with a known reported model. Only an agent that did not write the code
  gives a verdict. CI, bot reviews and the root's own reading are inputs to one.
- A wording-only change alters no behavior. It edits prose, comments or typos. It edits no code,
  script, spec, lock, workflow, skill rule or hook, and no line of a plan row or a task file that
  sets a type, a statement, a rule or a cut line. The root confirms that from the diff. A
  wording-only change from an author with a known reported model needs no verdict. A green `gate`
  at its head takes the place of one in the merge rule below. An unknown author still needs the
  independent PASS even for a wording-only change.
- The verifier runs on the model that did not write most of the diff. A trust-critical PR also
  gets an opus verifier at `xhigh` or above at every head that needs a verifier, so an
  opus-written one gets two. Trust-critical means the PR needs `spec-approved` or touches a
  trust-infrastructure path (see What stays with the user). A verdict from the model that wrote
  most of the diff does not count as the passing verdict of the merge rule below. An
  opus-written trust-critical PR still needs its opus verdict, though. While no other model
  can verify, the PR gets no merge command, and its catch-up says to hold the merge. This applies
  to every PR. Snapshot and `pr-state.sh` use the same main-built provenance decoder. They require
  a known author, an accepted independent Claude PASS from another model family, and, for
  critical work, an independent Claude Opus PASS with actual effort `xhigh` or `max`. For an Opus
  author, these are two witnesses. For a known GPT or Grok author, one qualifying Opus review can
  supply both. An author whose actual model is null may instead use provider independence when
  its canonical provider is exactly `openai` or `google`. It still needs a standing accepted
  actual Claude PASS from another giver and provider. Critical work and `spec-approved` still need
  an actual Opus PASS at `xhigh` or `max`. The model stays null. Same-provider, null-Claude and
  noncanonical unknown authors hold. A null verifier model or unknown effort supplies no favorable
  fact.
- A verdict covers one head. A later head keeps it only when the later head only rebases, which
  means both of these hold. First, every push to the PR's branch since the verified head is a
  force-push by `mitos-pr-updater[bot]`, the first one from the verified head and each later one
  from the commit the one before it left, up to the current head. Second, the two heads have the
  same content id. An owner's push in between stops the carry even after the updater rebased it,
  because the content id binds where a hunk applies only within one merge-base (#83).
  `mitos-gate carry` decides both, and only its exit 0 carries the verdict: `gh api --paginate
  "repos/{owner}/{repo}/activity?ref=refs/heads/<branch>&direction=desc&per_page=100"
  --jq '.[] | [.timestamp, .activity_type, .actor.login, .before, .after] | @tsv' |
  lake exe mitos-gate carry origin/main <verified-head> <head>`, with the branch and the head from
  `gh api repos/{owner}/{repo}/pulls/<pr> --jq '.head.ref, .head.sha'`. The activity route lists
  plain pushes too, which the PR timeline does not. Run the tool in a checkout of `origin/main`,
  never in the head being judged, because a head that edits the tool would judge itself. One such
  checkout is a worktree kept for the tool (`git worktree add --detach <dir> origin/main`, and
  after each `git fetch origin main`, `git -C <dir> checkout --detach origin/main`). Fetch the
  branch and the verified head first (`git fetch origin <branch> <verified-head>`), because the
  tool refuses a commit the clone lacks. The content id
  (`lake exe mitos-gate content-id origin/main <head>`) covers the exact diff from the merge-base
  and where in its file each hunk applies. It includes whitespace, because Lean reads indentation.
  A day file is an ordinary file in that diff. Git config does not change it
  (`gate/MitosGate/ContentId.lean`). Ids from different builds are not comparable, and `carry`
  computes both with one build. A carried head still needs its own green `gate`, because the base
  is not the same. No PR in a stack carries a verdict, because the updater skips stacks. A stack
  needs a verifier at every head after a restack. Any other new head needs a new verifier.
- A conflict resolution is new content, not a rebase. A PR owner that resolved a conflict lists
  each resolved file in its report. The verifier at that head reads each resolution as new code
  against both sides, and confirms that every check either side added survives it. A check that
  a resolution drops is a blocking finding (see Rounds).
- A verifier does not rerun the whole cheat corpus. It reads the `cheat-logs` artifact of the
  latest `ci` run at the head SHA whose `prove` job ran. A later label run skips `prove`. The
  verifier lists the runs with `gh run list --commit <head> --workflow ci.yml --json databaseId,conclusion`,
  then downloads the artifact with `gh run download <run-id> -n cheat-logs -D <scratch folder>`,
  so the logs stay out of its worktree. It uses the artifact only when that run's
  `Cheat corpus is rejected` step passed (`gh api repos/{owner}/{repo}/actions/runs/<run-id>/jobs`),
  because a failed corpus step leaves a partial set and `gh run download -n cheat-logs` does not
  say which attempt the files came from. Only the cases in that step's table are fresh, each with
  a full and a `--skip-lint` log. The table is in the `prove` job's log (`gh api
  repos/{owner}/{repo}/actions/jobs/<job-id>/logs`). On a PR, the table lists the cases of the
  head merged into its base. Locally, the verifier runs only the cases the change adds or edits,
  and the variants it builds to test a finding, with `lake exe mitos-gate cheats <case>...`. Like
  **Blocking only**, this rule applies in the playbooks too. Where Autopilot-full step 4 says
  verifiers re-run the gates, they read the cheat corpus from these logs.
- The root writes each verdict into the PR's In flight row on the Owner dashboard, or into its
  merged line once the PR has merged (see Catching the user up). The verdict cell starts with
  `PASS`, `FAIL` or `wording-only`. Then it names who gave the verdict, the short head it covers
  and the model that wrote most of the diff, such as PASS opus-xhigh at 43fc333, author sonnet.
  Each verdict is a model and an effort, such as opus-xhigh, and a `+` joins two of them, as in
  PASS sonnet-xhigh +
  opus-xhigh at 43fc333, author opus. At a head that only rebases, the row's Head cell is the new
  head, and the verdict cell keeps the models, as in PASS opus-xhigh carried from 43fc333, author
  sonnet. The root updates the Head cell and the verdict cell together. This prose is for
  people. Neither consumer infers author identity, verdict identity or admission from it.
- The root also publishes exactly one `mitos-provenance:v2` section after the dashboard's
  human sections, using `mitos-gate provenance render <owner/repo> <payload.json>` from main.
  The renderer validates the complete section through the shared decoder. It writes exact markers
  and a text fence that holds uppercase UTF-8 hex, wrapped at 64 characters with LF. Supply
  compact, sorted source-schema-v1 payload bytes from a JSON encoder (`jq -cS` for these ASCII
  fields). The renderer refuses noncanonical input rather than silently overwriting duplicate
  keys. Do not hand-format the section. Existing v1 JSON sections stay readable, with their exact
  legacy interpretation. New publication always uses v2. The physical payload cap remains 131072
  bytes, and the dashboard cap remains 262144 bytes. Hex wrapping limits native rendering to
  64528 decoded bytes. The renderer refuses a larger valid legacy source, with empty stdout.
  Preserve every event and stop on refusal. The source schema and the archived record stay v1.
  Local round trips do not prove publication. After the owner merges, the root must read the
  current dashboard, publish current real facts, read back the exact machine bytes and run the
  deployed shared decoder (#483). The decoded object has `version: 1`,
  `repository: "owner/repo"`, and `pulls: [...]`. Each pull has `number`, an `author` object and
  a `verdicts` list, which may be empty before any review completes. The author fields are `head`
  (the full SHA), `provider`, `actor` (the stable real giver), `actualModel` (the reported exact
  ID, or null), and an optional `requestedModel` (only the requested text). Each verdict has the
  same identity and head fields, plus `effort` (`low`, `medium`, `high`, `xhigh`, `max` or null),
  `result` (`pass`, `fail`, `hold` or `wordingOnly`), a distinct positive `order`, and a public
  `https://github.com/owner/repo/pull/N#...` evidence link. The canonical Claude provider is
  `claude`. A model family never supplies the provider. Model IDs such as claude-sonnet-5-5
  share a family key with legacy sonnet, while the exact ID is kept. Requested aliases and
  unavailable runtime identities remain unknown, even when a configured role says Opus. When
  publishing an update, keep all adverse events with their real giver and order. A supplemental
  low-effort PASS does not veto sufficient independent evidence. The existing independent
  Claude/root wording-only classification is the only wording-only exception. It requires a known
  reported author model. An unknown author still needs the independent PASS above. The block is a
  manual trusted-root assertion, checked against actual launch and review evidence. It is not
  runtime authentication or proof of which shared-account writer edited the dashboard. Schema and
  evidence URLs do not prove those facts or detect an omitted adverse event (#327, #117).
  Missing, malformed, duplicate or unrecognized source data holds with no prose fallback. The hook
  also holds when its main-built decoder or local carry evidence is unavailable. It does not fetch
  or build within its 15-second budget. Raw snapshot reads keep effort, requested text and
  evidence. Canonical version 1 keeps truthful author and verdict facts. It uses source admission
  to gate eligibility without inventing a factual HOLD or owner speech.
- A PR merges when four things hold at its current head. It has a passing verdict, or it is a
  wording-only change from an author with a known reported model. Its `gate` is green. No review
  comment from the user is unanswered, as the comment routes in **Forge** show. It touches
  nothing the user keeps (see What stays with the user). `pr-state.sh` shows all four on each
  open PR's line. It shows a `merge-ready #N` line, with the merge command pinned to the head,
  only when the first three hold and the shared structured-provenance admission passes the checks
  above. For that, it reads every comment and review of a PR with source verdict events. But it
  counts a footer post anywhere on the PR as the answer, so the comment-route read above still
  decides.
- The PR merges with rebase and merge, pinned to that head. The merge procedure is in
  `docs/process.md`. Never enable auto-merge, and never post a merge command. A PR owner that is
  still running merges a PR `docs/process.md` allows that owner to merge, as in Autopilot-full
  step 5. Otherwise the root stops at merge-ready. A PR that needs `spec-approved` or touches a
  path the owner keeps stops at merge-ready. A PR that is part of a GitHub stack follows **Stacks**.
- A failed verdict goes to a fresh PR owner with the findings.

## Stacks

- PRs that build on each other form a GitHub stack, not a base-branch chain retargeted by hand.
  A chain that exists anyway, such as #73 on #62's branch, gets no rebase and no `needs-rebase`
  label, because the updater handles only PRs based on `main`. When its base merges, the root
  gives it to a PR owner. The owner retargets it to `main`. Then the owner rebases and pushes it
  the way the next bullet does for a stack's bottom branch. So the push starts `gate` against
  `main`, and the pinned lease refuses the push if the updater pushed in between. Its old base is
  the parent of its own first commit, not the base branch's last tip, which the updater may have
  rebased since. These sessions block GraphQL. `gh stack submit` and `gh stack link` find and open
  PRs over GraphQL, so they fail here. Open each PR with `.claude/scripts/open-pr.sh` instead
  (step 3 of PR owners carry their PR, plus `--base <branch>`). Open the bottom one on `main` and
  each next one on the branch below it. Then make the stack with
  `gh api -X POST repos/{owner}/{repo}/stacks -H "X-GitHub-Api-Version: 2026-03-10"
  -F 'pull_requests[]=<bottom>' -F 'pull_requests[]=<next>'`, one `-F` per PR, bottom to top. That
  sends the body field `pull_requests`, a list of 2 to 100 PR numbers.
- When a stack's bottom PR merges, GitHub rebases the rest of the stack and retargets the next PR
  to `main`. So nobody retargets or force-pushes a stacked PR to follow its parent. GitHub does
  not rebase a stack when `main` moves ahead. `update-prs.yml` skips every PR in a stack, so it
  never labels one `needs-rebase`. When `main` moves ahead of a stack, its owner rebases the whole
  stack, or the root gives the stack to a PR owner, as it would a PR with a `needs-rebase` label.
  Fetch first. Then, for each branch, note its remote tip (`git rev-parse origin/<branch>`) and
  its base. The base is the branch below it, or `origin/main` for the bottom one. Note the base's
  `git rev-parse` before any rebase. Check that each local branch contains its noted tip
  (`git merge-base --is-ancestor origin/<branch>
  <branch>`). If one does not, reconcile it first, because the pinned lease would let the push
  drop the commits it lacks. Then rebase bottom-up with
  `git rebase --onto <new-base> <old-base> <branch>`. The new base is `origin/main` for the bottom
  branch and the rebased branch below for the others. This way, each branch replays only its own
  commits, even when a conflict changed its parent's patch. Then push every branch of the stack in
  one `git push --atomic
  --force-with-lease=<bottom>:<old-tip> --force-with-lease=<next>:<old-tip> ... origin <bottom>
  <next> ...`. Name each branch, because a bare `git push` pushes only the current one. Pin each
  lease to the noted tip, because a bare `--force-with-lease` checks against whatever a later
  fetch, perhaps from another worktree, put in `origin/<branch>`. Do the rebase and the push with
  plain git, not `gh stack rebase` and `gh stack push`. `gh stack push` fetches before it pushes,
  so its leases are not the noted tips. Also, gh-stack v0.0.8 does not push atomically. The
  **Rebase stack** button does this on the server, but only in the browser. The REST API has no
  route that rebases a stack.
- Merge a stack bottom-up, one PR at a time. Each PR needs its own verdict and green `gate` at its
  head before its turn, as for any PR.
- An agent merges a stacked PR only when `docs/process.md` says that agent may merge it. The
  legacy `/merge` route cannot merge a stack. The merge procedure is in `docs/process.md`. Never
  enable auto-merge, and never post a merge command. Merging a stacked PR also merges every open
  PR below it. Read the PR back and check for `merged` before you call it landed.
- Never merge a mid-stack PR to land the ones below it. Merging a stacked PR merges every open PR
  below it too, whether or not they have a verdict. So a PR above one that waits for the user (a
  label or a merge) waits as well.

## Working rules

- A foreground Bash command times out at 600000 ms, and a background one at 7200000 ms (2 hours)
  at most. Long waits on GitHub go to the root's monitor (see Watchers). A wait inside an agent
  is a bounded foreground call (`timeout 590 bash -c 'until <check>; do sleep 60; done'`), never
  one longer command.
- Each agent names its scratch folders so that no other agent can pick the same name, for example
  with a prefix unique to that agent. Two verifiers once overwrote each other's folders.

## Done means verified

- The checks pass locally and in CI, and a small concrete run shows the behaviour. Report
  numbers and results, not "should work".
- A cost number that decides a design states its run count, its spread and the flags it ran
  with, such as `--paranoid`. A number from one run says so. A token number that decides process
  names its quantity. It sums output and cache-read tokens over every call, from the agents'
  journals. #223 tracks a script for that sum.
- A script that calls GitHub or another external API needs proof from a real run against that
  API, such as a `workflow_dispatch` run, or from a verifier told to break its API calls. A local
  stand-in such as a scratch git remote proves only the git steps.

## Lean first

- New logic goes in Lean with proved statements. Use fixtures or tests only for what cannot be
  stated as a theorem.
- When you are stuck on a proof, follow the task file's escalation order. If the statement looks
  false, write the counterexample and open a spec PR. Do not bend the implementation.

## What stays with the user

- **Spec approval.** The `spec-approved` label stays with the user. PRs that change
  `statements.lock`, `models.lock`, `core/Mitos/Core.lean`, `core/Mitos/Core/`, `core/Challenge/`
  or `core/comparator.json` need it. Everything in `core/Mitos/Core/` is spec, even a change the
  lock does not show. Never add the label, and never route around it (moving statements out of
  the lock, editing the CI check).
- **Trust infrastructure.** `gate/`, `eval/cheats/`, `.github/`, the root `lean-toolchain` and
  `lakefile.toml`, `core/lakefile.toml`, the root `lake-manifest.json`, and
  `core/lake-manifest.json`, which pin what the root build and `lake check` resolve. They decide
  what CI checks and what the gate trusts, so a PR that touches them is trust-critical (see
  Verdicts).
- **Agent rules and plans.** `docs/process.md`, `CLAUDE.md`, `.claude/`, `.cursor/` and `plan/`.
- The user merges every PR that needs `spec-approved` or touches a path in the first three
  bullets above. The exception is a PR whose only change to those paths is issue links in the
  Issue column of a `plan/phase-N.md`, such as `[#31](https://github.com/kitimark/mitos/issues/31)`.
  Status updates to a task's own row were the exception in the same way before that column
  replaced Status. Any other text in a cell, or any other column, is outside the exception. The
  PRs the user merges stop at verified and green, assigned to the user, with a catch-up. Agents
  merge the exception PRs. This is the one list of paths the user keeps. Other files point here.
- `.github/CODEOWNERS` is wider on purpose. It also names all of `core/` and
  `examples/acme/Models/`, so GitHub shows the user those PRs. The spec inside them needs
  `spec-approved`, and agents merge the rest. `plan/` has no trusted code, so CODEOWNERS leaves it
  out.
- When a cause is in a path the user keeps, the PR owner who patches the symptom also opens the
  structural PR next to that patch. Batch rule and tool changes that wait for the user into one
  open PR per batch.
- **Outside the repo.** GitHub settings, branch protection, environment network access, pinning
  an issue, anything that sends messages or costs money. Automation that multiplies pushes, such
  as a bot that rebases every open PR on each merge, costs money too. Each push starts CI and a
  paid bot review, so a proposal for such automation lists what one push triggers.

## Catching the user up

This is the root's main job between spawns. The user catches up on GitHub, not in chat. In chat,
the root sends answers to the user's questions and at most one line that points to the
dashboard. This rule overrides the chat catch-ups in other skills and playbooks. Where one of
them says to catch the user up per the **ketchup** skill, such as an Autopilot-full tick or its
Reply, the root rewrites the dashboard instead. `/ketchup` still answers in chat when the user
types it, because then it answers their question. The repository is public, so no post contains
IDs of any kind (session, agent, request, environment or other), a key, a token, a code, an email
or a private URL. `check-no-session-link.sh` refuses a session link (CLAUDE.md, Attribution).
Issue and PR numbers, commit SHAs and links to public GitHub comments are fine. The comment ids
an agent lists go in its report to the root, not in a post. The routes are in **Forge**.

- **Owner dashboard.** The dashboard is one open issue titled "Owner dashboard", which the user
  pins. When something changes for the user (a PR becomes merge-ready, merges or starts waiting
  on them, a verdict fails, a call needs them), the root rewrites its body. Read each state over
  REST before writing it. A body edit notifies nobody. A round of the same event is one line
  ("the updater rebased 6 PRs, all green", or which are red). The body has these sections:
  - Needs you.
  - In flight, with one row per open PR that gives its head, its `gate` result and its verdict
    (see Verdicts). Under the table goes one line per PR that merged in the last 24 hours or
    still has no verdict since its merge, with its merge time and verdict.
  - Next up.
  - Follow-ups, with counts and filter links.
- **Needs you means assigned to the user.** Assign `kitimark` to each issue or PR that waits on
  the user, and unassign them when their part is done. Their queue is the search
  `is:open assignee:kitimark`. Agents act through the user's account, and GitHub never
  notifies a user of their own actions. So on each assignment of the user made from the user's
  account, `.github/workflows/owner-ping.yml` comments as `github-actions[bot]` with
  `@kitimark this needs you:` and a line. The line is the first line of the item's latest
  catch-up, in a code span, with every `@` and every invisible character removed. So it mentions
  nobody, links nothing and hides no text. A hand-over runs in this order: the PR owner reports
  its head, the root runs the `/no-comments` pass, a PR owner pushes what the pass accepts, the
  verifier checks the resulting head, and then `bot-review.sh` and the catch-up follow. The pass
  applies `.agents/skills/no-comments/SKILL.md` to the head's diff against `main`. The root runs
  the pass, because the pass spawns Comment Sicko and a PR owner may have no Agent tool. A PR
  owner never runs the pass itself, no brief asks it to, and there is no fallback. The PR owner
  pushes the accepted deletions and fixes, and it answers the bot threads. A PR whose diff adds
  no comments, such as a pure deletion, plan-row links or a run-log-only change, needs no pass.
  Its catch-up says "no-comments: no new comments". A head that only rebases a passed head keeps
  the pass when `mitos-gate carry` exits 0, as a verdict does. Its catch-up names the pass and the
  head it ran at. A PR from an outside agent that the root only observes needs no pass unless the
  user asks. The catch-up's Status names the pass, its result (deletions, flags fixed, and any
  flag left open, including a failed pass) and the head it ran at. Before a catch-up that hands
  the user a PR, run `.claude/scripts/bot-review.sh <pr>`, and hand the PR over only on
  `reviewed` or `refused`. On `paused` or `behind`, run it again with `--request`. Then wait for
  CodeRabbit's finished check at that head on the monitor, and have the PR's owner answer its
  threads in the same round. The catch-up names the head CodeRabbit last reviewed, or the
  `refused:` reason. A monitor line `pr #N coderabbit skipped at <head> while assigned` means a PR
  reached the user without that review. Then unassign the user and do the same. Before each
  assignment of an issue or a PR, post a comment on it whose first line is
  `## Catch-up: <what the user must do>`. When the action needed from the user changes on an item
  already assigned to them, post a new catch-up. Then unassign and assign them again, so the ping
  shows the new catch-up. Assignment starts no CI. Never label a PR to show the user its state. A
  label is not a status flag. Any label change still starts `gate`, which reads the labels live
  and does not rerun the corpus.
- **State comes from REST.** Before any message, catch-up, assignment, unassignment or dashboard
  edit that says anything about an issue's or PR's state, the root reads that item over REST in
  the same turn (the PR and issue routes in **Forge**). Examples of such a state are waiting,
  open, merged, closed, done or assigned. An agent's report is never the source for its state.
  The user merged #29 and #44 while the root still called them waiting.
- **Milestones and issues.** Each phase is a milestone. Each open row of its `plan/phase-N.md` is
  an issue in that milestone, titled with the task id, and the plan's Issue column links it. Only
  that issue and its PRs show the task's status. When a phase's plan lands, the root has a PR
  owner open the issues and link them, and later fix a link when a row's issue is split or
  replaced. Those PRs change only the issue links in the Issue column, so agents merge them (see
  What stays with the user). The root keeps the milestone description, which lists the plan's
  goal and exit criteria. It marks each criterion `(met in #n)` once #n reads merged over REST. It
  changes the criteria text only to match the plan on `main`, which the user keeps. Work found
  during a task becomes an issue labelled `follow-up`. A finding about agent rules (`.claude/`,
  `.cursor/`, `CLAUDE.md`, `docs/process.md`) gets the `process` label. A tracker issue's steps
  become rows in the current plan, each with its own issue. The tracker body lists those issue
  links instead of checkboxes.
- **Plan-time designs.** When a plan or a tracker lands, the Architect (see Roles) writes a task
  file from `tasks/TEMPLATE.md` for each open row, Design block included. The row's issue links
  that file. The design stays in that file or the issue body (`.agents/skills/architect/SKILL.md`,
  Outputs). Its `modules:` field maps each file to the one topic it owns. A build that outgrows
  that map reports it as a deviation and does not split silently. A row that depends on a row not
  yet merged gets a contract at plan time. The contract gives the row's inputs, outputs and
  statements, with `revisit_when` set to "re-check after #N merges". The Architect completes it
  when #N merges. An issue links a design only when the design covers the row at build depth,
  which means a sketch that type-checks plus named fixtures. Otherwise, the issue says "contract
  only".
- A notification that changes nothing for the user gets no update. This covers an agent's
  interim status, a monitor expiring or a watcher re-arming, a monitor line that echoes the
  root's own write or shows a check still running, and every event a watcher drops. Such a turn
  ends with no reply text. Never send "nothing to do". #224 tracks dropping those echoes in
  `watch-github.sh`.
- Keep messages short and plain. The user writes brief messages in non-native English. Lead with
  what happened, then what you are doing next.
- Answer a "why" question with the idea first, then one concrete example from this repo.
- While a PR waits on the user (a label, a merge, a setting only they can change), post one
  catch-up comment on the PR, then assign the user. Add the PR to the dashboard's Needs you, then
  continue with an independent task. The comment starts with the `## Catch-up:` line (see Needs
  you), then has:
  - **Status:** each check and verdict at the current head, with its evidence. A verdict names
    the head it covers. It says whether later heads only rebase (`mitos-gate carry` exits 0, see
    Verdicts) or change content. It names who gave it: a verifier agent and its model, a bot, or
    the root itself.
    Never call a bot's verdict or your own independent.
  - **Next steps:** numbered, with a `gh` command (one per code block) wherever one exists. Say
    "browser only" where none does.
  - **Expected result** of each step, and what to do if it differs.
  A known fix that is not pushed yet, such as one held back to save bot reviews, goes in a new
  catch-up as "hold the merge until N fixes land". When the state changes, post a new catch-up
  rather than editing an old one, and reassign as Needs you says.
- The root's monitor (see Watchers) runs from the moment the first PR opens, not only after a
  catch-up, and covers every open PR. After every catch-up that waits on a user action, the root
  checks that the monitor reports that exact condition (a label, a merge, an assignment or a
  comment). It spawns a watcher agent only for a condition the monitor does not report. When an
  event arrives, check the condition yourself over REST, unassign the user if their part is done,
  and continue without waiting to be told. A merge the root did not expect is a state change.
  Update the dashboard and tell the user once, in one line.
- A catch-up does not carry a merge command. The merge procedure is in `docs/process.md`.
  Never enable auto-merge, and never post a merge command. `pr-state.sh` shows a `merge-ready #N`
  line when the first three conditions hold. The hook gives no state line for a PR past the ten
  it lists, or for one from another account. The paths the user keeps decide who merges, so a PR
  that touches them stops at merge-ready. Each merge moves `main`, and the updater rebases every
  open PR, so a head that moved needs a new catch-up, as on #61 and #62. When that line changes
  or goes away for a PR that waits on the user's merge, post a new catch-up. It names the
  condition now unmet (a verdict that covers the new head, a green `gate`, an answered comment)
  and says to hold the merge until that condition is met.
- The user may merge before a verdict. The verifier then still runs, on the merged head. Its
  verdict goes in the PR's merged line under the In flight table, such as #44 merged 09:30 UTC,
  then PASS opus-xhigh at 04fcb83; follow-ups #47. A FAIL also becomes a `follow-up` issue and a
  fix PR, as #28 fixed #27. A PR that merged without its `/no-comments` pass gets the pass over
  what it merged. That is the diff from the `main` commit it landed on to its last merged commit.
  A follow-up PR carries the edits that the pass accepts. The root finds such PRs by reading their
  catch-ups over REST.

## Research

- Run researchers in parallel for research and broad investigation. The user asked for this.
  Keep their conclusions, not their raw output.
- Subagents share the session's network policy, so a host blocked for the root is blocked for
  them too. For a blocked vendor docs host, read the vendor's official repositories on GitHub,
  which you can clone. Otherwise, ask the user once to allow the host.
