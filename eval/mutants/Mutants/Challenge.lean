import Mutants.Manifest

/-!
# The Challenges and solution modules the runner generates

A mutant is caught when the comparator accepts a proof that a Challenge theorem is **false** for
it. The statement to refute is taken from the approved Challenge (`core/Challenge/Resolver.lean`),
never written by hand: each named theorem

```
theorem Mitos.Proofs.<name> : <statement> := sorry
```

becomes `theorem Mitos.Refute.<name> : ¬ (<statement>) := sorry`, in a copy of the Challenge that
keeps every other line and drops the theorems not named. The comparator then compares the case's
`Refute.lean` with this Challenge as kernel terms, so a refutation of anything but what that line
states is rejected. The Challenge imports the mutated implementation (below), so what the line
states is the approved statement only because the implementation declares no syntax: a macro there
would rewrite the line (review on #86, round 2). The lint (`Mutants.Lint`) ensures that before
anything is built.

## The holes are compared by value

The approved Challenge declares the definition holes (`def Mitos.Impl.resolve : … := sorry`), and
the comparator compares a hole by its name and **type** only. If the refutation Challenge kept
those lines, any declaration of that name and type in the solution's environment would do, such as
one the case's `Refute.lean` makes itself. So the Challenges the runner generates drop the hole
lines and **import the mutated core's `Mitos/Impl/` modules** instead, and their configurations
name no definition holes. Each hole is then an ordinary constant of the Challenge, which the
comparator compares by **value**: the solution's `Mitos.Impl.resolve`, with every constant it uses,
must be exactly the one the mutated implementation declares. Whatever the case declares, a
different hole is rejected.

Every refutation Challenge also states `Mitos.Refute.holes`, an equation naming every definition
hole, which the runner's own solution module proves by `rfl`. So every hole is compared by value
in every refutation run, also one the named theorems do not mention, and every hole's definition is
in the export the kernels replay (without `Mitos.Impl.impact`'s, Lean's replay kernel could not
reduce the `decide` in `src_dst_swapped`'s refutation).

The **hole run** (`Mutants.Verdict`) shows separately that the mutated `Mitos/Impl/` modules build
from the approved core alone and declare every hole publicly. Its implementation files are the
other runs' (`holeCore_impl`), and the lint ensures they run no code and read no file while Lean
elaborates them, so they elaborate the same in every run, whatever other files a run holds.

The reader fails closed: every line of the Challenge must be blank, a comment, an `import`, a
one-line definition hole (`def … := sorry`) or a one-line theorem in the form above, so no line
that could change what a statement means (`open`, `namespace`, notation) is dropped or moved.
-/

namespace Mutants

/-- One line of the Challenge. -/
inductive Line where
  /-- `import …`, outside a comment. -/
  | imp (text : String)
  /-- Kept as it is: blank, or a comment. -/
  | keep (text : String)
  /-- A one-line definition hole, `def … := sorry`. -/
  | hole (text : String)
  /-- `theorem Mitos.Proofs.<name> : <stmt> := sorry`, the whole line being `text`. -/
  | thm (name stmt text : String)
  deriving Repr, DecidableEq

def thmPrefix : List Char := "theorem Mitos.Proofs.".toList
def sorrySuffix : List Char := " := sorry".toList

/-- The name and statement of a one-line theorem hole, if `l` is one. -/
def theoremHole (l : List Char) : Option (String × String) :=
  if thmPrefix.isPrefixOf l && sorrySuffix.isSuffixOf l then
    let rest := l.drop thmPrefix.length
    let name := rest.takeWhile fun c => c.isAlphanum || c == '_'
    let after := rest.drop name.length
    if !name.isEmpty && " : ".toList.isPrefixOf after && after.length ≥ 3 + sorrySuffix.length then
      some (String.ofList name,
        String.ofList ((after.drop 3).take (after.length - 3 - sorrySuffix.length)))
    else none
  else none

/-- Reads one line; `inDoc` says whether it is inside a block comment. -/
def readLine (inDoc : Bool) (l : String) : Except String (Line × Bool) :=
  let cs := l.toList
  let closes := "-/".toList.isSuffixOf cs
  if inDoc then .ok (.keep l, !closes)
  else if "/-".toList.isPrefixOf cs then .ok (.keep l, !closes)
  else if cs.all (· == ' ') || "--".toList.isPrefixOf cs then .ok (.keep l, false)
  else if "import ".toList.isPrefixOf cs then .ok (.imp l, false)
  else if "def ".toList.isPrefixOf cs && sorrySuffix.isSuffixOf cs then .ok (.hole l, false)
  else match theoremHole cs with
    | some (n, s) => .ok (.thm n s l, false)
    | none => .error s!"the Challenge has a line the refutation reader does not handle: {l}"

def readLines (inDoc : Bool) : List String → Except String (List Line)
  | [] => if inDoc then .error "the Challenge ends inside a block comment" else .ok []
  | l :: ls => do
    let (x, inDoc') ← readLine inDoc l
    return x :: (← readLines inDoc' ls)

def readChallenge (src : String) : Except String (List Line) :=
  readLines false (src.splitOn "\n")

def Line.isThm (name : String) : Line → Bool
  | .thm n _ _ => n == name
  | _ => false

def negated (name stmt : String) : String :=
  s!"theorem Mitos.Refute.{name} : ¬ ({stmt}) := sorry"

/-! ## Modules and imports -/

/-- The module of a `.lean` path: `Mitos/Impl/Resolve.lean` is `Mitos.Impl.Resolve`. -/
def moduleOf (path : String) : String :=
  ".".intercalate ((String.ofList (path.toList.take (path.length - 5))).splitOn "/")

/-- The implementation modules of a core, given its paths: every module under `Mitos/Impl/`. -/
def implModules (paths : List String) : List String :=
  (paths.filter (inArea "Impl")).map moduleOf

theorem mem_implModules {paths : List String} {m : String} :
    m ∈ implModules paths ↔ ∃ p ∈ paths, inArea "Impl" p = true ∧ m = moduleOf p := by
  simp only [implModules, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨p, ⟨hp, hi⟩, rfl⟩; exact ⟨p, hp, hi, rfl⟩
  · rintro ⟨p, hp, hi, rfl⟩; exact ⟨p, ⟨hp, hi⟩, rfl⟩

def importLine (m : String) : String := s!"import {m}"

/-! ## The Challenges with the holes as values -/

/-- A Challenge with the holes as values: an import of each implementation module, then the
approved Challenge's lines with the hole lines dropped and each theorem line as `thm` renders it,
then `extra`. -/
def byValue (impls : List String) (thm : String → String → String → Option String)
    (ls : List Line) (extra : List String) : List String :=
  impls.map importLine ++
    ls.filterMap (fun
      | .imp t => some t
      | .keep t => some t
      | .hole _ => none
      | .thm n s t => thm n s t) ++
    extra

theorem mem_byValue {impls : List String} {thm : String → String → String → Option String}
    {ls : List Line} {extra : List String} {x : String} :
    x ∈ byValue impls thm ls extra ↔
      (∃ m ∈ impls, x = importLine m) ∨ Line.imp x ∈ ls ∨ Line.keep x ∈ ls ∨
        (∃ n s t, Line.thm n s t ∈ ls ∧ thm n s t = some x) ∨ x ∈ extra := by
  simp only [byValue, List.mem_append, List.mem_map, List.mem_filterMap]
  constructor
  · rintro ((⟨m, hm, rfl⟩ | ⟨l, hl, hr⟩) | he)
    · exact .inl ⟨m, hm, rfl⟩
    · cases l with
      | imp t => simp only [Option.some.injEq] at hr; exact .inr (.inl (hr ▸ hl))
      | keep t => simp only [Option.some.injEq] at hr; exact .inr (.inr (.inl (hr ▸ hl)))
      | hole t => simp at hr
      | thm n s t => exact .inr (.inr (.inr (.inl ⟨n, s, t, hl, hr⟩)))
    · exact .inr (.inr (.inr (.inr he)))
  · rintro (⟨m, hm, rfl⟩ | hi | hk | ⟨n, s, t, hl, hr⟩ | he)
    · exact .inl (.inl ⟨m, hm, rfl⟩)
    · exact .inl (.inr ⟨_, hi, rfl⟩)
    · exact .inl (.inr ⟨_, hk, rfl⟩)
    · exact .inl (.inr ⟨_, hl, hr⟩)
    · exact .inr he

/-- The statement that names every definition hole: `(h₁, h₂, …) = (h₁, h₂, …)`. -/
def holesStatement (defs : List String) : String :=
  let t := s!"({", ".intercalate defs})"
  s!"{t} = {t}"

def holesName : String := "Mitos.Refute.holes"

/-- The extra line of a refutation Challenge, if the Challenge has definition holes. -/
def holesHole (defs : List String) : List String :=
  if defs.isEmpty then [] else [s!"theorem {holesName} : {holesStatement defs} := sorry"]

/-- The refutation Challenge for `names`: the holes as values, the named theorems negated, the
others dropped, and `Mitos.Refute.holes`. Every name must be a theorem the Challenge states exactly
once. -/
def refutation (impls defs : List String) (ls : List Line) (names : List String) :
    Except String (List String) :=
  match names.find? (fun b => (ls.filter (·.isThm b)).length != 1) with
  | some b => .error s!"breaks= names {b}, which the Challenge states {(ls.filter (·.isThm b)).length} times"
  | none => .ok (byValue impls (fun n s _ => if names.contains n then some (negated n s) else none)
      ls (holesHole defs))

/-- Every name a refutation is built for is a theorem the Challenge states exactly once. -/
theorem refutation_once {impls defs : List String} {ls : List Line} {names : List String}
    {out : List String} (h : refutation impls defs ls names = .ok out) :
    ∀ b ∈ names, (ls.filter (·.isThm b)).length = 1 := by
  unfold refutation at h
  split at h
  · simp at h
  · rename_i hnone
    intro b hb
    have := List.find?_eq_none.mp hnone b hb
    simpa using this

/-- **The refutation Challenge states only approved text, with the holes as values.** Each of its
lines is an import of an implementation module, an import or comment line of the Challenge, the
negation of the statement of a named Challenge theorem, or the `Mitos.Refute.holes` line; and each
named theorem's negation is there. -/
theorem mem_refutation {impls defs : List String} {ls : List Line} {names : List String}
    {out : List String} (h : refutation impls defs ls names = .ok out) (x : String) :
    x ∈ out ↔ ((∃ m ∈ impls, x = importLine m) ∨ Line.imp x ∈ ls ∨ Line.keep x ∈ ls ∨
      (∃ n ∈ names, ∃ s t, Line.thm n s t ∈ ls ∧ x = negated n s) ∨ x ∈ holesHole defs) := by
  unfold refutation at h
  split at h
  · simp at h
  · simp only [Except.ok.injEq] at h
    subst h
    rw [mem_byValue]
    constructor
    · rintro (h | h | h | ⟨n, s, t, hl, hr⟩ | h)
      · exact .inl h
      · exact .inr (.inl h)
      · exact .inr (.inr (.inl h))
      · split at hr
        · rename_i hn
          simp only [Option.some.injEq] at hr
          exact .inr (.inr (.inr (.inl ⟨n, by simpa using hn, s, t, hl, hr.symm⟩)))
        · simp at hr
      · exact .inr (.inr (.inr (.inr h)))
    · rintro (h | h | h | ⟨n, hn, s, t, hl, rfl⟩ | h)
      · exact .inl h
      · exact .inr (.inl h)
      · exact .inr (.inr (.inl h))
      · exact .inr (.inr (.inr (.inl ⟨n, s, t, hl, by simpa using hn⟩)))
      · exact .inr (.inr (.inr (.inr h)))

/-- The approved Challenge with the holes as values: every theorem line kept verbatim. -/
def approvedByValue (impls : List String) (ls : List Line) : List String :=
  byValue impls (fun _ _ t => some t) ls []

/-- **The approved Challenge by value states the approved theorems verbatim.** Each of its lines is
an import of an implementation module or a line of the approved Challenge that is not a hole, and
every theorem line of the approved Challenge is there. -/
theorem mem_approvedByValue {impls : List String} {ls : List Line} {x : String} :
    x ∈ approvedByValue impls ls ↔
      (∃ m ∈ impls, x = importLine m) ∨ Line.imp x ∈ ls ∨ Line.keep x ∈ ls ∨
        ∃ n s, Line.thm n s x ∈ ls := by
  rw [approvedByValue, mem_byValue]
  constructor
  · rintro (h | h | h | ⟨n, s, t, hl, hr⟩ | h)
    · exact .inl h
    · exact .inr (.inl h)
    · exact .inr (.inr (.inl h))
    · simp only [Option.some.injEq] at hr
      exact .inr (.inr (.inr ⟨n, s, hr ▸ hl⟩))
    · simp at h
  · rintro (h | h | h | ⟨n, s, hl⟩)
    · exact .inl h
    · exact .inr (.inl h)
    · exact .inr (.inr (.inl h))
    · exact .inr (.inr (.inr (.inl ⟨n, s, x, hl, rfl⟩)))

/-! ## The hole run's core -/

/-- Outside `Mitos/Proofs/`, where the proofs, a known gap's proof repairs and the case's
`Refute.lean` go. -/
def outsideProofs (path : String) : Bool :=
  match path.splitOn "/" with
  | "Mitos" :: "Proofs" :: _ => false
  | _ => true

theorem outsideProofs_of_impl {p : String} (h : inArea "Impl" p = true) : outsideProofs p = true := by
  obtain ⟨rest, hr⟩ := inArea_head h
  simp [outsideProofs, hr]

/-- The core of the hole run: the core without `Mitos/Proofs/`, with the mutant's edits under
`Mitos/Impl/` and no others. -/
def holeCore (files : List (String × String)) (m : Mutant) : Except String (List (String × String)) :=
  applyEdits (files.filter fun f => outsideProofs f.1) m.implEdits

/-- **The hole run's core is the approved core without `Mitos/Proofs/`, with only the mutant's
implementation edited**: each of its paths is a path of the core outside `Mitos/Proofs/`, and
each file outside `Mitos/Impl/` is the core's. So it holds no file the case wrote for its proofs.
-/
theorem holeCore_spec {files out : List (String × String)} {m : Mutant}
    (h : holeCore files m = .ok out) :
    (∀ p ∈ out.map (·.1), outsideProofs p = true ∧ p ∈ files.map (·.1)) ∧
      ∀ p, inArea "Impl" p = false → out.lookup p = (files.filter fun f => outsideProofs f.1).lookup p := by
  unfold holeCore at h
  refine ⟨?_, fun p hp => applyEdits_lookup h ?_⟩
  · rw [applyEdits_paths h]
    intro p hp
    simp only [List.mem_map, List.mem_filter] at hp
    obtain ⟨f, ⟨hf, ho⟩, rfl⟩ := hp
    exact ⟨ho, List.mem_map_of_mem hf⟩
  · simp only [Mutant.implEdits, List.mem_map, List.mem_filter, not_exists, not_and]
    intro e he hpe
    rw [hpe] at he
    simp [hp] at he

/-- The text of the file `p`, `src`, after the edits that name it, in order. -/
def editsOn (p src : String) : List Edit → Option String
  | [] => some src
  | e :: es =>
    if e.file = p then (applyEdit src e.find e.replace).bind (editsOn p · es) else editsOn p src es

theorem lookup_replaceFile_self {p text : String} :
    ∀ {files : List (String × String)}, (files.lookup p).isSome →
      (replaceFile files p text).lookup p = some text
  | [], h => by simp at h
  | (q, t) :: fs, h => by
    show List.lookup p ((if q == p then (q, text) else (q, t)) :: replaceFile fs p text) = some text
    by_cases hq : q = p
    · subst hq; simp
    · have h1 : (q == p) = false := by simpa using hq
      have h2 : (p == q) = false := by simpa using Ne.symm hq
      simp only [h1, Bool.false_eq_true, ite_false, List.lookup, h2]
      simp only [List.lookup, h2] at h
      exact lookup_replaceFile_self h

/-- After edits, a file's text is its text before them with the edits that name it applied. -/
theorem applyEdits_lookup_eq {p s : String} :
    ∀ {files out : List (String × String)} {es : List Edit},
      applyEdits files es = .ok out → files.lookup p = some s → out.lookup p = editsOn p s es
  | files, out, [], h, hs => by
    simp only [applyEdits, Except.ok.injEq] at h
    rw [← h, hs]; rfl
  | files, out, e :: es, h, hs => by
    simp only [applyEdits] at h
    split at h
    · simp at h
    · rename_i src hsrc
      split at h
      · simp at h
      · rename_i o ho
        by_cases he : e.file = p
        · subst he
          rw [hs] at hsrc
          cases hsrc
          rw [applyEdits_lookup_eq h (lookup_replaceFile_self (by simp [hs]))]
          simp [editsOn, ho]
        · rw [applyEdits_lookup_eq h (by rw [lookup_replaceFile_of_ne (Ne.symm he)]; exact hs)]
          simp [editsOn, he]

theorem editsOn_filter {p : String} {f : Edit → Bool} :
    ∀ {src : String} {es : List Edit}, (∀ e ∈ es, e.file = p → f e = true) →
      editsOn p src (es.filter f) = editsOn p src es
  | _, [], _ => rfl
  | src, e :: es, h => by
    have ih : ∀ s, editsOn p s (es.filter f) = editsOn p s es :=
      fun _ => editsOn_filter fun e' he' => h e' (List.mem_cons_of_mem _ he')
    by_cases hf : f e = true
    · simp only [List.filter_cons, hf, ite_true, editsOn, ih]
    · have he : e.file ≠ p := fun he => hf (h e (List.mem_cons_self ..) he)
      simp only [List.filter_cons, hf, Bool.false_eq_true, ite_false, editsOn, he, ih]

theorem lookup_filter_key {p : String} {g : String → Bool} :
    ∀ {l : List (String × String)}, (l.filter fun f => g f.1).lookup p = if g p then l.lookup p else none
  | [] => by simp
  | (q, t) :: l => by
    by_cases hq : p = q
    · subst hq
      by_cases hg : g p = true <;> simp [hg, List.lookup, lookup_filter_key]
    · have hpq : (p == q) = false := by simpa using hq
      by_cases hg : g q = true <;>
        simp [hg, List.lookup, hpq, lookup_filter_key]

/-- **The hole run's implementation files are the other runs'**: each file under `Mitos/Impl/` has
the same text in the hole run's core as in the mutated core the other runs use. -/
theorem holeCore_impl {files hole full : List (String × String)} {m : Mutant}
    (hh : holeCore files m = .ok hole) (hf : applyEdits files m.edits = .ok full)
    {p : String} (hp : inArea "Impl" p = true) : hole.lookup p = full.lookup p := by
  unfold holeCore at hh
  cases hs : files.lookup p with
  | none =>
    have hkeys : ∀ q ∈ files.map (·.1), (p != q) = true := by
      intro q hq
      obtain ⟨f, hf', rfl⟩ := List.mem_map.mp hq
      exact List.lookup_eq_none_iff.mp hs f hf'
    have hnone : ∀ {l : List (String × String)}, l.map (·.1) ⊆ files.map (·.1) → l.lookup p = none :=
      fun hsub => List.lookup_eq_none_iff.mpr fun f hf' =>
        hkeys f.1 (hsub (List.mem_map_of_mem hf'))
    rw [hnone (by rw [applyEdits_paths hh]; intro q hq; simp only [List.mem_map, List.mem_filter] at hq ⊢
                  obtain ⟨f, ⟨hf', _⟩, rfl⟩ := hq; exact ⟨f, hf', rfl⟩),
      hnone (by rw [applyEdits_paths hf]; exact List.Subset.refl _)]
  | some s =>
    have h1 : (files.filter fun f => outsideProofs f.1).lookup p = some s := by
      rw [lookup_filter_key, outsideProofs_of_impl hp, hs]; rfl
    rw [applyEdits_lookup_eq hh h1, applyEdits_lookup_eq hf hs, Mutant.implEdits]
    exact editsOn_filter fun e _ he => he ▸ hp

/-! ## The solution modules -/

/-- The case's `Refute.lean` is written as this module. -/
def caseModule : String := "Mitos.Proofs.RefuteCase"

/-- The refutation's solution module: the case's module, and the proof of `Mitos.Refute.holes`.
It imports nothing else: the binding to the mutant is the comparison by value, not an import. -/
def refutationSolution (defs : List String) : String :=
  s!"{importLine caseModule}\n" ++
    if defs.isEmpty then "" else s!"\ntheorem {holesName} : {holesStatement defs} := rfl\n"

/-- The hole run's solution module: it imports every implementation module of the core, and nothing
else. -/
def holesSolution (paths : List String) : String :=
  String.join ((implModules paths).map fun m => importLine m ++ "\n")

#guard holesSolution ["Challenge/Resolver.lean", "Mitos/Core/Graph.lean",
    "Mitos/Impl/Impact.lean", "Mitos/Impl/README.md", "Mitos/Impl/Resolve.lean",
    "Mitos/Proofs/Resolver.lean", "comparator.json"] =
  "import Mitos.Impl.Impact\nimport Mitos.Impl.Resolve\n"
#guard refutationSolution ["Mitos.Impl.resolve", "Mitos.Impl.impact"] =
  "import Mitos.Proofs.RefuteCase\n\ntheorem Mitos.Refute.holes : (Mitos.Impl.resolve, Mitos.Impl.impact) = (Mitos.Impl.resolve, Mitos.Impl.impact) := rfl\n"

#guard (readChallenge "import Mitos.Core\n\n/-!\n# Doc\ntheorem below, said in prose\n-/\n\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t_1 : Mitos.Spec.P Mitos.Impl.f := sorry\ntheorem Mitos.Proofs.u : ∀ x, x = x := sorry\n").toOption ==
  some [.imp "import Mitos.Core", .keep "", .keep "/-!", .keep "# Doc",
    .keep "theorem below, said in prose", .keep "-/", .keep "", .hole "def Mitos.Impl.f : Nat := sorry",
    .thm "t_1" "Mitos.Spec.P Mitos.Impl.f" "theorem Mitos.Proofs.t_1 : Mitos.Spec.P Mitos.Impl.f := sorry",
    .thm "u" "∀ x, x = x" "theorem Mitos.Proofs.u : ∀ x, x = x := sorry", .keep ""]
-- The refutation drops the hole, imports the implementation and states the holes.
#guard ((readChallenge "import Mitos.Core\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t : P := sorry\ntheorem Mitos.Proofs.u : Q := sorry").toOption.bind
    fun ls => (refutation ["Mitos.Impl.F"] ["Mitos.Impl.f"] ls ["u"]).toOption) ==
  some ["import Mitos.Impl.F", "import Mitos.Core", "theorem Mitos.Refute.u : ¬ (Q) := sorry",
    "theorem Mitos.Refute.holes : (Mitos.Impl.f) = (Mitos.Impl.f) := sorry"]
#guard ((readChallenge "import Mitos.Core\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t : P := sorry").toOption.map
    (approvedByValue ["Mitos.Impl.F"])) ==
  some ["import Mitos.Impl.F", "import Mitos.Core", "theorem Mitos.Proofs.t : P := sorry"]
-- A line that could change what a statement means is refused, and so is an unknown theorem.
#guard (readChallenge "import Mitos.Core\nopen Mitos\ntheorem Mitos.Proofs.t : P := sorry").toOption == none
#guard (readChallenge "theorem Mitos.Proofs.t : P :=\n  sorry").toOption == none
#guard ((readChallenge "theorem Mitos.Proofs.t : P := sorry").toOption.bind
    fun ls => (refutation [] [] ls ["v"]).toOption) == none

end Mutants
