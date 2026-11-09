/-!
# Applying a mutant's edits

A mutant is the reference implementation with a few small edits. Each edit names a file, a piece of
text to find and its replacement. An edit applies only where its text occurs **exactly once**, so a
manifest cannot be read two ways, and it changes that occurrence and nothing else
(`applyEdit_eq_some_iff`). Files no edit names are left as they are (`applyEdits_lookup`), so the
spec, the Challenge and the comparator configuration in a mutant's workspace are the approved ones.

The search works on `List Char`, so the proofs are list algebra.
-/

namespace Mutants

/-- The text before and after the first occurrence of `pat` in `s`. -/
def splitFirst (pat : List Char) : List Char → Option (List Char × List Char)
  | [] => if pat.isPrefixOf [] then some ([], []) else none
  | c :: cs =>
    if pat.isPrefixOf (c :: cs) then some ([], (c :: cs).drop pat.length)
    else (splitFirst pat cs).map fun (pre, post) => (c :: pre, post)

theorem isPrefixOf_iff {pat s : List Char} : pat.isPrefixOf s = true ↔ ∃ t, s = pat ++ t := by
  rw [List.isPrefixOf_iff_prefix]
  exact ⟨fun ⟨t, h⟩ => ⟨t, h.symm⟩, fun ⟨t, h⟩ => ⟨t, h.symm⟩⟩

/-- `splitFirst` finds an occurrence, and no occurrence starts earlier. -/
theorem splitFirst_some {pat : List Char} :
    ∀ {s pre post : List Char}, splitFirst pat s = some (pre, post) →
      s = pre ++ pat ++ post ∧ ∀ pre' post', s = pre' ++ pat ++ post' → pre.length ≤ pre'.length
  | [], pre, post, h => by
    simp only [splitFirst] at h
    split at h
    · rename_i hp
      obtain ⟨t, ht⟩ := isPrefixOf_iff.mp hp
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      have : pat = [] := (List.append_eq_nil_iff.mp ht.symm).1
      subst this
      simp
    · simp at h
  | c :: cs, pre, post, h => by
    simp only [splitFirst] at h
    split at h
    · rename_i hp
      obtain ⟨t, ht⟩ := isPrefixOf_iff.mp hp
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨?_, fun _ _ _ => Nat.zero_le _⟩
      rw [ht]; simp
    · rename_i hp
      obtain ⟨⟨pre₀, post₀⟩, h₀, he⟩ := Option.map_eq_some_iff.mp h
      simp only [Prod.mk.injEq] at he
      obtain ⟨rfl, rfl⟩ := he
      obtain ⟨ih₁, ih₂⟩ := splitFirst_some h₀
      refine ⟨by rw [ih₁]; simp, ?_⟩
      intro pre' post' hs
      match pre', hs with
      | [], hs => exact absurd (isPrefixOf_iff.mpr ⟨post', by simpa using hs⟩) hp
      | d :: pre'', hs =>
        simp only [List.cons_append, List.cons.injEq] at hs
        have := ih₂ pre'' post' (by simpa using hs.2)
        simp only [List.length_cons]
        omega

/-- If `pat` occurs in `s`, `splitFirst` finds an occurrence. -/
theorem splitFirst_isSome {pat : List Char} :
    ∀ {pre s post : List Char}, s = pre ++ pat ++ post → (splitFirst pat s).isSome
  | [], s, post, hs => by
    have hp : pat.isPrefixOf s = true := isPrefixOf_iff.mpr ⟨post, by simpa using hs⟩
    cases s with
    | nil => simp [splitFirst, hp]
    | cons c cs => simp [splitFirst, hp]
  | d :: pre, s, post, hs => by
    subst hs
    simp only [List.cons_append, splitFirst]
    split
    · rfl
    · simp only [Option.isSome_map]
      exact splitFirst_isSome (pre := pre) (post := post) rfl

/-- The text before and after the only occurrence of `pat` in `s`; `none` if `pat` occurs in `s`
never or more than once. -/
def splitOnce (pat s : List Char) : Option (List Char × List Char) :=
  match splitFirst pat s with
  | none => none
  | some (pre, post) =>
    if (splitFirst pat (s.drop (pre.length + 1))).isSome then none else some (pre, post)

/-- **An edit's text is found exactly once.** For a non-empty `pat`, `splitOnce` returns `pre` and
`post` exactly when `s` is `pre ++ pat ++ post` and no other occurrence of `pat` in `s` exists. -/
theorem splitOnce_eq_some_iff {pat s pre post : List Char} (hpat : pat ≠ []) :
    splitOnce pat s = some (pre, post) ↔
      s = pre ++ pat ++ post ∧ ∀ pre' post', s = pre' ++ pat ++ post' → pre' = pre := by
  constructor
  · intro h
    simp only [splitOnce] at h
    split at h
    · simp at h
    · rename_i pre₀ post₀ h₀
      split at h
      · simp at h
      · rename_i hnone
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        obtain ⟨hs, hmin⟩ := splitFirst_some h₀
        refine ⟨hs, fun pre' post' hs' => ?_⟩
        have hle := hmin pre' post' hs'
        rcases Nat.lt_or_eq_of_le hle with hlt | heq
        · -- a second occurrence starts after the first one's first character
          exfalso
          apply hnone
          have : s.drop (pre₀.length + 1) = pre'.drop (pre₀.length + 1) ++ pat ++ post' := by
            rw [hs', List.append_assoc, List.drop_append_of_le_length (by omega),
              List.append_assoc]
          exact splitFirst_isSome this
        · have := hs.symm.trans hs'
          rw [List.append_assoc, List.append_assoc] at this
          exact (List.append_inj this heq).1.symm
  · rintro ⟨hs, huniq⟩
    have hsome := splitFirst_isSome hs
    obtain ⟨⟨pre₀, post₀⟩, h₀⟩ := Option.isSome_iff_exists.mp hsome
    obtain ⟨hs₀, -⟩ := splitFirst_some h₀
    have hpre : pre₀ = pre := huniq pre₀ post₀ hs₀
    subst hpre
    have hpost : post₀ = post := by
      rw [hs₀, List.append_assoc, List.append_assoc] at hs
      exact List.append_cancel_left (List.append_cancel_left hs)
    subst hpost
    simp only [splitOnce, h₀]
    split
    · rename_i hsome'
      exfalso
      obtain ⟨⟨a, b⟩, hab⟩ := Option.isSome_iff_exists.mp hsome'
      obtain ⟨hab', -⟩ := splitFirst_some hab
      -- `pat` occurs again at position `pre₀.length + 1 + a.length`
      have hlen : pre₀.length + 1 ≤ s.length := by
        have : (s.drop (pre₀.length + 1)).length ≠ 0 := by
          rw [hab']
          simp only [List.length_append]
          have : pat.length ≠ 0 := by simpa using hpat
          omega
        simp only [List.length_drop] at this
        omega
      have hsplit : s = (s.take (pre₀.length + 1) ++ a) ++ pat ++ b := by
        conv => lhs; rw [← List.take_append_drop (pre₀.length + 1) s]
        rw [hab']
        simp
      have := huniq _ _ hsplit
      have hl := congrArg List.length this
      simp only [List.length_append, List.length_take] at hl
      omega
    · rfl

/-- `src` with the only occurrence of `find` replaced by `replace`; `none` if `find` occurs never
or more than once. -/
def applyEdit (src find replace : String) : Option String :=
  (splitOnce find.toList src.toList).map fun (pre, post) =>
    String.ofList (pre ++ replace.toList ++ post)

/-- An edit with a non-empty text applies exactly when the text occurs once, and it replaces that
occurrence and nothing else. -/
theorem applyEdit_eq_some_iff {src find replace out : String} (hfind : find ≠ "") :
    applyEdit src find replace = some out ↔
      ∃ pre post, src.toList = pre ++ find.toList ++ post ∧
        (∀ pre' post', src.toList = pre' ++ find.toList ++ post' → pre' = pre) ∧
        out.toList = pre ++ replace.toList ++ post := by
  have hpat : find.toList ≠ [] := by simpa [String.toList_eq_nil_iff] using hfind
  simp only [applyEdit, Option.map_eq_some_iff, Prod.exists]
  constructor
  · rintro ⟨pre, post, h, rfl⟩
    obtain ⟨hs, hu⟩ := (splitOnce_eq_some_iff hpat).mp h
    exact ⟨pre, post, hs, hu, by simp⟩
  · rintro ⟨pre, post, hs, hu, hout⟩
    refine ⟨pre, post, (splitOnce_eq_some_iff hpat).mpr ⟨hs, hu⟩, ?_⟩
    rw [← hout, String.ofList_toList]

/-- One edit of a mutant: in `file` (relative to `core/`), replace the only occurrence of `find`. -/
structure Edit where
  file    : String
  find    : String
  replace : String
  deriving Repr, DecidableEq

/-- The files (path, text) with `e` applied to the one named `e.file`. -/
def replaceFile (files : List (String × String)) (path text : String) : List (String × String) :=
  files.map fun (p, t) => if p == path then (p, text) else (p, t)

/-- Apply the edits in order, each to the text the earlier ones left. -/
def applyEdits (files : List (String × String)) : List Edit → Except String (List (String × String))
  | [] => .ok files
  | e :: es =>
    match files.lookup e.file with
    | none => .error s!"{e.file}: no such file in core/"
    | some src =>
      match applyEdit src e.find e.replace with
      | none => .error s!"{e.file}: the text to find does not occur exactly once: {e.find}"
      | some out => applyEdits (replaceFile files e.file out) es

theorem lookup_replaceFile_of_ne {files : List (String × String)} {path text p : String}
    (h : p ≠ path) : (replaceFile files path text).lookup p = files.lookup p := by
  induction files with
  | nil => rfl
  | cons f fs ih =>
    obtain ⟨q, t⟩ := f
    show List.lookup p ((if q == path then (q, text) else (q, t)) :: replaceFile fs path text) =
      List.lookup p ((q, t) :: fs)
    by_cases hq : q = path
    · subst hq
      have : (p == q) = false := by simpa using h
      simp [List.lookup, this, ih]
    · have : (q == path) = false := by simpa using hq
      simp only [this, Bool.false_eq_true, ite_false, List.lookup]
      split <;> simp_all

/-- **Edits add and remove no file**: the paths are the same, in the same order. -/
theorem applyEdits_paths :
    ∀ {files out : List (String × String)} {es : List Edit},
      applyEdits files es = .ok out → out.map (·.1) = files.map (·.1)
  | files, out, [], h => by
    simp only [applyEdits, Except.ok.injEq] at h
    rw [h]
  | files, out, e :: es, h => by
    simp only [applyEdits] at h
    split at h
    · simp at h
    · split at h
      · simp at h
      · rw [applyEdits_paths h]
        simp only [replaceFile, List.map_map]
        congr 1
        funext f
        simp only [Function.comp]
        split <;> rfl

/-- **Files no edit names are unchanged**, whatever the edits do to the others. -/
theorem applyEdits_lookup {p : String} :
    ∀ {files out : List (String × String)} {es : List Edit},
      applyEdits files es = .ok out → p ∉ es.map (·.file) → out.lookup p = files.lookup p
  | files, out, [], h, _ => by
    simp only [applyEdits, Except.ok.injEq] at h
    rw [h]
  | files, out, e :: es, h, hp => by
    simp only [List.map_cons, List.mem_cons, not_or] at hp
    simp only [applyEdits] at h
    split at h
    · simp at h
    · split at h
      · simp at h
      · rw [applyEdits_lookup h hp.2, lookup_replaceFile_of_ne hp.1]

end Mutants
