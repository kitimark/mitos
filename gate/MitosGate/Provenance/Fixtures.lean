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
    (project context { facts with author := ⟨"h", ⟨"openai", "builder", none, some "opus"⟩⟩ }).author =
      none := by decide +kernel

theorem authorExistsBeforeAnyVerdict :
    ((project context { facts with verdicts := [] }).author.map (·.model)) =
      some "gpt-6.2-astra" := by decide +kernel

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

end MitosGate.Provenance.Fixture
