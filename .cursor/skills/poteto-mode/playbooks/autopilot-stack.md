### Autopilot-stack

Run the Autopilot-full playbook, but do not merge.

1. **In place of step 5, stop at verified.** Stop when each PR is verified and green at its current head, then hand the PRs to the operator. After the handoff, nobody pushes without the operator's go. A push the operator then approves goes to a fresh owner with consolidated scope, never to you, and its new head gets the verification step 4 names for that change. Every loop tick prompt names this file, so each tick sees the no-merge rule.
2. **Stack a PR only when it builds on another PR.** This is the one exception to step 3. Base the PR on the other PR's branch in place of trunk, per **Size and stacks** in `playbooks/opening-a-pr.md`. In place of step 2's rebase onto trunk, each PR rebases onto its parent PR's branch, and the stack root rebases onto trunk. A new head on the lower PR restacks the PRs above it, and each restacked head gets a verifier, because no PR in a stack keeps a verdict through a restack, per the **kitimark-mode** skill's Verdicts.

**Reply:** list each PR with its verdict, in place of what merged.
