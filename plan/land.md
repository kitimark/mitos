# Land track: merges on the owner's /land

**Goal:** replace the updater that rebases every open PR with a `land` workflow that merges only
the planned PR, on the owner's typed `/land`. The tracker is
[#179](https://github.com/kitimark/mitos/issues/179) and the design is
[#178](https://github.com/kitimark/mitos/issues/178).

This track was split out of `plan/phase-1.md` on 23 Nov 2026 at the owner's request. It has its own
milestone and no phase exit criteria. Task ids keep their `P1-0xx` names, because task files,
issues, run logs and Lean fixture names cite them.

## Land track (#179)

The land / auto-rebase migration. It replaces the updater that rebases every open PR on each move
of `main` with a planner that pushes only the PR that lands next, so rebase churn stops costing CI
runs, paid bot reviews and agent tokens. The design is [#178](https://github.com/kitimark/mitos/issues/178)
and the tracker is [#179](https://github.com/kitimark/mitos/issues/179). Step numbers are the
tracker's.

| # | Task | Kind | Issue |
|---|---|---|---|
| (step 0) | Bind admins on `main`, so a behind PR cannot merge (405) | setting | none, owner setting, done |
| P1-010 | Step 1. `Land.lean` with its proofs; `mitos-gate land` over fixed JSON (owner-gated: `gate/`) | gate | [#189](https://github.com/kitimark/mitos/issues/189) |
| P1-011 | Step 2. Owner-speech parser with its statements; the one snapshot producer (owner-gated: `gate/`) | gate | [#190](https://github.com/kitimark/mitos/issues/190) |
| P1-012 | Step 3. Shadow run: `decide` only prints its plan (owner-gated: `.github/`) | ci | [#191](https://github.com/kitimark/mitos/issues/191) |
| P1-013 | Step 4. Claude connector: `land.sh`, which treats `present` on a kept path as nothing to do, wake rules, the `bot-review.sh` cover rule (owner-gated: `.claude/`) | tooling | [#192](https://github.com/kitimark/mitos/issues/192) |
| P1-014 | Step 5. The switch: the push joins P1-020's `apply`, which pushes only the planned PR; the old loop is deleted (owner-gated: `.github/`) | ci | [#193](https://github.com/kitimark/mitos/issues/193) |
| P1-015 | Step 6. Process rules, the rest after P1-021: merge means `land`; the old updater's rules go (owner-gated: `.claude/`, `docs/process.md`, `.cursor/`) | process | [#194](https://github.com/kitimark/mitos/issues/194) |
| P1-016 | Step 7. Grok connector: the relay applies the wake table (owner-gated: `.github/`, `.cursor/`) | tooling | [#195](https://github.com/kitimark/mitos/issues/195) |
| P1-017 | Step 8. Fold `/land`, `/hold`, `land`, the approval and the later-comment rule into the protocol draft; add them and a `behind` flag to the TLA+ model | process | [#196](https://github.com/kitimark/mitos/issues/196) |
| P1-018 | A1. `Land.lean`: the owner's approval (`approves`), a later owner comment (`ownerSpoke`) and the `merge` plan, with statements 15 to 18; `LandCli` reads and prints them, and `Shadow`'s assumed word approves (owner-gated: `gate/`) | gate | [#295](https://github.com/kitimark/mitos/issues/295) |
| P1-019 | A2. The reader: only a typed comment that holds just `/land` or `/land <commit>` approves, and any later typed owner comment or review post retires it; its statements and the JSON cases (owner-gated: `gate/`) | gate | [#296](https://github.com/kitimark/mitos/issues/296) |
| P1-019b | A2b. A bare `/land`, alone in a typed comment, approves the head that was current when the owner commented (owner's call, 19 Nov). A PR that needs `spec-approved` keeps `/land <commit>` (owner's call, 28 Nov). Its statements, fixtures and JSON cases, before P1-020's real runs (owner-gated: `gate/`) | gate | [#508](https://github.com/kitimark/mitos/issues/508) |
| P1-020 | A3. `land.yml`: `decide`'s outputs, `apply` that only merges the planned PR on the owner's approval, and `report`; `land-apply.sh` and its test (owner-gated: `.github/`, the last kept PR the owner merges by hand) | ci | [#297](https://github.com/kitimark/mitos/issues/297) |
| P1-021 | A4. Rules: the owner lands a kept PR by typing `/land` or `/land <commit>`, and no agent calls its merge; `land-ready` in `pr-state.sh`; no agent deletes a comment. Closes #270 (owner-gated: `CLAUDE.md`, `.claude/`, `docs/process.md`, `.cursor/`; landed with `/land`) | process | [#298](https://github.com/kitimark/mitos/issues/298) |

Steps 1 and 2 can start now. Steps 3 and 4 follow them. Step 5, the switch, needs steps 0 to 4,
issue [#171](https://github.com/kitimark/mitos/issues/171) must land first, and holder `push`
records must have started ([amendment](https://github.com/kitimark/mitos/issues/178#issuecomment-6832011164),
asked of #172 in round 3). To roll back step 5, revert it, and if step 6 has landed, revert step 6's
rules too. Step 6 follows step 5 at once. Step 7 follows steps 1 and 2 (it reads the one snapshot
and the parser) and is best after step 5. Step 8 follows step 1.

Rows P1-018 to P1-021 are A1 to A4 of the [auto-merge amendment](https://github.com/kitimark/mitos/issues/178#issuecomment-6890739593), which the owner accepted on 15 Nov: the owner's typed `/land` or `/land <commit>` makes the land workflow merge a PR they keep. They ship before step 5, in order. P1-018 needs steps 1 and 2. P1-019 needs P1-018. P1-019b amends P1-019's reader ([#508](https://github.com/kitimark/mitos/issues/508), the owner's calls of 19 and 28 Nov). It sits after P1-019 and before P1-020's real runs R1 to R16, so the trial tests the final rule. P1-020 needs P1-018, P1-019, the protection reader of [#245](https://github.com/kitimark/mitos/issues/245) ([#278](https://github.com/kitimark/mitos/pull/278)) and the [approved A3 shadow-entry requirement](../tasks/P1-020-land-merge-workflow.md#approved-a3-shadow-entry-requirement) on #191: preserve the full failed P1-019 historical report; after truthful provenance repair is deployed, require a complete prospective window, at least one independently ready real kept owner merge, agreement of every ready kept case, and individual accounting of all remaining refusals. New feature/main disagreements block unless the owner explicitly decides them. R0b, current-head CI and reviews, independence, and owner merge control remain separate. P1-021 follows P1-020 at once, after P1-020's real runs. Step 5 then adds its push to P1-020's `apply`. To roll them back, lightest first: `/hold` on one PR; then the owner disables the `land` workflow (`gh workflow disable land.yml`), or merges by hand a one-line PR that sets `LAND_MERGE` off; then revert P1-021 and P1-020. P1-018 and P1-019 stay, because nothing acts on a `merge` plan then. To roll back P1-019b alone, `/hold` cancels a bare `/land` on one PR like any approval; then revert P1-019b's PR, after which a bare `/land` on a kept path gets the line to type again. `/land <commit>` works throughout. The owner can merge by hand at any time.
