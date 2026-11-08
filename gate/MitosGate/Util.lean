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

/-- `c` itself if it is printable, otherwise `\u{XXXX}`. -/
def escapeChar (c : Char) : List Char :=
  if printable c then [c] else ['\\', 'u', '{'] ++ hexDigits c.toNat ++ ['}']

/-- Text from the workspace, Lean or the comparator, made safe to print: every code point outside
the `printable` allowlist is written as `\u{XXXX}`. So the text stays on one line and cannot move
the cursor, reorder what follows or start a line of its own, such as a forged `VERDICT:`; and since
`\` is escaped too, each output stands for one input. -/
def oneLine (s : String) : String :=
  String.ofList (s.toList.flatMap escapeChar)

theorem printable_hexDigit {d : Nat} (h : d < 16) : printable (hexDigit d) = true := by
  revert d; decide

/-- `oneLine` prints only allowlisted code points, and `\` to start an escape. -/
theorem oneLine_printable (s : String) :
    ∀ c ∈ (oneLine s).toList, printable c = true ∨ c = '\\' := by
  intro c hc
  simp only [oneLine, String.toList_ofList, List.mem_flatMap] at hc
  obtain ⟨a, -, ha⟩ := hc
  unfold escapeChar at ha
  split at ha
  · rename_i hp
    simp only [List.mem_singleton] at ha
    exact .inl (ha ▸ hp)
  · simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at ha
    rcases ha with ((rfl | rfl | rfl) | hd) | rfl
    · exact .inr rfl
    · exact .inl (by decide)
    · exact .inl (by decide)
    · simp only [hexDigits, List.mem_map] at hd
      obtain ⟨i, -, rfl⟩ := hd
      exact .inl (printable_hexDigit (Nat.mod_lt _ (by decide)))
    · exact .inl (by decide)

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

end MitosGate
