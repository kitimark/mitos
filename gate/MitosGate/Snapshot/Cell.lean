import MitosGate.Speech

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

def families : List (List Char) := ["opus", "sonnet", "haiku", "fable", "grok"].map String.toList

def efforts : List (List Char) := ["low", "medium", "high", "xhigh", "max"].map String.toList

def judgeChar (c : Char) : Bool := c.isLower || c == '-'

def judge? (w : List Char) : Option (List Char) :=
  match families.find? (fun f => (f ++ ['-']).isPrefixOf w) with
  | some f => if efforts.contains (w.drop (f.length + 1)) then some f else none
  | none => none

def judges : Nat → List Char → List (List Char) × List Char
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

def result? (s : List Char) : Option (Result × List Char) :=
  if "PASS".toList.isPrefixOf s then some (.pass, s.drop 4)
  else if "FAIL".toList.isPrefixOf s then some (.fail, s.drop 4)
  else if "wording-only".toList.isPrefixOf s then some (.wordingOnly, s.drop 12)
  else none

def atOrCarriedFrom? (s : List Char) : Option (List Char × List Char) :=
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

def within (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | c :: cs => p.isPrefixOf (c :: cs) || within p cs

def unwrap (c : List Char) : List Char := (Speech.trim c).dropWhile fun x => x == '*' || x == '_'

structure Said where
  result : Result
  judges : List (List Char)
  sha : List Char

def tailOf (js : List (List Char) × List Char) : Option (List Char) :=
  if js.1.isEmpty then some js.2
  else
    match js.2 with
    | ' ' :: x => some x
    | _ => none

def judgesInParenthesis (s : List Char) : List (List Char) :=
  match s with
  | ' ' :: '(' :: r =>
    match judges r.length r with
    | (js, ',' :: _) => js
    | (js, ')' :: _) => js
    | _ => []
  | _ => []

def judgedUnlessWordingOnly (r : Result) (js : List (List Char)) : Bool :=
  (r == .wordingOnly) == js.isEmpty

def judgesInAtMostOnePlace (beforeSha inParenthesis : List (List Char)) : Bool :=
  beforeSha.isEmpty || inParenthesis.isEmpty

def onlyAFailSaysFail (r : Result) (cell : List Char) : Bool :=
  r == .fail || !within "FAIL".toList ((unwrap cell).drop 1)

def said? (cell : List Char) : Option Said :=
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

def resolveKnown (known : List Sha) (p : List Char) : Option Sha :=
  match Speech.matching known p with
  | [] => none
  | s :: rest => if rest.all (· == s) then some s else none

def root : Teammate := ⟨"claude", "root"⟩

def verdictsOf (known : List Sha) (cell : List Char) : List Verdict :=
  match said? cell with
  | none => []
  | some s =>
    match resolveKnown known s.sha with
    | none => []
    | some h =>
      if s.result == .wordingOnly then [⟨0, h, root, "unknown", .wordingOnly⟩]
      else s.judges.map fun f =>
        ⟨0, h, ⟨"claude", "verifier-" ++ String.ofList f⟩, String.ofList f, s.result⟩

def suffixes (p : List Char) : Option Char → List Char → List (List Char)
  | _, [] => []
  | prev, c :: cs =>
    (if !(prev.any Char.isAlphanum) && p.isPrefixOf (c :: cs) then [(c :: cs).drop p.length]
      else []) ++ suffixes p (some c) cs

def noModelBeforeNextDot (s : List Char) : Bool :=
  !families.any fun f => within f (s.takeWhile (· != '.'))

def authorOf (cell : List Char) : Option Author :=
  match suffixes "author ".toList none cell with
  | [rest] =>
    let tok := rest.takeWhile Char.isLower
    if families.contains tok && noModelBeforeNextDot (rest.drop tok.length) then
      some ⟨⟨"claude", "author"⟩, String.ofList tok⟩
    else none
  | _ => none

def PassNamesNoFail : Prop :=
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

end MitosGate.Snapshot
