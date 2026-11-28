# tasks/603-fable-family.md

phase: 2
goal: The provenance decoder, `/land` and the `merge-ready` line accept a reported Fable id such as `claude-fable-5-2` as its own Claude model family, and the critical witness stays Opus.
statement: none locked (tooling task); new gate theorems `ModelIdentity.fableKeyIsNeverOpus`, `ModelIdentity.fableKeyOrUnknown`, `ModelIdentity.fableKeysAreOneFamily`, `ModelIdentity.fableIdIsAcceptedClaude`, `ModelIdentity.fableAndOtherFamiliesDiffer`, and the Fable cases in `Land.Fixture` and `Provenance.Fixture`
touches: gate/MitosGate/ModelIdentity.lean, gate/MitosGate/Land.lean (fixtures only), gate/MitosGate/Provenance/Fixtures.lean, gate/MitosGate/Snapshot.lean (axiom audit list), gate/snapshot-test.sh, .claude/skills/kitimark-mode/SKILL.md, .agents/skills/kitimark-mode/SKILL.md, .agents/scripts/agents-roster.tsv (stamp), this task, one run record
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, the source schema, `opus`, `requiresOpus`, `opusPass`, the Land coverage statements
checks: build, imports, lock, provenance and snapshot tests, Land, Speech, Shadow, runlog, agents-skills
budget: 40 iterations · 3h wall · tokens unmetered
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

Issue [#603](https://github.com/kitimark/mitos/issues/603). `ModelIdentity.family` knew only
`opus`, `sonnet` and `haiku`. So `claudeKey "claude-fable-5-2"` was `none`, `Decode.identity`
refused the identity, and `mitos-gate provenance render` refused any payload with a Fable author
or verifier (seen on #590). A published section with such an identity would refuse the whole
source for every PR.

## Design

depth: build
revisit_when: none
modules:
- `gate/MitosGate/ModelIdentity.lean`: the model families. Adds `Key.fable` and `family "fable"`,
  and the Fable theorems after the existing ones (about 40 lines).
- `gate/MitosGate/Land.lean`: Land coverage fixtures for Fable authors and verifiers, next to the
  Sonnet and Opus ones (about 30 lines).
- `gate/MitosGate/Provenance/Fixtures.lean`: source admission fixtures for a Fable author and a
  Fable verifier, and `decodePayload` cases from source JSON to admission (about 110 lines).
- `gate/MitosGate/Snapshot.lean`: its axiom audit also names the two general Fable theorems.
- `gate/snapshot-test.sh`: render, decode, Snapshot and native hook cases for Fable through the
  built binary. `render` itself is not decidable in the kernel (its JSON printer and parser do
  not reduce there), so render cases stay in this test.
types: `Key` gains the constructor `fable`. No signature changes.
statements: see `statement` above. The existing theorems keep their statements.
reuse: `claudeKey`'s version parser, so `claude-fable-5-2` is read the way `claude-sonnet-5-5` is.
fixtures: `Land.Fixture.fableWrittenReady`, `Land.Fixture.criticalFableAuthored`,
`Provenance.Fixture.fable`, `Provenance.Fixture.fableAuthored`, `Provenance.Fixture.opusAuthored`,
`Provenance.Fixture.source`, `Provenance.Fixture.decodedAdmitted`, and the Fable cases of
`gate/snapshot-test.sh`.
cut_line: Fable is one family for every version. Mythos is out of scope.
deferrals: none
owner_decisions: Fable is its own family for independence: Fable and Opus, Sonnet or Haiku verify
each other, and Fable does not verify Fable. The trust-critical witness stays Opus at `xhigh` or
`max`, and `ModelIdentity.opus` stays false for every Fable id. This is the root's default, taken
from the recommendation in #603, not an owner ruling. Its reason: Fable is a different model from
Opus, Sonnet and Haiku, so its review is independent of theirs, and the rule that names Opus as
the critical witness is the owner's to widen.

Refusals that stay: the bare short name `fable` as an `actualModel` is refused by
`Decode.identity`'s list, a malformed or placeholder Fable id (`claude-fable-5-2-latest`) has no
key, a compact alias (`fable5.2`) is no opaque author, and a provider is never inferred from the
model (`acceptedClaude "openai" "claude-fable-5-2" = false`). No `eval/cheats/` case: the cheat
corpus tests the plugin acceptance gate, and this change adds no acceptance check there.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)
