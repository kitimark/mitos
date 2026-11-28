# One Lean waiter for GitHub (#502)

## In short

The root waits on GitHub with a bash script under `Monitor`. The script trusts a footer that anyone
can type (#501). Only the root can use it, so Codex and the root cannot hear each other (#336). And
`Monitor` stops every 30 minutes, so the root wakes just to re-arm it: about 100M tokens in one
measured 12-day session.

This design replaces it with one command, `.claude/scripts/watch.sh wait`, backed by the
repository's own Lean tool, `mitos-gate`. Every agent uses the same command: the root, PR owners,
agents that each handle one topic, Codex. Each wait says with flags what its caller wants to hear:
kinds of line (your words, other agents' posts, checks that passed or failed, pull request changes,
alarms), on the whole repository or on some issues and pull requests. A wait blocks until something
its caller hears needs it, prints the news, and exits with the exact command to run next, flags
included. No process stays running: whoever is waiting reads GitHub once a minute for the whole
clone, and each caller keeps only where it stands. Who wrote a post is decided by what GitHub names
(the posting app) or by an id the agent recorded, never by the footer. The baseline host is a
provider's cloud container, for the root and for every other agent (Cloud host profile).

It ships as 21 small PRs, one of them optional (PR 14), and PR 0b, which amends the plan for
topics and the cloud baseline (`AMENDMENT-1.md`). Four may start now: the plan (PR 0), two fixes of
#501 in today's bash watcher and in `pr-state.sh`, and one fix of a hang in `pr-state.sh`. The Lean
rows wait until you merge the plan, and rows 7a to 13 wait for PR 0b too, after you answer
questions 10 to 13 below. The bash watcher is deleted last, after a week of use and your sign-off.
The Lean in this package is a contract: it was written without a Lean toolchain and never
type-checked, so each Lean PR starts by type-checking its part.

## Questions for you

You answered PR 0's part A on 27 November. Two answers changed the design, and amendment 1
(`AMENDMENT-1.md`, landed by PR 0b) folds them in: each agent subscribes to its own topics (5a),
and a provider's cloud container is the baseline host (2b). It adds four questions, 10 to 13.
Answer them on PR 0b, for example `10 yes, 11 yes, 12 yes, 13 pinned`. Part B lists the defaults
the root takes as its own choices: PR 0 and PR 0b record each with its reason in
`tasks/502-watch.md`, and merging them accepts them. Say no to any of them on PR 0b to change it.
`PR-SEQUENCE.md` (Gates) says which PRs wait for which answer.

### Part A: yours

Answered on 27 November:
- **1. No resident process: yes.** One shared poll per clone, in place of a watchd daemon. News
  can take up to about two minutes, and your words up to about one. Nothing watches while no one
  waits: the next wait catches up from the files and from the last day of posts and closes, and a
  clone left with no wait for more than about 23 hours says so. Building it is an estimated 35M
  builder tokens across the Lean rows, PR 3c included, plus verifiers (`tasks/502-watch.md`,
  budget). The sketch was never elaborated, so this is a rough number.
- **2b. Where the root runs: a provider's cloud container,** the baseline for every agent. In your
  words: "what's the best practices for cloud remote. it may use for another agent like codex, and
  another agent provider as well." The Cloud host profile below answers it.
- **2c. PR 12's spend: yes.** Its six idle sessions run in cloud containers, each about 2 hours,
  three per arm, and you start them (or the root does, if its harness can start a session). About
  12 label changes on a scratch draft PR each start one `gate` run, which does not rerun the cheat
  corpus. Tokens: at most about 11M for the arms and about 8M for the canary day (Alternatives).
- **3a. Getting main's tool: the attested release asset,** built on each push to `main`, fetched
  at session start and verified offline (question 13).
- **5a. Your Claude-app posts: per-agent topic subscriptions.** In your words: "i think the daemon
  could support specific each agent would like to subscribe. so, i may have multiple agents handle
  each topics independent." Each wait names its topic (Usage). The old yes or no is now one kind
  of a topic, `peers` (question 11).
- **8a. pr-state's rule: yes.** Land's rule plus the #501 fix. Four classes change against today's
  jq, each listed in `tasks/502-watch.md` (modules, the Voice note).
- **8b. land's rule: yes.** PR 3c is required, no longer optional. It changes `Snapshot/Types.lean`,
  `Snapshot/Fields.lean`, `Snapshot/Obs.lean` (with its proofs), the reader in `SnapshotCli` and
  the fixtures.
- **9. Deleting the bash watcher: yes,** once PR 15's gates hold (the bootstrap, the canary, the
  measurement passing, and a week of use that the root records on the dashboard).

Open, from amendment 1:
- **10. The root is always the catch-all.** Its wait names no `--topics` and no `--on`, so it is
  told every kind but `peers`. `outside` already rides for every wait, the root's included
  (default 6), and the root reads those lines itself when they come. Once a handler of `failed` or
  `alarms` is named in its brief and on the dashboard, may the root let that kind ride too?
  Recommended: yes. A `--ride` list replaces the default, so the root's names `outside` again. It
  keeps waking on `passed`, since a green gate is what it merges on, and `pulls` cannot ride at
  all. A head line where one check newly passed and another newly failed is both kinds, so it
  still wakes the root. A red check on a pull request belongs to that PR's owner, and only the
  root resumes one, so the root lets `failed` ride only while no PR owner it would resume waits
  on CI (Usage).
- **11. `peers` stays off by default.** A post you make through the Claude app on an issue comment
  is then heard by a Claude caller only when it asks for `peers` (another app's caller hears it as
  `agents`), and pr-state already reads such an unrecorded post as an agent's answer. That
  includes the root: its catch-all does not hear your Claude-app issue comments unless its wait
  adds `peers`. Your review-thread posts through the app carry no app key, so they still wake the
  root. A Claude agent that must hear Claude-app posts asks for `peers`. Recommended: yes. A no
  makes every caller hear `peers` by default.
- **12. Topic agents are sessions of their own, or live only while they have work.** A standing
  subagent that loops on a bounded wait inside the root's session re-reads its context at every
  deadline (Tradeoffs). Such loops wait until PR 12 measures their idle cost. Recommended: yes.
- **13. How the tool is verified.** Offline, against a trusted-root file pinned under `.github/`
  and renewed by a PR you merge when GitHub rotates its keys (several times a year); or online,
  with the Sigstore hosts allowed in every environment. Recommended: the pinned file. It is one
  path for every provider, and a rotated root fails closed to the bash watcher or the bounded `gh`
  loop until the renewal merges. After PR 15 deletes the bash watcher, only the bounded `gh` loop
  is left in that time, and it does not hear the root's posts. The renewal: on a host that reaches
  the Sigstore hosts (your own device, or an environment where you allowed them),
  `gh attestation trusted-root > .github/attest/trusted_root.jsonl`, in a PR that changes only
  that file. It is under `.github/`, so it gets an `opus` verdict and you merge it.

### Part B: the root's defaults

Each is an implementation choice that `kitimark-mode` (Decide, don't ask) leaves to the root.
- **2a. Transport.** `Monitor` with a wait that exits on the first event. The background-shell ban
  stays, and PR 14 lifts it only if PR 12's numbers show it is worth it and you say yes then.
  Exit-on-event saves about 66M of the about 100M; lifting the ban would save about 27M more, with
  the idle-stop risk (Alternatives has the arithmetic).
- **3b.** `pr-state.sh` uses main's tool for its unanswered column once PR 11 lands. Until then it
  keeps its jq, with PR 3a's fix.
- **3c.** An outside agent (Codex, Cursor) gets the tool the way 3a decided, through
  `watch.sh build --fetch`. An environment that can read GitHub but cannot get the tool keeps a
  bounded `gh` loop and does not hear the root's posts until it can. Under Codex's defaults the
  agent phase has no internet and no secrets, so neither `watch.sh` nor a `gh` loop can read
  GitHub there: a Codex task does not wait. It reports its head and stops, and the root hears its
  pull request. Its setup phase has internet, so the toolchain or the tool can be fetched there, a
  cache of up to 12 hours. The root asks you to allow agent-phase GET to `api.github.com` and set
  a read-only token there when Codex first takes a row.
- **4. Placement.** All the Lean goes in `gate/`, in the one `mitos-gate` binary. The IO part holds
  the offer and ack logic, so it bears on trust too, and one binary keeps one build and one
  bootstrap. The other choices were the IO part in its own `lean_exe`, or a separate package.
- **5b.** Agents record their review-thread reply ids with `watch.sh own`. GitHub names no app on
  review threads, so an unrecorded reply wakes every waiting agent that hears `words`. A recording
  hook can make this automatic later. `pr-state.sh` keeps its footer hint there.
- **6. Outside accounts.** A wait with no `--ride` lets `outside` ride: another account's pull
  request lines come with the next batch and never end a wait alone, and a wait that holds only
  such lines prints them at its deadline. `--ride none` makes them wake. A caller that wants only
  them waits with `--topics outside`, a digest printed at its deadline, or adds `--ride none`.
- **8c.** No app besides `claude` and `cursor` answers your words without its footer. A Codex reply
  then answers only with its footer, as in `land` today, so a Codex-built PR whose replies drop the
  footer does not read merge-ready until a footer or Claude reply exists.
- **14. At most three containers wait at once,** and fewer while more than five of your pull
  requests are open, until PR 12 reports. Each waiting container is its own clone with its own
  poll, on the one REST limit of the account's token, so containers × (6 + 3 × open owned heads)
  × 60 stays under about 4,000 an hour. That leaves the rest of 5,000 for pr-state, the builders'
  own `gh` calls and you (Cloud host profile). Raising it waits for PR 12's request counter and
  conditional requests.
- **7. #502's calls**, restated, follow from the above: (1) lift the ban: not now, see 2a; (2) build
  the daemon now: build the waiter now, see 1; (3) the classifier in `gate/`: yes, see 4; (5) #501
  is closed by PR 1 and PR 3a, and made structural by PRs 3 and 13, and #38 stays open. Call (4),
  an Actions workflow that writes events to an issue, is already answered no on #502.

## Problem

The root waits on GitHub through `.claude/scripts/watch-github.sh` under `Monitor`. #502 names
three problems:
- The script decides "the owner said this" by the footer, which anyone can type. A typed owner
  comment that quotes an agent's footer is dropped (#501).
- Only the root can use it. Codex and Claude PR owners cannot share it, so they cannot hear each
  other (#336).
- `Monitor` stops after 30 minutes, and each re-arm is a wake that re-reads the root's context. One
  measured 12-day session had 437 such expiries, about 100M tokens.

You asked for "a daemon like docker", a resident process every agent can subscribe to. On 27
November you added two requirements: each agent subscribes to its own topics, so several agents
can each handle one topic independently (5a), and a provider's cloud container is the baseline
host for every agent (2b). These constraints decide the shape more than the daemon ask:
- The harness stops a background shell at 2 hours and pauses an idle cloud session a few minutes
  after its last turn (Terms). `Monitor` runs at most 30 minutes, and only stdout lines wake it.
- GraphQL is blocked. Every read is REST, and the REST limit is shared by every agent on the
  account. The `x-ratelimit-limit` header says which limit applies; GitHub documents 5,000 an hour
  for a user token.
- Agents post through the owner's login. GitHub names the app on an issue comment
  (`performed_via_github_app`) but on no review comment or review (checked live).
- Logic belongs in Lean with proved statements, and `gate/` is trust infrastructure. Lean v4.35 has
  file locks (`flock`, Terms), an atomic rename, random bytes and the wall clock. It has no fsync.
- The cloud container has no `lake`, and it cannot reach the Actions artifact host. Main's tool
  cannot run there yet, so the bash watcher stays until it can.
- A container's disk is thrown away; at most a setup snapshot survives. Each container is a clone
  of its own, with its own poll, so a subscription cannot live in a file one container shares with
  another.

## Terms

- **Level view**: what is true now (open pull requests, their labels and assignees, the checks on
  the owner's heads), compared as a whole with what a caller last acknowledged, instead of a list
  of events.
- **Feed**: the events that are not levels (your posts, closes, and items that could not be read),
  kept for a day and numbered by the poll that first read them.
- **Lease**: a short lock on a file that lets one waiter at a time refresh the shared view. It uses
  `flock`, the operating system's lock on an open file, which ends when the process does.
- **Generation**: a random id of one shared state. A new one tells each caller that its place no
  longer applies, and it hears a "starting over" line.
- **Offer**: a printed batch with a number. It counts as read only when the next wait passes that
  number with `--seen`.
- **Coalescing window**: 60 seconds in which news gathers into one batch. Words that may be yours
  (typed, or on a review thread) do not wait for it.
- **Attested release asset**: a file attached to a GitHub release, with a signed statement from
  GitHub Actions that says which workflow and commit built it. `gh attestation verify` checks that
  statement, so a tool fetched this way is known to be `main`'s own build.
- **Idle stop**: a cloud session pauses a few minutes after no agent is in a model call or a
  foreground command, and that ends any background shell in it. A pause keeps the files; a
  container that is reclaimed loses them.
- **Contract depth**: the Lean states its types, functions and statements, but it was never
  type-checked and its central functions are stubs. Build depth, which the repository asks for
  before a row's issue links its design, means a sketch that type-checks plus named fixtures.
- **Shim**: `.claude/scripts/watch.sh`, a short bash script that finds the clone, the owner and
  main's tool, then runs the tool. All the logic is in the tool.
- **Echo**: the change a caller's own recorded write causes, such as a label it added. It is
  hidden from that caller only.
- **Tier**: the rank of a line in a batch: words (never cut), lines about your pull requests, then
  lines about other accounts' pull requests (cut first).
- **Kind**: what a line is about, one of eight: `words`, `agents`, `peers`, `passed`, `failed`,
  `pulls`, `outside` and `alarms` (Usage).
- **Topic**: the kinds a caller hears, about the whole repository or some issues and pull
  requests.
- **Subscription**: a topic plus the kinds that ride along. Each wait names it with flags, and the
  trailer prints it back.
- **Catch-all**: a wait with no `--topics` and no `--on`. It hears every kind but `peers`. The
  root's wait is one.
- **Ride along**: a line that does not end a wait by itself; it is printed with the next batch, or
  at the wait's deadline. Only `passed`, `failed`, `outside` and `alarms` can ride. A line of two
  kinds rides only when both ride.
- **Blind**: a wait that ends without a recent successful read of GitHub. It says so and exits 4.

## Usage (caller's view)

One command for every caller. The output is plain lines, and every end names the exact next
command after `next: `.

```
.claude/scripts/watch.sh wait   --as <app>/<name> [--seen <n>] [--topics <kind>[,<kind>]...]
                                [--on <n>[,<n>]...] [--ride none|<kind>[,<kind>]...]
                                [--max <min>] [--since <UTC>]
.claude/scripts/watch.sh own    --as <app>/<name> label|unlabel|assign|unassign <pr> <value>
.claude/scripts/watch.sh own    --as <app>/<name> merge|close <pr>
.claude/scripts/watch.sh own    --as <app>/<name> comment|review-comment|review <id>
.claude/scripts/watch.sh status [--as <app>/<name>]
.claude/scripts/watch.sh build [--fetch]     # --fetch and the host checks come with PR 11
```

`--as` names the caller. The first part is the GitHub app it posts through, which is its class.
The second part is its own name. The app part selects nothing: it only decides whether an app's
post is another agent's (`agents`) or one through the caller's own app (`peers`), and whose
recorded ids make a post quiet. `wait` blocks until something this caller hears wakes it, or until
`--max` minutes pass (27 by default). It prints a batch and exits.

**Topics.** The other three flags say what the caller hears. They are saved nowhere: the trailer
prints back each one that is not at its default, so a caller that runs the text after `next: `
keeps its topic, and a lost state folder loses nothing.

| Kind | Its lines |
|---|---|
| `words` | a post no app names: your typed words, a review-thread post no one recorded, a post that could not be read |
| `agents` | a post through an app other than the caller's |
| `peers` | a post through the caller's own app: its provider's other sessions, and your own posts through that app |
| `passed` | a head line where a listed check newly finished and passed: `success`, `skipped` (a label run skips `prove`) or `neutral` |
| `failed` | a head line where a listed check newly finished with any other conclusion, `cancelled` and one never seen included |
| `pulls` | one of your pull requests opened, relabeled, reassigned, merged, closed or gone |
| `outside` | the same for another account's pull request |
| `alarms` | `ci` health: no run, queued, stale, CodeRabbit skipped, a head unread |

A head line where one check newly passed and another newly failed is both `passed` and `failed`.
"Newly" is against the caller's acked place, so two checks that finish in two polls of one wait
make one line. Such a line is told to a caller that hears either kind.

- `--topics`: the kinds this caller hears. Default: every kind but `peers`.
- `--on 502,571`: only lines about these issues or pull requests. Default: the whole repository.
  A `ci` alarm about no pull request (`queued`, `stale`) is for the whole repository only.
- `--ride`: kinds that are told but do not end the wait. They come with the next batch, at the
  latest at the deadline. Default: `outside`. Only `passed`, `failed`, `outside` and `alarms` can
  ride, and a line of both `passed` and `failed` rides only when each of them that the caller
  hears rides. `--ride words` (or `agents`, `peers`, `pulls`) is a usage error, exit 2.
  A `--ride` list replaces the default, so name `outside` again to keep it riding.
  `--ride none` lets nothing ride. A topic whose kinds all ride (`--topics outside` with the
  default ride) is a digest: it ends only on a note or at its deadline, and `--ride none` makes it
  wake.
- Notes about the caller's own place and about GitHub (`starting over`, `redelivering`, `GitHub
  failing`, a changed topic) reach every caller, whatever its topic.
- A wait with no `--topics` and no `--on` is a **catch-all**: it hears every kind but `peers`. The
  root's wait is one.

| Exit | Meaning | What the caller does |
|---|---|---|
| 0 | a batch, or one line `watch: no change for <who> in M min; next: ...` | act on the lines, then run the text after `next: ` exactly, `--seen` included |
| 1 | `watch: cannot run: <why>; next: <what>` | do not re-arm at once: read REST yourself, then re-arm after 10 minutes with a Monitor whose command is `sleep 600; <the same wait>`, or keep the bash watcher |
| 2 | usage. For `wait`, first one stdout line `watch: usage: <why>; next: <what>`, in the shape of the exit-1 line, so a Monitor wakes on a mistyped arm; the usage text goes to stderr | run the same command once in the foreground under `timeout 60` and read stderr, fix it, then re-arm |
| 3 | a newer wait of the same caller took over (stderr only) | do nothing. A Monitor that ends with no stdout line: run `watch.sh status`. If a wait of this caller still runs, do nothing, so a double arm never livelocks. If none runs, run the same command once in the foreground under `timeout 60` and read stderr before re-arming |
| 4 | `watch: blind for M min, GitHub failing since <time>: <why>; next: ...` | re-arm with the text after `next: `; read REST for anything urgent |

These are the caller's half of the guarantees: a caller that copies the trailer never spins, and
one that drops `--seen` hears its whole backlog at every deadline. PR 13 writes this table into the
rules, and PR 12 measures whether a Monitor's exit notification carries the code. The `timeout 60`
keeps the foreground run of rows 2 and 3 from being a full wait (27 minutes for the root): a broken
command fails within seconds, and a sound one prints a batch or is stopped with no line, which
loses nothing. Do not probe with `--max 0`: its trailer prints `--max 0` back.

**The root**, under Monitor, at the start of a session, is a catch-all:

```
Monitor  command: .claude/scripts/watch.sh wait --as claude/root --since 2026-11-23T08:00:00Z
         timeout_ms: 1800000
```

It prints this:

```
owner comment 3456789 on #512: please split the fixture into two cases
pr #512 head abc1234 checks gate=success,prove=success,scorecard-comment=success,CodeRabbit=success
agent comment 3456801 (chatgpt-codex-connector) on #336: ## Catch-up: review the fix
watch: next: .claude/scripts/watch.sh wait --as claude/root --seen 183467
```

The monitor ends with the batch. The root acts, then re-arms with the command after `next: `,
copied exactly. A wait that does not pass `--seen 183467` prints the same batch once more under
`watch: redelivering offer 183467`, then waits for news. Its acked place does not move until it
passes the number, so a caller that drops `--seen` keeps hearing everything since its last ack.
Offer numbers start at a random six-digit base per caller, and only the exact pending number is
taken. Once the dashboard names a CI-failures agent, the root may re-arm with
`--ride failed,outside,alarms` (question 10): red checks then come with its next batch, at the
latest at its deadline, and never wake it alone. It does so only while no PR owner it would
resume waits on CI.

**Where a wait starts.** `--since` applies only to a caller with no saved state; later waits go by
the acked place. A new caller without `--since` starts from the last day the feed keeps. A caller
whose state was lost, or belongs to another shared state, hears `watch: starting over from the
current state and the feed's last day; read anything older over REST`. A `--since` older than the
feed's day, or a clone left with no successful poll for more than about 23 hours, prints `watch:
some facts this consumer should see are older than the feed keeps; read GitHub over REST`. Your
words older than that still show in pr-state's unanswered column.

**Changing a topic.** A caller may change its flags at any re-arm. Its place does not move: a
narrower topic shows less from the same place, and a wider one shows only what is new since it.
The first batch under a new topic says so, in one `topic changed` line. It names both topics and
what is newly heard and newly hidden, and it counts the facts since the last taken batch that the
new topic hides. Taking that batch moves the place past them, and re-arming with the old flags
does not bring them back, so a caller that narrowed by mistake reads them over REST, or waits
under a new name with `--since`. A count of 0 says nothing was hidden. A copied trailer carries
the same flags, so the line never repeats.

**The root's own writes** are recorded once they succeed, as `watch-own.sh` is today:

```
gh api -X POST repos/{owner}/{repo}/issues/512/assignees -f 'assignees[]=<login>' \
  && .claude/scripts/watch.sh own --as claude/root assign 512 <login>
```

A caller runs one `wait` before its first `own` in a new state folder. A record made before any
poll has no shared state to belong to, so `own` warns that it is dead and the echo wakes once. A
merge is recorded only after the merge reports merged (for `merge-async`, after `.status` is
`merged` and the PR reads back merged).

**An owner-comments agent, a CI-failures agent and a PR owner** each wait in one foreground call:

```
timeout 590 .claude/scripts/watch.sh wait --as claude/words --topics words --max 7
timeout 590 .claude/scripts/watch.sh wait --as claude/ci --topics failed,alarms --max 7
timeout 590 .claude/scripts/watch.sh wait --as claude/pr-512 --on 512 --max 7
```

The CI-failures agent's batch, whose trailer keeps its topic:

```
pr #512 head abc1234 checks gate=failure,prove=success,scorecard-comment=success,CodeRabbit=success
watch: next: .claude/scripts/watch.sh wait --as claude/ci --topics failed,alarms --max 7 --seen 402118
```

`--max 7` under `timeout 590` follows the bound in the Cloud host profile. The trailer prints no
`timeout`, so the agent puts `timeout 590` in front of the `next:` text each time. Each such agent
is a session of its own or lives only while it has work (question 12), and it acts only as Who
acts (Shape) says. In this repository a red check on a pull request belongs to that PR's owner
(`kitimark-mode`): a running PR owner hears it on its own `--on` wait, and the root resumes one
that returned or gives the pull request a new one. The CI-failures agent handles what no PR owner
holds, the `ci:` alarms (failures no PR owns, which `kitimark-mode` gives a researcher first), and
only observes every other red check.

**Codex, or any outside agent,** runs the same command with `--as chatgpt-codex-connector/<name>`
under a time bound, for example:

```
timeout 360 .claude/scripts/watch.sh wait --as chatgpt-codex-connector/pr-571 --on 502,571 --max 4
```

The bound and 4 are starting values, not measured, and they meet the bound in the Cloud host
profile. It loops by running the command after `next: `. It hears the root's catch-ups, and the
root hears its posts. It records its review-thread reply ids with
`watch.sh own ... review-comment <id>`, because GitHub names no app on those routes. This needs agent-phase GET to `api.github.com` and a read-only token. Under Codex's
defaults it has neither, so a Codex task does not wait at all: it reports its head and stops
(default 3c). Another outside agent that can read GitHub but cannot get main's tool keeps a
bounded `gh` loop.

**`status`** reads and writes nothing on GitHub. With `--as` it adds the caller's last
subscription to its offer and poll lines; with no caller it lists this clone's callers:

```
caller claude/root: hears words,agents,passed,failed,pulls,outside,alarms on the repository, riding outside (catch-all); waiting
caller claude/ci: hears failed,alarms on the repository; not waiting
caller claude/pr-512: hears words,agents,passed,failed,pulls,outside,alarms on #512, riding outside; waiting
overlap: claude/ci and claude/pr-512 both hear failed,alarms
watch: callers in other containers are not listed
```

A `riding` part lists the riding kinds the caller hears, and is left out when there are none:
`claude/ci` lets `outside` ride by default but does not hear it. An `overlap` line names two
callers, neither a catch-all, that hear one kind on the same items: here the owner of #512 handles
its red checks and the CI-failures agent observes them. It is a hint for whoever briefs the agents,
never a lock (Who acts). The root's catch-all overlaps every topic by design and is never named.
So a second catch-all, such as a handler respawned without its flags, shows only as a second
`(catch-all)` tag (Tradeoffs).

**`pr-state.sh`** asks the same Lean rules which owner words are unanswered:

```
mitos-gate watch unanswered --owner <login> --issue-comments ic.json \
  --review-comments rc.json --reviews rv.json        # prints {"512":[3456789]}, exits 1 on any refusal
```

It takes no app flag: the apps that answer are the slugs of `Speech.apps`, as in `land`.

## Shape

**Mental model.** GitHub is the record. One clone keeps one shared observation of it. Whoever is
waiting refreshes the observation when it is older than a minute, under a short lease. Each caller
keeps only where it stands: its acked place and its own records. Each wait looks at the observation
through its caller's subscription, a lens that changes what that caller is told, never what the
clone observes or where the caller stands: `report = notes ++ lens (facts)`. Nothing runs while
nobody waits. GitHub's clock, not the local one, decides what the feed asks for. This is the job
redone from first principles (`principle-redesign-from-first-principles`): the job is "wake the
right agent when GitHub changes", and in this harness a waiter that polls does it with nothing to
supervise.

**Data** (`sketch/gate/MitosGate/Watch/`). The shared state holds the level view, the feed with its
cursor on GitHub's clock, a random generation, the poll count and the failure streak. A caller's
state is its acked place (generation, view, feed position, whether it was told GitHub is down) and
at most one pending offer, each with the subscription it was taken under, as data only: no file
holds a setting. Write records belong to one caller; post records are shared by its class. The topic
types are in `Watch/Topic.lean`. Every file carries a version, and every load checks what the proofs
assume. A file that fails is set aside.

**One wait.**
1. The shim stamps the start, fetches `main` once (at most 20 seconds), finds main's tool, and runs
   a private copy of it with stdin closed.
2. The wait claims the caller, so an older wait of the same caller exits 3.
3. It takes the pending offer if `--seen` names it exactly.
4. It loops: check the claim, read the shared state, work out what this caller has not acked, what
   its subscription keeps of that, and whether any of it wakes, then deliver, poll, sleep 2 seconds,
   or end. A poll takes the lease, reads the shared state again (another waiter may have polled),
   reads `main` for GitHub's time, then the fixed routes from the cursor, then each head that is
   due, and writes by rename.
5. Every end takes the caller's lock, checks the claim again, re-reads its state, and saves the
   offer that one pure step makes, with the batch, from the shared state its last step reported from
   (never a newer read); then it prints. A wait whose report holds anything delivers it, at the
   latest at its deadline; only an empty report ends quiet or blind. An IO error that escapes prints
   one `watch: cannot run` line and exits 1, so a Monitor still wakes.

**Decisions.** `tasks/502-watch.md` names the proved statement behind each one.
- **Level, not edges.** A caller compares its acked view with the current one, so a gap between
  waits repeats nothing and loses no state. Posts and closes live in the feed, keyed so that a
  reread adds nothing, and numbered by poll, so a post GitHub lists late still counts as new. A
  gap longer than the feed keeps is told, never silent.
- **GitHub's clock.** Each poll reads `main` first with `--include`, and its `Date` header is the
  poll's time. The feed asks from its cursor minus an hour, and a new feed asks a day back. A
  queued run's age is measured on that time too. The local clock only paces sleeps, the deadline
  and how long a head has waited for its first `ci` run, which is local at both ends.
- **One poll per clone, one view per caller.** REST reads no longer grow with the number of
  waiters. Identity and echoes stay per caller. The poll steps the state it re-read under the
  lease, so two waiters never both step one state. The poll stays whole: a narrow caller saves
  wakes, not REST reads, and an outside pull request is still read only from the list.
- **Identity is the app GitHub names, or a recorded id, never the footer.** Identity classifies a
  post and never hides it: the app part of `--as` makes an app's post `agents` or `peers`, and only
  a recorded id makes a post quiet. Your typed words are never quiet, even with a footer. On review
  threads only a recorded id makes a post quiet; an unrecorded one is shown as
  `no app key: the owner or an unrecorded agent`, never as your words. An empty `COMMENTED` review
  is not a post. Each route has its own reader, one boundary per source
  (`principle-boundary-discipline`).
- **One unanswered rule.** `watch unanswered` is land's rule (`speaks`: the owner's login, no app,
  no footer; `answers`: an app in `Speech.apps`, or the footer) with the #501 fix: a typed issue
  comment is words even with a footer, and never answers (question 8a).
- **Offer and ack.** A batch counts only once its caller passes the trailer's exact number, so a
  lost turn replays instead of losing events. The offer marks the same shared state the batch was
  reported from, so taking it acks nothing the subscription selects that the batch did not show. A
  caller that copies the trailer
  then blocks until news; one that ignores it gets one replay, then blocks. News includes an alarm
  that time starts, such as a head that has waited too long for `ci`.
- **A topic is a lens on one wait.** `facts` (every waking change, post, close and unreadable item
  since the caller's place that its own records do not explain) reads no subscription and no app,
  so it is one list for every caller with the same place. `notes` (its place, and GitHub's health)
  reach every caller. The lens keeps the facts of a kind the topic hears about its items, and
  marks the kinds that ride. The kind is a closed type of eight, and riding a closed type of four,
  so `--ride words` cannot be written. Left out on purpose: labels, milestones, issue versus pull
  request, one check, one app. Label and milestone membership moves, and the view holds no issues;
  whoever briefs an agent turns a milestone into numbers for `--on`.
- **A place does not depend on a topic.** One mark, one offer and one ack per caller, whatever its
  flags, so there is no mark per topic and no saved subscription. A caller that changes its topic
  is told once what is newly heard and newly hidden, and how many facts since its place the new
  topic hides; taking that batch passes them, and facts before its place are not replayed.
- **Coverage is one caller's form, and it rests on one rule.** A filter hides lines by design, so
  the guarantee is stated for the form the root runs. A catch-all is told every fact but `peers`;
  words that may be yours (typed, or an unrecorded review-thread post) wake whoever hears `words`
  about their thread, whatever it lets ride; and a quiet or blind end of a catch-all hid only
  `peers`. That a catch-all waits at all is a rule
  (PR 13: the root's wait is one), because callers in different containers share no state the
  tool could check.
- **Riding only delays.** A riding line is in the report like any other. It does not end the wait,
  and the wait delivers it at the latest at its deadline, so a quiet end acks nothing the
  subscription selects.
- **Who acts is a rule, not a lock.** One handler per topic, named in its brief and on the
  dashboard; the root handles what no line names. A handler reads the item over REST before it
  writes, stops if a post or commit already answers it, and records the id of its post with `own`.
  A second subscriber of a topic observes. Two handlers woken by one poll can still both write: the
  rule narrows that window, it does not close it. Only the root resumes agents, so `failed` or
  `alarms` rides for the root only while its named handler handles it end to end (`outside` rides
  by default, and the root reads those lines itself). Riding lines still reach the root
  with its next batch, at the latest at its deadline, and the root takes a kind back when a riding
  line shows a fact unhandled. PR 13 writes this into the rules.
- **Failure is visible.**
  - A failed poll changes nothing but the failure streak. Its reason names the route in fixed
    words, never what `gh` printed.
  - A wait ends "no change" only after a recent successful read; otherwise it ends blind with
    exit 4. At five failures in a row every caller hears a `GitHub failing` line once, and every
    blind end repeats it.
  - A head whose read of one route (its checks, its reviews, or the second look for a missing run)
    fails five polls in a row becomes an `unread` line that names the route.
  - Inside a good answer, an item the reader cannot read (your comment without the app key, for
    example) is told once as `could not be read`, and the rest of the poll applies. A whole answer
    of the wrong shape still fails the poll (Tradeoffs).
  - A state file that does not read is set aside, and its caller hears the reset. A file of a
    newer version is left in place and the wait exits 1.
- **Types carry their checks** (`principle-type-system-discipline`). Per-head reads are planned
  only for open pull requests by the owner. A repository name or SHA that could add a path segment
  does not type-check. An excerpt carries its proof that it is one printable line. The route list
  can only read. `gh`'s stderr never leaves `Gh.lean`.
- **What wakes.** Words that may be yours go out at once: typed words, a review-thread post that no
  one recorded (an unrecorded agent reply there looks the same, so it goes out at once too), and a
  post that could not be read. Other news, other apps' posts included, waits one 60-second window. A
  finished listed check wakes, also on a new head; its line is `failed` when a newly finished check
  does not pass (`success`, `skipped` or `neutral`), `passed` when one does, and both when both
  happen, so a label run's skipped `prove` is `passed` and a green gate beside a new red check
  still wakes a root that lets `failed` ride. Pending checks, `main` moving and a condition
  clearing are absorbed. A pull request that left the open list is one line with its close, also
  when the close was read in the same poll that still listed it open. The cap of 30 lines never
  cuts words or notes, cuts outside lines first and head lines last.
- **Bounded waits.** One poll budget (90 seconds) past its deadline, a wait's decision is to end;
  a poll in flight is bounded by `gh`'s timeout, which is tested, not proved. A wait that finds
  the lease busy sleeps instead of polling. A wait whose polls succeeded ends quiet, never blind,
  at whatever step it reaches its deadline.

**Interface depth.** The public surface is three verbs and `build`, plus `unanswered` for one hook
(and `read` and `replay`, refused outside tests). A topic is three flags whose defaults make the
catch-all, so a caller that wants everything names none. Behind them sit the polling and its lease,
dedupe, generations, per-caller echoes, offers, the cut, `ci` health and quarantine. A caller learns
none of these: the shim fills the internal flags (`--state`, `--repo`, `--owner`, `--started`,
`--tool-note`), and `--now` exists only for tests.

**What it does not do.** No resident process, socket or push. It reads no other account's posts
and no outside pull request's head. It writes nothing to GitHub. It never builds inside a wait. It
names no unlisted check. It saves no subscription, routes no fact to one caller alone and holds no
claim on a topic.

## Cloud host profile

The baseline host is a provider's cloud container, for the root and for every other agent (2b).
A host that keeps more, such as your own device, only keeps the cache longer. Each row is one
assumption, how the design meets it, the best practice, and its check. Seven rows have one
read-only command, and from PR 11 `watch.sh build --fetch` runs those seven and prints one
`watch: host: <row>: <what failed>` line per failed one. Time, wake and slug are the caller's own
checks: time is arithmetic on the caller's `--max` and bound, wake has no command (a provider's
own subscriptions show only in its settings), and slug needs one of your comment ids. For those
three it prints `unchecked`. A `cannot run` line names the row that stopped it.

| Row | The design assumes | How it is met | Best practice | Check |
|---|---|---|---|---|
| disk | The disk is thrown away; at most a setup snapshot survives | Every watcher file is a cache under `<git-common-dir>/mitos-watch/`; flags hold the subscription. A lost folder makes a new caller: the current state and the feed's day, or `--since`. The `own` records go with it and never cross containers, so a new container hears its own earlier review-thread replies again (Tradeoffs) | GitHub is the record. The root's first wait passes `--since <the dashboard's last update>`. Never commit state | `test -w "$(git rev-parse --git-common-dir)"` |
| time | No process outlives a turn, and a command's time is bounded | A wait is one command, and whoever waits polls. `--max` × 60 + 90 + 30 ≤ the caller's own bound in seconds (`timeout` or the Monitor's): 90 for the last poll's budget, 30 for the margin. The 30-second margin is a starting value: PR 12 measures the longest run past a deadline | `--max 7` under `timeout 590` (in Claude Code, a Bash `timeout` parameter of 600000 ms, with `timeout 590` inside the command); `--max 27` under a 30-minute Monitor (28 is the largest the bound allows). No background loop | the caller's own: `[ $((max * 60 + 90 + margin)) -le "$bound" ]`, with `margin=30`. `build --fetch` lacks both inputs and prints `unchecked` |
| cpu | The host runs the asset: one x86_64 Linux binary, linked against the libc it was built with | `build --fetch` runs the fetched copy once, after it is verified and before it is installed, and refuses a host where it does not run with one line | Elsewhere, a local `build`, or the bounded `gh` loop | `<the verified copy> watch status`, which reads only the state folder, exits 0 |
| rest | GitHub answers REST reads; GraphQL may be blocked; `gh` is installed, and its `attestation verify` takes `--custom-trusted-root` | Every route is a `gh api` GET (`OnlyRestReads`) | GET to `api.github.com` is all a wait needs | `gh attestation verify --help \| grep -q -- --custom-trusted-root && gh api rate_limit --jq .rate.limit` |
| token | A read-only credential, with a known limit, and no secret in a file or a line | `gh` holds the credential; its stderr never leaves `Gh.lean`. The limit is the `x-ratelimit-limit` header: GitHub documents 5,000 an hour for a user token, and 60 an hour without one, which a poll spends at once [5] | The host's credential path (a proxy, or a read-only token in an environment variable). Codex needs a token | `gh api -i rate_limit \| grep -i '^x-ratelimit-limit'` |
| asset | Release assets are reachable | `build --fetch` installs main's attested asset into the private `bin/`; `wait` never fetches | Fetch and verify at session start; a setup-phase copy is only a cache | `curl -sfIL -o /dev/null "$(gh api repos/{owner}/{repo}/releases/tags/<the tag row 11 fixes> --jq '.assets[] \| select(.name == "<the asset name row 11 fixes>") \| .browser_download_url')"` (a tag, not `releases/latest`, which skips a prerelease) |
| verify | Verification needs no Sigstore host | Offline, against the pinned trusted root (below) | Renew the pinned file by a PR you merge | the verify command below, run offline on the installed binary |
| slug | An agent's issue comment names a non-null app | `--as <slug>/<name>`. A host whose posts name no app posts no issue comment. If it did, its words would reach every caller as your typed words | Read the slug off your own first comment. On Claude cloud this needs the Claude GitHub App connection, which the package's live check saw on this repository | `gh api repos/{owner}/{repo}/issues/comments/<your id> --jq .performed_via_github_app.slug` |
| wake | One wake source per caller | One wait per name (exit 3) | Turn the host's own wake source off beside a wait: Claude's PR-activity and auto-fix subscriptions, Cursor's CI subscriptions | the caller's own: `.claude/scripts/watch.sh status`; a provider's own subscriptions show only in its settings, so `build --fetch` prints `unchecked` |
| fleet | A small number of containers wait at once | Each waiting container is its own clone with its own poll: about 6 requests plus 2 or 3 per owned head a minute. With 5 open owned heads that is about 960 to 1,260 an hour per container, so 4 containers can pass a 5,000 limit and 3 use most of it (an estimate; PR 12 counts) | At most 3 at once, fewer above 5 open owned heads: containers × (6 + 3 × heads) × 60 under about 4,000 an hour, which leaves room for pr-state, the builders' own `gh` calls and you (default 14). Raising it waits for conditional requests and PR 12's counter | `gh api rate_limit --jq .resources.core` (used and remaining, for every container on the token) |

**The tool.** Fetch and verify at session start is the rule. A setup-phase copy is only a cache:
a setup snapshot lasts about 7 days on Claude, Codex caches a container up to 12 hours, and Cursor
refreshes Builds on a schedule it does not state (with "Update stale builds" on, an agent whose
Build is older than 24 hours pulls the latest default-branch code at start), while `main` moves on
every merge. Row 11
installs only an asset of the commit the shim resolved for `origin/main`. Verification is offline
on every host:

```
gh attestation verify <bin> --bundle <bundle.jsonl> \
  --custom-trusted-root .github/attest/trusted_root.jsonl --repo <owner/repo> \
  --signer-workflow <owner/repo>/.github/workflows/<the release workflow> \
  --source-ref refs/heads/main
```

Then a check that the bundle's source repository id equals `gh api repos/{owner}/{repo} --jq .id`,
because offline `--repo` is matched only against names, and a rename goes unseen. The asset's
commit is compared after the verify, not with `--source-digest`: right after a merge the newest
asset is often of the commit before, which is routine and must be told from a bad asset, so the
shim installs nothing and runs its private copy with `--tool-note`. The id is read
from the same command with `--format json --jq
'.[].verificationResult.signature.certificate.sourceRepositoryIdentifier'`, a path row 11's real
run confirms. The bundle comes from `gh attestation download <bin> --repo <owner/repo>`, which
writes JSON lines, or from the REST answer of `repos/{owner}/{repo}/attestations/sha256:<digest>`
turned into JSON lines with `jq -c '.attestations[].bundle'`. The pinned file is the output of
`gh attestation trusted-root`. It has no expiry, but GitHub rotates its keys several times a year;
an asset signed after a rotation fails closed to the bash watcher or the bounded `gh` loop (after
PR 15, the loop alone) until a PR you merge renews the file (question 13 says where and how). A
key revoked after the file was made is not noticed until it is renewed [5]. Row 11 is not done
before one real run on Claude cloud. One design runner probed Claude cloud live (the release host
and the attestations route answered; the Sigstore TUF host was refused). That is one runner's observation, and it was not replicated.

**Your own device.** The same profile holds. What differs: the state folder outlives sessions, so
an old caller's state stays until it waits again; there is no background cap; the `gh` token is
the one you use yourself, so the agents' polls share its limit with you; GraphQL is not blocked;
and the CPU may not be x86_64, so `build --fetch` refuses it and a local `build` takes its place.

| Host | What its pages say | `--max` | It needs |
|---|---|---|---|
| Claude Code cloud [1] | x86_64 Ubuntu 24.04, `gh` installed. A setup snapshot lasts about 7 days. An idle VM pauses after a few minutes and keeps its files. Foreground commands: 2 minutes by default, at most 10 asked for (`BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` change both); a command that reaches its timeout is moved to the background, not stopped, for 30 more minutes, so `timeout 590` inside the command is what ends a wait. Monitor at most 30. A proxy holds the GitHub credential; GraphQL gets 403. The Trusted list holds `api.github.com` and `release-assets.githubusercontent.com`, and no Sigstore host | 7 under `timeout 590`; 27 under Monitor | the Claude GitHub App connection, so posts name `claude`; `build --fetch` at session start |
| Codex cloud [2] | Container cache up to 12 hours. Setup has internet; the agent phase has none by default and can allow GET, HEAD and OPTIONS to listed hosts. Secrets are removed before the agent phase starts, per its environments page; no page found on 27 November says a proxy passes them to the agent phase. Not verified further | 4 under `timeout 360`, both starting values | agent-phase GET to `api.github.com` and a read-only token (default 3c). Until then neither `watch.sh` nor a `gh` loop reads GitHub in the agent phase, so a task does not wait; the setup phase can fetch the toolchain and the tool |
| Cursor cloud agents [3] | `install` runs when a Build is made, and a Build keeps disk, not processes. Cursor rebuilds Builds on a recurring schedule it does not state. With "Update stale builds" on, an agent whose Build is older than the threshold (24 hours by default) pulls the latest default-branch code at start. The agent has internet by default; a team admin can set another mode. It has its own CI subscriptions | 7 under `timeout 590`, both starting values | `build --fetch` at session start; its CI subscription off beside a wait |
| Antigravity remote agents [4] | Rolled out from 3 November 2026 (v2.29.0) to 9 November per its changelog. A Google-managed environment that clones the repositories, with GitHub by OAuth. Post-clone setup scripts appear only in a later changelog line; the `env-setup.sh` name is not verified. No network policy, time limit or identity is stated | 5 under `timeout 420`, both starting values | the slug check before it posts: an OAuth post may name no app |

[1] code.claude.com/docs/en/cloud-environments, /claude-code-on-the-web, /tools-reference.
[2] learn.chatgpt.com/docs/environments/cloud-environment and /docs/cloud/internet-access (the
developers.openai.com/codex/cloud pages redirect there).
[3] cursor.com/docs/cloud-agent, /cloud-agent/setup, /cloud-agent/capabilities, /cloud-agent/builds,
/cloud-agent/security-network.
[4] antigravity.google/docs/remote-agents, /docs/changelog (/changelog redirects there), /sandbox.
[5] docs.github.com: "Rate limits for the REST API", "Best practices for using the REST API", and
"Verifying attestations offline"; cli.github.com/manual/gh_attestation_verify.

**Not verified.** `gh` and the CPU on Codex, Cursor and Antigravity; a command bound on each of
them; Codex's agent-phase secrets; how often Cursor rebuilds a Build; Antigravity's setup script;
the slugs `chatgpt-codex-connector` (from this repository's posts) and `cursor` (from
`Speech.apps`);
Antigravity's network and identity; whether a wait under Monitor keeps a Claude VM from pausing.
Every `--max` but Claude's is a starting value. A 304 answer to a conditional request does not
count against the REST limit [5], so conditional requests are the first REST saving
(`tasks/502-watch.md`, deferrals).

## Synthesis decision

All three design runners, on three models, dropped the resident daemon. In all three the waiter
polls inside `wait`, state is files, and GitHub is the record. The premise review found that the
premise mostly holds in this harness. The design ships that shape and put the deviation from your
ask to you as question 1, which you answered yes.

The base is candidate-opus (rubric 26, against fable 23 and sonnet 22): the smallest public
surface, per-caller identity and echo, the only honest bootstrap story (keep the bash watcher
until main's tool runs where the root runs), and the best PR order. Grafted onto it, under the one
mental model above:
1. One shared poll with a view per caller (sonnet, fable). Opus polled once per caller, which
   multiplies REST reads, and that was rated blocking.
2. Offer and ack, with a one-replay rule so an unattended caller cannot spin (fable).
3. Types that carry their checks, and the token-on-stderr test (fable).
4. The `ci` alarm statements and the #84 history fixture (fable).
5. One Lean classifier for pr-state on land's classes plus the #501 fix (sonnet), behind PR 3a's
   jq fix until the tool runs where the root runs.
6. A differential replay of every bash-watcher fixture through both watchers before deletion
   (sonnet).
7. A pure `nextMove` with a 60-second window that never holds words that may be yours (sonnet).

Rejected: polling per caller (REST cost); a superseded wait that wakes its caller (livelock);
print-then-commit (loses a batch on a lost turn); cold-start absorption and the footer in the
quiet rule (both hide your words); `--peek` (a second way to wait); an Actions-artifact fetch in
the shared `main-tool.sh` (blocked host, trusted helper); a global "suppressed" flag (one caller's
echo hid it from all); an `own` with no writer; an event journal with sequence numbers (a large
codec that the level view makes unnecessary); hourly reminders (noise); exit 3 meaning both idle
and cannot-run; Codex in `Speech.apps`; and any deletion before a bootstrap.

**Amendment 1.** Three runners redesigned the package for topics and the cloud baseline. All three
made a topic a small closed set of kinds plus a repository-or-items scope, declared by flags on
every wait and printed back by the trailer, with no `subscribe` verb and the shared poll whole. The
base is candidate-fable (judge 28, against opus 21 and sonnet 21): a subscription is a lens on one
wait, the place a caller stands does not read it, and `--ride` replaces the outside policy. The
root's decisions on top of it: checks split into `passed` and `failed` (your own example is "one
for CI failures", and a root that let all checks ride would learn of a green gate only at its
deadline); riding as a closed type of four kinds; a changed topic told once; `status` showing
subscriptions and an overlap hint; the who-acts rule; the idle cost of standing topic agents; and
sonnet's Lean grafts (the kind reader derived from one list, a typed round trip of the trailer's
flags). Rejected: opus's ranked topics and peer taking (one caller hides facts from another, a
`--since` case blocks, and your words could wait up to 30 minutes); a required `--topic`; sonnet's
ack bound to a topic and its coverage statement over a topic nobody runs; a saved subscription;
claims or exclusive routing; a mark per topic; narrowing the shared poll; and any proof claim over
a Json codec or `String.splitOn`. `AMENDMENT-1.md` has the summary and the statement delta.

The judge's must-fix list and review rounds 1 and 2 are in `REVIEW-LOG.md`.

## Tradeoffs accepted

- Up to about two minutes from a change to a wake (one poll plus one window), for no resident
  process and one batch per burst. Your words, typed or on a review thread, wait at most one poll.
- A label added and removed between two of a caller's waits shows nothing, for a level comparison
  that never loses or repeats a state. Merges, closes and posts are events in the feed, and the
  level comparison never folds them away. The 30-line cap still can: a batch with more than 30
  head lines (a fresh caller with many open pull requests) can cut a merge of yours, and the `more`
  line then says to read REST. Ranking such a close with the notes is deferred to PR 7c.
- A fact GitHub lists more than an hour after its own time is lost (the overlap). PR 12 counts how
  late facts are listed.
- An unrecorded agent reply on a review thread wakes every caller that hears `words` at once, even
  with a footer. GitHub gives those routes no app, so it cannot be told from your review words,
  which never wait for the window; the other way would hide or delay them.
- A review-thread id recorded by mistake (an agent records the id of the comment it answers, not
  of its reply) hides that post from every caller of its class for a day. `own` takes the id as
  typed; a read-back check of the id is deferred to PR 8.
- Reviews are read per open head, so a review body posted on a pull request that closes before the
  next poll is never read (inline review comments are read repository-wide and are not affected).
  A reviews answer with one unreadable item fails that head's reviews read until it changes, and
  shows as `unread` after five polls; reading the rest of it is deferred to PR 4 and PR 6.
- With more than 100 open pull requests (a fork flood), a close between two page reads can shift a
  page and hide a pull request for one poll: it reads as having left the open list, then as
  opened. The bash watcher pages the same way. A second look before `gone` is deferred to PR 6.
- `peers` is off by default (question 11), so a post you make through the Claude app on an issue
  comment is heard by a Claude caller only when it asks for `peers` (another app's caller hears it
  as `agents`). GitHub names only the app, so for a Claude caller `peers` holds your Claude-app
  posts and every other Claude session's alike. A class that hears `peers`
  records its own issue-comment ids.
- An agent that posts issue comments with your token and no app (a local CLI, for example) reads as
  your typed words and wakes every caller that hears `words`, itself included. The other way would
  trust text.
- A change you make yourself that equals a write the root recorded in the same poll (you add the
  label the root just added) is hidden from the root. Both act through one account, so GitHub
  cannot tell them apart, and the state is the same either way (#239).
- Until PR 3c lands (question 8b: yes), `land` keeps its footer rule, so `land` and `pr-state`
  differ on a typed comment that ends with a footer.
- An answer whose whole shape is wrong (not an array of pages, an item with no readable id), or an
  open-pulls or runs item that cannot be read, fails every poll until the answer changes or the
  tool is fixed. Every caller hears it as a `GitHub failing` line that names the route, then as
  blind ends. One bad item on a post or close route is told and skipped instead.
- The bash watcher's first-poll scan of every open thread is gone. Your words older than the feed's
  day show in pr-state's unanswered column, and the root's first wait of a session passes `--since`
  the dashboard's last update (PR 13).
- Under default 6, a line about another account's pull request waits until the wait's deadline
  (up to 27 minutes) when nothing else wakes. The same holds for any kind a caller lets ride.
- An edited post is told again, marked `(edited)`. The bash watcher did not re-announce edits.
- What the cap cuts is absorbed, as today, with a `more` line that says to read REST. Words and
  notes are never cut.
- No fsync. A crash keeps the old or the new state file whole, and at worst loses one record, which
  costs one echo line. A consumer file left ahead of the shared one resets with a line.
- The PRs that touch `gate/` or `.github/` are trust-critical (an `opus` verdict, and you merge),
  for the watcher's rules being proved in the same gate as everything else (default 4). The PRs
  that touch only `.claude/`, `docs/process.md` or `plan/` are yours to merge, with a normal
  verifier.
- A private copy of the tool binary sits in the state folder, so a rebuild never races a wait.
- Two clones poll twice, on one machine or in two containers. State is per clone, and every
  container polls on the one REST limit, which default 14 bounds.
- A narrow caller's place passes what its lens hid, so a kind it adds later starts at that place.
  In exchange: one place per caller and no stored subscription.
- Coverage rests on one rule, that the root waits as a catch-all, and the tool cannot warn when no
  catch-all waits. In exchange: no state shared between containers.
- A handler respawned under a new name with no flags is a second catch-all: it gets no `topic
  changed` line and wakes on every fact. `status` shows it only as a second `(catch-all)` tag,
  with no `overlap:` line, so whoever briefs a handler gives it its flags.
- A riding kind whose handler stopped reaches the root up to `--max` minutes late, as riding
  lines, and is never lost.
- Two handlers woken by one poll can both write (Who acts). The rule narrows that window; nothing
  closes it without a lock that containers cannot share.
- A standing topic agent has an idle cost. An agent that re-arms a bounded wait re-reads its
  context at every deadline: the repository's own number is about 70k tokens over 99 minutes for
  one watcher agent (one run). So a topic agent is a session of its own (its own container and wake
  source) or lives only while it has work, and standing subagents that loop inside the root's
  session wait for PR 12's idle-cost counter (question 12).
- In a cloud container a lost state folder is routine, and the `own` records go with it: they
  never cross containers. So in each new container a respawned handler hears its own earlier
  review-thread replies since `--since` again, as `no app key`. It reads the thread over REST
  before it writes, and its earlier reply already answers it, so the cost is one wake per new
  container; a handler that takes its own reply for your words could answer it once more.
- A caller that narrows its topic by mistake (the root included) is told once (`topic changed`),
  with the count of facts since its last taken batch that the new topic hides, and its trailer
  shows the flag on every batch. Taking that batch passes those facts, and re-arming with the old
  flags does not bring them back, so it reads them over REST. That is the cost of one place for
  every topic.
- Eight kinds, no finer. A broad kind costs wakes, never a loss.

## Alternatives considered

- **A resident daemon with a socket (watchd).** It hides polling, but the harness stops a background
  process at 2 hours and an idle session soon after. It needs supervision, a restart story and its
  own trust review, and its subscribers still need a wake transport, which is the same
  Monitor-plus-exit wait.
- **Each wait polls REST for itself.** The simplest shape, and opus's. REST reads grow with the
  number of waiters, against a limit every agent shares; rated blocking.
- **An append-only event journal with sequence numbers.** Exact edges, but a large codec,
  compaction and replay rules, and after a gap it still needs a level view.
- **A resident watcher agent holding the wait.** The caller side stays the same. You answered
  question 1 yes, so it is not an arm of the measurement.
- **An Actions workflow that writes events to an issue (#502 call 4).** Actions minutes, latency, a
  trusted workflow, and it still needs a reader. #502 already answered no.
- **A saved subscription** (`watch.sh subscribe`, then `wait --as` looks it up). It hides the flags
  from each wait, but adds a lifecycle and a second place for the declaration, and it dies with the
  container, so every session would declare it again.
- **Routing by claims**, a structurally different shape: each fact goes to the one live claimant of
  its topic, and the rest to the root. It would answer "who acts" in the tool. It needs leases and
  reads of other callers' state, a dead claimant loses what it was shown, and across containers no
  disk can hold a claim.
- **Ranked topics, where one caller takes a fact from another.** One caller then hides facts from
  another, a `--since` case blocks, your words could wait up to 30 minutes, and topics become a
  hierarchy instead of independent.
- **A mark, an offer and an ack per topic.** Exact history when a topic widens, for one offer per
  topic on every trailer. The level view makes one place enough.
- **Narrowing the shared poll to the union of topics.** It saves reads only when every caller of a
  clone is narrow, and one caller's flags would change what another observes. Deferred behind
  PR 12.
- **A committed topics file with a coverage test.** Every change would be a merge you make, and
  per-PR names do not belong in a file. The dashboard's handler lines do this job.

**The token numbers.** All come from one 12-day session (one run, no spread), counted as cache-read
tokens per wake:
- 437 `Monitor` expiries at about 235k tokens each: about 100M on re-arms, about 8M a day.
- Exit-on-event folds the 282 expiries that followed an event into that event's own wake: 282 ×
  235k, about 66M saved.
- Left are the 155 expiries with no event: 155 × 235k, about 36M, about 3M a day.
- Lifting the ban moves the cap from 30 minutes to 2 hours, which leaves about a quarter of those:
  about 116 fewer wakes, about 27M saved.
- A watcher agent: #26's used about 70k tokens in 99 minutes (one run), about 1M a day.
- PR 12: each 2-hour idle session has about 8 wakes (four expiries, two label changes and the `gate`
  result of each), so six sessions are about 48 wakes, at most about 11M. That is an upper bound,
  since a fresh session's context is smaller than the root's 235k. The canary day adds at most one
  day of today's re-arm cost, about 8M. PR 12 reports the real sums.

## Risks

The questions are at the top (Questions for you). These are the risks, each with the PR that
checks it:
- **The issues route** is assumed to carry `pull_request.merged_at` for closed pull requests. PR 4
  confirms it live before the reader relies on it.
- **The `Date` header.** `gh api --include` writes the status line, then `Name: value` header lines
  ending in CR LF, then an empty CR LF line. The reader strips one CR per line and matches header
  names in any case. PR 4 tests a captured answer with its CR bytes and confirms the header live.
  Without it the poll fails with `main: no Date header`; there is no fallback to the local clock.
- **Contract depth.** A statement may turn out false when its module is first elaborated.
  `HANDOVER.md` says to write the counterexample and stop, never to bend the code. Round 3 found
  three such statements in the sketch and fixed them. The Lean is budgeted at about 5,800 lines
  with three planned splits, and each row's budget is an estimate the Architect redoes.
- **Monitor** may send a separate exit notification after the printed lines, which would double
  each wake, and it may not say the exit code. PR 12 counts both. Either way, the rules treat a
  Monitor that ends with no stdout line as exit 3 while `watch.sh status` shows a wait of that
  caller, and otherwise run the same command once in the foreground under `timeout 60` and read
  stderr. A usage error of `wait` prints a stdout line, so a mistyped arm wakes the Monitor.
- **IsoReadsBack** may not land cheaply. Its fallback is a run-time check, which deletes the named
  statement, so the PR records it as a deviation.
- **REST cost.** The shared poll reads reviews and checks per owned head every minute, the bash
  watcher's cost, and each waiting container polls on its own. The per-poll bound counts `gh`
  processes, not paged requests. PR 12 measures requests per container. Conditional requests are
  the first deferred fix, because a 304 answer does not count against the limit.
- **The trusted root.** GitHub rotates its attestation keys several times a year. Until a renewal
  merges, a newer asset fails closed to the bash watcher or the bounded `gh` loop, and after
  PR 15 to the loop alone (question 13).
  PR 11 is done only after one real run on Claude cloud.
- **A host's slug.** An agent post that names no app reads as your typed words. The caller checks
  its own slug (the slug row), since `build --fetch` prints `unchecked` for it, and a host without
  one posts no issue comment.

## Next implementation step

Build PR 1 from `sketch/.claude/scripts/watch-github.pr1.diff`, which applies to `main` at
`7dfd6cb`: judge an issue comment by `performed_via_github_app` (null means owner words, even with
a footer; an app object means that app; no key keeps today's footer rule, because every existing
fixture predates the key), keep the footer rule on review routes, and add the five test cases in
`PR-SEQUENCE.md`. PR 3a (the same rule in `pr-state.sh`, `sketch/.claude/hooks/pr-state.pr3a.diff`)
runs beside it, and PR 3b after PR 3a.

## Verification log

Round 3: 31 findings (correctness 9, lean 11, owner-fit 11; 11 major, 20 minor), each checked
against the package and `main` at `7dfd6cb`. All majors are fixed. A minor is fixed where its fix
is a line in a file this round touched; otherwise it is deferred to a named row in `tasks/502-watch.md`
(deferrals). One part of one finding is rejected. Rounds 1 and 2 are in `REVIEW-LOG.md`.

1. No caller protocol in PR 13 (major). Fixed: Usage, `WatchCli` and row 13 say what each exit asks
   (exit 3 or a silent end: nothing unless `watch.sh status` shows no wait; exit 1: back off with
   `sleep 600` in a Monitor); PR 12 counts whether Monitor reports the code.
2. Offer mark not tied to the reported state (major). Fixed: pure `finish`,
   `OfferMarksTheReportedState`, a per-consumer lock around every `state.json` write, two PR 8 cases.
3. Review-thread words waited the window (major). Fixed: `Told.skipsWindow` (posts no app names, and
   unreadable posts), `OnlyPossibleOwnerWordsSkipTheWindow`; question 1 corrected.
4. Two "adds nothing" statements false for a refused item (major). Fixed: `Feed.add` dedupes against
   kept entries; counterexample fixture; `AReReadAddsNoPostOrClose` over a later `Date`.
5. `OutsideIsCutFirst` false (major). Fixed: the witness is not a head line.
6. Budgets off scale; PR 7 too big (major). Fixed: per-row estimates (about 29M tokens); PR 7 split
   into 7a to 7c. PR 5 kept whole: its alarms are stated over `View.of`.
7. No entry point for PR 4's and PR 5's file checks; `Gh` unbuilt (major). Fixed: test-only
   `watch read` (PR 4) and `watch replay` (PR 6), pure `Gh.frame`, `history-84` moved to PR 6.
8. PR 15 would turn CI red (major). Fixed: row 15 edits both test scripts, the fallback paragraph
   and `docs/process.md`; row 9 adds `watch.sh` to `sourced-bash.test.sh`.
9. HANDOVER omitted provider and model (major). Fixed in Reporting.
10. Too many owner questions (major). Fixed: part A is yours, part B the root's defaults; PR 0 opens
    now and its merge accepts them.
11. PR 12 unrunnable under `kitimark-mode` (major). Fixed: you (or a launch tool) start the arm
    sessions; a routine PR owner makes the toggles; question 2c says so.
12. Mis-recorded review id (minor). Named in Tradeoffs; read-back check deferred to PR 8.
13. Unordered write records (minor). Fixed: `WriteRecord.seq`; a row 7a fixture.
14. The cap can cut an owned merge (minor). Named in Tradeoffs; re-rank deferred to PR 7c.
15. All-or-nothing reviews read (minor). Named in Tradeoffs; deferred to PR 4 and PR 6.
16. Page shifts under a fork flood (minor). Named in Tradeoffs; deferred to PR 4, 6 and 7b.
17. Small inconsistencies (minor). Fixed (a) to (e); (d) keeps the `owner comment` label, the
    root's habit, and fixes the wording.
18. A healthy wait could end blind (minor). Fixed: freshness at `min now deadline` plus
    `freshSlack`; `AHealthyWaitNeverEndsBlind`; the moment as a fixture.
19. Sticky `noRunFound` (minor). Fixed: `ARunOnThePageIsFound`; `AFailedLookMovesNothing` narrowed.
20. The `String` appends rule (minor). Fixed: appends dropped, the rest marked unverified.
21. Glosses beyond their statements (minor). Fixed by rewording all three.
22. Audit reach (minor). Fixed in part: axioms checked on every constant, statements outside
    `variable`, a `sorry` check for the IO modules. Rejected: failing every `def` whose type ends in
    `Prop`, which would fail needed predicates (`Feed.WF`, `Shared.Inv`, `View.Equiv`).
23. `cheats` marked CI-only (minor). Fixed in `checks`, the Lean rows and HANDOVER.
24. No admission rule for a fetched binary (minor). Fixed in row 11.
25. No A/B decision rule (minor). Fixed: tokens not above arm A, latency at most 3 minutes.
26. "Every change is trust-critical" (minor). Fixed in Tradeoffs.
27. PR 3b with a plan row (minor). Fixed: no plan row.
28. PR 3 under "Q1 no" (minor). Fixed: it needs PR 11 or its replacement.
29. Facts and slips (minor). Fixed: 15,000 REST limit, `build [--fetch]`, iterations, `plan/`
    wording, row 11's test file.
30. HANDOVER's missing rules (minor). Fixed: Review rounds, exit codes, PR 1's closing order.
31. Readability (minor). Fixed: round 2's log moved out, six terms defined, Risks retitled, 2b
    marked a fact. This log stays here, as the brief asked.
