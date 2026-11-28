import MitosGate.Watch.Deliver

/-! UNCHECKED SKETCH (#502). The text of every line a wait prints.

Every line is one line of printable characters: each piece that came from GitHub (a label, a
login, an app slug, a check conclusion, an error) goes through `oneLine`, and an excerpt carries its
own proof. A body is always after a fixed prefix, so it can never begin a line. Every end of a wait
ends with `next: ` and the exact next command, so any caller (the root's Monitor, a PR owner,
Codex) re-arms by running the text after `next: ` on the last line. The command carries the wait's
subscription flags, each only when it is not at its default (`Subscription.flags`), so the
catch-all's command names none and a copied command keeps its topic.

The formats keep the bash watcher's where the meaning did not change, so the root's habits stay
valid:

  pr #N[ outside] opened labels=a,b assignees=x
  pr #N[ outside] labels=a,b assignees=x
  pr #N[ outside] merged|closed at 2026-11-23T10:12Z
  pr #N[ outside] left the open list with no close read; read it over REST
  pr #N head abc1234 checks gate=success,prove=pending,scorecard-comment=success,CodeRabbit=success
  owner comment <id> on #N[ (edited)]: <excerpt>
  agent comment|review comment|review <id> (<slug>) on #N[ (edited)]: <excerpt>
  review comment|review <id> on #N[ (edited)] (no app key: the owner or an unrecorded agent): [<state>: ]<excerpt>
  ci: pr #N head abc1234 has no ci run 12 min after its push
  ci: run <id> queued for 15 min on pr #N head abc1234
  ci: run <id> is not completed on abc1234, which is no longer the head of any open PR or main
  pr #N coderabbit skipped at abc1234 while assigned
  watch: pr #N head abc1234 checks|reviews|second look unread for 5 polls; read it over REST
  watch: comment|review comment|review <id>[ on #N] could not be read: <why>; read it over REST
  watch: the close of pr #N could not be read: <why>; read it over REST
  watch: GitHub failing for N polls since 2026-11-23T10:12Z|the first poll: <route>: <why>
  watch: GitHub answers again
  watch: some facts this consumer should see are older than the feed keeps; read GitHub over REST
  watch: starting over from the current state and the feed's last day; read anything older over REST
  watch: redelivering offer <n>; pass the last line's --seen to take it
  watch: topic changed: now <kinds> on <items>, was <kinds> on <items>; newly heard: <kinds>; newly hidden: <kinds>; taking this batch passes <n> facts since your last taken batch that the new topic hides, and the old flags do not bring them back: read REST, or use a new name with --since
  watch: main's tool is stale at abc1234; run .claude/scripts/watch.sh build
  watch: N more changes are not shown; read them over REST
  watch: next: .claude/scripts/watch.sh wait --as claude/root --seen 183467
  watch: next: .claude/scripts/watch.sh wait --as claude/ci --topics failed,alarms --seen 183467

`owner comment` is used only for typed words: an issue comment from the owner's login whose app key
GitHub gives as null. That is the owner's own typing, or an agent that posts with the owner's token
and no app, which `HANDOVER.md` forbids (`DESIGN.md`, Tradeoffs); the label keeps the bash
watcher's word, so the root's habits stay. The review routes name no app, so a review-route post
that no one recorded is labeled for what is known: the owner, or an agent that did not record it.
The bash watcher called those `owner` unless they ended with the footer; `watch-diff.intended`
lists the change. An edit is a new feed entry, so an edited post of any kind is told again with
`(edited)`; the bash watcher did not re-announce edits, and `watch-diff.intended` lists that too.
`since` names the last successful poll, or `the first poll` when this clone has had none.

The `starting over` line is the reset note: a consumer whose state was set aside, one of another
generation, and one whose mark is ahead of the shared state hear it. A new consumer starts the same
way (the current state and the feed from its floor or `--since`) without the note.

The `topic changed` line is the `newTopic` note (`Topic.text` for each side). The newly heard kinds
are those `now` hears and `was` did not, the newly hidden ones the reverse, and `none` when there
are none; a change of items alone shows in the two `on` parts. `<n>` is the note's count
(`hiddenBy`): the facts since the acked place that `was` tells and `now` does not. Taking the
batch moves the place past them, so after a narrowing they are lost to this name; 0 says nothing
was. A post through the caller's own app (`peers`) prints as an agent's post, with its slug.

A quiet end is one line, `watch: no change for claude/root in 27 min; next: <command>`. A blind
end is one line, `watch: blind for 27 min, GitHub failing since <time>: <why>; next: <command>`.
Both happen only over an empty report (`QuietEndAcksNothingUnshown`). The stale-tool note goes
inside a batch (`batchLines`); at a quiet or blind end `WatchCli` writes it to stderr, so the stdout
end stays one line. A wait that cannot run prints `watch: cannot run: <why>; next: <step>`, where
the step is prose (`WatchCli`, `watch.sh`). A usage error of `wait` prints `watch: usage: <why>;
next: <step>` the same way, before the usage text on stderr (`WatchCli.waitUsage`). -/

namespace MitosGate.Watch

open Land (Pr)

/-- Kind names joined by commas, or `none`: the text `--topics` and `--ride` read back. -/
def kindsText (ks : List Kind) : String :=
  if ks.isEmpty then "none" else String.intercalate "," (ks.map Kind.name)

/-- Digits through `Nat.toDigits`, not `toString`, so a `decide +kernel` fixture can evaluate it
(`tasks/502-watch.md`, Lean lens fixes). -/
def decimal (n : Nat) : String := String.ofList (Nat.toDigits 10 n)

def Scope.text : Scope → String
  | .repo => "the repository"
  | .items ns => String.intercalate "," (ns.map fun n => "#" ++ decimal n)

def Topic.text (t : Topic) : String := s!"{kindsText t.hears.items} on {t.on.text}"

/-- One flag as the trailer prints it. An empty `ride` is `--ride none`. -/
def Flag.text : Flag → String
  | .topics ks => " --topics " ++ kindsText ks
  | .on ns => " --on " ++ String.intercalate "," (ns.map decimal)
  | .ride ks => " --ride " ++ kindsText ks

def Subscription.text (sub : Subscription) : String := String.join (sub.flags.map Flag.text)

/-- The flags a wait was started with, enough to rebuild its command. -/
structure Invocation where
  consumer : Consumer
  sub : Subscription
  max : Option Nat
  deriving DecidableEq, Repr

def Invocation.next (i : Invocation) (seen : Nat) : String :=
  let max := match i.max with
    | some m => s!" --max {m}"
    | none => ""
  s!".claude/scripts/watch.sh wait --as {oneLine i.consumer.app}/{oneLine i.consumer.name}{i.sub.text}{max} --seen {seen}"

def Place.word : Place → String
  | .issueComment => "comment"
  | .reviewComment => "review comment"
  | .review => "review"

def Item.line : Item → String := panic! "not implemented"

/-- `toolNote` is the short sha of a stale main tool, from `--tool-note`. It is appended to a batch
that is printed anyway, so it never wakes a wait or ends one alone. -/
def batchLines (i : Invocation) (b : Batch) (offer : Nat) (toolNote : Option String) : List String :=
  b.shown.map (·.item.line) ++
    (if b.more = 0 then [] else [s!"watch: {b.more} more changes are not shown; read them over REST"]) ++
    (match toolNote with
      | some t => [s!"watch: main's tool is stale at {oneLine t}; run .claude/scripts/watch.sh build"]
      | none => []) ++
    [s!"watch: next: {i.next offer}"]

def quietLine (i : Invocation) (minutes offer : Nat) : String :=
  s!"watch: no change for {oneLine i.consumer.app}/{oneLine i.consumer.name} in {minutes} min; next: {i.next offer}"

/-- `lastOk` is `0` until a poll succeeds; the line then says so instead of printing 1970. -/
def sinceText (lastOk : Epoch) : String :=
  if lastOk = 0 then "the first poll" else iso lastOk

def blindLine (i : Invocation) (minutes offer : Nat) (since : Epoch) (why : Excerpt) : String :=
  s!"watch: blind for {minutes} min, GitHub failing since {sinceText since}: {why.text}; next: {i.next offer}"

/-- Moderate: every piece is a decimal, a fixed word (a kind's name included), `iso`, `oneLine`
output or an excerpt, so every character is printable or the escape backslash: no newline,
carriage return, line or paragraph separator, NEL or escape. It covers every end of a wait, not
only a batch. -/
def EveryLineIsOneLine : Prop :=
  (∀ i b offer note, ∀ l ∈ batchLines i b offer note, ∀ c ∈ l.toList,
    printable c = true ∨ c = '\\') ∧
  (∀ i minutes offer, ∀ c ∈ (quietLine i minutes offer).toList, printable c = true ∨ c = '\\') ∧
  (∀ i minutes offer since why, ∀ c ∈ (blindLine i minutes offer since why).toList,
    printable c = true ∨ c = '\\')

def OwnerWordsNameTheirId : Prop :=
  ∀ p : Post, p.speaker = .typed →
    (Item.post p).line.startsWith s!"owner {p.place.word} {p.id} on #{p.thread}" = true

/-- Only typed words are called the owner's. -/
def OnlyTypedWordsAreCalledTheOwners : Prop :=
  ∀ p : Post, p.speaker ≠ .typed → (Item.post p).line.startsWith "owner " = false

/-- The last line of a batch is `watch: next: ` and the command; quiet and blind ends are one line
that ends with `; next: ` and the command. -/
def TheLastLineIsTheNextCommand : Prop :=
  (∀ i b offer note, (batchLines i b offer note).getLast? = some s!"watch: next: {i.next offer}") ∧
  (∀ i minutes offer, (quietLine i minutes offer).endsWith s!"; next: {i.next offer}" = true) ∧
  (∀ i minutes offer since why,
    (blindLine i minutes offer since why).endsWith s!"; next: {i.next offer}" = true)

namespace Fixture

/-- The wait with no flags prints none, so the root's trailer is as before. -/
theorem theDefaultPrintsNoFlag : ({} : Subscription).text = "" := by decide +kernel

theorem aFailuresAgentsFlags :
    ({ topic := { hears := { failed := true, alarms := true } } } : Subscription).text =
      " --topics failed,alarms" := by decide +kernel

theorem aRidingRootsFlags :
    ({ rides := { failed := true, outside := true, alarms := true } } : Subscription).text =
      " --ride failed,outside,alarms" := by decide +kernel

theorem aPrOwnersFlags :
    ({ topic := { on := .items [502, 571] } } : Subscription).text = " --on 502,571" := by
  decide +kernel

end Fixture

end MitosGate.Watch
