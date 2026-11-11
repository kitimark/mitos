---- MODULE AgentProtocol ----
\* One task and two providers. The owner is not a holder.
\* The holder is one slot. Claim and handoff assign it. They never add a second name.
\* spec is chosen at the start and does not change. On a spec task only the owner merges,
\* and only after the owner has added spec-approved. A plain task stays with the owner until the
\* owner delegates merge to one provider.

EXTENDS Naturals, TLC

CONSTANTS A, B
Actors == {A, B}
Symmetry == Permutations(Actors)

VARIABLES
  phase, holder, head, handedOff,
  spec, specBy, gate, pass, author, delegated, expired, mergedBy

vars == << phase, holder, head, handedOff, spec, specBy, gate, pass, author,
           delegated, expired, mergedBy >>

TypeOK ==
  /\ phase \in {"idle", "held", "asked", "merged", "done"}
  /\ holder \in {"none"} \cup Actors
  /\ head \in {"none", "sha"}
  /\ handedOff \in BOOLEAN
  /\ spec \in BOOLEAN
  /\ specBy \in {"none", "owner"}
  /\ gate \in {"missing", "success", "skipped"}
  /\ pass \in BOOLEAN
  /\ author \in {"none"} \cup Actors
  /\ delegated \in {"none"} \cup Actors
  /\ expired \in BOOLEAN
  /\ mergedBy \in {"none", "owner"} \cup Actors

\* A pass covers this head. The judge is not the author. The model records that fact as `pass`
\* and allows Pass only when the judge differs from the author.
Covers == pass /\ author \in Actors

Init ==
  /\ phase = "idle"
  /\ holder = "none"
  /\ head = "none"
  /\ handedOff = FALSE
  /\ spec \in BOOLEAN
  /\ specBy = "none"
  /\ gate = "missing"
  /\ pass = FALSE
  /\ author = "none"
  /\ delegated = "none"
  /\ expired = FALSE
  /\ mergedBy = "none"

\* a provider claims the task
Claim(a) ==
  /\ a \in Actors
  /\ \/ phase = "idle"
     \/ (phase = "held" /\ expired)
  /\ phase' = "held"
  /\ holder' = a
  /\ expired' = FALSE
  /\ UNCHANGED << head, handedOff, spec, specBy, gate, pass, author, delegated, mergedBy >>

\* the holder publishes the head
Publish(a) ==
  /\ a \in Actors
  /\ phase = "held"
  /\ holder = a
  /\ ~expired
  /\ head = "none"
  /\ head' = "sha"
  /\ author' = a
  /\ gate' = "missing"
  /\ pass' = FALSE
  /\ UNCHANGED << phase, holder, handedOff, spec, specBy, delegated, expired, mergedBy >>

\* the gate check on this head is reported. It does not flip once set, except the updater resets it.
SetGate(g) ==
  /\ phase \in {"held", "asked"}
  /\ head = "sha"
  /\ gate = "missing"
  /\ g \in {"success", "skipped"}
  /\ gate' = g
  /\ UNCHANGED << phase, holder, head, handedOff, spec, specBy, pass, author, delegated, expired, mergedBy >>

\* the holder hands the task to the other provider and names the current head
Handoff(from, to) ==
  /\ from \in Actors
  /\ to \in Actors
  /\ from # to
  /\ phase = "held"
  /\ holder = from
  /\ ~expired
  /\ head = "sha"
  /\ ~handedOff
  /\ holder' = to
  /\ handedOff' = TRUE
  /\ UNCHANGED << phase, head, spec, specBy, gate, pass, author, delegated, expired, mergedBy >>

\* the provider who did not write the head records a pass
Pass(judge) ==
  /\ judge \in Actors
  /\ phase \in {"held", "asked"}
  /\ head = "sha"
  /\ author \in Actors
  /\ judge # author
  /\ ~pass
  /\ pass' = TRUE
  /\ UNCHANGED << phase, holder, head, handedOff, spec, specBy, gate, author, delegated, expired, mergedBy >>

\* the updater rebases. The pass still covers the new head. The new head needs its own green gate.
Updater ==
  /\ phase = "held"
  /\ head = "sha"
  /\ pass
  /\ gate = "success"
  /\ gate' = "missing"
  /\ UNCHANGED << phase, holder, head, handedOff, spec, specBy, pass, author, delegated, expired, mergedBy >>

\* the orchestrator asks the owner
Ask ==
  /\ phase = "held"
  /\ ~expired
  /\ phase' = "asked"
  /\ UNCHANGED << holder, head, handedOff, spec, specBy, gate, pass, author, delegated, expired, mergedBy >>

\* the owner replies
OwnerReply ==
  /\ phase = "asked"
  /\ phase' = "held"
  /\ UNCHANGED << holder, head, handedOff, spec, specBy, gate, pass, author, delegated, expired, mergedBy >>

\* the owner adds spec-approved
OwnerApprovesSpec ==
  /\ phase \in {"idle", "held", "asked"}
  /\ spec
  /\ specBy = "none"
  /\ specBy' = "owner"
  /\ UNCHANGED << phase, holder, head, handedOff, spec, gate, pass, author, delegated, expired, mergedBy >>

\* the owner delegates merge of this task to one provider
OwnerDelegates(a) ==
  /\ a \in Actors
  /\ phase \in {"idle", "held", "asked"}
  /\ ~spec
  /\ delegated = "none"
  /\ delegated' = a
  /\ UNCHANGED << phase, holder, head, handedOff, spec, specBy, gate, pass, author, expired, mergedBy >>

\* the claim time limit passes
Expire ==
  /\ phase = "held"
  /\ ~expired
  /\ expired' = TRUE
  /\ UNCHANGED << phase, holder, head, handedOff, spec, specBy, gate, pass, author, delegated, mergedBy >>

\* a permitted actor rebase-merges
Merge(actor) ==
  /\ actor \in {"owner"} \cup Actors
  /\ \/ phase = "held"
     \/ (phase = "asked" /\ actor = "owner")
  /\ ~expired
  /\ gate = "success"
  /\ Covers
  /\ (spec => specBy = "owner")
  /\ (spec => actor = "owner")
  /\ (~spec => (actor = "owner" \/ delegated = actor))
  /\ phase' = "merged"
  /\ mergedBy' = actor
  /\ UNCHANGED << holder, head, handedOff, spec, specBy, gate, pass, author, delegated, expired >>

\* the issue closes because the pull request body names it
Close ==
  /\ phase = "merged"
  /\ phase' = "done"
  /\ UNCHANGED << holder, head, handedOff, spec, specBy, gate, pass, author, delegated, expired, mergedBy >>

\* the task is finished
Finished ==
  /\ phase = "done"
  /\ UNCHANGED vars

Next ==
  \/ \E a \in Actors : Claim(a)
  \/ \E a \in Actors : Publish(a)
  \/ \E g \in {"success", "skipped"} : SetGate(g)
  \/ \E from, to \in Actors : Handoff(from, to)
  \/ \E j \in Actors : Pass(j)
  \/ Updater
  \/ Ask
  \/ OwnerReply
  \/ OwnerApprovesSpec
  \/ \E a \in Actors : OwnerDelegates(a)
  \/ Expire
  \/ \E actor \in ({"owner"} \cup Actors) : Merge(actor)
  \/ Close
  \/ Finished

Spec == Init /\ [][Next]_vars

\* At most one holder.
OneHolder == holder = "none" \/ holder \in Actors

\* A handoff names the head that existed when it happened. There is no handoff from a task with no head.
HandoffNamesHead == handedOff => head = "sha"

\* Merged work has a successful gate, a covering pass, the owner's spec label when the task is spec,
\* and the owner as the merger of a spec task. A plain task is merged by the owner or by the provider
\* the owner named.
OwnerGate ==
  phase \in {"merged", "done"} =>
    /\ gate = "success"
    /\ Covers
    /\ (spec => specBy = "owner")
    /\ (spec => mergedBy = "owner")
    /\ (~spec => (mergedBy = "owner" \/ delegated = mergedBy))

\* A skipped gate does not count as a pass.
NoSkipAsPass == phase \in {"merged", "done"} => gate = "success"

\* The spec label is unset, or the owner action set it.
SpecLabelIsOwner == specBy \in {"none", "owner"}

====
