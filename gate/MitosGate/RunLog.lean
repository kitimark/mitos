import Lean.Data.Json
import MitosGate.Util

/-!
# The run-log check (`mitos-gate runlog`)

Each attempt's record is its own file, `ops/runs/<YYYY-MM-DD>/<task>-<role>-<attempt>.json`,
holding the record on one line (#91, B7). A PR only adds such files, and a file on the base branch
never changes, so a rebase replays additions only: no line of a shared file is context for a PR's
change, `git patch-id --verbatim` stays the same over a rebase, and no merge driver is needed.
Two PRs that add a record for one attempt on one day write one path, which git merges as one file
or stops on as a conflict.

* `recordFile`: a record file holds one line (`singleLine?_spec`), that line is a record, its task
  and role are safe characters (`safeTask`, `safeRole`), and the file is named by its key
  (`fileName`). `recordFile_ok` states this; `fileName_safe` shows such a name is one plain path
  entry; `day_keys_nodup` shows a day folder then holds each key at most once.
* `problems`: the whole check on a merge-base tree and a head tree, read into a `Tree`.
  `problems_eq_nil` states what a pass means: each base day file's lines equal the head file of
  the same name, every merge-base record is kept (`records_kept`), no two head records share a
  key, every head record file passes `recordFile` in a folder named by a date, and the head has
  no day file the base lacks.

The day files from before one record per attempt, `ops/runs/<YYYY-MM-DD>.ndjson`, are frozen
(`ops/runs/README.md`). Each one on the head must equal the one on the base, line for line and in
order. The four files from 2026-11-06 to 2026-11-09 stay on `main`, and `readTree` still reads
them. A PR may not add a day file, and may not append, edit, delete or reorder a line.

The `appendOnly` and union theorems stay as the record of why those files were safe to freeze.
While git's `union` driver merged them, a change was right only when no branch edited or deleted
a line it did not add: union turns an edited line into two records for one attempt and reports no
conflict. The check does not use them.

* `appendOnly base head`: every line of the merge-base file is still in the head file, at least as
  often; order is ignored (`appendOnly_iff_count`, `appendOnly_iff_subperm`). Equivalently, the
  head is the base plus some lines (`appendOnly_iff_perm_append`). An edit or a deletion on the PR
  fails it (`appendOnly_eq_false_of_count_lt`, `appendOnly_edit`, `appendOnly_delete`).
* `noDupKeys rs`: no two records share `(task, role, attempt)` (`noDupKeys_iff`).
* Union of two sides that only append keeps every base line (`union_appendOnly`), and passes
  `noDupKeys` exactly when all the lines' keys are distinct (`union_noDupKeys_iff`). The model of
  union is an assumption about git, stated at `union_appendOnly`.
* An edit that union kept next to the line it replaced fails `noDupKeys`
  (`noDupKeys_eq_false_of_mem`, `edit_then_union`).

`check` is the executable. It reads the files into a `Tree` (`readTree`), parses each record with
Lean core's `Lean.Json`, and decides with `problems`, which uses day-file equality, `noDupKeys`,
`recordFile` and the proved locator `dupAt?`. The file I/O, the JSON parser
and the field checks in `parseRecord` are not proved; the theorems about `problems` hold for any
parser. Every line
`check` and `cli` print that holds a file name, a field value, a message or an I/O error is the
gate's own `::error` command, with the text through `oneLine` and GitHub's escaping
(`gate/MitosGate/Util.lean`, with its proof). The runner reads such a line as that one command, so
the text in it starts none. The argument error is not a command, so it goes through `ciLine`.
-/

namespace MitosGate.RunLog

/-! ## Lines: append-only -/

/-- Every line of `base` occurs in `head` at least as often as in `base`. Order is ignored, so a
union merge that interleaves the two sides' lines passes. -/
def appendOnly (base head : List String) : Bool :=
  base.all fun l => base.count l ≤ head.count l

/-- The index in `base` of the first line that occurs fewer times in `head` than in `base`: the
line an edit or a deletion removed. -/
def firstMissing? (base head : List String) : Option Nat :=
  base.findIdx? fun l => head.count l < base.count l

/-- `l₁` is a sub-multiset of `l₂`: some reordering of `l₁` is a sublist of `l₂`. This is
Mathlib's `List.Subperm`; core Lean v4.35 has no such definition. -/
def Subperm {α : Type} (l₁ l₂ : List α) : Prop :=
  ∃ l : List α, l.Perm l₁ ∧ l.Sublist l₂

theorem subperm_iff_count {α : Type} [BEq α] [LawfulBEq α] {l₁ l₂ : List α} :
    Subperm l₁ l₂ ↔ ∀ a, l₁.count a ≤ l₂.count a := by
  constructor
  · rintro ⟨l, hp, hs⟩ a
    rw [← hp.count_eq a]
    exact hs.count_le a
  · intro h
    induction l₁ generalizing l₂ with
    | nil => exact ⟨[], .nil, List.nil_sublist _⟩
    | cons x t ih =>
      have hx : x ∈ l₂ := by
        have := h x
        rw [List.count_cons_self] at this
        exact List.count_pos_iff.mp (by omega)
      have ht : ∀ a, t.count a ≤ (l₂.erase x).count a := by
        intro a
        by_cases hax : a = x
        · subst hax
          have := h a
          rw [List.count_cons_self] at this
          rw [List.count_erase_self]
          omega
        · have := h a
          rw [List.count_cons_of_ne (Ne.symm hax)] at this
          rwa [List.count_erase_of_ne hax]
      obtain ⟨s, hs, hsub⟩ := ih ht
      obtain ⟨s', hs', hsub'⟩ :=
        List.exists_perm_sublist (hsub.cons_cons x) (List.perm_cons_erase hx).symm
      exact ⟨s', hs'.trans (hs.cons x), hsub'⟩

theorem appendOnly_iff_count {base head : List String} :
    appendOnly base head = true ↔ ∀ l, base.count l ≤ head.count l := by
  unfold appendOnly
  rw [List.all_eq_true]
  constructor
  · intro h l
    by_cases hl : l ∈ base
    · exact of_decide_eq_true (h l hl)
    · rw [List.count_eq_zero_of_not_mem hl]
      exact Nat.zero_le _
  · intro h l _
    exact decide_eq_true (h l)

theorem appendOnly_iff_subperm {base head : List String} :
    appendOnly base head = true ↔ Subperm base head :=
  appendOnly_iff_count.trans subperm_iff_count.symm

/-- A head passes exactly when it is the base plus some lines `a`, in any order. -/
theorem appendOnly_iff_perm_append {base head : List String} :
    appendOnly base head = true ↔ ∃ a, head.Perm (base ++ a) := by
  constructor
  · intro h
    obtain ⟨s, hs, hsub⟩ := appendOnly_iff_subperm.mp h
    obtain ⟨a, ha⟩ := hsub.exists_perm_append
    exact ⟨a, ha.trans (hs.append_right a)⟩
  · rintro ⟨a, ha⟩
    apply appendOnly_iff_count.mpr
    intro l
    rw [ha.count_eq l, List.count_append]
    exact Nat.le_add_right _ _

/-- Some line occurs fewer times in the head than in the base: the check fails. -/
theorem appendOnly_eq_false_of_count_lt {base head : List String} {l : String}
    (h : head.count l < base.count l) : appendOnly base head = false := by
  cases hb : appendOnly base head with
  | false => rfl
  | true =>
    have := appendOnly_iff_count.mp hb l
    omega

/-- An edit on the PR itself: the head replaces one occurrence of the base line `l`, at any
position, with a different line `l'`, and changes nothing else. The check fails. -/
theorem appendOnly_edit (p s : List String) {l l' : String} (hne : l ≠ l') :
    appendOnly (p ++ l :: s) (p ++ l' :: s) = false := by
  apply appendOnly_eq_false_of_count_lt (l := l)
  rw [List.count_append, List.count_append, List.count_cons_self,
    List.count_cons_of_ne (Ne.symm hne)]
  omega

/-- A deletion on the PR itself: the head drops one occurrence of a base line. The check fails. -/
theorem appendOnly_delete (p s : List String) (l : String) :
    appendOnly (p ++ l :: s) (p ++ s) = false := by
  apply appendOnly_eq_false_of_count_lt (l := l)
  rw [List.count_append, List.count_append, List.count_cons_self]
  omega

/-- **Union keeps the base.** The model of the `union` driver that merged day files until #113, an
assumption about git that is not proved here: when one side is the base plus lines `a` and the
other the base plus lines `b`, union keeps each base line once and every added line of each side,
so its result `r` is some order of `base ++ a ++ b`. The check no longer uses this. It is why an
append-only union kept every base line, and so why those files were safe to freeze as equality. -/
theorem union_appendOnly {base a b r : List String} (hunion : r.Perm (base ++ a ++ b)) :
    appendOnly base r = true :=
  appendOnly_iff_perm_append.mpr ⟨a ++ b, by rw [← List.append_assoc]; exact hunion⟩

theorem firstMissing?_eq_none_iff {base head : List String} :
    firstMissing? base head = none ↔ appendOnly base head = true := by
  rw [firstMissing?, List.findIdx?_eq_none_iff, appendOnly, List.all_eq_true]
  constructor
  · intro h l hl
    have := h l hl
    simp only [decide_eq_false_iff_not, Nat.not_lt] at this
    exact decide_eq_true this
  · intro h l hl
    have := of_decide_eq_true (h l hl)
    exact decide_eq_false (Nat.not_lt.mpr this)

/-- The locator is right: the line it names occurs fewer times in the head than in the base. -/
theorem firstMissing?_spec {base head : List String} {i : Nat}
    (h : firstMissing? base head = some i) :
    ∃ l, base[i]? = some l ∧ head.count l < base.count l := by
  have := List.of_findIdx?_eq_some h
  revert this
  cases hi : base[i]? with
  | none => intro h; exact absurd h (by simp)
  | some l => intro h; exact ⟨l, rfl, of_decide_eq_true h⟩

/-! ## Records: one per `(task, role, attempt)` -/

/-- The fields of a run-log record that identify the attempt it describes. -/
structure Record where
  task : String
  role : String
  attempt : Nat
  deriving DecidableEq, Repr, Inhabited

abbrev Key := String × String × Nat

def Record.key (r : Record) : Key := (r.task, r.role, r.attempt)

/-- A pair of positions `(i, j)`, `i < j`, that hold equal elements: `i` is the first position
whose element occurs again, and `j` is where it next occurs. -/
def dupAt? {α : Type} [BEq α] : List α → Option (Nat × Nat)
  | [] => none
  | x :: xs =>
    if xs.contains x then some (0, xs.idxOf x + 1)
    else (dupAt? xs).map fun p => (p.1 + 1, p.2 + 1)

theorem dupAt?_eq_none_iff {α : Type} [BEq α] [LawfulBEq α] {xs : List α} :
    dupAt? xs = none ↔ xs.Nodup := by
  induction xs with
  | nil => simp [dupAt?]
  | cons x xs ih =>
    rw [dupAt?, List.nodup_cons]
    by_cases hc : xs.contains x = true
    · have : x ∈ xs := List.contains_iff_mem.mp hc
      simp [this]
    · have : x ∉ xs := fun hm => hc (List.contains_iff_mem.mpr hm)
      simp [this, ih]

/-- The locator is right: the two positions it names hold equal elements. -/
theorem dupAt?_spec {α : Type} [BEq α] [LawfulBEq α] {xs : List α} {i j : Nat}
    (h : dupAt? xs = some (i, j)) : i < j ∧ ∃ x, xs[i]? = some x ∧ xs[j]? = some x := by
  induction xs generalizing i j with
  | nil => simp [dupAt?] at h
  | cons x xs ih =>
    rw [dupAt?] at h
    by_cases hc : xs.contains x = true
    · simp only [hc, ↓reduceIte] at h
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
      have hm : x ∈ xs := List.contains_iff_mem.mp hc
      have hlt := List.idxOf_lt_length_of_mem hm
      refine ⟨Nat.succ_pos _, x, rfl, ?_⟩
      rw [List.getElem?_cons_succ, List.getElem?_eq_getElem hlt, List.getElem_idxOf hlt]
    · simp only [hc, Bool.false_eq_true, ↓reduceIte] at h
      obtain ⟨⟨i', j'⟩, hp, hq⟩ := Option.map_eq_some_iff.mp h
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj hq
      obtain ⟨hlt, y, hy₁, hy₂⟩ := ih hp
      exact ⟨Nat.succ_lt_succ hlt, y, hy₁, hy₂⟩

/-- No two records share `(task, role, attempt)`. -/
def noDupKeys (rs : List Record) : Bool :=
  (dupAt? (rs.map Record.key)).isNone

theorem noDupKeys_iff {rs : List Record} :
    noDupKeys rs = true ↔ (rs.map Record.key).Nodup := by
  rw [noDupKeys, Option.isNone_iff_eq_none, dupAt?_eq_none_iff]

theorem noDupKeys_perm {rs rs' : List Record} (h : rs.Perm rs') :
    noDupKeys rs = noDupKeys rs' := by
  apply Bool.eq_iff_iff.mpr
  rw [noDupKeys_iff, noDupKeys_iff]
  exact (h.map Record.key).nodup_iff

/-- **Union adds no duplicate of its own.** Under the model of union at `union_appendOnly`, and for
any parser `f` from a line to its record, union's result passes `noDupKeys` exactly when the lines
of the base and of both sides have distinct keys. -/
theorem union_noDupKeys_iff (f : String → Record) {base a b r : List String}
    (hunion : r.Perm (base ++ a ++ b)) :
    noDupKeys (r.map f) = true ↔ ((base ++ a ++ b).map fun l => (f l).key).Nodup := by
  rw [noDupKeys_perm (hunion.map f), noDupKeys_iff, List.map_map]
  rfl

theorem eq_of_nodup_map {α β : Type} {g : α → β} {x y : α} :
    ∀ {l : List α}, (l.map g).Nodup → x ∈ l → y ∈ l → g x = g y → x = y
  | [], _, hx, _, _ => absurd hx List.not_mem_nil
  | c :: l, h, hx, hy, hg => by
    rw [List.map_cons, List.nodup_cons] at h
    obtain ⟨hc, hl⟩ := h
    rcases List.mem_cons.mp hx with hxc | hxl <;> rcases List.mem_cons.mp hy with hyc | hyl
    · exact hxc.trans hyc.symm
    · subst hxc; exact (hc (hg ▸ List.mem_map_of_mem hyl)).elim
    · subst hyc; exact (hc (hg ▸ List.mem_map_of_mem hxl)).elim
    · exact eq_of_nodup_map hl hxl hyl hg

/-- Two different lines of `r` whose records have the same key fail the check. -/
theorem noDupKeys_eq_false_of_mem (f : String → Record) {r : List String} {l₁ l₂ : String}
    (h₁ : l₁ ∈ r) (h₂ : l₂ ∈ r) (hne : l₁ ≠ l₂) (hkey : (f l₁).key = (f l₂).key) :
    noDupKeys (r.map f) = false := by
  cases hd : noDupKeys (r.map f) with
  | false => rfl
  | true =>
    rw [noDupKeys_iff, List.map_map] at hd
    exact absurd (eq_of_nodup_map hd h₁ h₂ hkey) hne

/-- **The edit is caught on either side of the merge.** The base ends with the record `l`. The PR
replaces it with `l'`, a corrected record for the same attempt, and changes nothing else; another
branch appends lines `b` after `l`. On the PR alone, `appendOnly` fails. Union keeps both sides of
the hunk where they differ, so its result `r` holds `l` (from the other branch) and `l'` (from the
PR): that is the only assumption about `r`, whatever order union puts them in. Then `noDupKeys`
fails on `r`, though `appendOnly` against either side's base may pass. -/
theorem edit_then_union (f : String → Record) (p : List String) {l l' : String}
    (hne : l ≠ l') (hkey : (f l).key = (f l').key) {r : List String} (hl : l ∈ r) (hl' : l' ∈ r) :
    appendOnly (p ++ [l]) (p ++ [l']) = false ∧ noDupKeys (r.map f) = false :=
  ⟨appendOnly_edit p [] hne, noDupKeys_eq_false_of_mem f hl hl' hne hkey⟩

/-! ## Small cases, checked by the kernel -/

example : appendOnly ["a", "b"] ["a", "b", "c"] = true := by decide
example : appendOnly ["a", "b"] ["c", "b", "x", "a"] = true := by decide
example : appendOnly ["a", "b"] ["a", "b'"] = false := by decide
example : appendOnly ["a", "b"] ["a"] = false := by decide
example : appendOnly ["a", "a"] ["a", "b"] = false := by decide
example : appendOnly [] ["a"] = true := by decide
example : firstMissing? ["a", "b", "c"] ["a", "c", "d"] = some 1 := by decide
example : firstMissing? ["a", "b"] ["b", "a"] = none := by decide
example : dupAt? [1, 2, 3, 2, 1] = some (0, 4) := by decide
example : dupAt? [1, 2, 3, 2] = some (1, 3) := by decide
example : dupAt? [1, 2, 3] = none := by decide
example : noDupKeys [⟨"T", "builder", 1⟩, ⟨"T", "builder", 2⟩, ⟨"T", "verifier", 1⟩] = true := by
  decide
example : noDupKeys [⟨"T", "builder", 1⟩, ⟨"U", "builder", 1⟩, ⟨"T", "builder", 1⟩] = false := by
  decide

/-- The old union replay: the base is `A`, `B`; the PR corrects `B` to `B'` in place; `main` appends
`C`; git's rebase with `merge=union` gave `A`, `B`, `C`, `B'`. Against `main`, that result passes
`appendOnly`, since `B` is still there, and fails `noDupKeys`. The driver is gone; equality
rejects both the edit and the append. -/
example :
    appendOnly ["A", "B"] ["A", "B'"] = false ∧
    appendOnly ["A", "B", "C"] ["A", "B", "C", "B'"] = true ∧
    noDupKeys [⟨"A", "builder", 1⟩, ⟨"B", "builder", 1⟩, ⟨"C", "builder", 1⟩,
      ⟨"B", "builder", 1⟩] = false := by
  decide

/-! ## The executable: file I/O and JSON (not proved) -/

/-- The lines of a file's text: the pieces between `\n`s, without the empty piece after a final
`\n`. An empty file has no lines. -/
def splitLines (s : String) : List String :=
  if s.isEmpty then []
  else
    let ls := s.splitOn "\n"
    if s.endsWith "\n" then ls.dropLast else ls

/-- `s` quoted for a message: `"` and `\` are escaped with `\`, and only the first `max` characters
are kept. It does not sanitize: every message is printed through `oneLine`. -/
def quote (s : String) (max : Nat := 60) : String :=
  let cs := s.toList
  let esc (acc : String) (c : Char) : String :=
    if c == '"' then acc ++ "\\\""
    else if c == '\\' then acc ++ "\\\\"
    else acc.push c
  "\"" ++ (cs.take max).foldl esc "" ++ (if cs.length > max then "\"..." else "\"")

/-- GitHub's escaping for the message of a workflow command. Written character by character, not
with `String.replace`, so that the kernel can evaluate `Problem.render` in the examples below. -/
def escapeData (s : String) : String :=
  String.ofList <| s.toList.flatMap fun
    | '%' => ['%', '2', '5']
    | '\r' => ['%', '0', 'D']
    | '\n' => ['%', '0', 'A']
    | c => [c]

/-- GitHub's escaping for a property value of a workflow command. -/
def escapeProperty (s : String) : String :=
  String.ofList <| (escapeData s).toList.flatMap fun
    | ':' => ['%', '3', 'A']
    | ',' => ['%', '2', 'C']
    | c => [c]

structure Problem where
  file : String
  line : Nat
  msg : String

/-- A problem as a GitHub error annotation. The file name and the message are untrusted (a file
name in `ops/runs/`, a field value, a JSON error): `oneLine` keeps the annotation on one line and
free of controls, bidi and format characters and blanks; the escapes after it only add `%XX`. -/
def Problem.render (p : Problem) : String :=
  s!"::error file={escapeProperty (oneLine p.file)},line={p.line}::{escapeData (oneLine p.msg)}"

/-! ## What the check prints, checked by the kernel -/

/-- A zero-width space (U+200B) in the file name, and a zero-width joiner (U+200D), a soft hyphen
(U+00AD) and a braille blank (U+2800) in a task: each is printed as an escape. -/
example : (Problem.mk "ops/runs/d\u200b1.ndjson" 4
      s!"a second record for task {quote "B\u200d\u00ad\u2800"}, role {quote "builder"}").render =
    "::error file=ops/runs/d\\u{200B}1.ndjson,line=4::a second record for task " ++
      "\"B\\u{200D}\\u{00AD}\\u{2800}\", role \"builder\"" := by
  decide

/-- The case in `gate/runlog-test.sh`: a newline, a workflow command, an ANSI escape, a bidi
override and a `%0A` in a task, and a comma and colons in the file name, stay on one line. -/
example : (Problem.mk "ops/runs/a,b::c.ndjson" 2
      s!"task {quote "x\n::warning::injected\x1b[2J\u202e%0A,y"}").render =
    "::error file=ops/runs/a%2Cb%3A%3Ac.ndjson,line=2::task " ++
      "\"x\\u{000A}::warning::injected\\u{001B}[2J\\u{202E}%250A,y\"" := by
  decide

/-- A quote and a backslash in a value: `quote` writes a string literal, escaping each with `\`,
and `oneLine` then writes every `\` as `\u{005C}`. Decoding those gives back the literal, so a
value cannot end its quotes early. -/
example : (Problem.mk "f" 1 (quote "a\"b\\c")).render =
    "::error file=f,line=1::\"a\\u{005C}\"b\\u{005C}\\u{005C}c\"" := by
  decide

/-! ## Record files: one record per attempt, named by its key -/

/-- The characters a task or a role may hold: ASCII letters and digits, `.`, `_` and `-`. -/
def safeChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '_' || c == '-'

/-- A task that can start a file name: not empty, only `safeChar`s, and a letter or a digit first,
so that the name starts with neither `.` (a hidden file) nor `-` (read as an option). -/
def safeTask (s : String) : Bool :=
  match s.toList with
  | [] => false
  | c :: cs => c.isAlphanum && cs.all safeChar

/-- A role: not empty, and only `safeChar`s. -/
def safeRole (s : String) : Bool := !s.toList.isEmpty && s.toList.all safeChar

/-- The name of the file that holds the record with key `k`: `<task>-<role>-<attempt>.json`. -/
def fileName (k : Key) : String := k.1 ++ "-" ++ k.2.1 ++ "-" ++ toString k.2.2 ++ ".json"

/-- The name built from a safe task and role is one plain path entry: only `safeChar`s, so no `/`,
no control character and no blank, and a letter or a digit first. -/
theorem fileName_safe {k : Key} (ht : safeTask k.1 = true) (hr : safeRole k.2.1 = true) :
    (∀ c ∈ (fileName k).toList, safeChar c = true) ∧
      ∃ c cs, (fileName k).toList = c :: cs ∧ c.isAlphanum = true := by
  obtain ⟨t, r, n⟩ := k
  simp only at ht hr
  unfold safeTask at ht
  split at ht
  · exact absurd ht (by decide)
  · rename_i c cs hcs
    simp only [Bool.and_eq_true, List.all_eq_true] at ht
    unfold safeRole at hr
    simp only [Bool.and_eq_true, List.all_eq_true] at hr
    have hdig : ∀ x ∈ (toString n).toList, safeChar x = true := by
      intro x hx
      simp only [toString, Nat.repr, String.toList_ofList] at hx
      have := Nat.isDigit_of_mem_toDigits (by decide) (by decide) hx
      simp [safeChar, Char.isAlphanum, this]
    refine ⟨?_, c, cs ++ ('-' :: r.toList ++ '-' :: (toString n).toList ++ ".json".toList), ?_, ht.1⟩
    · intro x hx
      simp only [fileName, String.toList_append, hcs, List.mem_append, List.mem_cons] at hx
      rcases hx with ((((hx | hx) | hx) | hx) | hx) | hx
      · rcases hx with rfl | hx
        · simp [safeChar, ht.1]
        · exact ht.2 x hx
      · revert hx; decide +revert
      · exact hr.2 x hx
      · revert hx; decide +revert
      · exact hdig x hx
      · revert hx; decide +revert
    · simp [fileName, String.toList_append, hcs]

/-- The one line of a record file's text: the text without a final `\n`, when that is not empty
and holds no other `\n`. -/
def singleLine? (s : String) : Option String :=
  let cs := if s.toList.getLast? = some '\n' then s.toList.dropLast else s.toList
  if cs = [] ∨ '\n' ∈ cs then none else some (String.ofList cs)

/-- **A record file is one line.** The line is not empty and holds no `\n`, and the text is the
line, with or without a final `\n`. -/
theorem singleLine?_spec {s l : String} (h : singleLine? s = some l) :
    l.toList ≠ [] ∧ '\n' ∉ l.toList ∧
      (s.toList = l.toList ∨ s.toList = l.toList ++ ['\n']) := by
  have key : ∀ cs : List Char,
      (if cs = [] ∨ '\n' ∈ cs then none else some (String.ofList cs)) = some l →
        l.toList = cs ∧ cs ≠ [] ∧ '\n' ∉ cs := by
    intro cs hcs
    split at hcs
    · cases hcs
    · rename_i hc
      cases hcs
      exact ⟨String.toList_ofList, fun h => hc (Or.inl h), fun h => hc (Or.inr h)⟩
  unfold singleLine? at h
  by_cases hl : s.toList.getLast? = some '\n'
  · simp only [hl, ↓reduceIte] at h
    obtain ⟨h1, h2, h3⟩ := key _ h
    obtain ⟨ys, hys⟩ := List.getLast?_eq_some_iff.mp hl
    refine ⟨h1 ▸ h2, h1 ▸ h3, Or.inr ?_⟩
    rw [h1, hys, List.dropLast_concat]
  · simp only [hl, ↓reduceIte] at h
    obtain ⟨h1, h2, h3⟩ := key _ h
    exact ⟨h1 ▸ h2, h1 ▸ h3, Or.inl h1.symm⟩

/-- The record a record file named `name` holds, or why it is refused: the text is one line
(`singleLine?`), the line is a record (`parse`), its task and role are safe (`safeTask`,
`safeRole`), and the file is named `fileName` of its key. -/
def recordFile (parse : String → Except String Record) (name text : String) :
    Except String Record :=
  match singleLine? text with
  | none => .error ("a record file holds one record on one line; this one is empty or has " ++
      "more lines (ops/runs/README.md)")
  | some l =>
    match parse l with
    | .error e => .error e
    | .ok r =>
      if safeTask r.task = false then
        .error s!"task {quote r.task} must start with a letter or a digit and hold only letters, \
          digits, '.', '_' and '-', because it names the file"
      else if safeRole r.role = false then
        .error s!"role {quote r.role} must not be empty and must hold only letters, digits, \
          '.', '_' and '-', because it names the file"
      else if name = fileName r.key then .ok r
      else
        .error s!"the file must be named {quote (fileName r.key) 120}, from its record's task, \
          role and attempt, so that two records for one attempt on one day are one path \
          (ops/runs/README.md)"

/-- **A record file that passes holds one record, named by its key.** -/
theorem recordFile_ok {parse : String → Except String Record} {name text : String} {r : Record}
    (h : recordFile parse name text = .ok r) :
    (∃ l, singleLine? text = some l ∧ parse l = .ok r) ∧ safeTask r.task = true ∧
      safeRole r.role = true ∧ name = fileName r.key := by
  unfold recordFile at h
  split at h
  · cases h
  · rename_i l hl
    split at h
    · cases h
    · rename_i r' hr
      split at h
      · cases h
      · rename_i ht
        split at h
        · cases h
        · rename_i hro
          split at h
          · rename_i hn
            cases h
            refine ⟨⟨l, hl, hr⟩, ?_, ?_, hn⟩
            · simpa using ht
            · simpa using hro
          · cases h

/-- **A day folder holds each key at most once.** A folder lists each name once (`hnames`), and a
record file that passes `recordFile` is named `fileName` of its record's key (`hname`), so two
files of one folder never hold records with one key. -/
theorem day_keys_nodup {fs : List (String × Record)} (hnames : (fs.map (·.1)).Nodup)
    (hname : ∀ p ∈ fs, p.1 = fileName p.2.key) : (fs.map (·.2.key)).Nodup := by
  have : fs.map (·.1) = (fs.map (·.2.key)).map fileName := by
    rw [List.map_map]
    exact List.map_congr_left hname
  rw [this] at hnames
  exact List.Pairwise.of_map fileName (fun _ _ h e => h (congrArg fileName e)) hnames

/-- Whether a folder name is a date: `YYYY-MM-DD`, with digits. -/
def isDate (s : String) : Bool :=
  match s.toList with
  | [y₁, y₂, y₃, y₄, '-', m₁, m₂, '-', d₁, d₂] =>
    [y₁, y₂, y₃, y₄, m₁, m₂, d₁, d₂].all Char.isDigit
  | _ => false

/-! ## The check on whole trees -/

/-- What the check reads under `ops/runs/`: each day file directly in it, with its name and lines,
and each record file in its folders, with the folder's name, the file's name and its text. -/
structure Tree where
  days : List (String × List String) := []
  files : List (String × String × String) := []

/-- The lines of the day file `n` of a tree, none if it has no such file. -/
def linesOf (t : Tree) (n : String) : List String :=
  ((t.days.find? (·.1 == n)).map (·.2)).getD []

/-- The records of a tree: the lines of its day files that parse, then its record files that pass
`recordFile`. -/
def records (parse : String → Except String Record) (t : Tree) : List Record :=
  t.days.flatMap (fun d => d.2.filterMap fun l => (parse l).toOption) ++
    t.files.filterMap fun f => (recordFile parse f.2.1 f.2.2).toOption

/-- The records of the lines `ls` of the file `f`, each with its file and line number, the first
line numbered `i`. -/
def lineRecords (parse : String → Except String Record) (f : String) :
    Nat → List String → List (String × Nat × Record)
  | _, [] => []
  | i, l :: ls =>
    match parse l with
    | .ok r => (f, i, r) :: lineRecords parse f (i + 1) ls
    | .error _ => lineRecords parse f (i + 1) ls

/-- The problems of the lines `ls` of the file `f`: each line `parse` refuses, at its number. -/
def lineErrors (parse : String → Except String Record) (f : String) :
    Nat → List String → List Problem
  | _, [] => []
  | i, l :: ls =>
    match parse l with
    | .ok _ => lineErrors parse f (i + 1) ls
    | .error e => ⟨f, i, e⟩ :: lineErrors parse f (i + 1) ls

/-- The records of a tree under `dir`, each with the file and line it is at. -/
def located (parse : String → Except String Record) (dir : System.FilePath) (t : Tree) :
    List (String × Nat × Record) :=
  t.days.flatMap (fun d => lineRecords parse (dir / d.1).toString 1 d.2) ++
    t.files.filterMap fun f =>
      match recordFile parse f.2.1 f.2.2 with
      | .ok r => some ((dir / f.1 / f.2.1).toString, 1, r)
      | .error _ => none

theorem lineRecords_map (parse : String → Except String Record) (f : String) (i : Nat)
    (ls : List String) :
    (lineRecords parse f i ls).map (·.2.2) = ls.filterMap fun l => (parse l).toOption := by
  induction ls generalizing i with
  | nil => rfl
  | cons l ls ih =>
    simp only [lineRecords, List.filterMap_cons]
    cases parse l <;> simp [Except.toOption, ih]

/-- The located records are the records. -/
theorem located_map (parse : String → Except String Record) (dir : System.FilePath) (t : Tree) :
    (located parse dir t).map (·.2.2) = records parse t := by
  simp only [located, records, List.map_append, List.map_flatMap, lineRecords_map,
    List.map_filterMap]
  congr 1
  congr 1
  funext f
  cases recordFile parse f.2.1 f.2.2 <;> rfl

theorem lineErrors_eq_nil {parse : String → Except String Record} {f : String} {i : Nat}
    {ls : List String} (h : lineErrors parse f i ls = []) : ∀ l ∈ ls, ∃ r, parse l = .ok r := by
  induction ls generalizing i with
  | nil => simp
  | cons l ls ih =>
    unfold lineErrors at h
    intro x hx
    split at h
    · rename_i r hr
      rcases List.mem_cons.mp hx with rfl | hx
      · exact ⟨r, hr⟩
      · exact ih h x hx
    · cases h

/-- The problem of one record file, if it has one: its folder is not a date, or `recordFile`
refuses it. -/
def fileProblem (parse : String → Except String Record) (dir : System.FilePath)
    (f : String × String × String) : Option Problem :=
  let p := (dir / f.1 / f.2.1).toString
  if isDate f.1 = false then
    some ⟨p, 1, "a record file must be in a folder named by its date, YYYY-MM-DD " ++
      "(ops/runs/README.md)"⟩
  else
    match recordFile parse f.2.1 f.2.2 with
    | .ok _ => none
    | .error e => some ⟨p, 1, e⟩

/-- Every line of a day file that is not a record, and every record file that is refused. -/
def parseProblems (parse : String → Except String Record) (dir : System.FilePath) (t : Tree) :
    List Problem :=
  t.days.flatMap (fun d => lineErrors parse (dir / d.1).toString 1 d.2) ++
    t.files.filterMap (fileProblem parse dir)

def keyText (r : Record) : String :=
  s!"task {quote r.task}, role {quote r.role}, attempt {r.attempt}"

/-- The first record of a tree whose key an earlier record has, located by `dupAt?`. -/
def dupProblems (parse : String → Except String Record) (dir : System.FilePath) (t : Tree) :
    List Problem :=
  let recs := located parse dir t
  match dupAt? (recs.map fun x => x.2.2.key) with
  | none => []
  | some (i, j) =>
    -- The positions are in `recs`, and hold one key, by `dupAt?_spec`.
    let (fi, li, r) := recs[i]!
    let (fj, lj, _) := recs[j]!
    [⟨fj, lj, s!"a second record for {keyText r}; the first is at {fi}:{li}. An attempt has " ++
      "one record: a correction goes in the next attempt's record (ops/runs/README.md)"⟩]

/-- The first index where `base` and `head` differ, counting from 0. When `head` extends a shared
prefix the index is `base.length`, the first appended line. When `head` runs out first the index
is where it ends. The check calls this only when the lists are not equal. -/
def firstDiff? : List String → List String → Nat
  | [], _ => 0
  | _ :: _, [] => 0
  | a :: as, b :: bs => if a == b then firstDiff? as bs + 1 else 0

example : firstDiff? ["a", "b"] ["a", "b", "c"] = 2 := by decide
example : firstDiff? ["a", "b", "c"] ["a", "x", "c"] = 1 := by decide
example : firstDiff? ["a", "b"] ["a"] = 1 := by decide

/-- What the head `h` changed against the merge base `b`: a day file whose lines are not the base
file's, line for line (`firstDiff?` names the first one), a day file the base lacks, and a record
file of the base that the head lacks or holds with other text. -/
def keptProblems (dir : System.FilePath) (b h : Tree) : List Problem :=
  b.days.filterMap (fun d =>
    let hl := linesOf h d.1
    if d.2 == hl then none
    else
      let i := firstDiff? d.2 hl
      let line := i + 1
      let msg :=
        if !h.days.any (·.1 == d.1) then
          s!"line {line} of the merge-base version is missing: the file was deleted. " ++
            "A day file on the base branch is frozen and must match main (ops/runs/README.md)"
        else if i ≥ d.2.length then
          s!"line {line} is not in the merge-base version: a day file may not gain a line. " ++
            "A day file on the base branch is frozen and must match main (ops/runs/README.md)"
        else
          s!"line {line} of the merge-base version differs from this file. " ++
            "A day file on the base branch is frozen and must match main (ops/runs/README.md)"
      some ⟨(dir / d.1).toString, line, msg⟩) ++
  h.days.filterMap (fun d =>
    if b.days.any (·.1 == d.1) then none
    else some ⟨(dir / d.1).toString, 1, "a new day file. Each attempt's record goes in its own " ++
      "file, ops/runs/<date>/<task>-<role>-<attempt>.json (ops/runs/README.md)"⟩) ++
  b.files.filterMap (fun f =>
    if h.files.contains f then none
    else
      let what := if h.files.any (fun g => g.1 == f.1 && g.2.1 == f.2.1) then "was changed" else
        "was deleted"
      some ⟨(dir / f.1 / f.2.1).toString, 1, s!"this record file is on the base branch and " ++
        s!"{what}. A record file never changes once it is on main: a correction goes in the " ++
        "note of the next attempt's record (ops/runs/README.md)"⟩)

/-- The whole check: the records parse, no two share a key, and, given the merge-base tree, each
day file equals the base and each base record file is kept (`keptProblems`). `problems_eq_nil`
states what an empty result means. -/
def problems (parse : String → Except String Record) (dir : System.FilePath) (base : Option Tree)
    (head : Tree) : List Problem :=
  parseProblems parse dir head ++ dupProblems parse dir head ++
    match base with
    | some b => keptProblems dir b head
    | none => []

theorem parseProblems_eq_nil {parse : String → Except String Record} {dir : System.FilePath}
    {t : Tree} (h : parseProblems parse dir t = []) :
    (∀ d ∈ t.days, ∀ l ∈ d.2, ∃ r, parse l = .ok r) ∧
      (∀ f ∈ t.files, isDate f.1 = true ∧ ∃ r, recordFile parse f.2.1 f.2.2 = .ok r) := by
  rw [parseProblems, List.append_eq_nil_iff, List.flatMap_eq_nil_iff,
    List.filterMap_eq_nil_iff] at h
  refine ⟨fun d hd => lineErrors_eq_nil (h.1 d hd), fun f hf => ?_⟩
  have hp := h.2 f hf
  unfold fileProblem at hp
  split at hp
  · cases hp
  · rename_i hd
    refine ⟨by simpa using hd, ?_⟩
    split at hp
    · rename_i r hr
      exact ⟨r, hr⟩
    · cases hp

theorem dupProblems_eq_nil {parse : String → Except String Record} {dir : System.FilePath}
    {t : Tree} (h : dupProblems parse dir t = []) : noDupKeys (records parse t) = true := by
  dsimp only [dupProblems] at h
  split at h
  · rename_i hn
    rw [noDupKeys, ← located_map parse dir, List.map_map, Option.isNone_iff_eq_none]
    exact hn
  · cases h

theorem keptProblems_eq_nil {dir : System.FilePath} {b h : Tree} (hk : keptProblems dir b h = []) :
    (∀ d ∈ b.days, linesOf h d.1 = d.2) ∧
      (∀ d ∈ h.days, ∃ d' ∈ b.days, d'.1 = d.1) ∧ (∀ f ∈ b.files, f ∈ h.files) := by
  simp only [keptProblems, List.append_eq_nil_iff, List.filterMap_eq_nil_iff] at hk
  obtain ⟨⟨h1, h2⟩, h3⟩ := hk
  refine ⟨fun d hd => ?_, fun d hd => ?_, fun f hf => ?_⟩
  · have := h1 d hd
    split at this
    · rename_i heq
      exact (beq_iff_eq.mp heq).symm
    · cases this
  · have := h2 d hd
    split at this
    · rename_i ha
      obtain ⟨d', hd', he⟩ := List.any_eq_true.mp ha
      exact ⟨d', hd', beq_iff_eq.mp he⟩
    · cases this
  · have := h3 f hf
    split at this
    · exact List.contains_iff_mem.mp (by assumption)
    · cases this

/-- **Every merge-base record is kept.** When each base day file's lines equal the head file of
the same name, and each base record file is in the head with the same text, every record of the
base is a record of the head, for any parser. -/
theorem records_kept (parse : String → Except String Record) {b h : Tree}
    (hdays : ∀ d ∈ b.days, linesOf h d.1 = d.2)
    (hfiles : ∀ f ∈ b.files, f ∈ h.files) :
    ∀ r ∈ records parse b, r ∈ records parse h := by
  intro r hr
  simp only [records, List.mem_append, List.mem_flatMap, List.mem_filterMap] at hr ⊢
  rcases hr with ⟨d, hd, l, hl, hp⟩ | ⟨f, hf, hp⟩
  · left
    have hlh : l ∈ linesOf h d.1 := (hdays d hd).symm ▸ hl
    unfold linesOf at hlh
    cases hfind : h.days.find? (fun x => x.1 == d.1) with
    | none => simp [hfind] at hlh
    | some d' =>
      simp only [hfind, Option.map_some, Option.getD_some] at hlh
      exact ⟨d', List.mem_of_find?_eq_some hfind, l, hlh, hp⟩
  · exact Or.inr ⟨f, hfiles f hf, hp⟩

/-- **What a pass means.** When `problems` finds nothing: no two records of the head, in day files
and record files together, share a key; every line of a head day file is a record; every head
record file is in a folder named by a date and passes `recordFile`, so it is one line, one record,
named by its key (`recordFile_ok`). Given the merge-base tree `b`, also each day file of `b` has
the same lines in the head, every record of `b` is a record of the head (`records_kept`), and the
head has no day file that `b` lacks. -/
theorem problems_eq_nil (parse : String → Except String Record) (dir : System.FilePath)
    {base : Option Tree} {h : Tree} (hp : problems parse dir base h = []) :
    noDupKeys (records parse h) = true ∧
      (∀ d ∈ h.days, ∀ l ∈ d.2, ∃ r, parse l = .ok r) ∧
      (∀ f ∈ h.files, isDate f.1 = true ∧ ∃ r, recordFile parse f.2.1 f.2.2 = .ok r) ∧
      (∀ b, base = some b → (∀ d ∈ b.days, linesOf h d.1 = d.2) ∧
        (∀ r ∈ records parse b, r ∈ records parse h) ∧
        ∀ d ∈ h.days, ∃ d' ∈ b.days, d'.1 = d.1) := by
  unfold problems at hp
  rw [List.append_eq_nil_iff, List.append_eq_nil_iff] at hp
  obtain ⟨⟨hpar, hdup⟩, hkept⟩ := hp
  obtain ⟨hl, hf⟩ := parseProblems_eq_nil hpar
  refine ⟨dupProblems_eq_nil hdup, hl, hf, fun b hb => ?_⟩
  subst hb
  obtain ⟨k1, k2, k3⟩ := keptProblems_eq_nil hkept
  exact ⟨k1, records_kept parse k1 k3, k2⟩

/-! ## Record files, checked by the kernel -/

example : fileName ("ci-escape-68", "builder", 12) = "ci-escape-68-builder-12.json" := by decide
example : safeTask "P1-006" = true ∧ safeTask ".x" = false ∧ safeTask "-x" = false ∧
    safeTask "a/b" = false ∧ safeTask "" = false ∧ safeRole "red-team" = true ∧
    safeRole "" = false ∧ safeRole "a b" = false := by decide
example : isDate "2026-11-09" = true ∧ isDate "2026-1-09" = false ∧ isDate "notes" = false := by
  decide
example : singleLine? "{}\n" = some "{}" ∧ singleLine? "{}" = some "{}" ∧
    singleLine? "{}\n{}\n" = none ∧ singleLine? "" = none ∧ singleLine? "\n" = none ∧
    singleLine? "{}\n\n" = none := by decide

def outcomes : List String := ["in-review", "merged", "stuck", "counterexample", "abandoned"]

open Lean in
private def isNat (j : Json) : Bool := (j.getNat?).toBool

open Lean in
private def isStr : Json → Bool
  | .str _ => true
  | _ => false

open Lean in
private def isObj : Json → Bool
  | .obj _ => true
  | _ => false

open Lean in
private def isStrArray : Json → Bool
  | .arr a => a.all isStr
  | _ => false

open Lean in
private def isNatObject : Json → Bool
  | .obj kvs => kvs.all fun _ v => isNat v
  | _ => false

/-- Parse one run-log line and check its fields against `ops/runs/README.md`. Required, with the
type every record on `main` has: `task`, `role`, `model` and `outcome` strings, `outcome` one of
`outcomes`; `attempt`, `iterations` and `wall_min` natural numbers; `tokens` a natural number or
`null` (the README says int; every record so far is `null`, since sessions do not meter tokens);
`errors_by_kind` an object of natural numbers; `lint_hits` and `escalations` arrays of strings.
`note`, which the README's merging rules use, is optional but must be a string. Other fields are
allowed. -/
def parseRecord (line : String) : Except String Record := do
  let j ← match Lean.Json.parse line with
    | .ok j => pure j
    | .error e => throw s!"the line is not valid JSON ({quote e})"
  unless isObj j do throw "the line is not a JSON object"
  let get (k : String) : Except String Lean.Json :=
    match j.getObjVal? k with
    | .ok v => pure v
    | .error _ => throw s!"field {quote k} is missing"
  let want (k ty : String) (ok : Lean.Json → Bool) : Except String Unit := do
    unless ok (← get k) do throw s!"field {quote k} must be {ty}"
  let str (k : String) : Except String String := do
    match ← get k with
    | .str s => pure s
    | _ => throw s!"field {quote k} must be a string"
  let task ← str "task"
  let role ← str "role"
  let _ ← str "model"
  let attempt ← match (← get "attempt").getNat? with
    | .ok n => pure n
    | .error _ => throw s!"field {quote "attempt"} must be a natural number"
  want "iterations" "a natural number" isNat
  want "wall_min" "a natural number" isNat
  want "tokens" "a natural number or null" fun v => isNat v || v.isNull
  want "errors_by_kind" "an object of natural numbers" isNatObject
  want "lint_hits" "an array of strings" isStrArray
  want "escalations" "an array of strings" isStrArray
  let outcome ← str "outcome"
  unless outcomes.contains outcome do
    throw s!"field {quote "outcome"} is {quote outcome}, not one of {", ".intercalate outcomes}"
  if let .ok v := j.getObjVal? "note" then
    unless isStr v do throw s!"field {quote "note"} must be a string"
  return { task, role, attempt }

/-- The text of a run-log file, or why it cannot be read. A symlink is refused, so the check
never reads, or prints part of, a file outside the directory. -/
def readText (path : System.FilePath) : IO (Except String String) := do
  let md ← path.symlinkMetadata
  if md.type != .file then
    return .error "not a regular file; run-log files must be plain files, not symlinks or directories"
  match String.fromUTF8? (← IO.FS.readBinFile path) with
  | none => return .error "not valid UTF-8"
  | some s => return .ok s

/-- The lines of a day file, or why it cannot be read. -/
def readLines (path : System.FilePath) : IO (Except String (List String)) :=
  return (← readText path).map splitLines

/-- The entries directly in `dir`, sorted by name. -/
def sortedEntries (dir : System.FilePath) : IO (Array IO.FS.DirEntry) :=
  return (← dir.readDir).qsort (·.fileName < ·.fileName)

/-- Read a run-log directory into a `Tree`. A name directly in `dir` that ends in `.ndjson` is a
day file, a name that starts with a dot included. The frozen day files on `main` are read here.
A directory directly in `dir`, not a symlink to one, is a folder of record files: each
entry in it whose name ends in `.json`. `problems` checks the folder's name and the files.

It also returns the problems with what it cannot read or what does not belong, and the paths it
could not read. A problem names its path under `shown`, the head directory, so that an annotation
for the merge-base copy (`isBase`) points into the repository. In the merge base only a day or
record file that cannot be read is a problem, since `main` is checked on its own push. -/
def readTree (dir shown : System.FilePath) (isBase : Bool) :
    IO (Tree × Array Problem × Array String) := do
  let pre := if isBase then "the merge-base copy: " else ""
  let mut days : Array (String × List String) := #[]
  let mut files : Array (String × String × String) := #[]
  let mut ps : Array Problem := #[]
  let mut bad : Array String := #[]
  for e in ← sortedEntries dir do
    let n := e.fileName
    let p := dir / n
    let f := (shown / n).toString
    let ty := (← p.symlinkMetadata).type
    if n.endsWith ".ndjson" then
      match ← readLines p with
      | .ok ls => days := days.push (n, ls)
      | .error err => ps := ps.push ⟨f, 1, pre ++ err⟩; bad := bad.push f
    else if ty == .dir then
      for e' in ← sortedEntries p do
        let q := (shown / n / e'.fileName).toString
        if e'.fileName.endsWith ".json" then
          match ← readText (p / e'.fileName) with
          | .ok s => files := files.push (n, e'.fileName, s)
          | .error err => ps := ps.push ⟨q, 1, pre ++ err⟩; bad := bad.push q
        else unless isBase do
          ps := ps.push ⟨q, 1, "does not belong in a run-log folder, which holds only record " ++
            "files <task>-<role>-<attempt>.json (ops/runs/README.md)"⟩
    else unless isBase || (n == "README.md" && ty == .file) do
      ps := ps.push ⟨f, 1, "does not belong in the run log, which holds README.md, the day files " ++
        "<date>.ndjson and the folders <date>/ of record files (ops/runs/README.md)"⟩
  return ({ days := days.toList, files := files.toList }, ps, bad)

/-- Run the check on the run-log directory `head`, given the merge base's copy `base` on a pull
request: `readTree` reads both, and `problems` decides (`problems_eq_nil`). -/
def check (base : Option System.FilePath) (head : System.FilePath) : IO UInt32 := do
  for d in base.toList ++ [head] do
    let isDir ← try pure ((← d.symlinkMetadata).type == .dir) catch _ => pure false
    unless isDir do
      let msg := s!"run-log directory {quote d.toString} is missing, or is not a plain directory"
      IO.println s!"::error::{escapeData (oneLine msg)}"
      return 1
  let (h, hps, hbad) ← readTree head head false
  let mut ps := hps
  let mut b? : Option Tree := none
  if let some bd := base then
    let (b, bps, _) ← readTree bd head true
    ps := ps ++ bps
    b? := some b
  -- A head file that could not be read is reported above, not again as missing.
  ps := ps ++ ((problems parseRecord head b? h).filter fun p => !hbad.contains p.file).toArray
  if ps.isEmpty then
    let vs := match b? with
      | some b => s!", every day file matches the merge base and every record file is kept " ++
          s!"({b.days.length + b.files.length} file(s) compared)"
      | none => ""
    IO.println (s!"run log OK: {h.days.length + h.files.length} file(s), " ++
      s!"{(records parseRecord h).length} record(s), one per (task, role, attempt){vs}")
    return 0
  for p in ps do IO.println p.render
  IO.println s!"{ps.size} run-log problem(s); see ops/runs/README.md"
  return 1

def parseArgs : List String → Option String → Option String →
    Except String (Option String × Option String)
  | [], b, h => .ok (b, h)
  | "--base" :: v :: rest, _, h => parseArgs rest (some v) h
  | "--head" :: v :: rest, b, _ => parseArgs rest b (some v)
  | a :: _, _, _ => .error s!"unknown or incomplete argument {quote a}"

/-- `check`, but an I/O error it throws is printed as one `::error::` line through `oneLine`, with
exit 1. The Lean runtime would print an uncaught one raw, and the error names the path it failed
on, which can hold a newline. A file name that is not UTF-8 throws one: Lean reads it back with
U+FFFD, and no file has that name. -/
def cli (args : List String) (usage : String) : IO UInt32 := do
  match parseArgs args none none with
  | .ok (b, some h) =>
    try check (b.map System.FilePath.mk) h
    catch e =>
      let msg := s!"the run-log check stopped on an I/O error: {e}"
      IO.println s!"::error::{escapeData (oneLine msg)}"
      return 1
  | .ok (_, none) => IO.eprintln "runlog needs --head <dir>"; IO.eprintln usage; return 2
  | .error e => IO.eprintln (ciLine e); IO.eprintln usage; return 2

end MitosGate.RunLog
