# tasks/P1-021-land-merge-rules.md

phase: 1
goal: The rules say the owner lands every pull request they keep by typing `/land <commit>`, the land workflow merges it, and no agent calls a merge route for it, asked or not; `pr-state.sh` prints `land-ready #N` with the line to type; no agent deletes a comment or edits one it did not post, and a Bash hook refuses `DELETE` on the comment routes. Closes #270.
statement: none (process rules)
touches: CLAUDE.md, .claude/skills/kitimark-mode/SKILL.md, docs/process.md, .cursor/ (the port of the same rules), .claude/hooks/pr-state.sh, .claude/hooks/pr-state.test.sh, .claude/hooks/check-no-comment-delete.sh, .claude/hooks/check-no-comment-delete.test.sh, .claude/settings.json (one hook entry), this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, .github/, plan/, .claude/scripts/watch-github.sh
checks: pr-state.test.sh, check-no-comment-delete.test.sh, check-no-session-link.test.sh, check-agent-spawn.test.sh, gh-api-rest.test.sh, plan-tasks.test.sh, shellcheck, cheats (in ci)
budget: 10 iterations · 3h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-021 in `plan/phase-1.md` (Land track), row A4 of the auto-merge amendment (#178,
  comment 6890739593, accepted by the owner on 15 Nov in #179, comment 6890996353); issue none
  yet; tracker #179. It closes #270.
- Needs P1-020 (A3) and its real runs. It lands right after them.
- Who merges: the owner, with `/land`, so it is the first kept pull request the land workflow
  merges. It touches agent rules, so it is kept; it touches no trust-infrastructure path.
- #270: the owner's merge request on a kept PR is refused by the session's permission check. The
  owner closed fix (a) with #271 ("we'll improve #179 do auto-merge when i approve the pr",
  6889810263). Until this row lands, the root gives the pinned merge command at once (#270, fix
  (b); #179, 6891010165).
- P1-015 (step 6) changes the same files later and keeps the rules this row does not take.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: contract only, so this row's issue says "contract only". The amendment's section 7 is the
rule text; nothing of this row is built.

revisit_when: re-check after P1-020 merges and its real runs are reported on #179.

modules: one topic per file.
- `CLAUDE.md` and `.claude/skills/kitimark-mode/SKILL.md`: the rules of section 7, each in the
  section it names: What stays with the user, Verdicts (the merge rule), Catching the user up and
  The root orchestrates. Watchers gains `<!-- land-report -->` beside `<!-- owner-ping -->` among
  the `github-actions[bot]` comments a watcher drops, as section 4 says.
- `docs/process.md`: the same rules where it states who merges and how the owner catches up.
- `.cursor/`: the port of those lines (`.cursor/rules/kitimark-mode.mdc` and the playbooks under
  `.cursor/skills/poteto-mode/playbooks/` that say who merges).
- `.claude/hooks/pr-state.sh` and its test: for a kept pull request whose first three merge
  conditions hold, `land-ready #N, the user lands it: comment /land <full head sha>`, and no merge
  command.
- `.claude/hooks/check-no-comment-delete.sh` and its test: refuses a Bash command or a GitHub tool
  call that sends `DELETE` to a comment route (`issues/comments/<id>`, `pulls/comments/<id>`,
  review routes). Its own file, because `check-no-session-link.sh` owns one topic; copies that
  hook's layout and its matcher in `.claude/settings.json`.

### Usage (caller's view)

A catch-up that hands the owner a kept pull request ends with:

```
/land <the full head sha>
```

to paste as a comment. Expected result: `github-actions` answers within minutes, and the merge
follows `gate` on `main`'s tip. The line stays valid when `main` moves, so no new catch-up follows a
rebase.

types: none.

statements: none. The rules rest on P1-018's `PlannedMergeIsGated` and P1-019's
`KeptMergeIsTheOwnersTypedApproval`.

reuse:
- `.claude/hooks/pr-state.sh`: the `merge-ready` line (314) and `user_kept`.
- `.claude/hooks/check-no-session-link.sh`: the hook layout and its `Bash|mcp__.*github.*`
  matcher in `.claude/settings.json`.

fixtures:
- `pr-state.test.sh`: a kept pull request with a passing verdict, a green `gate` and no unanswered
  comment prints `land-ready #N` with its full head and no `merge-ready` line; a pull request off
  the kept paths still prints `merge-ready`.
- `check-no-comment-delete.test.sh`: `gh api -X DELETE repos/o/r/issues/comments/1` and
  `--method DELETE` on each comment route are refused; a `GET` of the same routes and a `DELETE`
  elsewhere pass.
- The `gh pr comment` form of the catch-up joins only if P1-020's real run "A comment from the
  owner's own `gh` reads as typed" passed.

cut_line: one PR, `Closes #270`, `Part of #179`. It ships section 7's rules, `land-ready`, the
watcher drop rule and the comment hook. Merge means `land` for agents' own pull requests, and the
old updater's rules, stay with P1-015.

deferrals:
- To P1-015 (#194): every rule section 7 does not change (step 6 keeps the rest of the rules).
- From P1-019: the rule and the hook for a deleted comment (N6).

owner_decisions:
- **Settled by the owner's acceptance (15 Nov):** call 2 flips (one owner action on a kept path,
  the line `/land <commit>`; a spec pull request keeps its label first), call 6 (the owner must
  type), call 7 (`plan/` is kept), and N6 (accept, with the rule and the hook of section 7).
- **Root's defaults, made at plan time:** the hook in its own file; the `land-ready` line's
  words; the `gh pr comment` form only after the real run shows it reads as typed.

### The amendment's text for this row

Section 6, row A4:

| Row | Change | Needs | Merged by |
|---|---|---|---|
| A4, new, right after A3 | The rules of section 7. Closes #270. | A3 and its real runs | the owner, with `/land` |

Section 7:

- **`CLAUDE.md`, What stays with the user.** "The user merges every PR that…" becomes "the user lands every such PR by typing `/land <commit>`, and the land workflow merges it. No agent calls a merge route for it, asked or not."
- **Verdicts, merge rule.** The four conditions stay for the PRs agents merge. For a kept PR, `pr-state.sh` prints `land-ready #N` with the line to type, not a merge command.
- **Catch-ups.** Next steps hold one code block with only `/land <full head sha>`, to paste as a comment. The `gh pr comment` form is added once the real run shows it reads as typed. Expected result: `github-actions` answers within minutes, and the merge follows `gate` on `main`'s tip. The line stays valid when `main` moves, so no new catch-up follows a rebase. Only new content needs one.
- **The root.** On "approved, merge it" on a kept PR it replies with the line to type and makes no call. When the monitor shows the merge, it reads the PR over REST, unassigns the owner and writes the merged line.
- **Comments.** No agent deletes a comment, or edits one it did not post. The Bash hook refuses `DELETE` on the comment routes.
- **#270.** The owner closed fix (a) with #271. Fix (b) holds until A3 and A4 land: the root gives the pinned command at once. A4 closes #270.
- **Same PR:** `docs/process.md`, the mode skill under `.claude/skills/` and the `.cursor` port.

## Done when
- [ ] `pr-state.test.sh` and `check-no-comment-delete.test.sh` pass
- [ ] every hook test and `plan-tasks.test.sh` pass; shellcheck reports nothing
- [ ] the owner landed it with `/land <commit>`, and the merge is the land workflow's
- [ ] run-log record written (ops/runs/)
