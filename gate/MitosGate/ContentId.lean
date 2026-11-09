import MitosGate.RunLog

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
  (`isRunLog`: `ops/runs/*.ndjson`, as `.gitattributes` matches it), after `normalize`. That drops
  each `index` line, which names the base blob, and each hunk header's line numbers and function
  context, which move when `main` adds lines above the hunk. Every other line is kept byte for
  byte, whitespace included, because Lean reads indentation (`kind_body`, `normLine_body`,
  `normalize_ne`). So a hunk that only moves keeps the id (`normalize_hunkHeader`,
  `normalize_index`), and a change in any added, removed or context line changes it.
* `runs` lists each run-log file the PR changes, with the lines the PR adds to it, sorted
  (`RunLog.addedSorted?`). The change must be append-only, as `mitos-gate runlog` already requires
  in CI: the file is added or modified, not deleted or changed in type, it is a regular file
  (mode 100644) on both sides, and every merge-base line is still there. Otherwise the tool refuses
  and prints no id (`RunLog.addedSorted?_eq_none_iff`, `RunLog.addedSorted?_edit`). The sorted lines
  depend only on which lines the PR adds, not on where union put them among `main`'s
  (`RunLog.addedSorted?_of_perm_append`), so a union rebase keeps them
  (`RunLog.addedSorted?_union`).

The id does not depend on the caller's git config or environment. Every option that changes what
`git diff` prints is pinned (`diffArgs`, `rawArgs`), config without a flag is pinned with `-c`,
which wins over every config file and over `GIT_CONFIG_COUNT` (`gitConfig`), and the environment
variables that change a diff are removed (`gitEnv`). `--text` makes every file a text diff, so
neither attributes nor `core.bigFileThreshold` can turn one into a binary patch, and a binary file
is bound byte for byte. The tool reads git's output as bytes (`latin1`), refuses a line no text
diff has (`kind`, `.unknown`), and checks that the patch has exactly the file blocks `--raw`
lists, in its order, with the header git prints for each path (`diffHeader`).

What the id leaves out, on purpose: where in a file a hunk sits, as `git patch-id` also leaves it
out, so the same hunk with the same three context lines moved elsewhere in the same file keeps the
id; the base blob of each file, which is `main`'s; and where union put the added run-log lines.
A `main` change within three lines of a PR hunk changes the id, because the verifier read that
context.

The pure parts are proved or checked by the kernel here. The git calls, the parse of `--raw`, the
block matching and the hashing (`sha256sum`, as `Util.sha256`) are not proved;
`gate/content-id-test.sh` runs them on scratch repositories, with each git config variant, and
replays the heads of #79.
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
set as `RunLog.ndjsonNames`, which `mitos-gate runlog` reads. -/
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

/-- One line, normalized: an `index` line is dropped, a hunk header becomes `@@`, which keeps
where one hunk ends and the next begins, and every other line is kept as it is. -/
def normLine (l : String) : Option String :=
  match kind l with
  | .index => none
  | .hunkHeader => some "@@"
  | _ => some l

def normalize (ls : List String) : List String := ls.filterMap normLine

theorem normLine_body {l : String} (h : kind l = .body) : normLine l = some l := by
  simp [normLine, h]

/-- **A change in any hunk line changes the normalized diff**, a change in whitespace alone
included. -/
theorem normalize_ne (p s : List String) {l l' : String} (hl : kind l = .body)
    (hl' : kind l' = .body) (hne : l ≠ l') : normalize (p ++ l :: s) ≠ normalize (p ++ l' :: s) := by
  intro h
  simp only [normalize, List.filterMap_append, List.filterMap_cons_some (normLine_body hl),
    List.filterMap_cons_some (normLine_body hl')] at h
  exact hne (List.cons.inj (List.append_cancel_left h)).1

/-- A hunk that only moves, so that only its header's line numbers or function context change,
keeps the normalized diff. -/
theorem normalize_hunkHeader (p s : List String) {h h' : String} (hh : kind h = .hunkHeader)
    (hh' : kind h' = .hunkHeader) : normalize (p ++ h :: s) = normalize (p ++ h' :: s) := by
  simp [normalize, List.filterMap_append, normLine, hh, hh']

/-- An `index` line, which names the base blob, does not count. -/
theorem normalize_index (p s : List String) {i : String} (hi : kind i = .index) :
    normalize (p ++ i :: s) = normalize (p ++ s) := by
  simp [normalize, List.filterMap_append, normLine, hi]

/-- A rebase moved this hunk down by 40 lines, and `main` changed the base blob. -/
example : normalize ["diff --git a/A.lean b/A.lean", "index 1111111..2222222 100644",
      "--- a/A.lean", "+++ b/A.lean", "@@ -3,2 +3,2 @@ theorem t", " a", "-  exact h", "+  exact h'"] =
    normalize ["diff --git a/A.lean b/A.lean", "index 3333333..4444444 100644",
      "--- a/A.lean", "+++ b/A.lean", "@@ -43,2 +43,2 @@ theorem t", " a", "-  exact h",
      "+  exact h'"] := by
  decide

/-- The same change with one space less of indentation, which Lean reads, has another id. -/
example : normalize ["@@ -3,2 +3,2 @@", " a", "-  exact h", "+  exact h'"] ≠
    normalize ["@@ -3,2 +3,2 @@", " a", "-  exact h", "+ exact h'"] := by
  decide

/-- So does a change in a context line, and in a missing final newline. -/
example : normalize ["@@ -3,2 +3,2 @@", " a", "+b"] ≠ normalize ["@@ -3,2 +3,2 @@", " a ", "+b"] := by
  decide
example : normalize ["@@ -1 +1 @@", "+b"] ≠
    normalize ["@@ -1 +1 @@", "+b", "\\ No newline at end of file"] := by
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

/-- Each changed run-log file and the lines the PR adds to it. Every path and line is written with
its length first, so no path or line can run into the next one. -/
def runsText (runs : List (String × List String)) : String :=
  String.join <| runs.map fun (p, ls) =>
    s!"file {p.length}:{p}\n" ++ String.join (ls.map fun l => s!"+{l.length}:{l}\n")

/-- The bytes the id is the SHA-256 of. `rest` is the hex SHA-256 of the normalized diff outside
the run logs. -/
def preimage (rest : String) (runs : List (String × List String)) : String :=
  "rest " ++ rest ++ "\nruns\n" ++ runsText runs

example : preimage "e3b0" [("ops/runs/d.ndjson", ["{\"a\":1}", "x"])] =
    "rest e3b0\nruns\nfile 17:ops/runs/d.ndjson\n+7:{\"a\":1}\n+1:x\n" := by
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

/-- Environment variables that change a diff, removed for every git call; `LC_ALL=C` keeps git's
messages in one language. -/
def gitEnv : Array (String × Option String) :=
  #[("GIT_DIFF_OPTS", none), ("GIT_EXTERNAL_DIFF", none), ("GIT_ATTR_SOURCE", none),
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

/-- The lines the PR adds to the run-log file `e`, sorted, or why it refuses. -/
def runLogLines (e : Entry) : M (List String) := do
  let read (oid : String) : M (List String) := do
    return splitLines (latin1 (← git #["cat-file", "blob", oid]))
  let regular := "a run-log file must be a regular file with mode 100644"
  let (base, head) ← match e.status with
    | "A" =>
      unless e.newMode == "100644" do throw s!"{quote e.path} is added with mode {e.newMode}; {regular}"
      pure ([], ← read e.newOid)
    | "M" =>
      unless e.oldMode == "100644" && e.newMode == "100644" do
        throw s!"{quote e.path} changes mode from {e.oldMode} to {e.newMode}; {regular}"
      pure (← read e.oldOid, ← read e.newOid)
    | "D" => throw s!"{quote e.path} is deleted. Run-log files are append-only (ops/runs/README.md)"
    | st => throw s!"{quote e.path} changes in type (status {quote st}); {regular}"
  match addedSorted? base head with
  | some ls => return ls
  | none =>
    -- `some`, by `firstMissing?_eq_none_iff` and `addedSorted?_eq_none_iff`.
    let i := (firstMissing? base head).getD 0
    throw (s!"line {i + 1} of the merge-base version of {quote e.path} is missing at the head. " ++
      "Run-log lines are append-only: a line already on the base branch may not be edited or " ++
      "deleted (ops/runs/README.md)")

structure Result where
  mergeBase : String
  rest : String
  restFiles : Nat
  runs : List (String × List String)
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
  let mut runs : Array (String × List String) := #[]
  for e in entries do
    -- A change of type (file, symlink, submodule) is two blocks: a deletion and an addition.
    let n := if e.status == "T" then 2 else 1
    let mine := left.take n
    left := left.drop n
    unless mine.length == n && mine.all (·.head? == some (diffHeader e.path)) do
      throw s!"the diff and the --raw listing disagree at {quote e.path}"
    if isRunLog e.path then
      runs := runs.push (e.path, ← runLogLines e)
    else
      restFiles := restFiles + 1
      for blk in mine do rest := rest ++ (normalize blk).toArray
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
counts of added lines on standard error. -/
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
          for (p, ls) in r.runs do
            IO.eprintln (logLine s!"runs {quote p (max := 200)}: {ls.length} added line(s)")
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
