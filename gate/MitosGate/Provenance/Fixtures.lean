import MitosGate.Provenance.Decode

namespace MitosGate.Provenance.Fixture

open Land (Obs)

def context : Obs := Land.Fixture.gptAuthoredCritical

def opus (actor : String := "independent-reviewer") (effort : Option Effort := some .xhigh)
    (order : Nat := 1) : VerdictFact :=
  ⟨"h", ⟨"claude", actor, some "claude-opus-4-6", none⟩, effort, .pass, order,
    "https://github.com/owner/repo/pull/1#issuecomment-1"⟩

def facts : PullFact :=
  ⟨1, ⟨"h", ⟨"openai", "builder", some "gpt-6.2-astra", none⟩⟩, [opus]⟩

theorem knownGptAuthorAndIndependentOpus : admitted context facts = true := by decide +kernel

theorem lowEffortCannotDischargeCritical :
    admitted context { facts with verdicts := [opus (effort := some .low)] } = false := by
  decide +kernel

theorem unknownEffortCannotDischargeCritical :
    admitted context { facts with verdicts := [opus (effort := none)] } = false := by decide +kernel

theorem lowEffortPassRemainsAPass :
    ((project context { facts with verdicts := [opus (effort := some .low)] }).verdicts.map
      (·.result)) = [.pass] := by decide +kernel

theorem supplementalLowEffortDoesNotVeto :
    admitted context { facts with verdicts := [opus,
      opus "supplemental-reviewer" (some .low) 2] } = true := by decide +kernel

theorem anUnknownActualAuthorStaysUnknown :
    ((project context { facts with author := ⟨"h", ⟨"openai", "builder", none, some "opus"⟩⟩ }).author.map
      fun a => (a.who, a.model)) = some (⟨"openai", "builder"⟩, .absent) := by decide +kernel

theorem authorExistsBeforeAnyVerdict :
    ((project context { facts with verdicts := [] }).author.map (·.model)) =
      some (.reported "gpt-6.2-astra") := by decide +kernel

theorem pendingVerdictsHaveNoAdmission :
    admitted context { facts with verdicts := [] } = false := by decide +kernel

theorem aStandingFailSurvivesAndBlocks :
    admitted context { facts with verdicts := [opus, { opus "other-reviewer" with
      result := .fail, order := 2 }] } = false := by decide +kernel

theorem aStandingHoldSurvivesAndBlocks :
    admitted context { facts with verdicts := [opus, { opus "other-reviewer" with
      result := .hold, order := 2 }] } = false := by decide +kernel

theorem newerSameGiverPassRetiresItsFail :
    admitted context { facts with verdicts := [{ opus with result := .fail }, opus (order := 2)] } =
      true := by decide +kernel

theorem anOpenAiWordingEntryCannotSupplyTheRootException :
    admitted context { facts with verdicts := [{ opus with
      identity := ⟨"openai", "root", some "gpt-6.2-sol", none⟩, result := .wordingOnly }] } =
      false := by decide +kernel

theorem onlyTrustedRootWordingCanSupplyTheException :
    admitted context { facts with verdicts := [{ opus "root" none with result := .wordingOnly }] } =
      true := by decide +kernel

theorem lowEffortRefusalDoesNotInventOwnerSpeech :
    (project context { facts with verdicts := [opus (effort := some .low)] }).words =
      context.words := rfl


def sonnetOnly : PullFact :=
  { facts with verdicts := [{ opus with identity :=
    ⟨"claude", "sonnet-reviewer", some "claude-sonnet-5-5", none⟩ }] }

theorem ordinaryWorkCanUseIndependentSonnet :
    admitted { context with paths := some ["ordinary.txt"] } sonnetOnly = true := by decide +kernel

theorem labelAloneRequiresQualifyingOpus :
    admitted { context with paths := some ["ordinary.txt"] } sonnetOnly ["spec-approved"] = false := by
  decide +kernel

theorem labelAloneAcceptsQualifyingOpus :
    admitted { context with paths := some ["ordinary.txt"] } facts ["spec-approved"] = true := by
  decide +kernel

def absentFacts : PullFact :=
  { facts with author := ⟨"h", ⟨"openai", "builder", none, none⟩⟩ }

def ordinary : Obs := { context with paths := some ["ordinary.txt"] }

def withProvider (provider : String) : PullFact :=
  { absentFacts with author := ⟨"h", ⟨provider, "builder", none, none⟩⟩ }

theorem canonicalGoogleAlsoAdmits : admitted context (withProvider "google") = true := by decide +kernel
theorem nullClaudeHolds : admitted context (withProvider "claude") = false := by decide +kernel
theorem emptyProviderHolds : admitted context (withProvider "") = false := by decide +kernel
theorem unknownProviderHolds : admitted context (withProvider "unknown") = false := by decide +kernel
theorem noncanonicalProviderHolds : admitted context (withProvider "outside") = false := by decide +kernel
theorem caseVariantProviderHolds : admitted context (withProvider "OpenAI") = false := by decide +kernel
theorem familyProviderHolds : admitted context (withProvider "opus") = false := by decide +kernel
theorem ambiguousProviderHolds : admitted context (withProvider "grok") = false := by decide +kernel
theorem sameProviderHolds :
    admitted ordinary { absentFacts with verdicts := [{ opus with identity :=
      ⟨"openai", "reviewer", some "gpt-6.2-astra", none⟩ }] } = false := by decide +kernel
theorem unknownWithoutPassHolds :
    admitted ordinary { absentFacts with verdicts := [] } = false := by decide +kernel
theorem unknownWithoutPassKeepsSourceGuardFalse :
    sourceGuard ordinary { absentFacts with verdicts := [] } = false := by decide +kernel
theorem unknownRootWordingCannotBypassPass :
    admitted ordinary { absentFacts with verdicts := [{ opus "root" none with
      result := .wordingOnly }] } = false := by decide +kernel
theorem unknownRootWordingCannotBypassEffort :
    admitted context { absentFacts with verdicts := [opus (effort := some .low),
      { opus "root" none (order := 2) with result := .wordingOnly }] } = false := by decide +kernel
theorem unknownCriticalNeedsActualEffort :
    [none, some Effort.low, some .medium, some .high].all (fun effort =>
      !admitted context { absentFacts with verdicts := [opus (effort := effort)] }) = true := by
  decide +kernel
theorem unknownLabelNeedsActualEffort :
    admitted ordinary { absentFacts with verdicts := [opus (effort := none)] }
      ["spec-approved"] = false := by decide +kernel
theorem aNewWordingEventRetiresTheUnknownAuthorsPass :
    admitted ordinary { absentFacts with verdicts := [opus,
      { opus (order := 2) with result := .wordingOnly }] } = false := by decide +kernel
theorem unknownStandingAdverseSurvives :
    [Land.Result.fail, .hold].all (fun result => !admitted ordinary
      { absentFacts with verdicts := [opus, { opus "adverse" (order := 2) with result }] }) = true := by
  decide +kernel
theorem unknownCannotLoseAuthorCarry :
    admitted context { absentFacts with author := { absentFacts.author with head := "other" } } =
      false := by decide +kernel
theorem unknownVerifierHasNoComparisonCredit :
    ModelIdentity.different "openai" .absent "claude" "unknown" = false := by decide +kernel
theorem absentSameProviderHasNoComparisonCredit :
    ModelIdentity.different "openai" .absent "openai" "gpt-6.2-astra" = false := by decide +kernel
theorem unknownAliasesDoNotSupplyIdentity :
    admitted context { absentFacts with author := ⟨"h", ⟨"openai", "builder", some "inherited",
      some "claude-opus-5-5"⟩⟩ } = false := by decide +kernel
theorem requestedAliasDoesNotChangeAbsentAdmission :
    admitted context { absentFacts with author := ⟨"h", ⟨"openai", "builder", none,
      some "claude-opus-5-5"⟩⟩ } = true := by decide +kernel

def real488 : PullFact :=
  ⟨488, ⟨"60b10dc1c4428c26e5cbcb78a4f8aaf83e1977cc", ⟨"openai", "codex", none, none⟩⟩,
    [⟨"60b10dc1c4428c26e5cbcb78a4f8aaf83e1977cc",
      ⟨"claude", "verifier-488-60b10dc", some "claude-opus-5-5", none⟩, some .xhigh, .pass, 1,
      "https://github.com/kitimark/mitos/pull/488#issuecomment-6975170797"⟩]⟩

def real488Context : Obs :=
  { context with
    pr := 488
    head := real488.author.head
    ids := [(real488.author.head, "real-488-content")]
    paths := some ["gate/MitosGate/Snapshot/Obs.lean"] }

theorem real488UnknownAuthorAndIndependentOpus : admitted real488Context real488 = true := by
  decide +kernel

end MitosGate.Provenance.Fixture
