namespace MitosGate

/-- Run `cmd` and return its exit code and output. Standard output is flushed first: a child that
fails to start would otherwise write the gate's buffered lines into the output it returns. -/
def run (cmd : String) (args : Array String) (cwd : Option System.FilePath := none)
    (stdin : Option String := none) : IO (UInt32 × String) := do
  (← IO.getStdout).flush
  let out ← IO.Process.output { cmd, args, cwd } stdin
  return (out.exitCode, out.stdout ++ out.stderr)

def leanFiles (dir : System.FilePath) : IO (Array System.FilePath) := do
  if !(← dir.isDir) then return #[]
  let fs ← dir.walkDir
  let fs := fs.filter (·.extension == some "lean")
  return fs.qsort (·.toString < ·.toString)

def copyFile (src dst : System.FilePath) : IO Unit := do
  if let some p := dst.parent then IO.FS.createDirAll p
  IO.FS.writeBinFile dst (← IO.FS.readBinFile src)

def copyLeanTree (src dst : System.FilePath) : IO Unit := do
  for f in ← leanFiles src do
    let rel := (f.toString.drop (src.toString.length + 1)).toString
    copyFile f (dst / rel)

def sha256 (s : String) : IO String := do
  let (code, out) ← run "sha256sum" #["-"] none (some s)
  if code != 0 then throw <| IO.userError s!"sha256sum failed: {out}"
  return (out.splitOn " ").head!

def trim (s : String) : String := (s.trimAscii).toString

/-! ## Printing untrusted text on one line -/

/-- Code point ranges, beyond printable ASCII, that print as themselves on one line: letters,
digits, punctuation and symbols from the scripts Lean's messages and file names use. None holds a
control, a line or paragraph separator, a bidi or other format character, a combining mark, a
right-to-left letter, a non-ASCII space, a blank filler or a private-use code point. -/
def printableRanges : List (Nat × Nat) :=
  [ (0x00A1, 0x00AC), (0x00AE, 0x02FF),                     -- Latin-1 (no NBSP, soft hyphen) to modifiers
    (0x0370, 0x03FF), (0x0400, 0x0482), (0x048A, 0x04FF),   -- Greek, Cyrillic (no combining marks)
    (0x1D00, 0x1DBF), (0x1E00, 0x1FFF),                     -- phonetic, Latin and Greek extended
    (0x2010, 0x2027), (0x2030, 0x205E),                     -- punctuation (no spaces, U+2028–U+202F, U+205F–U+206F)
    (0x2070, 0x20CF), (0x2100, 0x27FF),                     -- super/subscripts, currency, symbols, math, arrows
    (0x2801, 0x2BFF), (0x2C60, 0x2C7F),                     -- braille (not the blank U+2800), arrows, math, Latin Ext-C
    (0x2E00, 0x2E7F), (0x3001, 0x3029), (0x3030, 0x303F),   -- supplemental punctuation, CJK symbols
    (0x3041, 0x3096), (0x309B, 0x30FF), (0x4E00, 0x9FFF),   -- kana, CJK ideographs
    (0xAC00, 0xD7A3), (0xFF01, 0xFF9F), (0xFFA1, 0xFFEE),   -- Hangul, full- and halfwidth forms (no filler)
    (0x1D400, 0x1D7FF), (0x1F300, 0x1FAFF) ]                -- math alphanumerics, pictographs

/-- Whether `c` is printed as itself by `oneLine`: printable ASCII other than `\`, or a code point
in `printableRanges`. This is an allowlist: every other code point is escaped. -/
def printable (c : Char) : Bool :=
  let n := c.toNat
  (0x20 ≤ n && n ≤ 0x7E && n != 0x5C) || printableRanges.any fun (lo, hi) => lo ≤ n && n ≤ hi

/-- The hexadecimal digit `d` (below 16), upper case. -/
def hexDigit (d : Nat) : Char :=
  if d < 10 then Char.ofNat (48 + d) else Char.ofNat (55 + d)

/-- `n` in upper-case hexadecimal, four digits, or six beyond the Basic Multilingual Plane. -/
def hexDigits (n : Nat) : List Char :=
  ((List.range (if n < 0x10000 then 4 else 6)).reverse).map fun i => hexDigit (n / 16 ^ i % 16)

/-- `c` written as the escape `\u{XXXX}`, whether or not it is printable. -/
def escape (c : Char) : List Char := ['\\', 'u', '{'] ++ hexDigits c.toNat ++ ['}']

/-- `c` itself if it is printable, otherwise `\u{XXXX}`. -/
def escapeChar (c : Char) : List Char :=
  if printable c then [c] else escape c

/-- Text from the workspace, Lean or the comparator, made safe to print: every code point outside
the `printable` allowlist is written as `\u{XXXX}`. So the text stays on one line and cannot move
the cursor, reorder what follows or start a line of its own, such as a forged `VERDICT:`; and since
`\` is escaped too, each output stands for one input (`unescape_oneLine`). A line bound for a CI
log goes through `ciLine` instead, which also keeps it from starting a workflow command. -/
def oneLine (s : String) : String :=
  String.ofList (s.toList.flatMap escapeChar)

/-- The code points an escape is made of. -/
def escapeAlphabet : List Char := "\\u{}0123456789ABCDEF".toList

theorem hexDigit_mem {d : Nat} (h : d < 16) : hexDigit d ∈ escapeAlphabet := by
  revert d; decide

theorem mem_escape {c x : Char} (h : x ∈ escape c) : x ∈ escapeAlphabet := by
  simp only [escape, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at h
  rcases h with ((rfl | rfl | rfl) | hd) | rfl
  · decide
  · decide
  · decide
  · simp only [hexDigits, List.mem_map] at hd
    obtain ⟨i, -, rfl⟩ := hd
    exact hexDigit_mem (Nat.mod_lt _ (by decide))
  · decide

theorem escapeAlphabet_printable : ∀ x ∈ escapeAlphabet, printable x = true ∨ x = '\\' := by
  decide

theorem escapeChar_printable (c : Char) :
    ∀ x ∈ escapeChar c, printable x = true ∨ x = '\\' := by
  intro x hx
  unfold escapeChar at hx
  split at hx
  · rename_i hp
    simp only [List.mem_singleton] at hx
    exact .inl (hx ▸ hp)
  · exact escapeAlphabet_printable x (mem_escape hx)

/-- `oneLine` prints only allowlisted code points, and `\` to start an escape. -/
theorem oneLine_printable (s : String) :
    ∀ c ∈ (oneLine s).toList, printable c = true ∨ c = '\\' := by
  intro c hc
  simp only [oneLine, String.toList_ofList, List.mem_flatMap] at hc
  obtain ⟨a, -, ha⟩ := hc
  exact escapeChar_printable a c ha

/-- What a hostile file name or message may contain to break a line, move the cursor, reorder the
text or hide in it: C0 and C1 controls (newline, carriage return, escape, NEL, CSI), DEL, the
no-break space, the soft hyphen, the line and paragraph separators, bidi embeddings, overrides,
isolates and marks, zero-width and other format characters, a private-use code point, a combining
mark, and the blank fillers (Hangul choseong, jungseong, compatibility and halfwidth fillers, and
the braille blank). Written as escapes so that each entry is visible in review. -/
def unsafeSamples : List Char :=
  [ '\x00', '\t', '\n', '\x0b', '\x0c', '\r', '\x1b', '\x7f', '\u0080', '\u0085', '\u009b',
    '\u009f', '\u00a0', '\u00ad', '\u061c', '\u200b', '\u200d', '\u200e', '\u200f', '\u2028',
    '\u2029', '\u202a', '\u202b', '\u202c', '\u202d', '\u202e', '\u2066', '\u2067', '\u2068',
    '\u2069', '\ufeff', '\ue000', '\u0301', '\u115f', '\u1160', '\u3164', '\uffa0', '\u2800' ]

theorem unsafeSamples_escaped : ∀ c ∈ unsafeSamples, printable c = false := by decide

example : oneLine "Models/Ev\u0085il ‮VERDICT: ACCEPTED\u009b31m.lean" =
    "Models/Ev\\u{0085}il\\u{2028}\\u{202E}VERDICT: ACCEPTED\\u{009B}31m.lean" := by decide

example : oneLine "a\nVERDICT: ACCEPTED" = "a\\u{000A}VERDICT: ACCEPTED" := by decide

/-- A zero-width space, a zero-width joiner, a soft hyphen and the braille blank are escaped; the
braille pattern next to the blank prints as itself. -/
example : oneLine "a\u200bb\u200dc\u00add\u2800e\u2801" =
    "a\\u{200B}b\\u{200D}c\\u{00AD}d\\u{2800}e\u2801" := by decide

example : oneLine "∀ x ∈ s, x ≤ é ⊢ «foo» → ℕ" = "∀ x ∈ s, x ≤ é ⊢ «foo» → ℕ" := by decide

/-! ## Reading printed text back

`unescape` is how a reader decodes what `oneLine` and `ciLine` print: each `\u{…}` stands for the
code point with that hexadecimal number, and every other code point for itself. It gives back the
original text (`unescape_oneLine`, `unescape_ciLine`), so the escapes lose nothing, and two texts
never print alike. -/

/-- The value of a digit `hexDigit` writes. -/
def hexVal (d : Char) : Nat := if d.toNat < 58 then d.toNat - 48 else d.toNat - 55

/-- The number that the hexadecimal digits `ds` write, most significant first. -/
def ofHex (ds : List Char) : Nat := ds.foldl (fun n d => 16 * n + hexVal d) 0

/-- `unescape`, from a state: `none` outside an escape, or `some (k, ds)` inside one, with `k` code
points of `u{` still to pass and the digits `ds` read so far. -/
def unescapeFrom : Option (Nat × List Char) → List Char → List Char
  | _, [] => []
  | none, c :: l => if c = '\\' then unescapeFrom (some (2, [])) l else c :: unescapeFrom none l
  | some (k + 1, ds), _ :: l => unescapeFrom (some (k, ds)) l
  | some (0, ds), c :: l =>
    if c = '}' then Char.ofNat (ofHex ds) :: unescapeFrom none l
    else unescapeFrom (some (0, ds ++ [c])) l

def unescape (l : List Char) : List Char := unescapeFrom none l

theorem hexVal_hexDigit {d : Nat} (h : d < 16) : hexVal (hexDigit d) = d := by
  revert d; decide

theorem hexDigit_ne_brace {d : Nat} (h : d < 16) : hexDigit d ≠ '}' := by
  revert d; decide

theorem toNat_lt_char (c : Char) : c.toNat < 0x110000 := by
  have h := c.valid
  simp only [UInt32.isValidChar, Nat.isValidChar] at h
  show c.val.toNat < 0x110000
  omega

theorem ofHex_hexDigits {n : Nat} (h : n < 0x1000000) : ofHex (hexDigits n) = n := by
  unfold hexDigits
  split
  · simp only [List.range, List.range.loop, List.reverse_cons, List.reverse_nil, List.nil_append,
      List.cons_append, List.map_cons, List.map_nil, ofHex, List.foldl_cons, List.foldl_nil,
      hexVal_hexDigit (Nat.mod_lt _ (by decide : 16 > 0)), Nat.pow_zero, Nat.pow_succ]
    omega
  · simp only [List.range, List.range.loop, List.reverse_cons, List.reverse_nil, List.nil_append,
      List.cons_append, List.map_cons, List.map_nil, ofHex, List.foldl_cons, List.foldl_nil,
      hexVal_hexDigit (Nat.mod_lt _ (by decide : 16 > 0)), Nat.pow_zero, Nat.pow_succ]
    omega

theorem unescape_cons {c : Char} (h : c ≠ '\\') (l : List Char) :
    unescape (c :: l) = c :: unescape l := by
  simp [unescape, unescapeFrom, h]

theorem unescapeFrom_digits {ds : List Char} (h : ∀ d ∈ ds, d ≠ '}') (acc l : List Char) :
    unescapeFrom (some (0, acc)) (ds ++ '}' :: l) =
      Char.ofNat (ofHex (acc ++ ds)) :: unescape l := by
  induction ds generalizing acc with
  | nil => simp [unescapeFrom, unescape]
  | cons d ds ih =>
    have hd : d ≠ '}' := h d (List.mem_cons_self ..)
    simp only [List.cons_append, unescapeFrom, hd, ↓reduceIte]
    rw [ih (fun x hx => h x (List.mem_cons_of_mem _ hx))]
    simp

theorem unescape_escape (c : Char) (l : List Char) :
    unescape (escape c ++ l) = c :: unescape l := by
  have hd : ∀ d ∈ hexDigits c.toNat, d ≠ '}' := by
    intro d hd
    simp only [hexDigits, List.mem_map] at hd
    obtain ⟨i, -, rfl⟩ := hd
    exact hexDigit_ne_brace (Nat.mod_lt _ (by decide))
  have hc : c.toNat < 0x1000000 := Nat.lt_trans (toNat_lt_char c) (by decide)
  simp only [escape, unescape, List.append_assoc, List.cons_append, List.nil_append, unescapeFrom,
    ↓reduceIte]
  rw [unescapeFrom_digits hd, List.nil_append, ofHex_hexDigits hc, Char.ofNat_toNat]
  rfl

theorem unescape_escapeChar (c : Char) (l : List Char) :
    unescape (escapeChar c ++ l) = c :: unescape l := by
  unfold escapeChar
  split
  · rename_i hp
    have : c ≠ '\\' := by rintro rfl; exact absurd hp (by decide)
    exact unescape_cons this l
  · exact unescape_escape c l

/-- `oneLine` loses nothing: a reader decodes what it prints back to the original text. -/
theorem unescape_oneLine (s : String) : unescape (oneLine s).toList = s.toList := by
  simp only [oneLine, String.toList_ofList]
  induction s.toList with
  | nil => rfl
  | cons c l ih => rw [List.flatMap_cons, unescape_escapeChar, ih]

theorem oneLine_injective {s t : String} (h : oneLine s = oneLine t) : s = t :=
  String.toList_injective (by rw [← unescape_oneLine s, ← unescape_oneLine t, h])

/-! ## Lines for a CI log

GitHub's runner reads every line a step prints, on standard output or standard error, as a possible
workflow command. `ActionCommandManager.TryProcessCommand` tries two parsers, in this order
(actions/runner, `src/Runner.Common/ActionCommand.cs`):

* `TryParseV2` removes the line's leading white space with `String.TrimStart()` and reads a command
  when what is left starts with `::`.
* `TryParse`, the legacy form, reads one when `##[` occurs anywhere in the line.

Either then needs a known command name right after the marker, such as `warning` or `add-mask`. A
forged command can add an annotation, mask a word in the rest of the log, or stop the runner from
reading commands. The runner splits lines at LF and CR. `startsCommand` models both parsers, and
`ciLine` writes text so that neither can read it (`ciLine_not_startsCommand`).

Assumption: the model and the proofs hold for the runner's parsers read as ordinal, which is how
they behave under the invariant and en-US cultures. The runner matches `::` and `##[` with .NET's
culture-sensitive `StartsWith` and `IndexOf`, and under other cultures that matches more lines:
under ja-JP a line that starts with a fullwidth colon (U+FF1A) before `:warning::` reads as a
command, and under th-TH, which ignores punctuation, `abcwarning]x` reads as a legacy command. A
self-hosted runner with such a culture is out of scope. The culture of a GitHub-hosted runner is
inferred to be en-US or invariant, not logged. `oneLine` also escapes the controls and format
characters, such as U+200B, that the matching can skip. -/

/-- The code points .NET's `char.IsWhiteSpace` accepts, which `String.TrimStart()` removes:
U+0009–U+000D, U+0085, and the space, line and paragraph separators (Unicode categories Zs, Zl and
Zp). -/
def runnerBlanks : List Nat :=
  [ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
    0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
    0x3000 ]

def runnerBlank (c : Char) : Bool := runnerBlanks.contains c.toNat

/-- The runner reads the line `s` as a workflow command, or would with a known command name after
the marker: after its leading blanks it starts with `::`, or it holds `##[`. -/
def startsCommand (s : String) : Prop :=
  [':', ':'] <+: s.toList.dropWhile runnerBlank ∨ ['#', '#', '['] <:+: s.toList

instance : DecidablePred startsCommand := fun _ => inferInstanceAs (Decidable (_ ∨ _))

/-- `ciLine` after a line's leading spaces: each code point as `oneLine` writes it, except that a
`[` right after `##` is written `\u{005B}`. `n` counts the `#`s just written. -/
def ciRest : Nat → List Char → List Char
  | _, [] => []
  | n, c :: l =>
    if c = '[' ∧ 2 ≤ n then escape c ++ ciRest 0 l
    else escapeChar c ++ ciRest (if c = '#' then n + 1 else 0) l

/-- `ciLine` on code points: leading spaces as they are, then a `:` that would come first is
written `\u{003A}`, then `ciRest`. -/
def ciChars : List Char → List Char
  | [] => []
  | c :: l =>
    if c = ' ' then c :: ciChars l
    else if c = ':' then escape c ++ ciRest 0 l
    else ciRest 0 (c :: l)

/-- **A line for a CI log.** Every line the gate prints that holds text from the workspace, Lean,
the comparator, a file or the invoker's arguments goes through `ciLine` as a whole, trusted words
and all. It writes the text as `oneLine` does, with two more escapes: a `[` right after `##` is
written `\u{005B}`, and a `:` that would come first after the leading spaces is written `\u{003A}`.
Those two are what the runner's parsers look for, and the escapes keep them from firing
(`ciLine_not_startsCommand`). The line stays on one line (`ciLine_no_break`) and holds only
`oneLine`'s code points (`ciLine_printable`), and a reader decodes it back to the original text
(`unescape_ciLine`). A Lean array `#[1, 2]` and a `::` after the start print as themselves. -/
def ciLine (s : String) : String := String.ofList (ciChars s.toList)

/-- Whether `##[` occurs in `l`, as a function to compute with: see `hasLegacy_iff`. -/
def hasLegacy : List Char → Bool
  | [] => false
  | a :: l => (a == '#' && l.take 2 == ['#', '[']) || hasLegacy l

theorem hasLegacy_iff {l : List Char} : hasLegacy l = true ↔ ['#', '#', '['] <:+: l := by
  induction l with
  | nil => simp [hasLegacy]
  | cons a l ih =>
    rw [hasLegacy, List.infix_cons_iff, ← ih, List.cons_prefix_cons, List.prefix_iff_eq_take]
    show _ ↔ ('#' = a ∧ ['#', '['] = l.take 2) ∨ _
    rw [@eq_comm _ '#' a, @eq_comm _ ['#', '['] (l.take 2)]
    simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq]

theorem hasLegacy_append {p : List Char} (h : ∀ x ∈ p, x ≠ '#') (l : List Char) :
    hasLegacy (p ++ l) = hasLegacy l := by
  induction p with
  | nil => rfl
  | cons a p ih =>
    have ha : a ≠ '#' := h a (List.mem_cons_self ..)
    simp [hasLegacy, ha, ih (fun x hx => h x (List.mem_cons_of_mem _ hx))]

theorem hasLegacy_replicate (n : Nat) : hasLegacy (List.replicate n '#') = false := by
  induction n with
  | zero => rfl
  | succ n ih =>
    rw [List.replicate_succ, hasLegacy, ih]
    rcases n with _ | _ | n <;> simp [List.replicate_succ]

/-- After the `#`s just written, a code point other than `#` starts no `##[`, unless it is a `[`
after two of them. -/
theorem hasLegacy_hashes (n : Nat) {c : Char} (hc : c ≠ '#') (hb : c = '[' → n < 2)
    (l : List Char) : hasLegacy (List.replicate n '#' ++ c :: l) = hasLegacy l := by
  induction n with
  | zero => simp [hasLegacy, hc]
  | succ n ih =>
    rw [List.replicate_succ, List.cons_append, hasLegacy, ih (fun h => by have := hb h; omega)]
    have : (List.replicate n '#' ++ c :: l).take 2 ≠ ['#', '['] := by
      rcases n with _ | _ | n
      · simp [hc]
      · intro h
        simp at h
        have := hb h
        omega
      · simp [List.replicate_succ]
    simp [this]

theorem escapeAlphabet_safe : ∀ x ∈ escapeAlphabet, x ≠ '#' ∧ runnerBlank x = false := by
  decide

theorem hasLegacy_escape (n : Nat) (c : Char) (l : List Char) :
    hasLegacy (List.replicate n '#' ++ (escape c ++ l)) = hasLegacy l := by
  show hasLegacy (List.replicate n '#' ++ '\\' :: ((escape c).tail ++ l)) = _
  rw [hasLegacy_hashes n (by decide) (fun h => absurd h (by decide)), hasLegacy_append]
  intro x hx
  exact (escapeAlphabet_safe x (mem_escape (List.mem_of_mem_tail hx))).1

theorem ciRest_legacy (l : List Char) (n : Nat) :
    hasLegacy (List.replicate n '#' ++ ciRest n l) = false := by
  induction l generalizing n with
  | nil => simpa [ciRest] using hasLegacy_replicate n
  | cons c l ih =>
    rw [ciRest]
    split
    · rw [hasLegacy_escape]
      simpa using ih 0
    · rename_i h
      by_cases hc : c = '#'
      · subst hc
        simp only [↓reduceIte]
        rw [show escapeChar '#' = ['#'] by decide, ← List.append_assoc, ← List.replicate_succ']
        exact ih (n + 1)
      · simp only [hc, ↓reduceIte]
        unfold escapeChar
        split
        · rw [List.singleton_append,
            hasLegacy_hashes n hc (fun hb => Nat.lt_of_not_le fun h2 => h ⟨hb, h2⟩)]
          simpa using ih 0
        · rw [hasLegacy_escape]
          simpa using ih 0

theorem ciChars_legacy (l : List Char) : hasLegacy (ciChars l) = false := by
  induction l with
  | nil => rfl
  | cons c l ih =>
    rw [ciChars]
    split
    · rename_i h
      subst h
      exact (hasLegacy_append (p := [' ']) (by decide) _).trans ih
    · split
      · simpa using hasLegacy_escape 0 c (ciRest 0 l) ▸ ciRest_legacy l 0
      · simpa using ciRest_legacy (c :: l) 0

/-- The only runner blank that `oneLine` prints as itself is the space. -/
theorem printable_runnerBlank {c : Char} (hb : runnerBlank c = true) (hp : printable c = true) :
    c = ' ' := by
  have key : ∀ n ∈ runnerBlanks, ((0x20 ≤ n && n ≤ 0x7E && n != 0x5C) ||
      printableRanges.any fun (lo, hi) => lo ≤ n && n ≤ hi) = true → n = 0x20 := by decide
  exact Char.toNat_inj.mp (key c.toNat (List.contains_iff_mem.mp hb) hp)

/-- After its leading blanks, a line `ciChars` writes never starts with `:`. -/
theorem ciChars_head (l : List Char) : ((ciChars l).dropWhile runnerBlank).head? ≠ some ':' := by
  induction l with
  | nil => simp [ciChars]
  | cons c l ih =>
    rw [ciChars]
    split
    · rename_i h
      subst h
      simpa [List.dropWhile_cons, show runnerBlank ' ' = true by decide] using ih
    · rename_i h1
      split
      · show (('\\' :: _).dropWhile runnerBlank).head? ≠ _
        simp [show runnerBlank '\\' = false by decide]
      · rename_i h2
        rw [ciRest]
        simp only [show ¬(c = '[' ∧ 2 ≤ 0) from fun h => absurd h.2 (by decide), ↓reduceIte]
        unfold escapeChar
        split
        · rename_i hp
          have hb : runnerBlank c = false := by
            cases hb : runnerBlank c
            · rfl
            · exact absurd (printable_runnerBlank hb hp) h1
          simp [hb, h2]
        · show (('\\' :: _).dropWhile runnerBlank).head? ≠ _
          simp [show runnerBlank '\\' = false by decide]

/-- **No line `ciLine` writes starts a workflow command**, by either of the runner's parsers. -/
theorem ciLine_not_startsCommand (s : String) : ¬ startsCommand (ciLine s) := by
  simp only [startsCommand, ciLine, String.toList_ofList]
  rintro (⟨t, ht⟩ | h)
  · have := ciChars_head s.toList
    rw [← ht] at this
    exact this rfl
  · rw [← hasLegacy_iff, ciChars_legacy] at h
    exact Bool.false_ne_true h

theorem ciRest_printable (n : Nat) (l : List Char) :
    ∀ x ∈ ciRest n l, printable x = true ∨ x = '\\' := by
  induction l generalizing n with
  | nil => simp [ciRest]
  | cons c l ih =>
    rw [ciRest]
    split
    · intro x hx
      rcases List.mem_append.mp hx with hx | hx
      · exact escapeAlphabet_printable x (mem_escape hx)
      · exact ih 0 x hx
    · intro x hx
      rcases List.mem_append.mp hx with hx | hx
      · exact escapeChar_printable c x hx
      · exact ih _ x hx

/-- `ciLine` prints only allowlisted code points, and `\` to start an escape, as `oneLine` does. -/
theorem ciLine_printable (s : String) :
    ∀ x ∈ (ciLine s).toList, printable x = true ∨ x = '\\' := by
  simp only [ciLine, String.toList_ofList]
  induction s.toList with
  | nil => simp [ciChars]
  | cons c l ih =>
    rw [ciChars]
    split
    · rename_i h
      subst h
      intro x hx
      rcases List.mem_cons.mp hx with rfl | hx
      · exact .inl (by decide)
      · exact ih x hx
    · split
      · intro x hx
        rcases List.mem_append.mp hx with hx | hx
        · exact escapeAlphabet_printable x (mem_escape hx)
        · exact ciRest_printable 0 l x hx
      · exact ciRest_printable 0 (c :: l)

/-- **A line `ciLine` writes stays one line**: it holds no line feed, vertical tab, form feed,
carriage return, next line, or line or paragraph separator. -/
theorem ciLine_no_break (s : String) :
    ∀ c ∈ ['\n', '\x0b', '\x0c', '\r', '\u0085', '\u2028', '\u2029'],
      c ∉ (ciLine s).toList := by
  have key : ∀ c ∈ ['\n', '\x0b', '\x0c', '\r', '\u0085', '\u2028', '\u2029'],
      ¬(printable c = true ∨ c = '\\') := by decide
  intro c hc hmem
  exact key c hc (ciLine_printable s c hmem)

theorem unescape_ciRest (n : Nat) (l : List Char) : unescape (ciRest n l) = l := by
  induction l generalizing n with
  | nil => rfl
  | cons c l ih =>
    rw [ciRest]
    split
    · rw [unescape_escape, ih]
    · rw [unescape_escapeChar, ih]

/-- **`ciLine` loses nothing**: a reader decodes what it prints back to the original text. -/
theorem unescape_ciLine (s : String) : unescape (ciLine s).toList = s.toList := by
  simp only [ciLine, String.toList_ofList]
  induction s.toList with
  | nil => rfl
  | cons c l ih =>
    rw [ciChars]
    split
    · rename_i h
      subst h
      rw [unescape_cons (by decide), ih]
    · split
      · rename_i h
        subst h
        rw [unescape_escape, unescape_ciRest]
      · exact unescape_ciRest 0 (c :: l)

/-- Two texts never print as one line. -/
theorem ciLine_injective {s t : String} (h : ciLine s = ciLine t) : s = t :=
  String.toList_injective (by rw [← unescape_ciLine s, ← unescape_ciLine t, h])

/-! ### What the runner reads, and what `ciLine` writes, checked by the kernel -/

/-- `startsCommand` fires on both forms, on any of .NET's blanks before `::` (here a space, a tab
and the ideographic space U+3000), and not on a `::` or a `#[` after the start. -/
example : startsCommand "::error::x" ∧ startsCommand " \t\u3000::warning::x" ∧
    startsCommand "x ##[warning]y" ∧ ¬ startsCommand "GATE 1 lint: a::b #[1, 2]" := by
  decide +kernel

/-- The legacy form anywhere in the line. -/
example : ciLine "##[warning]x" = "##\\u{005B}warning]x" := by decide

/-- A `:` that would come first, with or without leading spaces. -/
example : ciLine "::error::x" = "\\u{003A}:error::x" ∧
    ciLine "  ::add-mask::x" = "  \\u{003A}:add-mask::x" := by decide

/-- A tab before `::`: `oneLine`'s escape of the tab already comes first. -/
example : ciLine "\t::error::x" = "\\u{0009}::error::x" := by decide

/-- A carriage return or U+2028 cannot start a line of its own. -/
example : ciLine "a\r::warning::x" = "a\\u{000D}::warning::x" ∧
    ciLine "a\u2028##[add-mask]x" = "a\\u{2028}##\\u{005B}add-mask]x" := by decide

/-- Text that already holds an escape: its `\` is escaped, so a reader does not take it for one. -/
example : ciLine "##\\u{005B}warning]x" = "##\\u{005C}u{005B}warning]x" := by decide

/-- Every `[` right after `##` is escaped; a Lean array and a `::` later in the line are not. -/
example : ciLine "###[x ##[y" = "###\\u{005B}x ##\\u{005B}y" ∧
    ciLine "GATE 1 lint: a::b #[1, 2]" = "GATE 1 lint: a::b #[1, 2]" := by decide

end MitosGate
