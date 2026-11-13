---- MODULE AgentProtocolTip ----
\* Three pull requests and main's tip. P2 is kept.
\* A head is on the tip only when its number equals tip. Green is that head's own gate.
\* The owner's merge is strict: the head is the tip and the gate is for that head.
\* Statement 3 of the land design: while a landable pull request sits on the tip,
\* the only replay is the owner's, and only over an agent's.

EXTENDS Naturals, FiniteSets

CONSTANTS P1, P2, P3
PRs == {P1, P2, P3}
Kept == {P2}
MaxTip == 2

VARIABLES life, who, head, gateAt, gateOk, tip

vars == << life, who, head, gateAt, gateOk, tip >>

Gens == 0..MaxTip
Lives == {"idle", "open", "merged"}
Whos == {"none", "owner", "agent"}

TypeOK ==
  /\ life \in [PRs -> Lives]
  /\ who \in [PRs -> Whos]
  /\ head \in [PRs -> Gens]
  /\ gateAt \in [PRs -> Gens]
  /\ gateOk \in [PRs -> BOOLEAN]
  /\ tip \in Gens
  /\ \A p \in PRs:
       /\ (life[p] = "idle") <=> (who[p] = "none")
       /\ head[p] <= tip
       /\ gateAt[p] <= tip

OnTip(p) == life[p] = "open" /\ head[p] = tip
Landable(p) == life[p] = "open"
Green(p) == OnTip(p) /\ gateOk[p] /\ gateAt[p] = head[p]

Rank(p) ==
  << IF who[p] = "owner" THEN 0 ELSE 1,
     IF OnTip(p) THEN 0 ELSE 1,
     IF p = P1 THEN 0 ELSE IF p = P2 THEN 1 ELSE 2 >>

Beats(p, q) ==
  \/ Rank(p)[1] < Rank(q)[1]
  \/ Rank(p)[1] = Rank(q)[1] /\ Rank(p)[2] < Rank(q)[2]
  \/ Rank(p)[1] = Rank(q)[1] /\ Rank(p)[2] = Rank(q)[2] /\ Rank(p)[3] <= Rank(q)[3]

IsNext(p) == Landable(p) /\ \A q \in PRs: Landable(q) => Beats(p, q)

\* Land design statement 3. A push of a stale head, while someone landable is on the tip,
\* is the owner's push, and the one on the tip is an agent's.
OneLandingAllows(p) ==
  \/ ~ \E q \in PRs: q # p /\ OnTip(q) /\ Landable(q)
  \/ who[p] = "owner" /\ \A q \in PRs: (q # p /\ OnTip(q) /\ Landable(q)) => who[q] = "agent"

Init ==
  /\ life = [p \in PRs |-> IF p = P1 THEN "open" ELSE "idle"]
  /\ who \in [PRs -> Whos]
  /\ who[P1] \in {"owner", "agent"}
  /\ who[P2] = "none"
  /\ who[P3] = "none"
  /\ head = [p \in PRs |-> 0]
  /\ gateAt = [p \in PRs |-> 0]
  /\ gateOk = [p \in PRs |-> FALSE]
  /\ tip = 0

Queue(p, w) ==
  /\ p \in PRs
  /\ w \in {"owner", "agent"}
  /\ life[p] = "idle"
  /\ life' = [life EXCEPT ![p] = "open"]
  /\ who' = [who EXCEPT ![p] = w]
  /\ head' = [head EXCEPT ![p] = tip]
  /\ gateOk' = [gateOk EXCEPT ![p] = FALSE]
  /\ UNCHANGED << gateAt, tip >>

Update(p) ==
  /\ p \in PRs
  /\ life[p] = "open"
  /\ head[p] < tip
  /\ IsNext(p)
  /\ OneLandingAllows(p)
  /\ head' = [head EXCEPT ![p] = tip]
  /\ gateOk' = [gateOk EXCEPT ![p] = FALSE]
  /\ UNCHANGED << life, who, gateAt, tip >>

GateGreen(p) ==
  /\ p \in PRs
  /\ OnTip(p)
  /\ gateOk' = [gateOk EXCEPT ![p] = TRUE]
  /\ gateAt' = [gateAt EXCEPT ![p] = head[p]]
  /\ UNCHANGED << life, who, head, tip >>

AgentMerge(p) ==
  /\ p \in PRs
  /\ Green(p)
  /\ who[p] = "agent"
  /\ p \notin Kept
  /\ IsNext(p)
  /\ tip < MaxTip
  /\ life' = [life EXCEPT ![p] = "merged"]
  /\ tip' = tip + 1
  /\ UNCHANGED << who, head, gateAt, gateOk >>

\* Strict. The head is the tip and the gate is for that head. Not the agent's other gates.
OwnerMerge(p) ==
  /\ p \in PRs
  /\ who[p] = "owner"
  /\ Green(p)
  /\ tip < MaxTip
  /\ life' = [life EXCEPT ![p] = "merged"]
  /\ tip' = tip + 1
  /\ UNCHANGED << who, head, gateAt, gateOk >>

\* The owner takes a kept pull request an agent opened, and then merges it.
OwnerTakes(p) ==
  /\ p \in Kept
  /\ life[p] = "open"
  /\ who[p] = "agent"
  /\ who' = [who EXCEPT ![p] = "owner"]
  /\ UNCHANGED << life, head, gateAt, gateOk, tip >>

Resting ==
  \A p \in PRs: life[p] \in {"idle", "merged"} \/ (life[p] = "open" /\ tip = MaxTip /\ Green(p))

Finished ==
  /\ Resting
  /\ UNCHANGED vars

Next ==
  \/ \E p \in PRs: \E w \in {"owner", "agent"}: Queue(p, w)
  \/ \E p \in PRs: Update(p)
  \/ \E p \in PRs: GateGreen(p)
  \/ \E p \in PRs: AgentMerge(p)
  \/ \E p \in PRs: OwnerMerge(p)
  \/ \E p \in PRs: OwnerTakes(p)
  \/ Finished

Spec == Init /\ [][Next]_vars

\* A merge, the owner's included, is of the tip, and the gate is for that head.
StrictMerge ==
  [][\A p \in PRs:
       (life[p] # "merged" /\ life'[p] = "merged") =>
         head[p] = tip /\ gateOk[p] /\ gateAt[p] = head[p]]_vars

\* An agent does not merge a kept pull request.
KeptMergeIsOwner ==
  [][\A p \in Kept:
       (life[p] # "merged" /\ life'[p] = "merged") => who[p] = "owner"]_vars

\* A replay moves only the next stale head, and only when statement 3 allows it.
PushOnlyNext ==
  [][\A p \in PRs:
       (life[p] = "open" /\ head[p] < tip /\ head'[p] = tip) =>
         IsNext(p) /\ OneLandingAllows(p)]_vars

\* An agent merges on the tip. A stale green head is not enough.
MergeOnTip ==
  [][\A p \in PRs:
       (life[p] # "merged" /\ life'[p] = "merged" /\ who[p] = "agent") =>
         head[p] = tip]_vars

\* The owner outranks an agent. Stated on the heads, not on Rank.
OwnerBeforeAgent ==
  [][\A p, q \in PRs:
       (head[p] < tip /\ head'[p] = tip /\ who[p] = "agent" /\
        who[q] = "owner" /\ Landable(q)) => FALSE]_vars

\* A landable head on the tip outranks a stale head of the same class.
TipBeforeStale ==
  [][\A p, q \in PRs:
       (head[p] < tip /\ head'[p] = tip /\ who[p] = who[q] /\ OnTip(q) /\ Landable(q)) =>
         FALSE]_vars

\* Statement 3, as a step rule.
OneLandingAtATime ==
  [][\A p \in PRs:
       (life[p] = "open" /\ head[p] < tip /\ head'[p] = tip) =>
         OneLandingAllows(p)]_vars

====
