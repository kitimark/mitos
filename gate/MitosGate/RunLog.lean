import Lean.Data.Json
import MitosGate.Util

/-!
# The run-log check (`mitos-gate runlog`)

`.gitattributes` merges `ops/runs/*.ndjson` with git's `union` driver, which keeps the lines of
both sides. That is right only while no branch edits or deletes a line it did not add: union
turns an edited line into two records for one attempt and reports no conflict. This module
states that rule, proves the check that enforces it, and runs it.

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

`check` is the executable. It reads the files, parses each line with Lean core's `Lean.Json`, and
decides with `appendOnly`, `noDupKeys` and the proved locators `firstMissing?` and `dupAt?`. The
file I/O, the JSON parser and the field checks in `parseRecord` are not proved. Every line it
prints that holds a file name, a field value or a message passes through `oneLine`
(`gate/MitosGate/Util.lean`, with its proof), the gate's one sanitizer for untrusted text.
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

/-- **Union keeps the base.** The model of git's union merge, an assumption about git that is not
proved here: when one side is the base plus lines `a` and the other the base plus lines `b`, union
keeps each base line once and every added line of each side, so its result `r` is some order of
`base ++ a ++ b`. The replays in `gate/runlog-test.sh` check such merges on real git. -/
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

/-- The replay in `gate/runlog-test.sh`: the base is `A`, `B`; the PR corrects `B` to `B'` in place;
`main` appends `C`; git's rebase with `merge=union` gives `A`, `B`, `C`, `B'`. Against `main`, the
rebased PR passes `appendOnly`, since `B` is still there, and fails `noDupKeys`. -/
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

/-- The names of the entries directly in `dir` that end in `.ndjson`, sorted. This is the set
`.gitattributes` merges with union: `ops/runs/*.ndjson` does not match in subdirectories, and its
`*` also matches a name that starts with a dot or is empty. -/
def ndjsonNames (dir : System.FilePath) : IO (Array String) := do
  let es ← dir.readDir
  let ns := es.filterMap fun e => if e.fileName.endsWith ".ndjson" then some e.fileName else none
  return ns.qsort (· < ·)

/-- The lines of a run-log file, or why it cannot be read. A symlink is refused, so the check
never reads, or prints part of, a file outside the directory. -/
def readLines (path : System.FilePath) : IO (Except String (List String)) := do
  let md ← path.symlinkMetadata
  if md.type != .file then
    return .error "not a regular file; run-log files must be plain files, not symlinks or directories"
  match String.fromUTF8? (← IO.FS.readBinFile path) with
  | none => return .error "not valid UTF-8"
  | some s => return .ok (splitLines s)

private def keyText (r : Record) : String :=
  s!"task {quote r.task}, role {quote r.role}, attempt {r.attempt}"

/-- Run the check on the `*.ndjson` files in `head`: every line parses (`parseRecord`), no two
records share a key (`noDupKeys`, located by `dupAt?`), and, given `base`, every line of each base
file is still in the head file of the same name (`appendOnly`, located by `firstMissing?`). -/
def check (base : Option System.FilePath) (head : System.FilePath) : IO UInt32 := do
  for d in base.toList ++ [head] do
    let isDir ← try pure ((← d.symlinkMetadata).type == .dir) catch _ => pure false
    unless isDir do
      let msg := s!"run-log directory {quote d.toString} is missing, or is not a plain directory"
      IO.println s!"::error::{escapeData (oneLine msg)}"
      return 1
  let mut problems : Array Problem := #[]
  let mut recs : Array (String × Nat × Record) := #[]
  let mut headLines : List (String × List String) := []
  let headNames ← ndjsonNames head
  for n in headNames do
    let f := (head / n).toString
    match ← readLines (head / n) with
    | .error e => problems := problems.push ⟨f, 1, e⟩
    | .ok ls =>
      headLines := headLines ++ [(n, ls)]
      for (l, i) in ls.zipIdx do
        match parseRecord l with
        | .error e => problems := problems.push ⟨f, i + 1, e⟩
        | .ok r => recs := recs.push (f, i + 1, r)
  let mut compared := 0
  if let some b := base then
    for n in ← ndjsonNames b do
      let f := (head / n).toString
      match ← readLines (b / n) with
      | .error e => problems := problems.push ⟨f, 1, s!"the merge-base copy: {e}"⟩
      | .ok bl =>
        -- A head file that exists but could not be read is reported above.
        if headNames.contains n && !(headLines.any (·.1 == n)) then continue
        let hl := (headLines.find? (·.1 == n)).map (·.2) |>.getD []
        compared := compared + 1
        unless appendOnly bl hl do
          -- `some` here, by `firstMissing?_eq_none_iff`; the line it names is right by
          -- `firstMissing?_spec`.
          let i := (firstMissing? bl hl).getD 0
          let what := if headNames.contains n then "is missing from this file" else
            "is missing: the file was deleted"
          problems := problems.push ⟨f, i + 1, s!"line {i + 1} of the merge-base version {what}. " ++
            "Run-log lines are append-only: a line already on the base branch may not be edited " ++
            "or deleted (ops/runs/README.md)"⟩
  let rs := recs.toList.map (·.2.2)
  unless noDupKeys rs do
    match dupAt? (rs.map Record.key) with
    | some (i, j) =>
      let (fi, li, r) := recs[i]!
      let (fj, lj, _) := recs[j]!
      problems := problems.push ⟨fj, lj, s!"a second record for {keyText r}; the first is at " ++
        s!"{fi}:{li}. Union keeps both versions of an edited line. Run-log lines are " ++
        "append-only, with one record per attempt (ops/runs/README.md)"⟩
    | none => -- unreachable: `noDupKeys_iff` and `dupAt?_eq_none_iff`
      problems := problems.push ⟨head.toString, 1, "duplicate key with no location"⟩
  if problems.isEmpty then
    let vs := if base.isSome then s!", every merge-base line kept ({compared} file(s) compared)"
      else ""
    IO.println (s!"run log OK: {headNames.size} file(s), {rs.length} record(s), " ++
      s!"one per (task, role, attempt){vs}")
    return 0
  for p in problems do IO.println p.render
  IO.println s!"{problems.size} run-log problem(s); see ops/runs/README.md"
  return 1

def parseArgs : List String → Option String → Option String →
    Except String (Option String × Option String)
  | [], b, h => .ok (b, h)
  | "--base" :: v :: rest, _, h => parseArgs rest (some v) h
  | "--head" :: v :: rest, b, _ => parseArgs rest b (some v)
  | a :: _, _, _ => .error s!"unknown or incomplete argument {quote a}"

def cli (args : List String) (usage : String) : IO UInt32 := do
  match parseArgs args none none with
  | .ok (b, some h) => check (b.map System.FilePath.mk) h
  | .ok (_, none) => IO.eprintln "runlog needs --head <dir>"; IO.eprintln usage; return 2
  | .error e => IO.eprintln (oneLine e); IO.eprintln usage; return 2

end MitosGate.RunLog
