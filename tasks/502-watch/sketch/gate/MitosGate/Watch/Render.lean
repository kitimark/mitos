import MitosGate.Watch.Deliver

/-! Every line a wait prints:

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
  watch: no change for claude/root in 27 min; next: <command>
  watch: blind for 27 min, GitHub failing since <time>: <why>; next: <command> -/

namespace MitosGate.Watch

open Land (Pr)

def kindsText (ks : List Kind) : String :=
  if ks.isEmpty then "none" else String.intercalate "," (ks.map Kind.name)

def decimal (n : Nat) : String := String.ofList (Nat.toDigits 10 n)

def Scope.text : Scope → String
  | .repo => "the repository"
  | .items ns => String.intercalate "," (ns.map fun n => "#" ++ decimal n)

def Topic.text (t : Topic) : String := s!"{kindsText t.hears.items} on {t.on.text}"

def Flag.text : Flag → String
  | .topics ks => " --topics " ++ kindsText ks
  | .on ns => " --on " ++ String.intercalate "," (ns.map decimal)
  | .ride ks => " --ride " ++ kindsText ks

def Subscription.text (sub : Subscription) : String := String.join (sub.flags.map Flag.text)

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

def batchLines (i : Invocation) (b : Batch) (offer : Nat) (toolNote : Option String) : List String :=
  b.shown.map (·.item.line) ++
    (if b.more = 0 then [] else [s!"watch: {b.more} more changes are not shown; read them over REST"]) ++
    (match toolNote with
      | some t => [s!"watch: main's tool is stale at {oneLine t}; run .claude/scripts/watch.sh build"]
      | none => []) ++
    [s!"watch: next: {i.next offer}"]

def quietLine (i : Invocation) (minutes offer : Nat) : String :=
  s!"watch: no change for {oneLine i.consumer.app}/{oneLine i.consumer.name} in {minutes} min; next: {i.next offer}"

def sinceText (lastOk : Epoch) : String :=
  if lastOk = 0 then "the first poll" else iso lastOk

def blindLine (i : Invocation) (minutes offer : Nat) (since : Epoch) (why : Excerpt) : String :=
  s!"watch: blind for {minutes} min, GitHub failing since {sinceText since}: {why.text}; next: {i.next offer}"

def EveryLineIsOneLine : Prop :=
  (∀ i b offer note, ∀ l ∈ batchLines i b offer note, ∀ c ∈ l.toList,
    printable c = true ∨ c = '\\') ∧
  (∀ i minutes offer, ∀ c ∈ (quietLine i minutes offer).toList, printable c = true ∨ c = '\\') ∧
  (∀ i minutes offer since why, ∀ c ∈ (blindLine i minutes offer since why).toList,
    printable c = true ∨ c = '\\')

def OwnerWordsNameTheirId : Prop :=
  ∀ p : Post, p.speaker = .typed →
    (Item.post p).line.startsWith s!"owner {p.place.word} {p.id} on #{p.thread}" = true

def OnlyTypedWordsAreCalledTheOwners : Prop :=
  ∀ p : Post, p.speaker ≠ .typed → (Item.post p).line.startsWith "owner " = false

def TheLastLineIsTheNextCommand : Prop :=
  (∀ i b offer note, (batchLines i b offer note).getLast? = some s!"watch: next: {i.next offer}") ∧
  (∀ i minutes offer, (quietLine i minutes offer).endsWith s!"; next: {i.next offer}" = true) ∧
  (∀ i minutes offer since why,
    (blindLine i minutes offer since why).endsWith s!"; next: {i.next offer}" = true)

namespace Fixture

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
