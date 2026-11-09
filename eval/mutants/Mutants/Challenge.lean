import Mutants.Manifest

/-!
# The Challenges and solution modules the runner generates

A mutant is caught when the comparator accepts a proof that a Challenge theorem is **false** for
it. The statement to refute is taken from the approved Challenge (`core/Challenge/Resolver.lean`),
never written by hand: each named theorem

```
theorem Mitos.Proofs.<name> : <statement> := sorry
```

becomes `theorem _root_.Mitos.Refute.<name> : ¬ (<statement, qualified>) := sorry`, in a copy of the
Challenge that keeps every other line and drops the theorems not named. The comparator then compares
the case's `Refute.lean` with this Challenge as kernel terms, so a refutation of anything but what
that line states is rejected.

## Every name in a generated statement is absolute

The generated Challenges import the mutated implementation (below), so a name in a statement must
not resolve to a declaration the implementation makes. Lean elaborates `theorem Mitos.Refute.t : T`
inside namespace `Mitos.Refute`, where `Mitos.Spec.X` in `T` resolves first to
`Mitos.Refute.Mitos.Spec.X`, then to `Mitos.Mitos.Spec.X`, and only then to `Mitos.Spec.X`; an
implementation edit that declared `Mitos.Refute.Mitos.Spec.AssumptionsExact := False` made the
refutation Challenge state `¬ False` (review on #86, round 3). So the runner writes each generated
statement in the root namespace and with absolute names:

- **No namespace.** Every theorem the runner generates is declared as `_root_.Mitos.Refute.<t>` (or
  `_root_.Mitos.Proofs.<t>`, `_root_.Mitos.Refute.holes`). Lean opens no namespace for a
  declaration named with `_root_.`, and the generated files have no `namespace` or `open`, so the
  statement is elaborated in the root namespace. There a name with a `.` is looked up exactly
  (`Lean.ResolveName.resolveGlobalName`: with no namespace around there are no surrounding
  namespaces to try first, and nothing is open), so this alone keeps a shadow out.
- **Absolute names.** `qualify` writes every name of the statement as `_root_.<name>`, which at the
  root Lean also looks up exactly, after dropping `_root_.`, and which says so in the text.
  `_root_.` alone would not be enough: inside namespace `Mitos.Refute`, Lean tries
  `Mitos.Refute._root_.Mitos.Spec.X` before `Mitos.Spec.X`. `Mutants.Resolution` checks these
  facts about Lean whenever this package builds.

`qualify` accepts only a statement that is a list of names under `Mitos`, separated by single
spaces, as every approved statement is (`Mitos.Spec.Sound Mitos.Impl.resolve`); anything else, such
as a binder or a parenthesis, is refused, so the runner stops instead of qualifying a statement it
does not understand (`qualify_eq_some`). The definition hole names in `Mitos.Refute.holes` are
written the same way. These two are what keep a shadow from changing a statement, whatever names a
case declares. The lint (`Mutants.Lint`) also checks the names of a case's top-level declarations,
as defence in depth; it does not read nested names (`let rec`, `where`), and it bans
`with_decl_name%`, which declares nested names under any namespace.

The Challenge imports the mutated implementation, so what the line states is the approved
statement also only because the implementation declares no syntax: a macro there would rewrite
the line (review on #86, round 2). The lint ensures that before anything is built.

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

It reads block comments as Lean does, or refuses the line. Lean ends a block comment at its first
closer and nests a comment opened inside one, so the line `/- note -/ open Foo` runs `open Foo`,
and a theorem line between an inner and an outer closer is no theorem. A reader that took a comment
to end only with its line kept such lines as comment lines, so a hole line stayed (compared by type
only) and a theorem line stayed un-negated, or it negated a statement the Challenge does not make
(review on #86, round 6). So inside a comment the reader takes a line only if it holds no opener,
and no closer but in its last two characters; a line that opens a comment, only if the same holds
after the opener; and any other line, only if it is a line comment or holds neither, nor a string
literal or an escaped name (`«…»`), which Lean also reads on past a line's end.
`readLine_comments` proves that on every line it takes, Lean's scan of the comment (`leanScan`, a
transcription of `Lean.Parser.finishCommentBlock`) ends where the reader goes on: still in the
comment, or closed at the end of the line. The probes after it check that transcription's premises
whenever this package builds.
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

/-! ## Block comments

The words opener and closer below mean the two characters that open and close a block comment. -/

/-- Whether `a` is directly followed by `b` somewhere in `cs`. -/
def hasPair (a b : Char) : List Char → Bool
  | x :: y :: cs => (x == a && y == b) || hasPair a b (y :: cs)
  | _ => false

/-- Whether `cs` ends with `a` and then `b`. -/
def endsPair (a b : Char) : List Char → Bool
  | [x, y] => x == a && y == b
  | _ :: y :: z :: cs => endsPair a b (y :: z :: cs)
  | _ => false

/-- Lean's scan of a block comment over one line, as `Lean.Parser.finishCommentBlock` does it, at
nesting depth `n`: a closer ends one level, an opener starts another, and anything else is skipped
one character at a time. The result is the depth where the scan stops and the text after that: at
depth 0 the comment has ended, and Lean reads the rest of the line as code. A line break is neither
character, so a line can be scanned on its own. -/
def leanScan : Nat → List Char → Nat × List Char
  | 0, cs => (0, cs)
  | n + 1, c :: d :: cs =>
    if c = '-' ∧ d = '/' then leanScan n cs
    else if c = '/' ∧ d = '-' then leanScan (n + 2) cs
    else leanScan (n + 1) (d :: cs)
  | n + 1, _ => (n + 1, [])

/-- How a line inside a block comment leaves it, if the reader takes the line: `some true` when the
comment is still open after it, `some false` when the line's last two characters close it. A line
with an opener anywhere, or a closer before its last two characters, is refused (`none`). -/
def commentLine (cs : List Char) : Option Bool :=
  if hasPair '/' '-' cs || hasPair '-' '/' cs.dropLast then none
  else some !(endsPair '-' '/' cs)

/-- How a line that starts with an opener leaves the comment it opens, if the reader takes the
line: as `commentLine` reads the text after the opener, except that a closer right after the opener
is refused, since Lean does not read one there (it skips the character after the opener). -/
def openerLine (cs : List Char) : Option Bool :=
  match cs with
  | '/' :: '-' :: rest => if rest = ['-', '/'] then none else commentLine rest
  | _ => none

theorem hasPair_cons {a b c : Char} {cs : List Char} (h : hasPair a b (c :: cs) = false) :
    hasPair a b cs = false := by
  cases cs with
  | nil => rfl
  | cons d cs => simp only [hasPair, Bool.or_eq_false_iff] at h; exact h.2

theorem hasPair_dropLast_cons {a b c : Char} {cs : List Char}
    (h : hasPair a b (c :: cs).dropLast = false) : hasPair a b cs.dropLast = false := by
  cases cs with
  | nil => rfl
  | cons d cs => rw [List.dropLast_cons_cons] at h; exact hasPair_cons h

/-- On a line with no opener, and no closer but in its last two characters, Lean's scan at depth 1
ends the comment exactly at the end of the line if the line ends with a closer, and otherwise
reaches the end of the line still at depth 1. -/
theorem scan_plain : ∀ {cs : List Char}, hasPair '/' '-' cs = false →
    hasPair '-' '/' cs.dropLast = false →
    leanScan 1 cs = if endsPair '-' '/' cs then (0, []) else (1, [])
  | [], _, _ => by simp [leanScan, endsPair]
  | [c], _, _ => by simp [leanScan, endsPair]
  | c :: d :: cs, h1, h2 => by
    by_cases hc : c = '-' ∧ d = '/'
    · obtain ⟨rfl, rfl⟩ := hc
      cases cs with
      | nil => simp [leanScan, endsPair]
      | cons e cs => simp [hasPair] at h2
    · by_cases hc' : c = '/' ∧ d = '-'
      · obtain ⟨rfl, rfl⟩ := hc'
        simp [hasPair] at h1
      · rw [leanScan, ite_eq_right hc, ite_eq_right hc',
          scan_plain (hasPair_cons h1) (hasPair_dropLast_cons h2)]
        cases cs with
        | nil =>
          have : endsPair '-' '/' [c, d] = false := by
            simp only [endsPair, Bool.and_eq_false_iff, beq_eq_false_iff_ne]
            exact Classical.not_and_iff_not_or_not.mp hc
          rw [this]; simp [endsPair]
        | cons e cs => rfl

/-- **A comment line the reader takes ends where Lean's scan ends**: still in the comment at depth
1 (nothing nested) when the reader stays in it, or closed exactly at the end of the line, with no
text after the closer, when the reader leaves it. -/
theorem commentLine_scan {cs : List Char} {b : Bool} (h : commentLine cs = some b) :
    leanScan 1 cs = if b then (1, []) else (0, []) := by
  unfold commentLine at h
  split at h
  · simp at h
  · rename_i hc
    simp only [Bool.or_eq_true, not_or, Bool.not_eq_true] at hc
    simp only [Option.some.injEq] at h
    subst h
    rw [scan_plain hc.1 hc.2]
    cases endsPair '-' '/' cs <;> rfl

theorem commentLine_tail {c : Char} {cs : List Char} {b : Bool}
    (h : commentLine (c :: cs) = some b) (hne : c :: cs ≠ ['-', '/']) : commentLine cs = some b := by
  unfold commentLine at h ⊢
  split at h
  · simp at h
  · rename_i hc
    simp only [Bool.or_eq_true, not_or, Bool.not_eq_true] at hc
    rw [ite_eq_right (by simp [hasPair_cons hc.1, hasPair_dropLast_cons hc.2]), ← h]
    match cs with
    | [] => rfl
    | [d] =>
      have : ¬ (c = '-' ∧ d = '/') := fun ⟨h1, h2⟩ => hne (by rw [h1, h2])
      have : endsPair '-' '/' [c, d] = false := by
        simp only [endsPair, Bool.and_eq_false_iff, beq_eq_false_iff_ne]
        exact Classical.not_and_iff_not_or_not.mp this
      rw [this]; rfl
    | d :: e :: cs => rfl

/-- **A line the reader takes as opening a comment ends where Lean's scan ends**, whether the scan
starts right after the opener or one character later, as Lean starts it. -/
theorem openerLine_scan {cs : List Char} {b : Bool} (h : openerLine cs = some b) :
    leanScan 1 (cs.drop 2) = (if b then (1, []) else (0, [])) ∧
      leanScan 1 (cs.drop 3) = (if b then (1, []) else (0, [])) := by
  unfold openerLine at h
  split at h
  · rename_i rest
    split at h
    · simp at h
    · rename_i hne
      refine ⟨commentLine_scan h, ?_⟩
      cases rest with
      | nil => simpa [commentLine, hasPair, endsPair] using commentLine_scan h
      | cons c rest => exact commentLine_scan (commentLine_tail h hne)
  · simp at h

/-- Whether a code line holds a character that starts a token Lean may read on past the line's
end: a string literal (`"`) or an escaped name (`«`). -/
def spansLines (cs : List Char) : Bool := cs.any fun c => c == '"' || c == '«'

def lexError (l : String) : String :=
  s!"the Challenge has a line whose comments, strings or escaped names the refutation reader does not follow: {l}"

/-- Reads one line; `inDoc` says whether it is inside a block comment. -/
def readLine (inDoc : Bool) (l : String) : Except String (Line × Bool) :=
  let cs := l.toList
  if inDoc then
    match commentLine cs with
    | some b => .ok (.keep l, b)
    | none => .error (lexError l)
  else if "/-".toList.isPrefixOf cs then
    match openerLine cs with
    | some b => .ok (.keep l, b)
    | none => .error (lexError l)
  else if "--".toList.isPrefixOf cs then .ok (.keep l, false)
  else if hasPair '/' '-' cs || hasPair '-' '/' cs || spansLines cs then .error (lexError l)
  else if cs.all (· == ' ') then .ok (.keep l, false)
  else if "import ".toList.isPrefixOf cs then .ok (.imp l, false)
  else if "def ".toList.isPrefixOf cs && sorrySuffix.isSuffixOf cs then .ok (.hole l, false)
  else match theoremHole cs with
    | some (n, s) => .ok (.thm n s l, false)
    | none => .error s!"the Challenge has a line the refutation reader does not handle: {l}"

/-- **The reader follows Lean's block comments.** On a line inside a comment, and on a line that
opens one, it keeps the line as it is, and Lean's scan of the comment ends where the reader goes
on: still in the comment, or closed exactly at the end of the line. Every other line it takes leaves
it outside a comment, and is a line comment or holds no opener, no closer and no character that
starts a string literal or an escaped name, which Lean may read on past the line's end. -/
theorem readLine_comments {inDoc inDoc' : Bool} {l : String} {x : Line}
    (h : readLine inDoc l = .ok (x, inDoc')) :
    (inDoc = true →
      x = .keep l ∧ leanScan 1 l.toList = if inDoc' then (1, []) else (0, [])) ∧
    (inDoc = false → "/-".toList.isPrefixOf l.toList = true →
      x = .keep l ∧ leanScan 1 (l.toList.drop 2) = (if inDoc' then (1, []) else (0, [])) ∧
        leanScan 1 (l.toList.drop 3) = if inDoc' then (1, []) else (0, [])) ∧
    (inDoc = false → "/-".toList.isPrefixOf l.toList = false →
      inDoc' = false ∧ ("--".toList.isPrefixOf l.toList = true ∨
        hasPair '/' '-' l.toList = false ∧ hasPair '-' '/' l.toList = false ∧
          spansLines l.toList = false)) := by
  unfold readLine at h
  cases inDoc with
  | true =>
    simp only [ite_true] at h
    split at h
    · rename_i b hb
      simp only [Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨fun _ => ⟨rfl, commentLine_scan hb⟩, nofun, nofun⟩
    · simp at h
  | false =>
    simp only [Bool.false_eq_true, ite_false] at h
    refine ⟨nofun, fun _ hp => ?_, fun _ hp => ?_⟩
    · rw [ite_eq_left hp] at h
      split at h
      · rename_i b hb
        simp only [Except.ok.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨rfl, openerLine_scan hb⟩
      · simp at h
    · rw [ite_eq_right (Bool.ne_true_of_eq_false hp)] at h
      by_cases hd : "--".toList.isPrefixOf l.toList = true
      · rw [ite_eq_left hd] at h
        simp only [Except.ok.injEq, Prod.mk.injEq] at h
        exact ⟨h.2.symm, .inl hd⟩
      · rw [ite_eq_right hd] at h
        by_cases hq :
            (hasPair '/' '-' l.toList || hasPair '-' '/' l.toList || spansLines l.toList) = true
        · rw [ite_eq_left hq] at h; simp at h
        · rw [ite_eq_right hq] at h
          simp only [Bool.or_eq_true, not_or, Bool.not_eq_true] at hq
          refine ⟨?_, .inr ⟨hq.1.1, hq.1.2, hq.2⟩⟩
          have ok : ∀ {y : Line}, (Except.ok (y, false) : Except String (Line × Bool)) =
              .ok (x, inDoc') → inDoc' = false := by
            intro y hy
            simp only [Except.ok.injEq, Prod.mk.injEq] at hy
            exact hy.2.symm
          split at h
          · exact ok h
          split at h
          · exact ok h
          split at h
          · exact ok h
          split at h
          · exact ok h
          · simp at h

/-! The facts about Lean's block comments that `leanScan` transcribes, checked whenever this
package builds, as `Mutants.Resolution` checks name resolution: the code after a closer on the same
line is read (`CommentProbe.afterClose`); a comment opened inside another nests, so the inner
closer does not end the outer one; and the character after an opener is skipped, also for a doc
comment's opener, so a closer that starts there does not end the comment. In the last three, the
first declaration is inside a comment, or else the second would clash with it. -/

/- a -/ def CommentProbe.afterClose : Nat := 1
/- /- -/ def CommentProbe.nested : Nat := 1 -/
def CommentProbe.nested : Nat := 2
/-/
def CommentProbe.skipped : Nat := 1
-/
def CommentProbe.skipped : Nat := 2
/--/
def CommentProbe.skippedDoc : Nat := 1
-/
def CommentProbe.skippedDoc : Nat := 2

theorem CommentProbe.probes :
    CommentProbe.afterClose = 1 ∧ CommentProbe.nested = 2 ∧ CommentProbe.skipped = 2 ∧
      CommentProbe.skippedDoc = 2 := ⟨rfl, rfl, rfl, rfl⟩

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

/-! ## Absolute names -/

/-- A component the qualifier accepts: letters, digits and `_`, not starting with a digit. -/
def qualPart (c : String) : Bool :=
  plainName c.toList && !(c.toList.head?.getD '0').isDigit

/-- A name the qualifier accepts: `Mitos` and at least one more component, each a `qualPart`. -/
def qualName (w : String) : Bool :=
  match w.splitOn "." with
  | "Mitos" :: rest => !rest.isEmpty && rest.all qualPart
  | _ => false

/-- The statement with every name made absolute, `_root_.` before each word, if it is a list of
names under `Mitos` separated by single spaces; `none` for anything else. -/
def qualify (stmt : String) : Option String :=
  if (stmt.splitOn " ").all qualName then
    some (" ".intercalate ((stmt.splitOn " ").map ("_root_." ++ ·)))
  else none

/-- **What `qualify` does**: it accepts a statement exactly when every word is a name under `Mitos`,
and then writes each word as `_root_.<word>`, in order, and nothing else. -/
theorem qualify_eq_some {s q : String} :
    qualify s = some q ↔ (∀ w ∈ s.splitOn " ", qualName w = true) ∧
      q = " ".intercalate ((s.splitOn " ").map ("_root_." ++ ·)) := by
  unfold qualify
  split
  · rename_i h
    simp only [List.all_eq_true] at h
    simp only [Option.some.injEq]
    exact ⟨fun hq => ⟨h, hq.symm⟩, fun ⟨_, hq⟩ => hq.symm⟩
  · rename_i h
    simp only [List.all_eq_true] at h
    simp only [reduceCtorEq, false_iff, not_and]
    exact fun hall => absurd hall h

/-- Every name `qualName` accepts lies under `Mitos`. -/
theorem qualName_mitos {w : String} (h : qualName w = true) :
    ∃ rest, w.splitOn "." = "Mitos" :: rest ∧ rest ≠ [] := by
  unfold qualName at h
  split at h
  · rename_i rest hs
    simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at h
    exact ⟨rest, hs, h.1⟩
  · simp at h

/-- Whether a line of the Challenge is no theorem, or a theorem whose statement `qualify` takes. -/
def Line.qualifies : Line → Bool
  | .thm _ s _ => (qualify s).isSome
  | _ => true

/-- Why the runner cannot write a Challenge's statements and hole names with absolute names, if it
cannot. -/
def unqualified (ls : List Line) (defs : List String) : Option String :=
  match ls.find? (!·.qualifies), defs.find? (!qualName ·) with
  | some (.thm n s _), _ =>
    some s!"the statement of {n}, `{s}`, is not a list of names under Mitos; the runner writes only such statements with absolute names"
  | some _, _ => some "a Challenge line is not a theorem the runner can qualify"
  | none, some d => some s!"the definition hole {d} is not a name under Mitos"
  | none, none => none

theorem unqualified_none {ls : List Line} {defs : List String} (h : unqualified ls defs = none) :
    (∀ l ∈ ls, l.qualifies = true) ∧ ∀ d ∈ defs, qualName d = true := by
  unfold unqualified at h
  split at h
  · simp at h
  · simp at h
  · simp at h
  · rename_i h1 h2
    exact ⟨fun l hl => by simpa using List.find?_eq_none.mp h1 l hl,
      fun d hd => by simpa using List.find?_eq_none.mp h2 d hd⟩

/-- The negation of a named theorem's qualified statement, declared at the root. -/
def negated (name stmt : String) : String :=
  s!"theorem _root_.Mitos.Refute.{name} : ¬ ({stmt}) := sorry"

/-- An approved theorem with its qualified statement, declared at the root. -/
def stated (name stmt : String) : String :=
  s!"theorem _root_.Mitos.Proofs.{name} : {stmt} := sorry"

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

/-- The statement that names every definition hole, each as `_root_.<hole>`:
`(_root_.h₁, _root_.h₂, …) = (_root_.h₁, _root_.h₂, …)`. -/
def holesStatement (defs : List String) : String :=
  let t := s!"({", ".intercalate (defs.map ("_root_." ++ ·))})"
  s!"{t} = {t}"

def holesName : String := "Mitos.Refute.holes"

/-- The extra line of a refutation Challenge, if the Challenge has definition holes. -/
def holesHole (defs : List String) : List String :=
  if defs.isEmpty then [] else [s!"theorem _root_.{holesName} : {holesStatement defs} := sorry"]

/-- The refutation Challenge for `names`: the holes as values, the named theorems negated with
absolute names, the others dropped, and `Mitos.Refute.holes`. Every name must be a theorem the
Challenge states exactly once, and every statement and hole name must be one `qualify` takes. -/
def refutation (impls defs : List String) (ls : List Line) (names : List String) :
    Except String (List String) :=
  match names.find? (fun b => (ls.filter (·.isThm b)).length != 1) with
  | some b => .error s!"breaks= names {b}, which the Challenge states {(ls.filter (·.isThm b)).length} times"
  | none =>
    match unqualified ls defs with
    | some e => .error e
    | none => .ok (byValue impls
        (fun n s _ => if names.contains n then (qualify s).map (negated n) else none) ls (holesHole defs))

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

/-- A refutation is built only when every statement of the Challenge and every hole name can be
written with absolute names. -/
theorem refutation_qualifies {impls defs : List String} {ls : List Line} {names : List String}
    {out : List String} (h : refutation impls defs ls names = .ok out) :
    (∀ l ∈ ls, l.qualifies = true) ∧ ∀ d ∈ defs, qualName d = true := by
  unfold refutation at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i hq
      exact unqualified_none hq

/-- **The refutation Challenge states only approved text, with the holes as values and absolute
names.** Each of its lines is an import of an implementation module, an import or comment line of
the Challenge, the negation of the qualified statement of a named Challenge theorem, or the
`Mitos.Refute.holes` line. -/
theorem mem_refutation {impls defs : List String} {ls : List Line} {names : List String}
    {out : List String} (h : refutation impls defs ls names = .ok out) (x : String) :
    x ∈ out ↔ ((∃ m ∈ impls, x = importLine m) ∨ Line.imp x ∈ ls ∨ Line.keep x ∈ ls ∨
      (∃ n ∈ names, ∃ s t q, Line.thm n s t ∈ ls ∧ qualify s = some q ∧ x = negated n q) ∨
      x ∈ holesHole defs) := by
  unfold refutation at h
  split at h
  · simp at h
  · split at h
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
            obtain ⟨q, hq, hx⟩ := Option.map_eq_some_iff.mp hr
            exact .inr (.inr (.inr (.inl ⟨n, by simpa using hn, s, t, q, hl, hq, hx.symm⟩)))
          · simp at hr
        · exact .inr (.inr (.inr (.inr h)))
      · rintro (h | h | h | ⟨n, hn, s, t, q, hl, hq, rfl⟩ | h)
        · exact .inl h
        · exact .inr (.inl h)
        · exact .inr (.inr (.inl h))
        · refine .inr (.inr (.inr (.inl ⟨n, s, t, hl, ?_⟩)))
          simp [hn, hq]
        · exact .inr (.inr (.inr (.inr h)))

/-- **Each named theorem is refuted as approved**: the refutation Challenge holds the negation of
its statement, qualified, and the Challenge states it exactly once. -/
theorem refutation_states {impls defs : List String} {ls : List Line} {names : List String}
    {out : List String} (h : refutation impls defs ls names = .ok out) :
    ∀ n ∈ names, ∃ s t q, Line.thm n s t ∈ ls ∧ qualify s = some q ∧ negated n q ∈ out := by
  intro n hn
  have h1 := refutation_once h n hn
  obtain ⟨l, hl⟩ : ∃ l, l ∈ ls.filter (·.isThm n) := by
    cases hf : ls.filter (·.isThm n) with
    | nil => rw [hf] at h1; simp at h1
    | cons l _ => exact ⟨l, by simp⟩
  simp only [List.mem_filter] at hl
  obtain ⟨hl, hthm⟩ := hl
  cases l with
  | thm n' s t =>
    simp only [Line.isThm, beq_iff_eq] at hthm
    subst hthm
    have hq := (refutation_qualifies h).1 _ hl
    simp only [Line.qualifies, Option.isSome_iff_exists] at hq
    obtain ⟨q, hq⟩ := hq
    exact ⟨s, t, q, hl, hq,
      (mem_refutation h _).mpr (.inr (.inr (.inr (.inl ⟨n', hn, s, t, q, hl, hq, rfl⟩))))⟩
  | _ => simp [Line.isThm] at hthm

/-- The approved Challenge with the holes as values: every theorem line with its statement
qualified, declared at the root. -/
def approvedByValue (impls : List String) (ls : List Line) : Except String (List String) :=
  match unqualified ls [] with
  | some e => .error e
  | none => .ok (byValue impls (fun n s _ => (qualify s).map (stated n)) ls [])

/-- **The approved Challenge by value states the approved theorems with absolute names.** Each of
its lines is an import of an implementation module, a line of the approved Challenge that is no
hole and no theorem, or an approved theorem with its statement qualified. -/
theorem mem_approvedByValue {impls : List String} {ls : List Line} {out : List String}
    (h : approvedByValue impls ls = .ok out) {x : String} :
    x ∈ out ↔
      (∃ m ∈ impls, x = importLine m) ∨ Line.imp x ∈ ls ∨ Line.keep x ∈ ls ∨
        ∃ n s t q, Line.thm n s t ∈ ls ∧ qualify s = some q ∧ x = stated n q := by
  unfold approvedByValue at h
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
      · obtain ⟨q, hq, hx⟩ := Option.map_eq_some_iff.mp hr
        exact .inr (.inr (.inr ⟨n, s, t, q, hl, hq, hx.symm⟩))
      · simp at h
    · rintro (h | h | h | ⟨n, s, t, q, hl, hq, rfl⟩)
      · exact .inl h
      · exact .inr (.inl h)
      · exact .inr (.inr (.inl h))
      · exact .inr (.inr (.inr (.inl ⟨n, s, t, hl, by simp [hq]⟩)))

/-- **Every theorem of the approved Challenge is in the approved Challenge by value**, qualified. -/
theorem approvedByValue_states {impls : List String} {ls : List Line} {out : List String}
    (h : approvedByValue impls ls = .ok out) {n s t : String} (hl : Line.thm n s t ∈ ls) :
    ∃ q, qualify s = some q ∧ stated n q ∈ out := by
  have hu : unqualified ls [] = none := by
    unfold approvedByValue at h
    split at h
    · simp at h
    · assumption
  have hq := (unqualified_none hu).1 _ hl
  simp only [Line.qualifies, Option.isSome_iff_exists] at hq
  obtain ⟨q, hq⟩ := hq
  exact ⟨q, hq, (mem_approvedByValue h).mpr (.inr (.inr (.inr ⟨n, s, t, q, hl, hq, rfl⟩)))⟩

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

/-- The refutation's solution module: the case's module, and the proof of `Mitos.Refute.holes`,
stated as the Challenge states it, at the root and with absolute names. It imports nothing else:
the binding to the mutant is the comparison by value, not an import. -/
def refutationSolution (defs : List String) : String :=
  s!"{importLine caseModule}\n" ++
    if defs.isEmpty then "" else s!"\ntheorem _root_.{holesName} : {holesStatement defs} := _root_.rfl\n"

/-- The hole run's solution module: it imports every implementation module of the core, and nothing
else. -/
def holesSolution (paths : List String) : String :=
  String.join ((implModules paths).map fun m => importLine m ++ "\n")

#guard holesSolution ["Challenge/Resolver.lean", "Mitos/Core/Graph.lean",
    "Mitos/Impl/Impact.lean", "Mitos/Impl/README.md", "Mitos/Impl/Resolve.lean",
    "Mitos/Proofs/Resolver.lean", "comparator.json"] =
  "import Mitos.Impl.Impact\nimport Mitos.Impl.Resolve\n"
#guard refutationSolution ["Mitos.Impl.resolve", "Mitos.Impl.impact"] =
  "import Mitos.Proofs.RefuteCase\n\ntheorem _root_.Mitos.Refute.holes : (_root_.Mitos.Impl.resolve, _root_.Mitos.Impl.impact) = (_root_.Mitos.Impl.resolve, _root_.Mitos.Impl.impact) := _root_.rfl\n"

-- Every approved statement is qualified word by word; anything else is refused.
#guard qualify "Mitos.Spec.Sound Mitos.Impl.resolve" =
  some "_root_.Mitos.Spec.Sound _root_.Mitos.Impl.resolve"
#guard qualify "Mitos.Spec.ImpactCorrect Mitos.Impl.impact" =
  some "_root_.Mitos.Spec.ImpactCorrect _root_.Mitos.Impl.impact"
#guard qualify "Spec.Sound Mitos.Impl.resolve" = none
#guard qualify "Mitos.Spec.Sound (Mitos.Impl.resolve)" = none
#guard qualify "Mitos.Spec.Sound  Mitos.Impl.resolve" = none
#guard qualify "∀ x, x = x" = none
#guard qualify "Mitos" = none
#guard qualify "_root_.Mitos.Spec.Sound" = none
#guard qualify "Mitos.Spec.1 Mitos.Impl.resolve" = none
#guard qualify "" = none

#guard (readChallenge "import Mitos.Core\n\n/-!\n# Doc\ntheorem below, said in prose\n-/\n\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t_1 : Mitos.Spec.P Mitos.Impl.f := sorry\ntheorem Mitos.Proofs.u : ∀ x, x = x := sorry\n").toOption ==
  some [.imp "import Mitos.Core", .keep "", .keep "/-!", .keep "# Doc",
    .keep "theorem below, said in prose", .keep "-/", .keep "", .hole "def Mitos.Impl.f : Nat := sorry",
    .thm "t_1" "Mitos.Spec.P Mitos.Impl.f" "theorem Mitos.Proofs.t_1 : Mitos.Spec.P Mitos.Impl.f := sorry",
    .thm "u" "∀ x, x = x" "theorem Mitos.Proofs.u : ∀ x, x = x := sorry", .keep ""]
-- The refutation drops the hole, imports the implementation and states the holes, each statement
-- at the root with absolute names.
#guard ((readChallenge "import Mitos.Core\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry\ntheorem Mitos.Proofs.u : Mitos.Spec.Q Mitos.Impl.f := sorry").toOption.bind
    fun ls => (refutation ["Mitos.Impl.F"] ["Mitos.Impl.f"] ls ["u"]).toOption) ==
  some ["import Mitos.Impl.F", "import Mitos.Core",
    "theorem _root_.Mitos.Refute.u : ¬ (_root_.Mitos.Spec.Q _root_.Mitos.Impl.f) := sorry",
    "theorem _root_.Mitos.Refute.holes : (_root_.Mitos.Impl.f) = (_root_.Mitos.Impl.f) := sorry"]
#guard ((readChallenge "import Mitos.Core\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry").toOption.bind
    fun ls => (approvedByValue ["Mitos.Impl.F"] ls).toOption) ==
  some ["import Mitos.Impl.F", "import Mitos.Core",
    "theorem _root_.Mitos.Proofs.t : _root_.Mitos.Spec.P _root_.Mitos.Impl.f := sorry"]
-- A line that could change what a statement means is refused, and so is an unknown theorem, a
-- statement the qualifier does not take (also one the refutation does not name) and a hole name
-- outside `Mitos`.
#guard (readChallenge "import Mitos.Core\nopen Mitos\ntheorem Mitos.Proofs.t : P := sorry").toOption == none
#guard (readChallenge "theorem Mitos.Proofs.t : P :=\n  sorry").toOption == none
#guard ((readChallenge "theorem Mitos.Proofs.t : Mitos.P := sorry").toOption.bind
    fun ls => (refutation [] [] ls ["v"]).toOption) == none
#guard ((readChallenge "theorem Mitos.Proofs.t : Mitos.P := sorry\ntheorem Mitos.Proofs.u : ∀ x, x = x := sorry").toOption.bind
    fun ls => (refutation [] [] ls ["t"]).toOption) == none
#guard ((readChallenge "theorem Mitos.Proofs.t : Mitos.P := sorry").toOption.bind
    fun ls => (refutation [] ["f"] ls ["t"]).toOption) == none
#guard ((readChallenge "theorem Mitos.Proofs.t : P := sorry").toOption.bind
    fun ls => (approvedByValue [] ls).toOption) == none
-- A line whose block comments the reader could read otherwise than Lean is refused (review on #86,
-- round 6): a comment that ends before its line, so the reader would keep the hole and the theorem
-- below it; text after the closer inside a comment; a nested comment, so the theorem is in a
-- comment; an opener in a code line; a closer right after the opener, which Lean skips; a closer
-- before a carriage return; and a string literal and an escaped name in a hole line, which Lean
-- reads on over the theorem line below them.
#guard (readChallenge "/- a -/ open Foo\ndef Mitos.Impl.f : Nat := sorry\n-- -/").toOption == none
#guard (readChallenge "import Mitos.Core\n/- note -/ open Foo\ndef Mitos.Impl.f : Nat := sorry\ntheorem Mitos.Proofs.u : Mitos.Spec.Q Mitos.Impl.f := sorry\n-- end -/\ntheorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry").toOption == none
#guard (readChallenge "import Mitos.Core\n/- doc\ntext -/ def Mitos.Impl.f : Nat := sorry\n-- -/\ntheorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry").toOption == none
#guard (readChallenge "import Mitos.Core\ndef Mitos.Impl.f : Nat := sorry\n/- outer\n/- inner -/\ntheorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry\n/- -/ -/").toOption == none
#guard (readChallenge "import Mitos.Core\ndef Mitos.Impl.f /- : Nat := sorry\ntheorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry\n-- -/ : Nat := sorry").toOption == none
#guard (readChallenge "/--/\ntheorem Mitos.Proofs.t : Mitos.P := sorry\n-- -/\ndef Mitos.Impl.f : Nat := sorry").toOption == none
#guard (readChallenge "/-\r\n-/\r\ntheorem Mitos.Proofs.t : Mitos.P := sorry\n-- -/").toOption == none
#guard (readChallenge "import Mitos.Core\ndef Mitos.Impl.f : F \"x := sorry\ntheorem Mitos.Proofs.t : Mitos.P := sorry\n-- \" := 0").toOption == none
#guard (readChallenge "import Mitos.Core\ndef «Mitos.Impl.f := sorry\ntheorem Mitos.Proofs.t : Mitos.P := sorry\n-- » : Nat := 0").toOption == none
-- Lines Lean reads unambiguously are read as Lean reads them: a comment on one line, a closer at
-- the end of a line comment inside a comment, and an opener whose next character Lean skips.
#guard (readChallenge "/-- doc -/\ntheorem Mitos.Proofs.t : Mitos.P := sorry").toOption ==
  some [.keep "/-- doc -/", .thm "t" "Mitos.P" "theorem Mitos.Proofs.t : Mitos.P := sorry"]
#guard (readChallenge "/-\n-- -/\ntheorem Mitos.Proofs.t : Mitos.P := sorry").toOption ==
  some [.keep "/-", .keep "-- -/", .thm "t" "Mitos.P" "theorem Mitos.Proofs.t : Mitos.P := sorry"]
#guard (readChallenge "/-/\ntheorem Mitos.Proofs.t : Mitos.P := sorry\n-/").toOption ==
  some [.keep "/-/", .keep "theorem Mitos.Proofs.t : Mitos.P := sorry", .keep "-/"]

end Mutants
