# One Lean waiter for GitHub (#502)

## In short

The root waits on GitHub with a bash script under `Monitor`. The script trusts a footer that anyone
can type (#501). Only the root can use it, so Codex and the root cannot hear each other (#336). And
`Monitor` stops every 30 minutes, so the root wakes just to re-arm it: about 100M tokens in one
measured 12-day session.

This design replaces it with one command, `.claude/scripts/watch.sh wait`, backed by the
repository's own Lean tool, `mitos-gate`. Every agent uses the same command: the root, PR owners,
Codex. A wait blocks until something needs its caller, prints the news, and exits with the exact
command to run next. No process stays running: whoever is waiting reads GitHub once a minute for the
whole clone, and each caller keeps only where it stands. Who wrote a post is decided by what GitHub
names (the posting app) or by an id the agent recorded, never by the footer.

It ships as 21 small PRs, two of them optional. Four may start now: the plan (PR 0), two fixes of
#501 in today's bash watcher and in `pr-state.sh`, and one fix of a hang in `pr-state.sh`. The Lean
waits until you merge the plan, after answering part A of the questions below. The bash watcher is deleted last, after a week of use and your sign-off. The Lean in this
package is a contract: it was written without a Lean toolchain and never type-checked, so each Lean
PR starts by type-checking its part.

## Questions for you

Part A holds the questions only you can answer. Answer them on #502 or on PR 0, for example
`1 yes, 2b cloud, 2c yes, 3a asset, 5a yes, 8a yes, 8b no`; question 9 waits until PR 15's gates
hold. Part B lists the defaults the root takes as its own choices: PR 0 records each with its
reason in `tasks/502-watch.md`, and merging PR 0 accepts them. Say no to any of them on PR 0 to
change it. `PR-SEQUENCE.md` (Gates) says which PRs wait for which answer, and what changes if you
answer otherwise.

### Part A: yours

- **1. No resident process.** Will you accept a waiter that polls, with one shared poll per clone,
  in place of a watchd daemon? Recommended: yes. PR 0's merge waits for this answer.
  - You keep one command for every agent, Codex included. Nothing that wakes is lost across
    re-arms or lost turns, nothing runs while idle, and there is nothing to supervise.
  - You give up push. News can take up to about two minutes, and your words, typed or on a review
    thread, up to about one minute. Nothing watches while no one waits: the next wait catches up
    from the files and from the last day of posts and closes, and a clone left with no wait for
    more than about 23 hours says so.
  - Building it is an estimated 29M builder tokens across the Lean rows, plus verifiers
    (`tasks/502-watch.md`, budget). The sketch was never elaborated, so this is a rough number.
  - The way to keep a resident process is a watcher agent, at about 1M `sonnet` tokens a day
    (Alternatives).
- **2b. Where the root runs.** Does the root run on a cloud VM or on your device? This is a fact
  only you have, so there is no recommendation. It decides whether the 2-hour background cap and
  the idle stop apply at all.
- **2c. PR 12's spend.** May PR 12 spend what its measurement needs, and will you start its six
  idle sessions? Recommended: yes. Each arm runs in a session of its own for about 2 hours, three
  per arm. `kitimark-mode` keeps the root free, so the root cannot be an arm: you start them, or
  the root does if its harness can start a session. The canary is one day with both watchers in
  the root's own session. About 12 label changes on a scratch draft PR each start one `gate` run,
  which reads the labels and does not rerun the cheat corpus. There is no push, so no CodeRabbit
  review. Tokens: at most about 11M for the arms and about 8M for the canary day (Alternatives).
- **3a. Getting main's tool.** How should main's `mitos-gate` reach where the root runs?
  Recommended: an attested release asset (Terms) that a job builds on each push to `main`, fetched
  only from GitHub's release-assets host and checked with `gh attestation verify`. The other
  choices are allowing the Actions storage host, or a setup script that builds with `lake`. Cost:
  one extra Actions job per merge (one `lake build mitos-gate`, an attestation and an upload). It
  starts no `gate` run and no bot review. Until it lands, the bash watcher with the #501 fix stays.
- **5a. Your Claude-app posts.** Should your own posts made through the Claude app be quiet for
  Claude agents? Recommended: yes. The rule is then "the app GitHub names", with no footer in it.
  The cost: a post you make through the Claude app does not wake the root.
- **8a. pr-state's rule.** Should `pr-state.sh` decide your unanswered words by land's rule plus
  the #501 fix (a comment you type is your words even when it ends with a footer)? Recommended:
  yes. PR 0's merge waits for this answer. Four classes change against today's jq, each listed in
  `Voice.lean`.
- **8b. land's rule.** Should `land`'s merge admission take the same typed rule (optional PR 3c)?
  Recommended: yes, for one rule everywhere. It is a change across several trusted modules, not
  one file: land's `Post` has no field for where a post was made, so PR 3c changes
  `Snapshot/Types.lean`, `Snapshot/Fields.lean`, `Snapshot/Obs.lean` (with its proofs), the reader
  in `SnapshotCli` and the fixtures. No keeps a documented difference between land and pr-state.
- **9. Deleting the bash watcher.** PR 15 removes `watch-github.sh` and its test suite. Will you
  sign off once its gates hold (the bootstrap, the canary, the measurement passing, and a week of
  use that the root records on the dashboard)? Recommended: yes. Removing a test suite is your
  call under `kitimark-mode`. No keeps the bash watcher as the fallback.

### Part B: the root's defaults

Each is an implementation choice that `kitimark-mode` (Decide, don't ask) leaves to the root.
- **2a. Transport.** `Monitor` with a wait that exits on the first event. The background-shell ban
  stays, and PR 14 lifts it only if PR 12's numbers show it is worth it and you say yes then.
  Exit-on-event saves about 66M of the about 100M; lifting the ban would save about 27M more, with
  the idle-stop risk (Alternatives has the arithmetic).
- **3b.** `pr-state.sh` uses main's tool for its unanswered column once PR 11 lands. Until then it
  keeps its jq, with PR 3a's fix.
- **3c.** An outside agent (Codex, Cursor) gets the tool the way 3a decides, through
  `watch.sh build --fetch`. An environment that cannot fetch it keeps a bounded `gh` loop and does
  not hear the root's posts until it can.
- **4. Placement.** All the Lean goes in `gate/`, in the one `mitos-gate` binary. The IO part holds
  the offer and ack logic, so it bears on trust too, and one binary keeps one build and one
  bootstrap. The other choices were the IO part in its own `lean_exe`, or a separate package.
- **5b.** Agents record their review-thread reply ids with `watch.sh own`. GitHub names no app on
  review threads, so an unrecorded reply wakes every waiting agent at once. A recording hook can
  make this automatic later. `pr-state.sh` keeps its footer hint there.
- **6. Outside accounts.** Pull request events from other accounts (forks) ride along with the
  next batch and never wake alone; a wait that holds only such lines prints them at its deadline.
  The other choices were waking alone, as today, or an hourly digest.
- **8c.** No app besides `claude` and `cursor` answers your words without its footer. A Codex reply
  then answers only with its footer, as in `land` today, so a Codex-built PR whose replies drop the
  footer does not read merge-ready until a footer or Claude reply exists.
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

You asked for "a daemon like docker", a resident process every agent can subscribe to. These
constraints decide the shape more than that ask:
- The harness stops a background shell at 2 hours and an idle cloud session a few minutes after its
  last turn (Terms). `Monitor` runs at most 30 minutes, and only stdout lines wake it.
- GraphQL is blocked. Every read is REST, and the REST limit (15,000 an hour for this account's
  token, #502) is shared by every agent on the account.
- Agents post through the owner's login. GitHub names the app on an issue comment
  (`performed_via_github_app`) but on no review comment or review (checked live).
- Logic belongs in Lean with proved statements, and `gate/` is trust infrastructure. Lean v4.35 has
  file locks (`flock`, Terms), an atomic rename, random bytes and the wall clock. It has no fsync.
- The cloud container has no `lake`, and it cannot reach the Actions artifact host. Main's tool
  cannot run there yet, so the bash watcher stays until it can.

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
- **Idle stop**: a cloud session stops a few minutes after no agent is in a model call or a
  foreground command, and that ends any background shell in it.
- **Contract depth**: the Lean states its types, functions and statements, but it was never
  type-checked and its central functions are stubs. Build depth, which the repository asks for
  before a row's issue links its design, means a sketch that type-checks plus named fixtures.
- **Shim**: `.claude/scripts/watch.sh`, a short bash script that finds the clone, the owner and
  main's tool, then runs the tool. All the logic is in the tool.
- **Echo**: the change a caller's own recorded write causes, such as a label it added. It is
  hidden from that caller only.
- **Tier**: the rank of a line in a batch: words (never cut), lines about your pull requests, then
  lines about other accounts' pull requests (cut first).
- **Ride along**: a line that does not end a wait by itself; it is printed with the next batch, or
  at the wait's deadline.
- **Blind**: a wait that ends without a recent successful read of GitHub. It says so and exits 4.

## Usage (caller's view)

One command for every caller. The output is plain lines, and every end names the exact next
command after `next: `.

```
.claude/scripts/watch.sh wait   --as <app>/<name> [--seen <n>] [--pr <n>]... [--max <min>] [--since <UTC>]
.claude/scripts/watch.sh own    --as <app>/<name> label|unlabel|assign|unassign <pr> <value>
.claude/scripts/watch.sh own    --as <app>/<name> merge|close <pr>
.claude/scripts/watch.sh own    --as <app>/<name> comment|review-comment|review <id>
.claude/scripts/watch.sh status --as <app>/<name>
.claude/scripts/watch.sh build [--fetch]     # --fetch comes with PR 11 (question 3a)
```

`--as` names the caller. The first part is the GitHub app it posts through, which is its class.
The second part is its own name. `wait` blocks until something wakes this caller or until `--max`
minutes pass (29 by default). It prints a batch and exits.

| Exit | Meaning | What the caller does |
|---|---|---|
| 0 | a batch, or one line `watch: no change for <who> in M min; next: ...` | act on the lines, then run the text after `next: ` exactly, `--seen` included |
| 1 | `watch: cannot run: <why>; next: <what>` | do not re-arm at once: read REST yourself, then re-arm after 10 minutes with a Monitor whose command is `sleep 600; <the same wait>`, or keep the bash watcher |
| 2 | usage | fix the command |
| 3 | a newer wait of the same caller took over (stderr only) | do nothing. Treat a Monitor that ends with no stdout line the same way: `watch.sh status` says whether a wait of this caller still runs, and re-arm only when none does, so a double arm never livelocks |
| 4 | `watch: blind for M min, GitHub failing since <time>: <why>; next: ...` | re-arm with the text after `next: `; read REST for anything urgent |

These are the caller's half of the guarantees: a caller that copies the trailer never spins, and
one that drops `--seen` hears its whole backlog at every deadline. PR 13 writes this table into the
rules, and PR 12 measures whether a Monitor's exit notification carries the code.

**The root**, under Monitor, at the start of a session:

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
taken.

**Where a wait starts.** `--since` applies only to a caller with no saved state; later waits go by
the acked place. A new caller without `--since` starts from the last day the feed keeps. A caller
whose state was lost, or belongs to another shared state, hears `watch: starting over from the
current state and the feed's last day; read anything older over REST`. A `--since` older than the
feed's day, or a clone left with no successful poll for more than about 23 hours, prints `watch:
some facts this consumer should see are older than the feed keeps; read GitHub over REST`. Your
words older than that still show in pr-state's unanswered column.

**The root's own writes** are recorded once they succeed, as `watch-own.sh` is today:

```
gh api -X POST repos/{owner}/{repo}/issues/512/assignees -f 'assignees[]=<login>' \
  && .claude/scripts/watch.sh own --as claude/root assign 512 <login>
```

A caller runs one `wait` before its first `own` in a new state folder. A record made before any
poll has no shared state to belong to, so `own` warns that it is dead and the echo wakes once. A
merge is recorded only after the merge reports merged (for `merge-async`, after `.status` is
`merged` and the PR reads back merged).

**A PR owner** waits on its own PR in one foreground call:

```
timeout 590 .claude/scripts/watch.sh wait --as claude/pr-512 --pr 512 --max 9
```

**Codex, or any outside agent,** runs the same command with `--as chatgpt-codex-connector/codex
--max 4` (the per-host `--max` values are suggestions to tune), and loops by running the command
after `next: `. It hears the root's catch-ups, and the root hears its posts. It records its
review-thread reply ids with `watch.sh own ... review-comment <id>`, because GitHub names no app on
those routes. Where it cannot get main's tool, it keeps a bounded `gh` loop (default 3c).

**`pr-state.sh`** asks the same Lean rules which owner words are unanswered:

```
mitos-gate watch unanswered --owner <login> --issue-comments ic.json \
  --review-comments rc.json --reviews rv.json        # prints {"512":[3456789]}, exits 1 on any refusal
```

It takes no app flag: the apps that answer are the slugs of `Speech.apps`, as in `land`.

## Shape

**Mental model.** GitHub is the record. One clone keeps one shared observation of it. Whoever is
waiting refreshes the observation when it is older than a minute, under a short lease. Each caller
keeps only where it stands: its acked place and its own records. Nothing runs while nobody waits.
GitHub's clock, not the local one, decides what the feed asks for. This is the job redone from
first principles (`principle-redesign-from-first-principles`): the job is "wake the right agent
when GitHub changes", and in this harness a waiter that polls does it with nothing to supervise.

**Data** (`sketch/gate/MitosGate/Watch/`). The shared state holds the level view, the feed with its
cursor on GitHub's clock, a random generation, the poll count and the failure streak. A caller's
state is its acked place (generation, view, feed position, whether it was told GitHub is down) and
at most one pending offer. Write records belong to one caller; post records are shared by its
class. Every file carries a version, and every load checks what the proofs assume. A file that
fails is set aside.

**One wait.**
1. The shim stamps the start, fetches `main` once (at most 20 seconds), finds main's tool, and runs
   a private copy of it with stdin closed.
2. The wait claims the caller, so an older wait of the same caller exits 3.
3. It takes the pending offer if `--seen` names it exactly.
4. It loops: check the claim, read the shared state, work out what this caller has not acked and
   whether any of it wakes, then deliver, poll, sleep 2 seconds, or end. A poll takes the lease,
   reads the shared state again (another waiter may have polled), reads `main` for GitHub's time,
   then the fixed routes from the cursor, then each head that is due, and writes by rename.
5. Every end takes the caller's lock, checks the claim again, re-reads its state, and saves the
   offer that one pure step makes, with the batch, from the shared state its last step reported
   from (never a newer read); then it prints. A wait whose report holds anything delivers it, at
   the latest at its deadline; only an empty report ends quiet or blind. An IO error that escapes prints one `watch: cannot run` line and exits 1,
   so a Monitor still wakes.

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
  lease, so two waiters never both step one state.
- **Identity is the app GitHub names, or a recorded id, never the footer.** Your typed words are
  never quiet, even with a footer. On review threads only a recorded id makes a post quiet; an
  unrecorded one is shown as `no app key: the owner or an unrecorded agent`, never as your words.
  An empty `COMMENTED` review is not a post. Each route has its own reader, one boundary per source
  (`principle-boundary-discipline`).
- **One unanswered rule.** `watch unanswered` is land's rule (`speaks`: the owner's login, no app,
  no footer; `answers`: an app in `Speech.apps`, or the footer) with the #501 fix: a typed issue
  comment is words even with a footer, and never answers (question 8a).
- **Offer and ack.** A batch counts only once its caller passes the trailer's exact number, so a
  lost turn replays instead of losing events. The offer marks the same shared state the batch was
  reported from, so taking it acks nothing the batch did not show. A caller that copies the trailer then blocks until
  news; one that ignores it gets one replay, then blocks. News includes an alarm that time starts,
  such as a head that has waited too long for `ci`.
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
- **What wakes.** Words that may be yours go out at once: typed words, a review-thread post that
  no one recorded (an unrecorded agent reply there looks the same, so it goes out at once too), and
  a post that could not be read. Other news, other apps' posts included, waits one 60-second
  window. A finished listed check wakes, also on a new head. Pending
  checks, `main` moving and a condition clearing are absorbed. A pull request that left the open
  list is one line with its close, also when the close was read in the same poll that still listed
  it open. The cap of 30 lines never cuts words or notes, cuts outside lines first and head lines
  last.
- **Bounded waits.** One poll budget (90 seconds) past its deadline, a wait's decision is to end;
  a poll in flight is bounded by `gh`'s timeout, which is tested, not proved. A wait that finds
  the lease busy sleeps instead of polling. A wait whose polls succeeded ends quiet, never blind,
  at whatever step it reaches its deadline.

**Interface depth.** The public surface is three verbs and `build`, plus `unanswered` for one hook
(and `read` and `replay`, refused outside tests).
Behind them sit the polling and its lease, dedupe, generations, per-caller echoes, offers, the
cut, `ci` health and quarantine. A caller learns none of these: the shim fills the internal flags
(`--state`, `--repo`, `--owner`, `--started`, `--tool-note`), and `--now` exists only for tests.

**What it does not do.** No resident process, socket or push. It reads no other account's posts
and no outside pull request's head. It writes nothing to GitHub. It never builds inside a wait. It
names no unlisted check.

## Synthesis decision

All three design runners, on three models, dropped the resident daemon. In all three the waiter
polls inside `wait`, state is files, and GitHub is the record. The premise review found that the
premise mostly holds in this harness. The design ships that shape and puts the deviation from your
ask to you as question 1.

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
- An unrecorded agent reply on a review thread wakes every caller at once, even with a footer.
  GitHub gives those routes no app, so it cannot be told from your review words, which never wait
  for the window; the other way would hide or delay them.
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
- Your own posts through the Claude app are quiet for Claude callers (question 5a), for an identity
  rule with no footer in it.
- An agent that posts issue comments with your token and no app (a local CLI, for example) reads as
  your typed words and wakes everyone, itself included. The other way would trust text.
- A change you make yourself that equals a write the root recorded in the same poll (you add the
  label the root just added) is hidden from the root. Both act through one account, so GitHub
  cannot tell them apart, and the state is the same either way (#239).
- Until question 8b is answered and PR 3c lands, `land` keeps its footer rule, so `land` and
  `pr-state` differ on a typed comment that ends with a footer.
- An answer whose whole shape is wrong (not an array of pages, an item with no readable id), or an
  open-pulls or runs item that cannot be read, fails every poll until the answer changes or the
  tool is fixed. Every caller hears it as a `GitHub failing` line that names the route, then as
  blind ends. One bad item on a post or close route is told and skipped instead.
- The bash watcher's first-poll scan of every open thread is gone. Your words older than the feed's
  day show in pr-state's unanswered column, and the root's first wait of a session passes `--since`
  the dashboard's last update (PR 13).
- Under default 6, a line about another account's pull request waits until the wait's deadline
  (up to 29 minutes) when nothing else wakes.
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
- Two clones on one machine poll twice. State is per clone.

## Alternatives considered

- **A resident daemon with a socket (watchd).** It hides polling, but the harness stops a background
  process at 2 hours and an idle session soon after. It needs supervision, a restart story and its
  own trust review, and its subscribers still need a wake transport, which is the same
  Monitor-plus-exit wait.
- **Each wait polls REST for itself.** The simplest shape, and opus's. REST reads grow with the
  number of waiters, against a limit every agent shares; rated blocking.
- **An append-only event journal with sequence numbers.** Exact edges, but a large codec,
  compaction and replay rules, and after a gap it still needs a level view.
- **A resident watcher agent holding the wait.** The caller side stays the same. It stays an arm
  for the measurement if question 1 is answered no.
- **An Actions workflow that writes events to an issue (#502 call 4).** Actions minutes, latency, a
  trusted workflow, and it still needs a reader. #502 already answered no.

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
  three such statements in the sketch and fixed them. The Lean is budgeted at about 5,350 lines
  with three planned splits, and each row's budget is an estimate the Architect redoes.
- **Monitor** may send a separate exit notification after the printed lines, which would double
  each wake, and it may not say the exit code. PR 12 counts both; the rules treat a Monitor that
  ends with no stdout line as exit 3 either way.
- **IsoReadsBack** may not land cheaply. Its fallback is a run-time check, which deletes the named
  statement, so the PR records it as a deviation.
- **REST cost.** The shared poll reads reviews and checks per owned head every minute, the bash
  watcher's cost. The per-poll bound counts `gh` processes, not paged requests. PR 12 measures
  requests; conditional requests are the deferred fix.

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
