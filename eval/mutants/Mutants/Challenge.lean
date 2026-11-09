import Mutants.Manifest

/-!
# The refutation Challenge

A mutant is caught when the comparator accepts a proof that a Challenge theorem is **false** for
it. The statement to refute is taken from the approved Challenge (`core/Challenge/Resolver.lean`),
never written by hand: each named theorem

```
theorem Mitos.Proofs.<name> : <statement> := sorry
```

becomes `theorem Mitos.Refute.<name> : ¬ (<statement>) := sorry`, in a copy of the Challenge that
keeps every other line and drops the theorems not named. The comparator then compares the case's
`Refute.lean` with this Challenge as kernel terms, so a refutation of anything but the approved
statement is rejected.

The reader fails closed: every line of the Challenge must be blank, a comment, an `import`, a
one-line definition hole (`def … := sorry`) or a one-line theorem in the form above, so no line
that could change what a statement means (`open`, `namespace`, notation) is dropped or moved.
-/

namespace Mutants

/-- One line of the Challenge. -/
inductive Line where
  /-- Kept as it is: blank, a comment, an `import`, or a definition hole. -/
  | keep (text : String)
  /-- `theorem Mitos.Proofs.<name> : <stmt> := sorry` -/
  | thm (name stmt : String)
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
  else if cs.all (· == ' ') || "--".toList.isPrefixOf cs || "import ".toList.isPrefixOf cs then
    .ok (.keep l, false)
  else if "def ".toList.isPrefixOf cs && sorrySuffix.isSuffixOf cs then .ok (.keep l, false)
  else match theoremHole cs with
    | some (n, s) => .ok (.thm n s, false)
    | none => .error s!"the Challenge has a line the refutation reader does not handle: {l}"

def readLines (inDoc : Bool) : List String → Except String (List Line)
  | [] => if inDoc then .error "the Challenge ends inside a block comment" else .ok []
  | l :: ls => do
    let (x, inDoc') ← readLine inDoc l
    return x :: (← readLines inDoc' ls)

def readChallenge (src : String) : Except String (List Line) :=
  readLines false (src.splitOn "\n")

def Line.isThm (name : String) : Line → Bool
  | .thm n _ => n == name
  | .keep _ => false

def negated (name stmt : String) : String :=
  s!"theorem Mitos.Refute.{name} : ¬ ({stmt}) := sorry"

/-- A line of the refutation Challenge: kept lines as they are, the named theorems negated, the
other theorems dropped. -/
def render (names : List String) : Line → Option String
  | .keep t => some t
  | .thm n s => if names.contains n then some (negated n s) else none

/-- The lines of the refutation Challenge for `names`. Every name must be a theorem the Challenge
states exactly once. -/
def refutation (ls : List Line) (names : List String) : Except String (List String) :=
  match names.find? (fun b => (ls.filter (·.isThm b)).length != 1) with
  | some b => .error s!"breaks= names {b}, which the Challenge states {(ls.filter (·.isThm b)).length} times"
  | none => .ok (ls.filterMap (render names))

/-- Every name a refutation is built for is a theorem the Challenge states exactly once. -/
theorem refutation_once {ls : List Line} {names : List String} {out : List String}
    (h : refutation ls names = .ok out) : ∀ b ∈ names, (ls.filter (·.isThm b)).length = 1 := by
  unfold refutation at h
  split at h
  · simp at h
  · rename_i hnone
    intro b hb
    have := List.find?_eq_none.mp hnone b hb
    simpa using this

/-- **The refutation Challenge states only approved text.** Each of its lines is a line the
Challenge keeps, or the negation of the statement of a named Challenge theorem; and each named
theorem's negation is there. -/
theorem mem_refutation {ls : List Line} {names : List String} {out : List String}
    (h : refutation ls names = .ok out) (x : String) :
    x ∈ out ↔ (Line.keep x ∈ ls ∨ ∃ n ∈ names, ∃ s, Line.thm n s ∈ ls ∧ x = negated n s) := by
  unfold refutation at h
  split at h
  · simp at h
  · simp only [Except.ok.injEq] at h
    subst h
    simp only [List.mem_filterMap]
    constructor
    · rintro ⟨l, hl, hr⟩
      cases l with
      | keep t =>
        simp only [render, Option.some.injEq] at hr
        exact .inl (hr ▸ hl)
      | thm n s =>
        simp only [render] at hr
        split at hr
        · rename_i hn
          simp only [Option.some.injEq] at hr
          exact .inr ⟨n, by simpa using hn, s, hl, hr.symm⟩
        · simp at hr
    · rintro (hk | ⟨n, hn, s, hl, rfl⟩)
      · exact ⟨_, hk, rfl⟩
      · exact ⟨_, hl, by simp [render, hn]⟩

/-! ## The refutation's solution module

The case's `Refute.lean` is written as `Mitos.Proofs.RefuteCase`, and the solution module the
comparator judges, `Mitos.Proofs.Refute`, is generated: it imports every module under
`Mitos/Impl/` of the mutated core, then the case's file. The comparator compares the definition
holes (`Mitos.Impl.resolve`, `Mitos.Impl.impact`) by type only, so these imports are what bind
them to the mutated core: a case file that declared a hole itself would clash with the imported
declaration, and the solution would not build. -/

/-- The module of a `.lean` path: `Mitos/Impl/Resolve.lean` is `Mitos.Impl.Resolve`. -/
def moduleOf (path : String) : String :=
  ".".intercalate ((String.ofList (path.toList.take (path.length - 5))).splitOn "/")

/-- The case's own module, imported last. -/
def caseModule : String := "Mitos.Proofs.RefuteCase"

/-- The modules the refutation's solution imports, given the core's paths. -/
def solutionImports (paths : List String) : List String :=
  (paths.filter (inArea "Impl")).map moduleOf ++ [caseModule]

/-- **The solution imports every implementation module of the core**, and the case's module, and
nothing else. -/
theorem mem_solutionImports {paths : List String} {m : String} :
    m ∈ solutionImports paths ↔ m = caseModule ∨ ∃ p ∈ paths, inArea "Impl" p = true ∧ m = moduleOf p := by
  simp only [solutionImports, List.mem_append, List.mem_map, List.mem_filter, List.mem_singleton]
  constructor
  · rintro (⟨p, ⟨hp, hi⟩, rfl⟩ | rfl)
    · exact .inr ⟨p, hp, hi, rfl⟩
    · exact .inl rfl
  · rintro (rfl | ⟨p, hp, hi, rfl⟩)
    · exact .inr rfl
    · exact .inl ⟨p, ⟨hp, hi⟩, rfl⟩

def refutationSolution (paths : List String) : String :=
  String.join ((solutionImports paths).map fun m => s!"import {m}\n")

#guard refutationSolution ["Challenge/Resolver.lean", "Mitos/Core/Graph.lean",
    "Mitos/Impl/Impact.lean", "Mitos/Impl/README.md", "Mitos/Impl/Resolve.lean",
    "Mitos/Proofs/Resolver.lean", "comparator.json"] =
  "import Mitos.Impl.Impact\nimport Mitos.Impl.Resolve\nimport Mitos.Proofs.RefuteCase\n"

#guard (readChallenge "import Mitos.Core\n\n/-!\n# Doc\ntheorem below, said in prose\n-/\n\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t_1 : Mitos.Spec.P Mitos.Impl.f := sorry\ntheorem Mitos.Proofs.u : ∀ x, x = x := sorry\n").toOption ==
  some [.keep "import Mitos.Core", .keep "", .keep "/-!", .keep "# Doc",
    .keep "theorem below, said in prose", .keep "-/", .keep "", .keep "def Mitos.Impl.f : Nat := sorry",
    .thm "t_1" "Mitos.Spec.P Mitos.Impl.f", .thm "u" "∀ x, x = x", .keep ""]
#guard ((readChallenge "import Mitos.Core\ntheorem Mitos.Proofs.t : P := sorry\ntheorem Mitos.Proofs.u : Q := sorry").toOption.bind
    fun ls => (refutation ls ["u"]).toOption) ==
  some ["import Mitos.Core", "theorem Mitos.Refute.u : ¬ (Q) := sorry"]
-- A line that could change what a statement means is refused, and so is an unknown theorem.
#guard (readChallenge "import Mitos.Core\nopen Mitos\ntheorem Mitos.Proofs.t : P := sorry").toOption == none
#guard (readChallenge "theorem Mitos.Proofs.t : P :=\n  sorry").toOption == none
#guard ((readChallenge "theorem Mitos.Proofs.t : P := sorry").toOption.bind
    fun ls => (refutation ls ["v"]).toOption) == none

end Mutants
