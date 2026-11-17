import MitosGate.Snapshot.Fixtures

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

namespace Fixture
namespace Compatibility

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

private def families : List (List Char) := ["opus", "sonnet", "haiku", "fable", "grok"].map String.toList

private def efforts : List (List Char) := ["low", "medium", "high", "xhigh", "max"].map String.toList

private def judgeChar (c : Char) : Bool := c.isLower || c == '-'

private def judge? (w : List Char) : Option (List Char) :=
  match families.find? (fun f => (f ++ ['-']).isPrefixOf w) with
  | some f => if efforts.contains (w.drop (f.length + 1)) then some f else none
  | none => none

private def judges : Nat → List Char → List (List Char) × List Char
  | 0, s => ([], s)
  | n + 1, s =>
    match judge? (s.takeWhile judgeChar) with
    | none => ([], s)
    | some f =>
      match s.dropWhile judgeChar with
      | ' ' :: '+' :: ' ' :: r =>
        match judges n r with
        | ([], _) => ([f], s.dropWhile judgeChar)
        | (fs, r') => (f :: fs, r')
      | r => ([f], r)

private def result? (s : List Char) : Option (Result × List Char) :=
  if "PASS".toList.isPrefixOf s then some (.pass, s.drop 4)
  else if "FAIL".toList.isPrefixOf s then some (.fail, s.drop 4)
  else if "wording-only".toList.isPrefixOf s then some (.wordingOnly, s.drop 12)
  else none

private def atOrCarriedFrom? (s : List Char) : Option (List Char × List Char) :=
  let r := if "at ".toList.isPrefixOf s then some (s.drop 3)
    else if "carried from ".toList.isPrefixOf s then some (s.drop 13) else none
  r.bind fun r =>
    let (tick, r) := match r with
      | '`' :: r => (true, r)
      | r => (false, r)
    let h := r.takeWhile hex
    let after := r.dropWhile hex
    if 7 ≤ h.length && h.length ≤ 40 &&
        (if tick then after.head? == some '`' else !(after.head?.any Char.isAlphanum)) then
      some (h, if tick then after.drop 1 else after)
    else none

private def within (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | c :: cs => p.isPrefixOf (c :: cs) || within p cs

private def unwrap (c : List Char) : List Char := (Speech.trim c).dropWhile fun x => x == '*' || x == '_'

private structure Said where
  result : Result
  judges : List (List Char)
  sha : List Char

private def tailOf (js : List (List Char) × List Char) : Option (List Char) :=
  if js.1.isEmpty then some js.2
  else
    match js.2 with
    | ' ' :: x => some x
    | _ => none

private def judgesInParenthesis (s : List Char) : List (List Char) :=
  match s with
  | ' ' :: '(' :: r =>
    match judges r.length r with
    | (js, ',' :: _) => js
    | (js, ')' :: _) => js
    | _ => []
  | _ => []

private def judgedUnlessWordingOnly (r : Result) (js : List (List Char)) : Bool :=
  (r == .wordingOnly) == js.isEmpty

private def judgesInAtMostOnePlace (beforeSha inParenthesis : List (List Char)) : Bool :=
  beforeSha.isEmpty || inParenthesis.isEmpty

private def onlyAFailSaysFail (r : Result) (cell : List Char) : Bool :=
  r == .fail || !within "FAIL".toList ((unwrap cell).drop 1)

private def said? (cell : List Char) : Option Said :=
  match result? (unwrap cell) with
  | some (r, ' ' :: rest) =>
    match (tailOf (judges rest.length rest)).bind atOrCarriedFrom? with
    | some (h, after) =>
      let beforeSha := (judges rest.length rest).1
      let inParenthesis := judgesInParenthesis after
      if judgedUnlessWordingOnly r (beforeSha ++ inParenthesis) &&
          judgesInAtMostOnePlace beforeSha inParenthesis && onlyAFailSaysFail r cell then
        some ⟨r, beforeSha ++ inParenthesis, h⟩
      else none
    | none => none
  | _ => none

private def resolveKnown (known : List Sha) (p : List Char) : Option Sha :=
  match Speech.matching known p with
  | [] => none
  | s :: rest => if rest.all (· == s) then some s else none

private def root : Teammate := ⟨"claude", "root"⟩

private def verdictsOf (known : List Sha) (cell : List Char) : List Verdict :=
  match said? cell with
  | none => []
  | some s =>
    match resolveKnown known s.sha with
    | none => []
    | some h =>
      if s.result == .wordingOnly then [⟨0, h, root, "unknown", .wordingOnly⟩]
      else s.judges.map fun f =>
        ⟨0, h, ⟨"claude", "verifier-" ++ String.ofList f⟩, String.ofList f, s.result⟩

private def suffixes (p : List Char) : Option Char → List Char → List (List Char)
  | _, [] => []
  | prev, c :: cs =>
    (if !(prev.any Char.isAlphanum) && p.isPrefixOf (c :: cs) then [(c :: cs).drop p.length]
      else []) ++ suffixes p (some c) cs

private def noModelBeforeNextDot (s : List Char) : Bool :=
  !families.any fun f => within f (s.takeWhile (· != '.'))

private def authorOf (cell : List Char) : Option Author :=
  match suffixes "author ".toList none cell with
  | [rest] =>
    let tok := rest.takeWhile Char.isLower
    if families.contains tok && noModelBeforeNextDot (rest.drop tok.length) then
      some ⟨⟨"claude", "author"⟩, String.ofList tok⟩
    else none
  | _ => none

private def PassNamesNoFail : Prop :=
  ∀ c s, said? c = some s → s.result ≠ .fail → within "FAIL".toList ((unwrap c).drop 1) = false

theorem resolveKnown_spec {known : List Sha} {p : List Char} {s : Sha}
    (h : resolveKnown known p = some s) :
    s ∈ known ∧ p.isPrefixOf s.toList = true ∧
      ∀ k ∈ known, p.isPrefixOf k.toList = true → k = s := by
  unfold resolveKnown at h
  split at h
  · cases h
  · next s' rest hm =>
    split at h
    · next ha =>
      cases h
      have hmem : s ∈ Speech.matching known p := by rw [hm]; exact List.mem_cons_self
      simp only [Speech.matching, List.mem_filter] at hmem
      refine ⟨hmem.1, hmem.2, fun k hk hkp => ?_⟩
      have : k ∈ Speech.matching known p := List.mem_filter.2 ⟨hk, hkp⟩
      rw [hm] at this
      rcases List.mem_cons.1 this with rfl | this
      · rfl
      · simpa using List.all_eq_true.1 ha k this
    · cases h

theorem verdictsOf_spec {known : List Sha} {c : List Char} {v : Verdict}
    (h : v ∈ verdictsOf known c) :
    ∃ s, said? c = some s ∧ v.result = s.result ∧ resolveKnown known s.sha = some v.head := by
  unfold verdictsOf at h
  split at h
  · cases h
  · next s hs =>
    split at h
    · cases h
    · next hd hr =>
      refine ⟨s, hs, ?_⟩
      split at h
      · next hw =>
        simp only [List.mem_singleton] at h
        subst h
        exact ⟨(beq_iff_eq.1 hw).symm, hr⟩
      · simp only [List.mem_map] at h
        obtain ⟨f, -, rfl⟩ := h
        exact ⟨rfl, hr⟩

theorem passNamesNoFail : PassNamesNoFail := by
  intro c s h hf
  unfold said? at h
  split at h
  · next r rest hr =>
    split at h
    · dsimp only at h
      split at h
      · next hok =>
        cases h
        simp only [onlyAFailSaysFail, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq,
          Bool.not_eq_true'] at hok
        rcases hok.2 with h | h
        · exact absurd h hf
        · exact h
      · cases h
    · cases h
  · cases h

private def dashboardCell (g : Global) (n : Pr) : Option (List Char) :=
  g.verdictCells.bind (·.lookup n)

private def observation (g : Global) (p : Pull) (r : Reads) (x : Git) : Obs :=
  { sourceObs g p r x with
    author := (dashboardCell g p.number).bind authorOf
    verdicts := ((dashboardCell g p.number).map (verdictsOf (ctx g p r).known)).getD [] }

private def VerdictsFromTheCell : Prop :=
  ∀ g p r x, ∀ v ∈ (observation g p r x).verdicts,
    ∃ c s, dashboardCell g p.number = some c ∧ said? c = some s ∧ v.result = s.result ∧
      v.head ∈ (ctx g p r).known ∧ s.sha.isPrefixOf v.head.toList = true ∧
      ∀ k ∈ (ctx g p r).known, s.sha.isPrefixOf k.toList = true → k = v.head

theorem verdictsFromTheCell : VerdictsFromTheCell := by
  intro g p r x v hv
  simp only [observation] at hv
  cases hc : dashboardCell g p.number with
  | none => rw [hc] at hv; simp at hv
  | some c =>
    rw [hc] at hv
    simp only [Option.map_some, Option.getD_some] at hv
    obtain ⟨s, hs, hres, hk⟩ := verdictsOf_spec hv
    obtain ⟨h1, h2, h3⟩ := resolveKnown_spec hk
    exact ⟨c, s, rfl, hs, hres, h1, h2, h3⟩

private def withRow (verdict : String) : Global := { g with verdictCells := cellFor7 verdict }

private def o (g : Global := g) (p : Pull := pull) (r : Reads := reads) (x : Git := git) : Obs :=
  observation g p r x

private def stepOf (g : Global := g) (p : Pull := pull) (r : Reads := reads) (x : Git := git) : Land.Step :=
  let ob := o g p r x
  Land.step Land.Fixture.orchestrator (Land.queueOf [ob]) ob

theorem noRowIsNotEligible :
    stepOf (g := { g with verdictCells := some [] }) = .stop .notEligible := by decide +kernel

theorem anOpusAuthorIsNotCoveredByItsOwnModel :
    stepOf (g := withRow "PASS opus-xhigh at `85b0781`, author opus") = .stop .notEligible := by
  decide +kernel

theorem noAuthorNoteIsNotEligible :
    stepOf (g := withRow "PASS opus-xhigh at `85b0781`") = .stop .notEligible := by decide +kernel

theorem aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush :
    stepOf (g := withRow carried) = .present hB := by decide +kernel

theorem aVerdictOnOtherContentDoesNotCarry :
    stepOf (g := withRow carried) (x := ⟨[(hB, "id-1"), (hA, "id-2")], .current⟩) =
      .stop .notEligible := by decide +kernel

theorem theContentIdsAsked : contentIdCommits (o (g := withRow carried)) = [hB, hA] := by
  decide +kernel

end Compatibility

open Compatibility

private def v (s : String) : List (Nat × Sha × Teammate × String × Result) :=
  (verdictsOf known s.toList).map fun x => (x.said, x.head, x.judge, x.model, x.result)

theorem carriedPassOfOneJudge :
    v "PASS opus-xhigh carried from `5c258d6a`, author sonnet (round 2). Minors #241." =
      [(0, hA, ⟨"claude", "verifier-opus"⟩, "opus", .pass)] := by decide +kernel
theorem twoJudges :
    (v "PASS sonnet-xhigh + opus-xhigh at 85b0781").map (·.2.2.1.name) =
      ["verifier-sonnet", "verifier-opus"] := by decide +kernel
theorem failOfOneJudge :
    (v "**FAIL opus-xhigh at `85b0781`**: the line stalls").map (·.2.2.2.2) = [.fail] := by
  decide +kernel
theorem wordingOnlyIsTheRoots :
    v "wording-only at `85b0781`" = [(0, hB, root, "unknown", .wordingOnly)] := by decide +kernel
theorem noVerdictSaysNothing : v "No verdict. Opened by Grok Bot." = [] := by decide +kernel
theorem passThenFailSaysNothing :
    v "PASS opus-xhigh at `85b0781`. Then FAIL sonnet-xhigh at `85b0781`." = [] := by
  decide +kernel
theorem judgelessPassSaysNothing : v "PASS carried from `85b0781`" = [] := by decide +kernel
theorem judgesInAParenthesis :
    (v "PASS carried from `5c258d6a` (sonnet-xhigh + opus-xhigh, author opus), two rebases.").map
      (fun x => (x.2.1, x.2.2.1.name)) = [(hA, "verifier-sonnet"), (hA, "verifier-opus")] := by
  decide +kernel
theorem judgesInBothPlacesSayNothing : v "PASS opus-xhigh at `85b0781` (sonnet-xhigh)" = [] := by
  decide +kernel
theorem aParenthesisOfProseIsNoJudge : v "PASS carried from `85b0781` (carry exit 0)" = [] := by
  decide +kernel
theorem aParenthesisAfterAWordIsNoJudge :
    v "PASS carried from `85b0781`, then (opus-xhigh)" = [] := by decide +kernel
theorem unknownEffortSaysNothing : v "PASS opus-huge at `85b0781`" = [] := by decide +kernel
theorem judgedWordingOnlySaysNothing : v "wording-only opus-xhigh at `85b0781`" = [] := by
  decide +kernel
theorem ambiguousPrefixSaysNothing :
    (verdictsOf [hA, hC] "PASS opus-xhigh at `5c258d6`".toList).isEmpty = true := by
  decide +kernel
theorem unknownCommitSaysNothing : v "PASS opus-xhigh at `deadbee`" = [] := by decide +kernel
theorem shortShaSaysNothing : v "PASS opus-xhigh at `85b078`" = [] := by decide +kernel
theorem unclosedTickSaysNothing : v "PASS opus-xhigh at `85b0781" = [] := by decide +kernel
theorem upperCaseHexSaysNothing : v "PASS opus-xhigh at 85B0781" = [] := by decide +kernel
theorem lowerCasePassSaysNothing : v "pass opus-xhigh at 85b0781" = [] := by decide +kernel

private def a (s : String) : Option (Teammate × String) :=
  (authorOf s.toList).map fun x => (x.who, x.model)

theorem authorNoteInAParenthesis :
    a "PASS carried from `5c258d6` (opus-xhigh, author sonnet, round 2), through the rebases." =
      some (⟨"claude", "author"⟩, "sonnet") := by decide +kernel
theorem authorNote :
    a "PASS opus-xhigh carried from `5c258d6`, author sonnet (round 2)." =
      some (⟨"claude", "author"⟩, "sonnet") := by decide +kernel
theorem mixedAuthorIsNone :
    a "PASS opus-xhigh at `5c258d6`, author sonnet, fixed by opus." = none := by decide +kernel
theorem twoAuthorNotesAreNone :
    a "PASS opus-xhigh at `5c258d6`, author sonnet. Earlier author opus." = none := by
  decide +kernel
theorem noAuthorNoteIsNone : a "PASS opus-xhigh at `5c258d6`." = none := by decide +kernel
theorem coauthorIsNoNote : a "PASS opus-xhigh at `5c258d6`, coauthor sonnet." = none := by
  decide +kernel
theorem unknownModelIsNone : a "PASS opus-xhigh at `5c258d6`, author gpt." = none := by
  decide +kernel

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let obligations := [``carriedPassOfOneJudge,
    ``twoJudges,
    ``failOfOneJudge,
    ``wordingOnlyIsTheRoots,
    ``noVerdictSaysNothing,
    ``passThenFailSaysNothing,
    ``judgelessPassSaysNothing,
    ``judgesInAParenthesis,
    ``judgesInBothPlacesSayNothing,
    ``aParenthesisOfProseIsNoJudge,
    ``aParenthesisAfterAWordIsNoJudge,
    ``unknownEffortSaysNothing,
    ``judgedWordingOnlySaysNothing,
    ``ambiguousPrefixSaysNothing,
    ``unknownCommitSaysNothing,
    ``shortShaSaysNothing,
    ``unclosedTickSaysNothing,
    ``upperCaseHexSaysNothing,
    ``lowerCasePassSaysNothing,
    ``authorNoteInAParenthesis,
    ``authorNote,
    ``mixedAuthorIsNone,
    ``twoAuthorNotesAreNone,
    ``noAuthorNoteIsNone,
    ``coauthorIsNoNote,
    ``unknownModelIsNone,
    ``Compatibility.resolveKnown_spec,
    ``Compatibility.verdictsOf_spec,
    ``Compatibility.passNamesNoFail,
    ``Compatibility.verdictsFromTheCell,
    ``Compatibility.noRowIsNotEligible,
    ``Compatibility.anOpusAuthorIsNotCoveredByItsOwnModel,
    ``Compatibility.noAuthorNoteIsNotEligible,
    ``Compatibility.aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush,
    ``Compatibility.aVerdictOnOtherContentDoesNotCarry,
    ``Compatibility.theContentIdsAsked]
  for n in obligations do
    let some c := (← getEnv).find? n | throwError "missing compatibility obligation {n}"
    unless c.isTheorem do throwError "{n} is not a compatibility theorem"
    for a in ← collectAxioms n do
      unless standard.contains a do throwError "{n} depends on the axiom {a}"

end Fixture
end MitosGate.Snapshot
