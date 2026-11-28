# Amendment 1: topics per agent, the cloud container as the baseline

The owner answered PR 0's part A on 27 November. Two answers change the design. In their words:

- **5a**: "i think the daemon could support specific each agent would like to subscribe. so, i may
  have multiple agents handle each topics independent"
- **2b**: "what's the best practices for cloud remote. it may use for another agent like codex, and
  another agent provider as well."

The others stand as given: 1 yes, 2c ok, 3a ok (the attested release asset), 8a ok, 8b ok (PR 3c
is required), 9 yes. `DESIGN.md`, `tasks/502-watch.md` and `sketch/` are amended as one design.
PR #580 (PR 0) merges as it is. PR 0b lands this before rows 7a to 13 are built. It adds no plan
row and leaves the findings of #581 out.

## Usage

```
watch.sh wait --as <app>/<name> [--topics <kind>,...] [--on <n>,...] [--ride none|<kind>,...]
              [--seen <n>] [--max <min>] [--since <UTC>]
```

There are eight kinds: `words` (a post no app names, or an unreadable post), `agents` (another
app's post), `peers` (a post through the caller's own app), `passed` and `failed` (a newly finished
check that passes or not; `skipped` and `neutral` pass, and one line can be both), `pulls` (your
pull requests), `outside` (another account's) and `alarms` (`ci` health). By default a wait hears
every kind but `peers`, on the whole repository, and lets `outside` ride. Only `passed`, `failed`,
`outside` and `alarms` can ride. A `--ride` list replaces the default. A topic selects only by
kind and by issue or pull request number, never by label, milestone or app. Labels and milestones
change their members, so whoever briefs an agent turns a milestone into numbers for `--on`.

```
# the root: a catch-all, as before
Monitor: .claude/scripts/watch.sh wait --as claude/root --since 2026-11-27T08:00:00Z
# the root, once a CI-failures handler is named
.claude/scripts/watch.sh wait --as claude/root --ride failed,outside,alarms --seen 183467
# an owner-comments agent, a CI-failures agent, a PR owner
timeout 590 .claude/scripts/watch.sh wait --as claude/words --topics words --max 7
timeout 590 .claude/scripts/watch.sh wait --as claude/ci --topics failed,alarms --max 7
timeout 590 .claude/scripts/watch.sh wait --as claude/pr-512 --on 512 --max 7
# Codex, once its agent phase can read GitHub (starting values)
timeout 360 .claude/scripts/watch.sh wait --as chatgpt-codex-connector/pr-571 --on 502,571 --max 4
```

A red check on a pull request belongs to its PR's owner. The CI-failures agent handles only the
`ci:` alarms and observes the rest. The trailer prints each flag that is not at its default, so a
copied trailer keeps the topic. A mistyped wait prints one `watch: usage:` line and exits 2, so a
Monitor wakes on it. `status` shows each caller's last topic. `--on` replaces `--pr`.

## Shape

- One clone keeps one shared view of GitHub. Whoever waits reads GitHub once a minute for the
  whole clone. A narrow topic saves wakes, not REST reads.
- Each caller has one place: the last batch it took. The topic never moves the place. It only
  chooses which new lines the wait is told.
- Notes about the caller's place and about GitHub's health reach every caller.
- A riding line does not end a wait. It comes with the next batch, at the latest at the deadline.
- A wait whose topic changed is told so once, with a count of the lines the new topic hides.
  Taking that batch passes them for good. A copied trailer never changes the topic.
- The app part of `--as` only sorts a post into `agents` or `peers`. Only a recorded id makes a
  post quiet. Typed words are never quiet.
- Coverage is proved for the catch-all, the root's wait. It rests on one rule: the root waits as
  one (PR 13).
- Who acts is a rule (PR 13). Each topic has one handler, named in its brief and on the
  dashboard, and the root handles the rest. A handler reads REST before it writes, stops if the
  item is already answered, and records its post with `own`. Two handlers can still both write.
  `failed` or `alarms` rides for the root only while its handler does the work.

The topic types are in a new pure module, `Watch/Topic.lean`. `OutsidePolicy` and `--pr` are gone.

## Statements: 112 become 129

- New: 20 (`Topic` 4, `Wake` 4, `Deliver` 12). Removed: 3 (`Wake` 2, `Deliver` 1), each replaced
  by a new one. Restated: 23 (`Wake` 5, `Deliver` 18). Unchanged: 86.
- Row totals: 7a 13 to 19, 7b 17 to 25, 7c 24 to 27 (54 to 71).
- `tasks/502-watch.md` (statements, Amendment 1's delta) names each one. The coverage statement is
  TheCatchAllHearsEverything. Three are still EXPENSIVE.

## Cloud host profile (summary of `DESIGN.md`)

Ten rows: disk, time, cpu, rest, token, asset, verify, slug, wake and fleet. Seven have one
read-only command, which `build --fetch` runs from PR 11. It prints one `watch: host:` line per
failed row. Time, wake and slug are the caller's own checks, so for them it prints `unchecked`.

- The REST limit comes from the `x-ratelimit-limit` header: 5,000 an hour for a user token.
- A wait may run one poll (90 seconds) past its deadline, and 30 seconds are a margin. So `--max`
  minutes plus two minutes must fit in the command's time bound: 7 under `timeout 590`, and 27
  under a 30-minute Monitor.
- The tool is fetched and verified offline at session start, against a trusted root pinned under
  `.github/`. A setup-phase copy is only a cache. Row 11 needs one real run on Claude cloud.

Providers (every `--max` but Claude's is a starting value):
- **Claude Code cloud**: the baseline. Needs the Claude GitHub App. `--max 7`, or 27 under Monitor.
- **Codex cloud**: not yet. Its agent phase cannot read GitHub by default. `--max 4`, `timeout 360`.
- **Cursor cloud agents**: baseline once `build --fetch` passes there. Its CI subscription goes
  off beside a wait. `--max 7`.
- **Antigravity remote agents**: not yet. Its pages state no network, time limit or identity.
  `--max 5`, `timeout 420`.

## Rejected

The full reasons are in `REVIEW-LOG.md` (Amendment 1).
- **Routing by claims**, the structurally different shape: each fact goes to one live claimant of
  its topic. It needs leases, a dead claimant loses what it was shown, and no disk across
  containers can hold a claim.
- **Ranked topics**: one caller hides facts from another, and your words could wait 30 minutes.
- Also: a required `--topic`, a saved `subscribe` verb, a mark per topic, and narrowing the shared
  poll.

## Tradeoffs

- A narrow caller's place moves past what its topic hides.
- Coverage rests on the root's wait being a catch-all. The tool cannot warn when none waits.
- A handler respawned without its flags is a second catch-all. `status` shows it only by its
  `(catch-all)` tag.
- A riding kind whose handler stopped reaches the root up to `--max` minutes late, never lost.
- A standing topic agent re-reads its context at every deadline (about 70k tokens over 99
  minutes, one run). Hence question 12.
- Each container polls on its own, on one REST limit, so at most three wait at once.

## Questions for the owner

10. The root is always the catch-all. `outside` already rides by default (default 6). Once a
    handler of `failed` or `alarms` is named, may the root let that kind ride too? `failed` only
    while no PR owner it would resume waits on CI. Recommended: yes.
11. `peers` stays off by default. Then an issue comment you make through the Claude app wakes no
    Claude caller, the root included, unless its wait adds `peers`. Your review-thread posts still
    wake the root. Recommended: yes. A no makes every caller hear `peers`.
12. Topic agents are sessions of their own or short-lived. Standing subagent loops wait for PR 12.
    Recommended: yes.
13. Verify the tool offline against a pinned root file, or allow the Sigstore hosts everywhere.
    Recommended: the pinned file. After a key rotation you renew it on your device:
    `gh attestation trusted-root > .github/attest/trusted_root.jsonl`, in a PR that changes only
    that file, which you merge.

Root defaults the owner may overrule on PR 0b: at most three containers wait at once until PR 12
reports (default 14). A Codex task does not wait until the owner allows agent-phase GET to
`api.github.com` with a read-only token (default 3c).
