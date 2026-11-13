---- MODULE AgentProtocol ----
\* Two pull requests. P2 is kept. P1 starts opted in, by the owner or by an agent.
\* The owner assumption is the pair of flags ownerHolds and gateSucceeds.
\* Hold and a skipped gate are real actions. They are not fair.
\* Fairness is only the updater, a successful gate, and the two merge actions.
\* A merge of one pull request moves main, so the other on-tip pull request goes behind.

EXTENDS Naturals, FiniteSets

CONSTANTS P1, P2
PRs == {P1, P2}
Kept == {P2}

VARIABLES phase, who, enforced, ownerHolds, gateSucceeds

vars == << phase, who, enforced, ownerHolds, gateSucceeds >>

Phases == {"idle", "opted", "behind", "gating", "green", "skipped", "held", "merged"}
Whos == {"none", "owner", "agent"}

TypeOK ==
  /\ phase \in [PRs -> Phases]
  /\ who \in [PRs -> Whos]
  /\ enforced \in BOOLEAN
  /\ ownerHolds \in BOOLEAN
  /\ gateSucceeds \in BOOLEAN
  /\ \A p \in PRs:
       /\ phase[p] = "idle" => who[p] = "none"
       /\ who[p] = "none" => phase[p] = "idle"

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

IsNext(p) == Landable(p) /\ \A q \in PRs: Landable(q) => Beats(p, q)

\* After p merges, main has moved. Another pull request that was on the tip is now behind.
AfterMerge(p) ==
  [q \in PRs |->
    IF q = p THEN "merged"
    ELSE IF phase[q] \in {"opted", "green"} THEN "behind"
    ELSE phase[q]]

Init ==
  /\ phase = [p \in PRs |-> IF p = P1 THEN "opted" ELSE "idle"]
  /\ who \in [PRs -> Whos]
  /\ who[P1] \in {"owner", "agent"}
  /\ who[P2] = "none"
  /\ enforced \in BOOLEAN
  /\ ownerHolds \in BOOLEAN
  /\ gateSucceeds \in BOOLEAN

\* an allowed teammate, or the owner, opts in
Queue(p, w) ==
  /\ p \in PRs
  /\ w \in {"owner", "agent"}
  /\ phase[p] = "idle"
  /\ phase' = [phase EXCEPT ![p] = "opted"]
  /\ who' = [who EXCEPT ![p] = w]
  /\ UNCHANGED << enforced, ownerHolds, gateSucceeds >>

\* the owner types /hold
Hold(p) ==
  /\ ownerHolds
  /\ p \in PRs
  /\ phase[p] \in {"opted", "behind", "gating", "green"}
  /\ phase' = [phase EXCEPT ![p] = "held"]
  /\ UNCHANGED << who, enforced, ownerHolds, gateSucceeds >>

\* the owner's next /land clears the hold
ReleaseHold(p) ==
  /\ p \in PRs
  /\ phase[p] = "held"
  /\ phase' = [phase EXCEPT ![p] = "opted"]
  /\ who' = [who EXCEPT ![p] = "owner"]
  /\ UNCHANGED << enforced, ownerHolds, gateSucceeds >>

\* the updater replays only the next pull request, and only while admins are bound
Update(p) ==
  /\ p \in PRs
  /\ enforced
  /\ IsNext(p)
  /\ phase[p] = "behind"
  /\ phase' = [phase EXCEPT ![p] = "gating"]
  /\ UNCHANGED << who, enforced, ownerHolds, gateSucceeds >>

\* gate succeeds on a head that is on main
GateGreen(p) ==
  /\ gateSucceeds
  /\ p \in PRs
  /\ phase[p] \in {"opted", "gating"}
  /\ phase' = [phase EXCEPT ![p] = "green"]
  /\ UNCHANGED << who, enforced, ownerHolds, gateSucceeds >>

\* gate is skipped. This action is not fair.
GateSkip(p) ==
  /\ ~gateSucceeds
  /\ p \in PRs
  /\ phase[p] \in {"opted", "gating"}
  /\ phase' = [phase EXCEPT ![p] = "skipped"]
  /\ UNCHANGED << who, enforced, ownerHolds, gateSucceeds >>

\* an agent rebase-merges the next pull request. The owner's merge is a separate action.
AgentMerge(p) ==
  /\ p \in PRs
  /\ enforced
  /\ IsNext(p)
  /\ phase[p] = "green"
  /\ who[p] = "agent"
  /\ p \notin Kept
  /\ phase' = AfterMerge(p)
  /\ UNCHANGED << who, enforced, ownerHolds, gateSucceeds >>

\* The owner takes a kept pull request an agent opened. The agent does not merge it.
OwnerTakes(p) ==
  /\ p \in Kept
  /\ who[p] = "agent"
  /\ phase[p] \notin {"idle", "merged"}
  /\ who' = [who EXCEPT ![p] = "owner"]
  /\ UNCHANGED << phase, enforced, ownerHolds, gateSucceeds >>

\* the owner merges. Strict protection is the second model. This action is not the agent's gate.
OwnerMerge(p) ==
  /\ p \in PRs
  /\ who[p] = "owner"
  /\ phase[p] \notin {"idle", "merged"}
  /\ phase' = AfterMerge(p)
  /\ UNCHANGED << who, enforced, ownerHolds, gateSucceeds >>

Rest(p) == phase[p] \in {"idle", "merged", "held", "skipped"}

\* end states, including an unbound main where no owner merge is waiting
Finished ==
  /\ \/ \A p \in PRs: Rest(p)
     \/ (~enforced /\ \A p \in PRs: who[p] = "owner" => Rest(p))
  /\ UNCHANGED vars

Next ==
  \/ \E p \in PRs: \E w \in {"owner", "agent"}: Queue(p, w)
  \/ \E p \in PRs: Hold(p)
  \/ \E p \in PRs: ReleaseHold(p)
  \/ \E p \in PRs: Update(p)
  \/ \E p \in PRs: GateGreen(p)
  \/ \E p \in PRs: GateSkip(p)
  \/ \E p \in PRs: AgentMerge(p)
  \/ \E p \in PRs: OwnerMerge(p)
  \/ \E p \in PRs: OwnerTakes(p)
  \/ Finished

Fair ==
  /\ WF_vars(\E p \in PRs: Update(p))
  /\ WF_vars(\E p \in PRs: GateGreen(p))
  /\ WF_vars(\E p \in PRs: AgentMerge(p))
  /\ WF_vars(\E p \in PRs: OwnerMerge(p))

Spec == Init /\ [][Next]_vars /\ Fair

\* An agent may opt a kept pull request. Only the owner merges it.
KeptMergeIsOwner ==
  \A p \in Kept: phase[p] = "merged" => who[p] = "owner"

\* Two replays are not in flight together.
AtMostOneGating == Cardinality({p \in PRs: phase[p] = "gating"}) <= 1

\* The updater is the only step from behind to gating, and only for the next pull request.
PushOnlyNext ==
  [][\A p \in PRs:
       (phase[p] = "behind" /\ phase'[p] = "gating") =>
         enforced /\ IsNext(p)]_vars

\* An agent merge leaves a green head on the tip, with admins bound, and that pull request next.
\* Keyed on who = agent, so the owner's merge is not this rule.
AgentMergeIsGated ==
  [][\A p \in PRs:
       (phase'[p] = "merged" /\ phase[p] # "merged" /\ who[p] = "agent") =>
         phase[p] = "green" /\ enforced /\ IsNext(p) /\ p \notin Kept]_vars

\* An agent merge happens on the tip. Behind is not an agent merge.
MergeOnTip ==
  [][\A p \in PRs:
       (phase'[p] = "merged" /\ phase[p] # "merged" /\ who[p] = "agent") =>
         OnTip(p)]_vars

\* A hold lasts until the owner's next /land, or until the owner merges.
HoldClears ==
  [][\A p \in PRs:
       phase[p] = "held" =>
         phase'[p] \in {"held", "opted"} \/ (phase'[p] = "merged" /\ who[p] = "owner")]_vars

\* With admins unbound, the updater does not replay and an agent does not merge.
UnenforcedLandsNothing ==
  [][~enforced =>
       /\ \A p \in PRs: phase[p] = "behind" => phase'[p] # "gating"
       /\ \A p \in PRs: (phase'[p] = "merged" /\ phase[p] # "merged") => who[p] = "owner"]_vars

\* Behind does not become a rebased green in one step.
NoBackground ==
  [][\A p \in PRs:
       phase[p] = "behind" =>
         phase'[p] \in {"behind", "gating", "held", "merged"}]_vars

\* Owner assumption: the owner does not hold, and gate reaches success.
\* P1 starts opted, so this is a real obligation, not a state that never occurs.
Progress ==
  (enforced /\ ~ownerHolds /\ gateSucceeds) ~> (phase[P1] = "merged")

====
