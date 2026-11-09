import MitosGate.RunLog
import Std.Data.String.ToNat

/-!
# The content id (`mitos-gate content-id`)

A verdict covers a change, not a commit. When `main` moves, `update-prs.yml` rebases every open PR,
and `main`'s new run-log lines shift the context lines of each PR's own run-log hunks. So
`git diff <merge-base> <head> | git patch-id --verbatim`, the id the verdict rule used, changed on
nearly every bot rebase, and every rebase needed a new verifier (#79). The content id stays put when
only that happens, and changes on any other change.

`mitos-gate content-id <base> <head>` prints `sha256 (preimage rest runs)` as 64 hex digits. With
`mb` the one merge-base of `<base>` and `<head>`:

* `rest` is the SHA-256 of the diff from `mb` to `<head>` over every path that is not a run log
  (`isRunLog`: `ops/runs/*.ndjson`, as `.gitattributes` matches it), after `normalize` against
  each file's merge-base version. That drops each `index` line, which names the base blob, and
  writes each hunk header as `@@ <k>`. The header's line numbers and function context, which
  move when `main` adds lines above the hunk, are gone. `k` counts how many times the hunk's
  old-side lines (its context and removed lines) start earlier in the merge-base file (`occ`), so
  with that file it names the one place where the hunk applies (`occ_inj`, `normalize_pos_ne`).
  Every other line is kept byte for byte and in order, whitespace included, because Lean reads
  indentation (`kind_body`, `normalize_body`, `normalize_ne`). So a hunk that only moves keeps
  the id, as long as `main` adds no copy of the hunk's old-side lines above it
  (`occ_append_left`, `occ_append_right`, `normalize_index`), and a change in any added, removed
  or context line changes it.
* `runs` lists each run-log file the PR changes, with the lines the PR adds to it, sorted
  (`RunLog.addedSorted?`), and whether the head file ends without a newline. The change must be
  append-only, as `mitos-gate runlog` already requires
  in CI: the file is added or modified, not deleted or changed in type, it is a regular file
  (mode 100644) on both sides, and every merge-base line is still there. Otherwise the tool refuses
  and prints no id (`RunLog.addedSorted?_eq_none_iff`, `RunLog.addedSorted?_edit`). The sorted lines
  depend only on which lines the PR adds, not on where union put them among `main`'s
  (`RunLog.addedSorted?_of_perm_append`), so a union rebase keeps them
  (`RunLog.addedSorted?_union`).

The id does not depend on the caller's git config or environment. Every option that changes what
`git diff` prints is pinned (`diffArgs`, `rawArgs`), config without a flag is pinned with `-c`,
which wins over every config file and over `GIT_CONFIG_COUNT` (`gitConfig`), and the environment
variables that change a diff or the commits git reads are removed or pinned (`gitEnv`): replace
refs and grafts are off. `--text` makes every file a text diff, so neither attributes nor
`core.bigFileThreshold` can turn one into a binary patch, and the hunk lines of a binary file are
kept byte for byte like any other. The tool reads git's output as bytes (`latin1`), refuses a
line no text diff has (`kind`, `.unknown`), and checks that the patch has exactly the file blocks
`--raw` lists, in its order, with the header git prints for each path (`diffHeader`).

What the id leaves out, on purpose: the base blob of each file outside the hunks, which is
`main`'s, and so also a hunk's line numbers; and where union put the added run-log lines. So a
rebase over a `main` change elsewhere in a file keeps the id, a binary file included, where
`git patch-id` hashes a binary file's blob ids and changes. A `main` change within three lines of
a PR hunk changes the id, because the verifier read that context, and so does a `main` change
that adds a copy of a hunk's old-side lines above it, because the count moves. Both fail safe:
the head needs a new verifier.

The pure parts are proved or checked by the kernel here. The git calls, the parse of `--raw`, the
block matching, which base file a block's hunks apply to (`baseLines`) and the hashing
(`sha256sum`, as `Util.sha256`) are not proved, and the parse of a hunk header (`hunkOld`) is
checked on examples only. `gate/content-id-test.sh` runs them on scratch repositories, with each
git config variant, and replays the updater's rebases of the open PRs.
-/

namespace MitosGate.RunLog

/-! ## The lines a PR adds to a run-log file -/

/-- The lines `head` adds over `base`: `head` with one occurrence of each line of `base` removed. -/
def added : List String → List String → List String
  | [], head => head
  | b :: bs, head => added bs (head.erase b)

theorem count_added (base head : List String) (l : String) :
    (added base head).count l = head.count l - base.count l := by
  induction base generalizing head with
  | nil => simp [added]
  | cons b bs ih =>
    rw [added, ih, List.count_erase, List.count_cons]
    split <;> omega

/-- **#79's theorem.** A head that passes the append-only check is the base plus the lines `added`
names, in some order. -/
theorem appendOnly_iff_perm_added {base head : List String} :
    appendOnly base head = true ↔ head.Perm (base ++ added base head) := by
  constructor
  · intro h
    apply List.perm_iff_count.mpr
    intro l
    rw [List.count_append, count_added]
    have := appendOnly_iff_count.mp h l
    omega
  · intro h
    exact appendOnly_iff_perm_append.mpr ⟨_, h⟩

/-- The lines `added` names are the lines the PR added, whatever order they are in: the same
`added` means the same records. -/
theorem added_perm_of_perm_append {base head a : List String} (h : head.Perm (base ++ a)) :
    (added base head).Perm a := by
  apply List.perm_iff_count.mpr
  intro l
  rw [count_added, List.perm_iff_count.mp h l, List.count_append]
  omega

/-- The order the content id lists added lines in: `String`'s `≤`, a total order. -/
def sortLines (ls : List String) : List String :=
  ls.mergeSort fun a b => decide (a ≤ b)

theorem sortLines_eq_of_perm {l₁ l₂ : List String} (h : l₁.Perm l₂) :
    sortLines l₁ = sortLines l₂ := by
  have trans : ∀ a b c : String, decide (a ≤ b) = true → decide (b ≤ c) = true →
      decide (a ≤ c) = true := fun _ _ _ hab hbc =>
    decide_eq_true (String.le_trans (of_decide_eq_true hab) (of_decide_eq_true hbc))
  have total : ∀ a b : String, (decide (a ≤ b) || decide (b ≤ a)) = true := fun a b => by
    rcases String.le_total a b with h | h <;> simp [h]
  apply List.Perm.eq_of_pairwise (le := fun a b => decide (a ≤ b) = true)
  · intro a b _ _ hab hba
    exact String.le_antisymm (of_decide_eq_true hab) (of_decide_eq_true hba)
  · exact List.pairwise_mergeSort trans total _
  · exact List.pairwise_mergeSort trans total _
  · exact (List.mergeSort_perm _ _).trans (h.trans (List.mergeSort_perm _ _).symm)

/-- The lines `head` adds over `base`, sorted, or `none` when `head` is not append-only. -/
def addedSorted? (base head : List String) : Option (List String) :=
  if appendOnly base head then some (sortLines (added base head)) else none

theorem addedSorted?_eq_none_iff {base head : List String} :
    addedSorted? base head = none ↔ appendOnly base head = false := by
  unfold addedSorted?
  cases appendOnly base head <;> simp

/-- An edit to a base line, anywhere in the file, is refused. -/
theorem addedSorted?_edit (p s : List String) {l l' : String} (hne : l ≠ l') :
    addedSorted? (p ++ l :: s) (p ++ l' :: s) = none :=
  addedSorted?_eq_none_iff.mpr (appendOnly_edit p s hne)

/-- A deleted base line is refused. -/
theorem addedSorted?_delete (p s : List String) (l : String) :
    addedSorted? (p ++ l :: s) (p ++ s) = none :=
  addedSorted?_eq_none_iff.mpr (appendOnly_delete p s l)

/-- The result depends only on the lines the PR adds: a head that is the base plus `a`, in any
order, gives `a` sorted. -/
theorem addedSorted?_of_perm_append {base head a : List String} (h : head.Perm (base ++ a)) :
    addedSorted? base head = some (sortLines a) := by
  have hb : appendOnly base head = true := appendOnly_iff_perm_append.mpr ⟨a, h⟩
  simp only [addedSorted?, hb, ↓reduceIte, sortLines_eq_of_perm (added_perm_of_perm_append h)]

/-- **A union rebase keeps the run-log part of the id.** The PR's head is its merge-base `mb` plus
lines `a`; `main` is `mb` plus lines `m`. Rebasing with union gives a head that is some order of
`mb ++ a ++ m`, the model of union stated at `union_appendOnly`. Against the new merge-base,
`main`, the rebased head adds the same lines as before. -/
theorem addedSorted?_union {mb main a m head head' : List String}
    (hhead : head.Perm (mb ++ a)) (hmain : main.Perm (mb ++ m))
    (hunion : head'.Perm (mb ++ a ++ m)) :
    addedSorted? main head' = addedSorted? mb head := by
  rw [addedSorted?_of_perm_append hhead]
  apply addedSorted?_of_perm_append
  have hswap : (mb ++ a ++ m).Perm (mb ++ m ++ a) := by
    rw [List.append_assoc, List.append_assoc]
    exact List.Perm.append_left mb List.perm_append_comm
  exact hunion.trans (hswap.trans (hmain.append_right a).symm)

example : added ["A", "B"] ["A", "B", "D", "C"] = ["D", "C"] := by decide
/-- Union put `main`'s `M` between the PR's `C` and `D`. -/
example : added ["A", "B", "M"] ["A", "B", "C", "M", "D"] = ["C", "D"] := by decide
example : added ["A", "A"] ["A", "B", "A", "A"] = ["B", "A"] := by decide
example : addedSorted? ["A", "B"] ["A", "B'", "C"] = none := by decide
example : addedSorted? ["A", "B"] ["A", "C"] = none := by decide
example : addedSorted? ["A", "A"] ["A", "B"] = none := by decide

end MitosGate.RunLog

namespace MitosGate.ContentId

open RunLog (quote addedSorted? firstMissing? splitLines)

/-! ## Which paths are run logs -/

/-- `ops/runs/*.ndjson` as `.gitattributes` matches it: the files directly in `ops/runs/` whose
name ends in `.ndjson`, a name that starts with a dot and the bare `.ndjson` included. The same
set as the day files `RunLog.readTree` reads, which `mitos-gate runlog` checks. -/
def isRunLog (p : String) : Bool :=
  let cs := p.toList
  "ops/runs/".toList.isPrefixOf cs && ".ndjson".toList.isSuffixOf cs && !(cs.drop 9).contains '/'

example : isRunLog "ops/runs/2026-11-09.ndjson" = true := by decide
example : isRunLog "ops/runs/.ndjson" = true := by decide
example : isRunLog "ops/runs/.x.ndjson" = true := by decide
example : isRunLog "ops/runs/sub/x.ndjson" = false := by decide
example : isRunLog "ops/runs/README.md" = false := by decide
example : isRunLog "ops/runs.ndjson" = false := by decide
example : isRunLog "x/ops/runs/a.ndjson" = false := by decide

/-! ## The lines of the pinned diff -/

/-- The header lines `git diff` prints after `diff --git` for a text diff, apart from `index`,
`--- ` and `+++ `. With `--no-renames` and without `-B` there are no rename, copy or similarity
lines, and with `--text` no binary patch. -/
def modeHeaders : List String := ["old mode ", "new mode ", "deleted file mode ", "new file mode "]

inductive LineKind where
  /-- A hunk line: context, added or removed, or `\ No newline at end of file`. The file header
  lines `--- ` and `+++ ` also start with `-` and `+`, and are kept the same way. -/
  | body
  /-- `diff --git a/<path> b/<path>`, which starts each file's block. -/
  | diffGit
  /-- A mode header (`modeHeaders`). -/
  | mode
  /-- `index <old oid>..<new oid> [<mode>]`, which names the base blob. -/
  | index
  /-- `@@ -<line>,<n> +<line>,<n> @@ [<function>]`. -/
  | hunkHeader
  /-- Anything else: a line the pinned diff never prints. The tool refuses it. -/
  | unknown
  deriving DecidableEq, Repr

/-- What a line of the pinned diff is, read from its first characters. A hunk line starts with a
space, `+`, `-` or `\`, which no header starts with, so a hunk line is never dropped or rewritten,
whatever it holds. -/
def kind (l : String) : LineKind :=
  match l.toList with
  | ' ' :: _ | '+' :: _ | '-' :: _ | '\\' :: _ => .body
  | cs =>
    if "diff --git ".toList.isPrefixOf cs then .diffGit
    else if "index ".toList.isPrefixOf cs then .index
    else if "@@ ".toList.isPrefixOf cs then .hunkHeader
    else if modeHeaders.any (·.toList.isPrefixOf cs) then .mode
    else .unknown

/-- Every hunk line is a `body` line. -/
theorem kind_body {l : String} {c : Char} {t : List Char} (h : l.toList = c :: t)
    (hc : c = ' ' ∨ c = '+' ∨ c = '-' ∨ c = '\\') : kind l = .body := by
  unfold kind
  rw [h]
  rcases hc with rfl | rfl | rfl | rfl <;> rfl

/-! ## Where a hunk applies -/

/-- How many times the lines `o` start in `base` before line `p`, counting lines from 0. A hunk's
marker is this count for its old-side lines at its start (`hunkMarker`). -/
def occ (base o : List String) : Nat → Nat
  | 0 => 0
  | p + 1 => occ base o p + if o.isPrefixOf (base.drop p) then 1 else 0

theorem occ_mono (base o : List String) {m n : Nat} (h : m ≤ n) : occ base o m ≤ occ base o n := by
  induction n with
  | zero => rw [Nat.le_zero.mp h]; exact Nat.le_refl _
  | succ n ih =>
    rcases Nat.lt_or_eq_of_le h with h | h
    · exact Nat.le_trans (ih (Nat.le_of_lt_succ h)) (by simp only [occ]; omega)
    · rw [h]; exact Nat.le_refl _

/-- **The count names one place.** Two places in `base` where the lines `o` start have different
counts, so the base file and a hunk's marker give back where the hunk applies. -/
theorem occ_inj {base o : List String} {p p' : Nat} (hp : o.isPrefixOf (base.drop p) = true)
    (hp' : o.isPrefixOf (base.drop p') = true) (h : occ base o p = occ base o p') : p = p' := by
  rcases Nat.lt_trichotomy p p' with hlt | heq | hgt
  · have := occ_mono base o (Nat.succ_le_of_lt hlt)
    simp only [occ, hp, ↓reduceIte] at this
    omega
  · exact heq
  · have := occ_mono base o (Nat.succ_le_of_lt hgt)
    simp only [occ, hp', ↓reduceIte] at this
    omega

/-- **Lines above a hunk count only through the copies they hold.** The count at a place below the
lines `x` is the count up to the end of `x`, plus the count within the rest. So `main` may add,
remove or change lines above a hunk, and the count stays as long as the number of places in them
where `o` starts stays, as when it is 0 before and after. -/
theorem occ_append_left (x base o : List String) (p : Nat) :
    occ (x ++ base) o (x.length + p) = occ (x ++ base) o x.length + occ base o p := by
  induction p with
  | zero => rfl
  | succ p ih =>
    rw [← Nat.add_assoc, occ, ih, occ, List.drop_append, List.drop_eq_nil_of_le (by omega),
      List.nil_append, Nat.add_sub_cancel_left]
    omega

theorem isPrefixOf_append {o l y : List String} (h : o.length ≤ l.length) :
    o.isPrefixOf (l ++ y) = o.isPrefixOf l := by
  induction o generalizing l with
  | nil => simp [List.isPrefixOf]
  | cons a o ih =>
    cases l with
    | nil => simp at h
    | cons b l =>
      simp only [List.cons_append, List.isPrefixOf]
      rw [ih (by simp at h; omega)]

/-- **Lines below a hunk do not count.** Whatever follows the hunk's old-side lines `o` at place
`p`, `main` may change it and the count stays. -/
theorem occ_append_right (base y o : List String) {p : Nat} (h : p + o.length ≤ base.length) :
    occ (base ++ y) o p = occ base o p := by
  induction p with
  | zero => rfl
  | succ p ih =>
    rw [occ, occ, ih (by omega), List.drop_append_of_le_length (by omega),
      isPrefixOf_append (by simp; omega)]

theorem occ_succ' (o : List String) : ∀ (l : List String) (n : Nat),
    occ l o (n + 1) = (if o.isPrefixOf l then 1 else 0) + occ l.tail o n
  | l, 0 => by simp [occ]
  | l, n + 1 => by
    rw [occ, occ_succ' o l n, occ, List.drop_tail]
    omega

/-- `occ` in one pass over the file, as the tool runs it (`occ_eq_occTR`). -/
def occTR (base o : List String) (p : Nat) : Nat := go base p 0
where
  go : List String → Nat → Nat → Nat
    | _, 0, acc => acc
    | l, n + 1, acc => go l.tail n (if o.isPrefixOf l then acc + 1 else acc)

theorem occTR_go (o : List String) : ∀ (l : List String) (n acc : Nat),
    occTR.go o l n acc = acc + occ l o n
  | l, 0, acc => by simp [occTR.go, occ]
  | l, n + 1, acc => by
    rw [occTR.go, occTR_go o l.tail n, occ_succ']
    split <;> omega

@[csimp] theorem occ_eq_occTR : @occ = @occTR := by
  funext base o p
  simp [occTR, occTR_go]

/-! ## Hunk headers -/

/-- The number the digits at the start of `cs` write, and what follows them; `none` when `cs`
does not start with a digit. -/
def digits (cs : List Char) : Option (Nat × List Char) :=
  match cs.takeWhile Char.isDigit with
  | [] => none
  | ds => some (ds.foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0, cs.dropWhile Char.isDigit)

/-- The old side's start line and line count in a hunk header as git prints it,
`@@ -<start>[,<count>] +<start>[,<count>] @@ [<function>]`; `none` for any other line. -/
def hunkOld (h : String) : Option (Nat × Nat) :=
  match h.toList with
  | '@' :: '@' :: ' ' :: '-' :: cs =>
    match digits cs with
    | some (a, ',' :: cs) =>
      match digits cs with
      | some (b, ' ' :: '+' :: _) => some (a, b)
      | _ => none
    | some (a, ' ' :: '+' :: _) => some (a, 1)
    | _ => none
  | _ => none

example : hunkOld "@@ -3,2 +3,2 @@ theorem t" = some (3, 2) := by decide
example : hunkOld "@@ -1 +1 @@" = some (1, 1) := by decide
example : hunkOld "@@ -0,0 +1,5 @@" = some (0, 0) := by decide
example : hunkOld "@@ -120,7 +121,8 @@" = some (120, 7) := by decide
example : hunkOld "@@ -1,2 @@" = none := by decide
example : hunkOld "@@@ -1,2 -1,2 +1,3 @@@" = none := by decide

/-- Where the hunk's old side starts in the file, counting lines from 0. Git writes the line
before an empty old side, and the first line of any other. -/
def hunkStart (a b : Nat) : Nat := if b = 0 then a else a - 1

/-- A hunk's old-side lines: its context and removed lines, without their first character. -/
def oldSide (body : List String) : List String :=
  body.filterMap fun l =>
    match l.toList with
    | ' ' :: cs | '-' :: cs => some (String.ofList cs)
    | _ => none

/-- A hunk header, normalized. -/
def marker (k : Nat) : String := "@@ " ++ toString k

theorem marker_inj {k k' : Nat} (h : marker k = marker k') : k = k' := by
  have := congrArg String.toList h
  simp only [marker, String.toList_append, List.append_cancel_left_eq] at this
  exact Nat.repr_injective (String.toList_inj.mp this)

/-- A marker is never a hunk line. -/
theorem kind_marker (k : Nat) : kind (marker k) = .hunkHeader := by
  simp [kind, marker, String.toList_append, List.isPrefixOf]

/-- The marker of the hunk with header `h` and lines `body`: `@@ <k>`, with `k` the number of
times its old-side lines start before it in the merge-base file `base` (`occ`). `none` when the
header is not one git prints, or the old side is not at the place the header names. -/
def hunkMarker (base : List String) (h : String) (body : List String) : Option String :=
  match hunkOld h with
  | some (a, b) =>
    let o := oldSide body
    if o.length = b ∧ o.isPrefixOf (base.drop (hunkStart a b)) = true then
      some (marker (occ base o (hunkStart a b)))
    else none
  | none => none

/-! ## The normalized diff -/

/-- One file block of the pinned diff, normalized against the lines `base` of the file's
merge-base version: an `index` line is dropped, a hunk header becomes its marker (`hunkMarker`),
and every other line is kept as it is. `none` when a hunk header does not fit `base`. -/
def normalize (base : List String) : List String → Option (List String)
  | [] => some []
  | l :: ls =>
    match kind l with
    | .index => normalize base ls
    | .hunkHeader =>
      match hunkMarker base l (ls.takeWhile (kind · == .body)), normalize base ls with
      | some m, some r => some (m :: r)
      | _, _ => none
    | _ => (normalize base ls).map (l :: ·)

/-- `normalize` with an accumulator, as the tool runs it (`normalize_eq_normalizeTR`), so a long
block does not use one stack frame per line. -/
def normalizeTR (base ls : List String) : Option (List String) := go ls #[]
where
  go : List String → Array String → Option (List String)
    | [], acc => some acc.toList
    | l :: ls, acc =>
      match kind l with
      | .index => go ls acc
      | .hunkHeader =>
        match hunkMarker base l (ls.takeWhile (kind · == .body)) with
        | some m => go ls (acc.push m)
        | none => none
      | _ => go ls (acc.push l)

theorem normalizeTR_go (base : List String) : ∀ (ls : List String) (acc : Array String),
    normalizeTR.go base ls acc = (normalize base ls).map (acc.toList ++ ·)
  | [], acc => by simp [normalizeTR.go, normalize]
  | l :: ls, acc => by
    have ih := normalizeTR_go base ls
    cases hk : kind l <;> simp only [normalizeTR.go, normalize, hk, ih]
    case hunkHeader =>
      cases hunkMarker base l (List.takeWhile (fun x => kind x == LineKind.body) ls) <;>
        cases normalize base ls <;> simp
    all_goals (cases normalize base ls <;> simp)

@[csimp] theorem normalize_eq_normalizeTR : @normalize = @normalizeTR := by
  funext base ls
  simp [normalizeTR, normalizeTR_go]

/-- **Every hunk line is kept**, byte for byte and in order: the lines of the normalized diff
that are hunk lines are exactly the diff's hunk lines, whatever the base file. -/
theorem normalize_body {base : List String} :
    ∀ {ls out : List String}, normalize base ls = some out →
      out.filter (kind · == .body) = ls.filter (kind · == .body)
  | [], out, hn => by simp [normalize] at hn; subst hn; rfl
  | l :: ls, out, hn => by
    simp only [normalize] at hn
    split at hn
    · rename_i hk
      rw [normalize_body hn]
      simp [hk]
    · rename_i hk
      split at hn
      · rename_i m r hm hr
        simp only [Option.some.injEq] at hn
        subst hn
        have : kind m = .hunkHeader := by
          simp only [hunkMarker] at hm
          split at hm
          · split at hm
            · simp only [Option.some.injEq] at hm; subst hm; exact kind_marker _
            · simp at hm
          · simp at hm
        simp [this, hk, normalize_body hr]
      · simp at hn
    · cases hr : normalize base ls with
      | none => simp [hr] at hn
      | some r =>
        simp only [hr, Option.map_some, Option.some.injEq] at hn
        subst hn
        simp [List.filter_cons, normalize_body hr]

/-- **A change in any run of hunk lines changes the normalized diff**: the hunk lines `x` replaced
by other hunk lines `y` at one place. That covers an edit of one line, an insertion (`x = []`)
and a deletion (`y = []`), a change in whitespace alone included, and it holds whatever the two
base files are. -/
theorem normalize_ne {base base' p s x y out out' : List String}
    (hx : ∀ l ∈ x, kind l = .body) (hy : ∀ l ∈ y, kind l = .body) (hne : x ≠ y)
    (hn : normalize base (p ++ x ++ s) = some out) (hn' : normalize base' (p ++ y ++ s) = some out') :
    out ≠ out' := by
  intro heq
  have h1 := normalize_body hn
  have h2 := normalize_body hn'
  have ex : x.filter (kind · == .body) = x := List.filter_eq_self.mpr (by simpa using hx)
  have ey : y.filter (kind · == .body) = y := List.filter_eq_self.mpr (by simpa using hy)
  rw [heq, h2] at h1
  simp only [List.filter_append, ex, ey, List.append_assoc] at h1
  exact hne (List.append_cancel_right (List.append_cancel_left h1)).symm

/-- An `index` line, which names the base blob, does not count. It comes before the block's first
hunk, as git prints it. -/
theorem normalize_index {base s : List String} {i : String} (hi : kind i = .index) :
    ∀ {p : List String}, (∀ l ∈ p, kind l ≠ .hunkHeader) →
      normalize base (p ++ i :: s) = normalize base (p ++ s)
  | [], _ => by simp [normalize, hi]
  | l :: p, hp => by
    have hl := hp l (by simp)
    have ih := normalize_index (s := s) (base := base) hi (p := p) (fun l h => hp l (by simp [h]))
    simp only [List.cons_append, normalize]
    split
    · exact ih
    · contradiction
    · rw [ih]

theorem takeWhile_append_stop {f : String → Bool} {a : String} (ha : f a = false) (s : List String) :
    ∀ l : List String, (l ++ a :: s).takeWhile f = l.takeWhile f
  | [] => by simp [ha]
  | b :: l => by
    simp only [List.cons_append, List.takeWhile_cons]
    rw [takeWhile_append_stop ha s l]

theorem normalize_hunk {base s out : List String} {h : String} (hh : kind h = .hunkHeader) :
    normalize base (h :: s) = some out ↔ ∃ m r,
      hunkMarker base h (s.takeWhile (kind · == .body)) = some m ∧
      normalize base s = some r ∧ out = m :: r := by
  simp only [normalize, hh]
  split
  · rename_i m r hm hr
    constructor
    · intro h
      exact ⟨m, r, hm, hr, (Option.some.inj h).symm⟩
    · rintro ⟨m', r', hm', hr', rfl⟩
      rw [hm] at hm'
      rw [hr] at hr'
      cases hm'
      cases hr'
      rfl
  · rename_i hno
    constructor
    · intro h
      cases h
    · rintro ⟨m', r', hm', hr', rfl⟩
      exact absurd hr' (hno m' r' hm')

/-- Lines before a line that is not a hunk line normalize on their own: no hunk runs past it. -/
theorem normalize_split {base s : List String} {h : String} (hh : kind h ≠ .body) :
    ∀ {p out : List String}, normalize base (p ++ h :: s) = some out →
      ∃ a b, normalize base p = some a ∧ normalize base (h :: s) = some b ∧ out = a ++ b
  | [], out, hn => ⟨[], out, rfl, hn, rfl⟩
  | l :: p, out, hn => by
    have hstop : (kind h == LineKind.body) = false := by simp [hh]
    simp only [List.cons_append, normalize] at hn ⊢
    split at hn
    · obtain ⟨a, b, ha, hb, rfl⟩ := normalize_split hh hn
      exact ⟨a, b, ha, hb, rfl⟩
    · rw [takeWhile_append_stop hstop] at hn
      split at hn
      · rename_i m r hm hr
        obtain ⟨a, b, ha, hb, rfl⟩ := normalize_split hh hr
        simp only [Option.some.injEq] at hn
        subst hn
        refine ⟨m :: a, b, ?_, hb, rfl⟩
        simp [hm, ha]
      · simp at hn
    · cases hr : normalize base (p ++ h :: s) with
      | none => simp [hr] at hn
      | some r =>
        simp only [hr, Option.map_some, Option.some.injEq] at hn
        subst hn
        obtain ⟨a, b, ha, hb, rfl⟩ := normalize_split hh hr
        refine ⟨l :: a, b, ?_, hb, rfl⟩
        simp [ha]

/-- **Where a hunk applies is bound.** Two diffs of one base file that differ only in one hunk
header, so that the same hunk lines apply at two places, normalize differently. That holds even
when the hunk's old-side lines occur at both places, where the header's line numbers are the only
difference and `git patch-id` gives one id. -/
theorem normalize_pos_ne {base p s out out' : List String} {h h' : String} {a b a' b' : Nat}
    (hh : kind h = .hunkHeader) (hh' : kind h' = .hunkHeader)
    (ha : hunkOld h = some (a, b)) (ha' : hunkOld h' = some (a', b'))
    (hne : hunkStart a b ≠ hunkStart a' b')
    (hn : normalize base (p ++ h :: s) = some out) (hn' : normalize base (p ++ h' :: s) = some out') :
    out ≠ out' := by
  obtain ⟨x, y, hx, hy, rfl⟩ := normalize_split (by simp [hh]) hn
  obtain ⟨x', y', hx', hy', rfl⟩ := normalize_split (by simp [hh']) hn'
  rw [hx] at hx'
  cases hx'
  obtain ⟨m, r, hm, hr, rfl⟩ := (normalize_hunk hh).mp hy
  obtain ⟨m', r', hm', hr', rfl⟩ := (normalize_hunk hh').mp hy'
  rw [hr] at hr'
  cases hr'
  intro heq
  have hmm : m = m' := (List.cons.inj (List.append_cancel_left heq)).1
  subst hmm
  simp only [hunkMarker, ha, ha'] at hm hm'
  split at hm
  · rename_i c1
    split at hm'
    · rename_i c2
      exact hne (occ_inj c1.2 c2.2 (marker_inj ((Option.some.inj hm).trans (Option.some.inj hm').symm)))
    · cases hm'
  · cases hm

/-- A rebase moved this hunk down by two lines that `main` added above it, and changed the base
blob and the function context: the normalized block stays. -/
example : normalize ["a", "  exact h", "b"] ["diff --git a/A.lean b/A.lean",
      "index 1111111..2222222 100644", "--- a/A.lean", "+++ b/A.lean", "@@ -1,3 +1,3 @@ theorem t",
      " a", "-  exact h", "+  exact h'", " b"] =
    normalize ["m1", "m2", "a", "  exact h", "b"] ["diff --git a/A.lean b/A.lean",
      "index 3333333..4444444 100644", "--- a/A.lean", "+++ b/A.lean", "@@ -3,3 +3,3 @@ theorem u",
      " a", "-  exact h", "+  exact h'", " b"] := by
  decide

/-- The same hunk at the first and at the second place its lines occur, as when `main` has the
same block in two functions: two markers. -/
example : normalize ["s", "a", "x", "b", "t", "a", "x", "b"] ["@@ -2,3 +2,3 @@", " a", "-x", "+y", " b"] =
    some ["@@ 0", " a", "-x", "+y", " b"] := by
  decide
example : normalize ["s", "a", "x", "b", "t", "a", "x", "b"] ["@@ -6,3 +6,3 @@", " a", "-x", "+y", " b"] =
    some ["@@ 1", " a", "-x", "+y", " b"] := by
  decide

/-- A hunk whose old side is not at the place its header names is refused. -/
example : normalize ["a", "x", "b"] ["@@ -2,3 +2,3 @@", " a", "-x", "+y", " b"] = none := by decide

/-- The same change with one space less of indentation, which Lean reads, has another id. -/
example : normalize ["a", "  exact h"] ["@@ -1,2 +1,2 @@", " a", "-  exact h", "+  exact h'"] ≠
    normalize ["a", "  exact h"] ["@@ -1,2 +1,2 @@", " a", "-  exact h", "+ exact h'"] := by
  decide

/-- So does a change in a context line, and in a missing final newline. -/
example : normalize ["a"] ["@@ -1 +1,2 @@", " a", "+b"] ≠ normalize ["a "] ["@@ -1 +1,2 @@", " a ", "+b"] := by
  decide
example : normalize [] ["@@ -0,0 +1 @@", "+b"] ≠
    normalize [] ["@@ -0,0 +1 @@", "+b", "\\ No newline at end of file"] := by
  decide

/-- Lines the pinned diff never prints: a colored line, a binary patch, a rename, an empty line. -/
example : [kind "\x1b[1mdiff --git a/x b/x", kind "GIT binary patch", kind "Binary files a/x and b/x differ",
    kind "rename from x", kind "similarity index 90%", kind ""] =
    [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown] := by
  decide

example : [kind "diff --git a/x b/x", kind "new file mode 100644", kind "old mode 100644",
    kind "index 0000000..1111111", kind "@@ -0,0 +1 @@", kind "--- /dev/null", kind "+++ b/x"] =
    [.diffGit, .mode, .mode, .index, .hunkHeader, .body, .body] := by
  decide

/-! ## The `diff --git` line git prints for a path -/

/-- The three octal digits of a byte, as git writes them in a quoted path. -/
def octal (n : Nat) : List Char :=
  [Char.ofNat (48 + n / 64 % 8), Char.ofNat (48 + n / 8 % 8), Char.ofNat (48 + n % 8)]

/-- How git's `quote_c_style` writes one byte of a path with `core.quotePath=true`, or `none` when
the byte needs no quoting. A byte is a `Char` below 256 here (`latin1`). -/
def cEscape (c : Char) : Option (List Char) :=
  match c with
  | '\x07' => some ['\\', 'a']
  | '\x08' => some ['\\', 'b']
  | '\t' => some ['\\', 't']
  | '\n' => some ['\\', 'n']
  | '\x0b' => some ['\\', 'v']
  | '\x0c' => some ['\\', 'f']
  | '\r' => some ['\\', 'r']
  | '"' => some ['\\', '"']
  | '\\' => some ['\\', '\\']
  | c => if c.toNat < 0x20 || 0x7f ≤ c.toNat then some ('\\' :: octal c.toNat) else none

/-- A path as git prints it in a patch header: in double quotes, with `cEscape`, when any byte
needs quoting, and as it is otherwise. -/
def cQuote (s : String) : String :=
  let cs := s.toList
  if cs.any fun c => (cEscape c).isSome then
    String.ofList ('"' :: cs.flatMap (fun c => (cEscape c).getD [c]) ++ ['"'])
  else s

def diffHeader (path : String) : String :=
  "diff --git " ++ cQuote ("a/" ++ path) ++ " " ++ cQuote ("b/" ++ path)

/-- What git 2.43 prints for `néw<TAB>t"q\.txt`, its UTF-8 bytes read one per `Char`. -/
example : diffHeader "n\xC3\xA9w\tt\"q\\.txt" =
    "diff --git \"a/n\\303\\251w\\tt\\\"q\\\\.txt\" \"b/n\\303\\251w\\tt\\\"q\\\\.txt\"" := by
  decide
example : diffHeader "sp ace.txt" = "diff --git a/sp ace.txt b/sp ace.txt" := by decide
example : diffHeader "d\x7f\x01" = "diff --git \"a/d\\177\\001\" \"b/d\\177\\001\"" := by decide

/-! ## What is hashed -/

/-- A run-log file the PR changes: its path, the lines the PR adds to it, sorted, and whether the
head file ends without a newline. -/
structure RunFile where
  path : String
  lines : List String
  noEol : Bool

/-- Each changed run-log file, the lines the PR adds to it, and `noeol` when the head file ends
without a newline, so `{"b":2}` with and without a final newline gives two ids. Every path and
line is written with its length first, so no path or line can run into the next one, and only
`noeol` starts with `n`. -/
def runsText (runs : List RunFile) : String :=
  String.join <| runs.map fun f =>
    s!"file {f.path.length}:{f.path}\n" ++ String.join (f.lines.map fun l => s!"+{l.length}:{l}\n") ++
      (if f.noEol then "noeol\n" else "")

/-- The bytes the id is the SHA-256 of. `rest` is the hex SHA-256 of the normalized diff outside
the run logs. -/
def preimage (rest : String) (runs : List RunFile) : String :=
  "rest " ++ rest ++ "\nruns\n" ++ runsText runs

example : preimage "e3b0" [⟨"ops/runs/d.ndjson", ["{\"a\":1}", "x"], false⟩] =
    "rest e3b0\nruns\nfile 17:ops/runs/d.ndjson\n+7:{\"a\":1}\n+1:x\n" := by
  decide
example : preimage "e3b0" [⟨"ops/runs/d.ndjson", ["{\"b\":2}"], true⟩] =
    "rest e3b0\nruns\nfile 17:ops/runs/d.ndjson\n+7:{\"b\":2}\nnoeol\n" := by
  decide

/-! ## Running git (not proved) -/

/-- Each byte as the `Char` with the same code. Every byte string is read, a NUL or a byte that is
not UTF-8 included, and `latin1Bytes` gives the same bytes back. -/
def latin1 (b : ByteArray) : String :=
  b.foldl (fun s x => s.push (Char.ofNat x.toNat)) ""

def latin1Bytes (s : String) : ByteArray :=
  s.foldl (fun b c => b.push c.toNat.toUInt8) .empty

/-- Config that changes what `git diff` prints and has no command-line flag, or whose flag an
older git lacks. `-c` wins over every config file and over `GIT_CONFIG_COUNT`. -/
def gitConfig : List String :=
  ["core.quotePath=true", "core.attributesFile=/dev/null", "diff.noprefix=false",
    "diff.mnemonicPrefix=false", "diff.suppressBlankEmpty=false"]

/-- The environment of every git call. The variables that change a diff are removed. Replace refs
and grafts are off, so a clone's own `refs/replace/` or `info/grafts` cannot swap a commit, a tree
or a blob, or give a commit other parents. `LC_ALL=C` keeps git's messages in one language. -/
def gitEnv : Array (String × Option String) :=
  #[("GIT_DIFF_OPTS", none), ("GIT_EXTERNAL_DIFF", none), ("GIT_ATTR_SOURCE", none),
    ("GIT_NO_REPLACE_OBJECTS", some "1"), ("GIT_GRAFT_FILE", some "/dev/null"),
    ("LC_ALL", some "C")]

/-- The patch's options, each pinned to git's default where one exists, so that the config file
cannot change it. -/
def diffArgs : Array String :=
  #["diff", "--patch", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", "--text",
    "--full-index", "--diff-algorithm=myers", "--indent-heuristic", "--unified=3",
    "--inter-hunk-context=0", "--src-prefix=a/", "--dst-prefix=b/", "--no-relative",
    "--ignore-submodules=none", "--submodule=short", "-O/dev/null"]

/-- The `--raw` listing, with the same choice of files and order as `diffArgs`. -/
def rawArgs : Array String :=
  #["diff", "--raw", "-z", "--no-abbrev", "--no-color", "--no-ext-diff", "--no-textconv",
    "--no-renames", "--no-relative", "--ignore-submodules=none", "-O/dev/null"]

abbrev M := ExceptT String IO

/-- Run git with `gitConfig` and `gitEnv`, and return its standard output as bytes. -/
def git (args : Array String) : M ByteArray := do
  (← IO.getStdout).flush
  let child ← IO.Process.spawn {
    cmd := "git", args := (gitConfig.foldl (fun a c => a ++ #["-c", c]) #["--no-pager"]) ++ args
    env := gitEnv, stdin := .null, stdout := .piped, stderr := .piped }
  let out ← IO.asTask child.stdout.readBinToEnd .dedicated
  let err ← child.stderr.readBinToEnd
  let code ← child.wait
  let out ← (IO.ofExcept out.get : IO ByteArray)
  if code != 0 then
    throw s!"git {args[0]!} exited with {code}: {trim (latin1 err)}"
  return out

/-- The SHA-256 of `b` in hex, from coreutils' `sha256sum`, as `Util.sha256` computes it. -/
def sha256Hex (b : ByteArray) : IO String := do
  let child ← do
    let (stdin, child) ← (← IO.Process.spawn {
      cmd := "sha256sum", args := #["-"], stdin := .piped, stdout := .piped, stderr := .piped }).takeStdin
    stdin.write b
    stdin.flush
    pure child
  let out ← IO.asTask child.stdout.readToEnd .dedicated
  let err ← child.stderr.readToEnd
  let code ← child.wait
  let out ← IO.ofExcept out.get
  let hex := (out.splitOn " ").head!
  unless code == 0 && hex.length == 64 do
    throw <| IO.userError s!"sha256sum failed: {err}"
  return hex

/-- `<rev>` as a full commit id. A name that starts with `-` is refused, so it cannot be read as
an option. -/
def resolve (rev : String) : M String := do
  if rev.isEmpty || rev.startsWith "-" then throw s!"{quote rev} is not a revision"
  let r : Except String ByteArray ←
    (ExceptT.run (git #["rev-parse", "--verify", "--quiet", rev ++ "^{commit}"]) : IO _)
  match r with
  | .ok out => return trim (latin1 out)
  | .error _ => throw s!"{quote rev} is not a commit in this repository"

/-- One entry of `git diff --raw -z`. -/
structure Entry where
  oldMode : String
  newMode : String
  oldOid : String
  newOid : String
  status : String
  path : String

/-- Parse `:<old mode> <new mode> <old oid> <new oid> <status>` NUL `<path>` NUL, for each file. -/
def parseRaw : List String → Except String (List Entry)
  | [] | [""] => .ok []
  | info :: path :: rest =>
    match info.toList with
    | ':' :: cs =>
      match (String.ofList cs).splitOn " " with
      | [om, nm, oo, no, st] => return ⟨om, nm, oo, no, st, path⟩ :: (← parseRaw rest)
      | _ => .error s!"unexpected --raw entry {quote info}"
    | _ => .error s!"unexpected --raw entry {quote info}"
  | [x] => .error s!"unexpected end of --raw output after {quote x}"

/-- Split the patch into file blocks, each starting at a `diff --git` line. -/
def splitBlocks : List String → Except String (List (List String))
  | [] => .ok []
  | l :: ls =>
    if kind l == .diffGit then .ok (go [l] ls)
    else .error s!"the diff does not start with a diff --git line: {quote l}"
where
  /-- `cur` is the current block, reversed. -/
  go (cur : List String) : List String → List (List String)
    | [] => [cur.reverse]
    | l :: ls => if kind l == .diffGit then cur.reverse :: go [l] ls else go (l :: cur) ls

/-- A blob's bytes, one `Char` per byte. -/
def blob (oid : String) : M String :=
  return latin1 (← git #["cat-file", "blob", oid])

/-- The lines the PR adds to the run-log file `e`, sorted, or why it refuses. -/
def runLogLines (e : Entry) : M RunFile := do
  let regular := "a run-log file must be a regular file with mode 100644"
  let (base, head) ← match e.status with
    | "A" =>
      unless e.newMode == "100644" do throw s!"{quote e.path} is added with mode {e.newMode}; {regular}"
      pure ("", ← blob e.newOid)
    | "M" =>
      unless e.oldMode == "100644" && e.newMode == "100644" do
        throw s!"{quote e.path} changes mode from {e.oldMode} to {e.newMode}; {regular}"
      pure (← blob e.oldOid, ← blob e.newOid)
    | "D" => throw s!"{quote e.path} is deleted. Run-log files are append-only (ops/runs/README.md)"
    | st => throw s!"{quote e.path} changes in type (status {quote st}); {regular}"
  let (base, noEol) := (splitLines base, !head.isEmpty && !head.endsWith "\n")
  let head := splitLines head
  match addedSorted? base head with
  | some ls => return ⟨e.path, ls, noEol⟩
  | none =>
    -- `some`, by `firstMissing?_eq_none_iff` and `addedSorted?_eq_none_iff`.
    let i := (firstMissing? base head).getD 0
    throw (s!"line {i + 1} of the merge-base version of {quote e.path} is missing at the head. " ++
      "Run-log lines are append-only: a line already on the base branch may not be edited or " ++
      "deleted (ops/runs/README.md)")

/-- The lines of the file a block's hunks apply to: none when the block adds the file, the line
`--submodule=short` prints for a submodule, and the merge-base blob's lines otherwise. -/
def baseLines (e : Entry) (blk : List String) : M (List String) := do
  if blk.any (·.startsWith "new file mode ") then return []
  if e.oldMode == "160000" then return [s!"Subproject commit {e.oldOid}"]
  return splitLines (← blob e.oldOid)

structure Result where
  mergeBase : String
  rest : String
  restFiles : Nat
  runs : List RunFile
  id : String

/-- The content id of `head` against `base`. -/
def compute (base head : String) : M Result := do
  let b ← resolve base
  let h ← resolve head
  -- `git merge-base` exits 1 when there is none.
  let r : Except String ByteArray ← (ExceptT.run (git #["merge-base", "--all", b, h]) : IO _)
  let mb ← match r.map (splitLines ∘ latin1) with
    | .ok [mb] => pure mb
    | .ok [] => throw "the two commits have no merge-base"
    | .error e => throw s!"the two commits have no merge-base ({e})"
    | .ok _ => throw "the two commits have more than one merge-base"
  let entries ← ExceptT.mk (pure (parseRaw ((latin1 (← git (rawArgs ++ #[mb, h]))).splitOn "\x00")))
  let patch := splitLines (latin1 (← git (diffArgs ++ #[mb, h])))
  if let some i := patch.findIdx? (kind · == .unknown) then
    throw s!"line {i + 1} of the diff is not a line of a text diff: {quote patch[i]!}"
  let mut left ← ExceptT.mk (pure (splitBlocks patch))
  let mut rest : Array String := #[]
  let mut restFiles := 0
  let mut runs : Array RunFile := #[]
  for e in entries do
    -- A change of type (file, symlink, submodule) is two blocks: a deletion and an addition.
    let n := if e.status == "T" then 2 else 1
    let mine := left.take n
    left := left.drop n
    unless mine.length == n && mine.all (·.head? == some (diffHeader e.path)) do
      throw s!"the diff and the --raw listing disagree at {quote e.path}"
    if isRunLog e.path then
      runs := runs.push (← runLogLines e)
    else
      restFiles := restFiles + 1
      for blk in mine do
        let fileBase ← if blk.any (kind · == .hunkHeader) then baseLines e blk else pure []
        match normalize fileBase blk with
        | some ls => rest := rest ++ ls.toArray
        | none => throw s!"a hunk of {quote e.path} does not fit the merge-base version of the file"
  unless left.isEmpty do throw "the diff has a file block that the --raw listing does not have"
  let restHex ← sha256Hex (latin1Bytes (String.join (rest.toList.map (· ++ "\n"))))
  let id ← sha256Hex (latin1Bytes (preimage restHex runs.toList))
  return { mergeBase := mb, rest := restHex, restFiles, runs := runs.toList, id }

/-- A line for a CI log: `oneLine`, and the legacy workflow-command marker `##[`, which GitHub's
runner reads anywhere in a line, written with `oneLine`'s escape for its `[` (#68). Every line
`cli` prints starts with a fixed word, so none starts with `::`. -/
def logLine (s : String) : String :=
  (oneLine s).replace "##[" "##\\u{005B}"

/-- `mitos-gate content-id <base> <head> [--verbose]`. Prints the id on standard output, exit 0;
or one line on standard error, through `logLine`, with exit 1 when it refuses and 2 on a usage
error. `--verbose` also prints the merge-base, the `rest` digest and the run-log files with their
counts of added lines, and whether each ends without a newline, on standard error. -/
def cli (args : List String) (usage : String) : IO UInt32 := do
  let verbose := args.contains "--verbose"
  match args.filter (· != "--verbose") with
  | [base, head] =>
    try
      match ← (compute base head).run with
      | .ok r =>
        if verbose then
          IO.eprintln s!"merge-base {r.mergeBase}"
          IO.eprintln s!"rest {r.rest} ({r.restFiles} file(s) outside the run logs)"
          for f in r.runs do
            let eol := if f.noEol then ", no newline at end of file" else ""
            IO.eprintln (logLine s!"runs {quote f.path (max := 200)}: {f.lines.length} added line(s){eol}")
        IO.println r.id
        return 0
      | .error e =>
        IO.eprintln (logLine s!"content-id refused: {e}")
        return 1
    catch e =>
      IO.eprintln (logLine s!"content-id stopped on an I/O error: {e}")
      return 1
  | _ =>
    IO.eprintln "content-id needs <base> <head>"
    IO.eprintln usage
    return 2

end MitosGate.ContentId
