namespace MitosGate.ModelIdentity

inductive AuthorModel
  | reported (actual : String)
  | absent
  deriving DecidableEq, Repr

def canonicalOutside : String → Bool
  | "openai" | "google" => true
  | _ => false

inductive Key
  | opus | sonnet | haiku
  | reported (provider model : String)
  deriving DecidableEq, Repr

private def family : String → Option Key
  | "opus" => some .opus
  | "sonnet" => some .sonnet
  | "haiku" => some .haiku
  | _ => none

private def version (s : String) : Bool :=
  !s.isEmpty && s.length ≤ 2 && s.toList.all Char.isDigit &&
    (s.length == 1 || s.toList.head? != some '0')

private def date (s : String) : Bool :=
  s.length == 8 && s.toList.all Char.isDigit && s.startsWith "20" &&
    ((String.ofList (s.toList.drop 4 |>.take 2)).toNat?).any (fun n => 1 ≤ n && n ≤ 12) &&
    ((String.ofList (s.toList.drop 6)).toNat?).any (fun n => 1 ≤ n && n ≤ 31)

private def versions : List String → Bool
  | [major] => version major && major != "0"
  | [major, minor] => version major && major != "0" && (version minor || date minor)
  | [major, minor, stamp] => version major && major != "0" && version minor && date stamp
  | _ => false

private def parts : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    if c == '-' then [] :: parts cs
    else match parts cs with
      | [] => [[c]]
      | x :: xs => (c :: x) :: xs

def claudeKey (model : String) : Option Key :=
  match (parts model.toList).map String.ofList with
  | [alias] => family alias
  | "claude" :: name :: rest =>
    match family name with
    | some f => if versions rest then some f else none
    | none =>
      match rest with
      | [f, stamp] => if versions [name, stamp] then family f else none
      | [minor, f, stamp] => if versions [name, minor, stamp] then family f else none
      | _ => none
  | _ => none

def key (provider model : String) : Option Key :=
  if ["", "unknown", "inherited", "requested", "default", "?"].contains provider.toLower ||
      ["", "unknown", "inherited", "requested", "default", "?"].contains model.toLower then none
  else match claudeKey model with
    | some f => some f
    | none =>
      if provider == "claude" || ["claude", "opus", "sonnet", "haiku", "fable"].any
          (fun p => p.toList.isPrefixOf model.toLower.toList) then none
      else some (.reported provider model)

def acceptedClaude (provider model : String) : Bool :=
  provider == "claude" && (claudeKey model).isSome

def opus (provider model : String) : Bool :=
  provider == "claude" && claudeKey model == some .opus

def different (authorProvider : String) (authorModel : AuthorModel)
    (judgeProvider judgeModel : String) : Bool :=
  match authorModel with
  | .reported actual =>
    match key authorProvider actual, key judgeProvider judgeModel with
    | some a, some v => a != v
    | _, _ => false
  | .absent => canonicalOutside authorProvider && authorProvider != judgeProvider &&
      (key judgeProvider judgeModel).isSome

theorem reportedDifferent_eq (ap am vp vm : String) :
    different ap (.reported am) vp vm =
      (match key ap am, key vp vm with
       | some a, some v => a != v
       | _, _ => false) := rfl

theorem acceptedNeedsClaude {p m : String} (h : acceptedClaude p m = true) : p = "claude" := by
  simp only [acceptedClaude, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

theorem differentNeedsKnown {ap am vp vm : String} (h : different ap (.reported am) vp vm = true) :
    (key ap am).isSome = true ∧ (key vp vm).isSome = true := by
  simp only [different] at h
  split at h
  · simp_all
  · cases h

theorem unknownClaudeKey : claudeKey "unknown" = none := by decide +kernel

theorem unknownAcceptedClaude (provider : String) : acceptedClaude provider "unknown" = false := by
  simp [acceptedClaude, unknownClaudeKey]

theorem unknownOpus (provider : String) : opus provider "unknown" = false := by
  simp [opus, unknownClaudeKey]

theorem canonicalOutsideNotClaude {p : String} (h : canonicalOutside p = true) : p ≠ "claude" := by
  intro he
  subst p
  cases h

theorem absentDifferentNeedsKnown {ap vp vm : String}
    (h : different ap .absent vp vm = true) :
    canonicalOutside ap = true ∧ ap ≠ vp ∧ (key vp vm).isSome = true := by
  simpa only [different, Bool.and_eq_true, bne_iff_ne, and_assoc] using h

theorem legacyOpusIsFullOpus : key "claude" "opus" = key "claude" "claude-opus-4-6" := by
  decide +kernel

theorem fullSonnetIsNotAnotherFamily :
    different "claude" (.reported "sonnet") "claude" "claude-sonnet-4-6" = false := by decide +kernel

theorem providerCannotBeInferred : acceptedClaude "openai" "claude-opus-4-6" = false := by
  decide +kernel

theorem unknownIsNotDifferent : different "openai" (.reported "inherited") "claude" "opus" = false := by
  decide +kernel

theorem futureVersionKeepsItsFamily :
    acceptedClaude "claude" "claude-sonnet-5-5" = true := by decide +kernel

theorem placeholderSuffixIsUnknown :
    acceptedClaude "claude" "claude-opus-4-6-latest" = false := by decide +kernel

theorem malformedClaudeAuthorIsUnknownAcrossSystems :
    key "grok" "claude-sonnet-5-5-inherited" = none := by decide +kernel

theorem bareFamilyAliasIsNotAnOpaqueAuthor : key "grok" "sonnet4.5" = none := by decide +kernel

theorem caseVariantAliasIsNotAnOpaqueAuthor : key "openai" "Opus-xhigh" = none := by decide +kernel

theorem underscoreAliasIsNotAnOpaqueAuthor : key "grok" "claude_sonnet_5_5" = none := by
  decide +kernel

end MitosGate.ModelIdentity
