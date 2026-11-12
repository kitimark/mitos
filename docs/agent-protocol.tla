---- MODULE AgentProtocol ----
\* Two pull requests. P2 touches a kept path. There is no background rebase.
\* The updater runs only for the next pull request, and only while it is behind.
\* That step stands for a replay that keeps the content id. A replay that would
\* change the id is not this action, and the pull request stays behind.
\* Admission of comments is Lean, over the ledger prefix and created_at.
\* This model is the land loop only.

EXTENDS Naturals, FiniteSets

CONSTANTS P1, P2
PRs == {P1, P2}
Kept == {P2}

VARIABLES phase, who, enforced, moved

vars == << phase, who, enforced, moved >>

Phases == {"idle", "opted", "behind", "gating", "green", "skipped", "held", "merged"}
Whos == {"none", "owner", "agent"}

TypeOK ==
  /\ phase \in [PRs -> Phases]
  /\ who \in [PRs -> Whos]
  /\ enforced \in BOOLEAN
  /\ moved \in BOOLEAN
  /\ \A p \in PRs: (phase[p] = "idle" => who[p] = "none") /\ (who[p] = "none" => phase[p] = "idle")

Landable(p) == phase[p] \in {"opted", "behind", "gating", "green"}
OnTip(p) == phase[p] \in {"opted", "gating", "green"}

Rank(p) ==
  << IF who[p] = "owner" THEN 0 ELSE 1,
     IF OnTip(p) THEN 0 ELSE 1,
     IF p = P1 THEN 0 ELSE 1 >>

Beats(p, q) ==
  \/ Rank(p)[1] < Rank(q)[1]
  \/ Rank(p)[1] = Rank(q)[1] /\ Rank(p)[2] < Rank(q)[2]
  \/ Rank(p)[1] = Rank(q)[1] /\ Rank(p)[2] = Rank(q)[2] /\ Rank(p)[3] <= Rank(q)[3]

IsNext(p) ==
  /\ Landable(p)
  /\ \A q \in PRs: Landable(q) => Beats(p, q)

Init ==
  /\ phase = [p \in PRs |-> "idle"]
  /\ who = [p \in PRs |-> "none"]
  /\ enforced \in BOOLEAN
  /\ moved = FALSE

\* the owner, or a teammate allowed to merge a non-kept path, opts in
Queue(p, w) ==
  /\ p \in PRs
  /\ w \in {"owner", "agent"}
  /\ phase[p] = "idle"
  /\ w = "agent" => p \notin Kept
  /\ phase' = [phase EXCEPT ![p] = "opted"]
  /\ who' = [who EXCEPT ![p] = w]
  /\ UNCHANGED << enforced, moved >>

\* the owner types /hold
Hold(p) ==
  /\ p \in PRs
  /\ phase[p] \in {"opted", "behind", "gating", "green"}
  /\ phase' = [phase EXCEPT ![p] = "held"]
  /\ UNCHANGED << who, enforced, moved >>

\* main moves. No branch is rebased.
MainMove ==
  /\ ~moved
  /\ moved' = TRUE
  /\ phase' = [p \in PRs |-> IF phase[p] \in {"opted", "green"} THEN "behind" ELSE phase[p]]
  /\ UNCHANGED << who, enforced >>

\* the updater replays the next pull request and keeps the content id
Update(p) ==
  /\ p \in PRs
  /\ enforced
  /\ IsNext(p)
  /\ phase[p] = "behind"
  /\ phase' = [phase EXCEPT ![p] = "gating"]
  /\ UNCHANGED << who, enforced, moved >>

\* gate succeeds on a head that is already on main
GateGreen(p) ==
  /\ p \in PRs
  /\ phase[p] \in {"opted", "gating"}
  /\ phase' = [phase EXCEPT ![p] = "green"]
  /\ UNCHANGED << who, enforced, moved >>

\* gate is skipped
GateSkip(p) ==
  /\ p \in PRs
  /\ phase[p] \in {"opted", "gating"}
  /\ phase' = [phase EXCEPT ![p] = "skipped"]
  /\ UNCHANGED << who, enforced, moved >>

\* a permitted actor rebase-merges the next pull request
Merge(p) ==
  /\ p \in PRs
  /\ enforced
  /\ IsNext(p)
  /\ phase[p] = "green"
  /\ who[p] = "owner" \/ p \notin Kept
  /\ phase' = [phase EXCEPT ![p] = "merged"]
  /\ UNCHANGED << who, enforced, moved >>

\* the queue is finished, or protection does not bind admins and nothing else can land
Finished ==
  /\ \/ ~enforced
     \/ \A p \in PRs: phase[p] \in {"idle", "held", "merged", "skipped"}
  /\ UNCHANGED vars

Next ==
  \/ \E p \in PRs: \E w \in {"owner", "agent"}: Queue(p, w)
  \/ \E p \in PRs: Hold(p)
  \/ MainMove
  \/ \E p \in PRs: Update(p)
  \/ \E p \in PRs: GateGreen(p)
  \/ \E p \in PRs: GateSkip(p)
  \/ \E p \in PRs: Merge(p)
  \/ Finished

Safety == Init /\ [][Next]_vars
Spec == Safety /\ WF_vars(Next)

\* A kept path is queued and merged only by the owner.
KeptIsOwner == \A p \in Kept: who[p] \in {"none", "owner"} /\ (phase[p] = "merged" => who[p] = "owner")

\* Two replays are not in flight together.
AtMostOneGating == Cardinality({p \in PRs: phase[p] = "gating"}) <= 1

\* Behind becomes gating or held, never a rebased green, in one step.
NoBackground ==
  [][\A p \in PRs: phase[p] = "behind" => phase'[p] \in {"behind", "gating", "held"}]_vars

\* A merge step leaves a green head, with admins bound, by the owner or on a non-kept path, and that pull request is next.
MergeIsGated ==
  [][\A p \in PRs:
       (phase'[p] = "merged" /\ phase[p] # "merged") =>
         phase[p] = "green" /\ enforced /\ IsNext(p) /\ (who[p] = "owner" \/ p \notin Kept)]_vars

\* /hold stays held.
HoldWins == [][\A p \in PRs: phase[p] = "held" => phase'[p] = "held"]_vars

\* With admins unbound, nothing is replayed and nothing merges.
UnenforcedLandsNothing ==
  [][~enforced =>
       /\ \A p \in PRs: phase[p] = "behind" => phase'[p] \in {"behind", "held"}
       /\ \A p \in PRs: phase'[p] = "merged" => phase[p] = "merged"]_vars

\* A pull request that has left idle, while admins are bound, reaches merged, held, or skipped.
Progress ==
  \A p \in PRs: (phase[p] # "idle" /\ enforced) ~> (phase[p] \in {"merged", "held", "skipped"})

====
