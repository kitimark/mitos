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

def fable (actor : String := "fable-reviewer") (effort : Option Effort := some .xhigh)
    (order : Nat := 1) : VerdictFact :=
  ⟨"h", ⟨"claude", actor, some "claude-fable-5-2", none⟩, effort, .pass, order,
    "https://github.com/owner/repo/pull/1#issuecomment-2"⟩

def fableAuthored : PullFact :=
  { facts with author := ⟨"h", ⟨"claude", "builder", some "claude-fable-5-2", none⟩⟩ }

def opusAuthored : PullFact :=
  { facts with author := ⟨"h", ⟨"claude", "builder", some "claude-opus-5-5", none⟩⟩ }

theorem fableAuthorKeepsItsExactModel :
    ((project context fableAuthored).author.map (·.model)) = some (.reported "claude-fable-5-2") := by
  decide +kernel

theorem criticalFableAuthorAndIndependentOpus : admitted context fableAuthored = true := by
  decide +kernel

theorem fableAuthorNeedsActualOpusEffort :
    [none, some Effort.low, some .medium, some .high].all (fun effort =>
      !admitted context { fableAuthored with verdicts := [opus (effort := effort)] }) = true := by
  decide +kernel

theorem fablePassCannotCoverAFableAuthor :
    admitted ordinary { fableAuthored with verdicts := [{ fable with identity :=
      ⟨"claude", "fable-reviewer", some "claude-fable-5-3", none⟩ }] } = false := by decide +kernel

theorem fableJudgedOrdinaryGptWork : admitted ordinary { facts with verdicts := [fable] } = true := by
  decide +kernel

theorem fablePassCannotDischargeCritical :
    [some Effort.xhigh, some .max].all (fun effort =>
      !admitted context { facts with verdicts := [fable (effort := effort)] }) = true := by
  decide +kernel

theorem fablePassCannotDischargeTheLabel :
    admitted ordinary { facts with verdicts := [fable] } ["spec-approved"] = false := by
  decide +kernel

theorem fablePassCoversOrdinaryOpusWork :
    admitted ordinary { opusAuthored with verdicts := [fable] } = true := by decide +kernel

theorem criticalOpusWorkUsesFableAndAnotherOpus :
    admitted context { opusAuthored with verdicts := [fable] } = false ∧
      admitted context { opusAuthored with verdicts := [fable, opus (order := 2)] } = true := by
  decide +kernel

theorem unknownAuthorCanUseAnOrdinaryFablePass :
    admitted ordinary { absentFacts with verdicts := [fable] } = true := by decide +kernel

theorem unknownCriticalAuthorCannotUseFableAsOpus :
    admitted context { absentFacts with verdicts := [fable (effort := some .max)] } = false := by
  decide +kernel

open Lean (Json) in
def sourceIdentity (actor : String) (model : Json) : List (String × Json) :=
  [("head", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), ("provider", "claude"), ("actor", actor),
    ("actualModel", model)]

open Lean (Json) in
def source (author judge : Json) : Json :=
  Json.mkObj [("version", (1 : Nat)), ("repository", "owner/repo"),
    ("pulls", Json.arr #[Json.mkObj [("number", (1 : Nat)),
      ("author", Json.mkObj (sourceIdentity "builder" author)),
      ("verdicts", Json.arr #[Json.mkObj (sourceIdentity "reviewer" judge ++
        ([("effort", "xhigh"), ("result", "pass"), ("order", (1 : Nat)),
          ("evidence", "https://github.com/owner/repo/pull/1#issuecomment-1")] :
          List (String × Json)))])]])]

def sourceContext (paths : List String) : Obs :=
  { context with head := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                 ids := [("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "source-content")],
                 paths := some paths }

def decodedAdmitted (paths : List String) (author judge : String) : Bool :=
  match decodePayload "owner/repo" (source (.str author) (.str judge)) with
  | .ok [p] => admitted (sourceContext paths) p
  | _ => false

theorem fableAuthorDecodesExactly :
    ((decodePayload "owner/repo" (source "claude-fable-5-2" "claude-opus-5-5")).toOption.map
      (·.map fun p => (p.author.identity.actualModel, p.verdicts.map (·.identity.actualModel)))) =
      some [(some "claude-fable-5-2", [some "claude-opus-5-5"])] := by decide +kernel

theorem fableVerifierDecodesExactly :
    ((decodePayload "owner/repo" (source "claude-opus-5-5" "claude-fable-5-2")).toOption.map
      (·.map fun p => (p.author.identity.actualModel, p.verdicts.map (·.identity.actualModel)))) =
      some [(some "claude-opus-5-5", [some "claude-fable-5-2"])] := by decide +kernel

theorem decodedFableAuthorIsAdmittedWithOpus :
    decodedAdmitted ["gate/Main.lean"] "claude-fable-5-2" "claude-opus-5-5" = true := by
  decide +kernel

theorem decodedFableVerifierCoversOnlyOrdinaryOpusWork :
    decodedAdmitted ["ordinary.txt"] "claude-opus-5-5" "claude-fable-5-2" = true ∧
      decodedAdmitted ["gate/Main.lean"] "claude-opus-5-5" "claude-fable-5-2" = false := by
  decide +kernel

theorem decodedFableCannotVerifyFable :
    decodedAdmitted ["ordinary.txt"] "claude-fable-5-2" "claude-fable-5-3" = false := by
  decide +kernel

theorem bareOrMalformedFableIsRefused :
    ["fable", "claude-fable-5-2-latest", "claude-fable-0-1", "claude-fable-05-2", "Claude-fable-5-2",
      "fable5.2", "claude_fable_5_2"].all (fun m =>
      !(decodePayload "owner/repo" (source (.str m) "claude-opus-5-5")).isOk &&
        !(decodePayload "owner/repo" (source "claude-opus-5-5" (.str m))).isOk) = true := by
  decide +kernel

end MitosGate.Provenance.Fixture
