import Std

/-!
This reader models a closed, ASCII YAML line subset, not GitHub's parser. It preserves physical
lines and scalar text, cuts only separated comments outside quotes, and refuses unsupported
nodes and multiline scalars. The proofs concern this model. Refusal bounds the parser gap to
the accepted subset; it does not prove that GitHub gives every accepted file the same meaning.
-/

namespace MitosGate.Yaml

inductive Refusal where
  | char (line : Nat) (c : Char)
  | anchorOrAlias (line : Nat) | tag (line : Nat) | complexKey (line : Nat) | mergeKey (line : Nat)
  | marker (line : Nat) | escape (line : Nat) | multiline (line : Nat)
  | blockIndicator (line : Nat) | indent (line : Nat)
  deriving DecidableEq, Repr

inductive Line where
  | blank | comment
  | content (indent : Nat) (dash : Bool) (kept : List Char) (cut : List Char)
  | block (text : List Char)
  deriving DecidableEq, Repr

deriving instance DecidableEq for Except

def allowedChar (c : Char) : Bool := c == '\n' || (' ' ≤ c && c ≤ '~')

def physicalLines : List Char → List (List Char)
  | [] => []
  | c :: cs =>
    if c == '\n' then [] :: physicalLines cs else
      match physicalLines cs with
      | [] => [[c]]
      | l :: ls => (c :: l) :: ls

structure RawLine where
  number : Nat
  indent : Nat
  body : List Char
  deriving Repr

def rawLine (n : Nat) (s : List Char) : RawLine :=
  ⟨n, (s.takeWhile (· == ' ')).length, s.dropWhile (· == ' ')⟩

def isComment (l : RawLine) : Prop := l.body.head? = some '#'

instance (l : RawLine) : Decidable (isComment l) := inferInstanceAs (Decidable (_ = _))

inductive Mode where
  | node | plain | single | singleEnd | double | closed
  deriving DecidableEq, Repr

structure Context where
  mode : Mode := .node
  flow : Nat := 0
  mapping : Bool := false
  deriving Repr

def spaceOrEnd : List Char → Bool
  | [] => true
  | c :: _ => c == ' '

def colonBoundary (x : Context) (rest : List Char) : Bool :=
  spaceOrEnd rest || x.flow > 0 &&
    (x.mode == .closed || x.mode == .singleEnd ||
      rest.head?.any fun c => c == '[' || c == ']' || c == '{' || c == '}' || c == ',')

def advance (x : Context) (c : Char) (rest : List Char) : Context :=
  match x.mode with
  | .single => { x with mode := if c == '\'' then .singleEnd else .single }
  | .double => { x with mode := if c == '"' then .closed else .double }
  | .singleEnd =>
    if c == '\'' then { x with mode := .single } else advanceOutside x c rest
  | _ => advanceOutside x c rest
where
  advanceOutside (x : Context) (c : Char) (rest : List Char) : Context :=
    if c == ' ' then { x with mode := if x.mode == .singleEnd then .closed else x.mode } else
    if c == ':' && colonBoundary x rest then { x with mode := .node, mapping := x.mapping || x.flow == 0 } else
    if x.flow > 0 && c == ',' then { x with mode := .node } else
    if x.flow > 0 && (c == ']' || c == '}') then { x with mode := .closed, flow := x.flow - 1 } else
    if x.mode == .node then
      if c == '\'' then { x with mode := .single } else
      if c == '"' then { x with mode := .double } else
      if c == '[' || c == '{' then { x with mode := .node, flow := x.flow + 1 } else
      if c == '-' && spaceOrEnd rest then x else { x with mode := .plain }
    else { x with mode := .plain }

def outside (x : Context) : Bool := x.mode != .single && x.mode != .double

def prefixContext : List Char → Context → Context
  | [], x => x
  | c :: cs, x => prefixContext cs (advance x c cs)

def commentBoundary (kept : List Char) : Bool :=
  (kept.isEmpty || kept.getLast? == some ' ') && outside (prefixContext kept {})

def cutAllowed (kept cut : List Char) : Bool :=
  cut.isEmpty || (cut.head? == some '#' && commentBoundary kept)

def entryColumns : List Char → Nat → Option Nat → Nat × Nat
  | '-' :: ' ' :: rest, col, _ => entryColumns rest (col + 2) (some col)
  | ' ' :: rest, col, dash => entryColumns rest (col + 1) dash
  | _, col, dash => (col, dash.getD col)

private def headerMapping : List Char → Context → Bool → Option Bool
  | [], _, _ => none
  | c :: cs, x, space =>
    if c == '#' && space && outside x then none else
    if x.mode == .node && x.flow == 0 && (c == '|' || c == '>') then some x.mapping
    else headerMapping cs (advance x c cs) (c == ' ')

def blockHeader (l : RawLine) : Option Nat :=
  (headerMapping l.body {} true).map fun mapping =>
    let columns := entryColumns l.body l.indent none
    if mapping then columns.1 else columns.2

def sourceStep (block : Option Nat) (raw : List Char) : Bool × Option Nat :=
  let l := rawLine 0 raw
  match block with
  | some col => if l.body.isEmpty || l.indent > col then (true, block)
    else (false, blockHeader l)
  | none => (false, blockHeader l)

def linePartition (raw : List Char) (inBlock : Bool) (line : Line) : Bool :=
  if inBlock then line == .block raw else
    match line with
    | .blank => raw.all (· == ' ')
    | .comment => (raw.dropWhile (· == ' ')).head? == some '#'
    | .content n _ kept cut => raw == List.replicate n ' ' ++ kept ++ cut && cutAllowed kept cut
    | .block _ => false

structure SourceLine where
  number : Nat
  raw : List Char
  inBlock : Bool

def numbered : Nat → Option Nat → List (List Char) → List SourceLine
  | _, _, [] => []
  | n, block, raw :: rest =>
    let next := sourceStep block raw
    ⟨n, raw, next.1⟩ :: numbered (n + 1) next.2 rest

def DropsOnlyComment (s : List Char) (e : Nat × Line) : Prop :=
  ∃ src ∈ numbered 1 none (physicalLines s),
    src.number = e.1 ∧ linePartition src.raw src.inBlock e.2 = true

inductive PlainOwner where
  | entry (column : Nat)
  | standalone (column : Nat)
  deriving Repr

structure State where
  block : Option Nat := none
  contentIndent : Option Nat := none
  plain : Option (Nat × PlainOwner) := none
  pending : Option Nat := none
  deriving Repr

structure Scanned where
  kept : List Char
  cut : List Char
  context : Context
  block : Bool := false

private def mergeKeyStart (x : Context) : List Char → Bool
  | '<' :: '<' :: cs => match cs.dropWhile (· == ' ') with
    | ':' :: rest => colonBoundary x rest
    | _ => false
  | _ => false

private def scan (n : Nat) : List Char → List Char → Context → Except Refusal Scanned
  | [], rev, x =>
    if outside x && x.flow == 0 then .ok ⟨rev.reverse, [], x, false⟩ else .error (.multiline n)
  | c :: cs, rev, x => do
    if c == '#' && (rev.isEmpty || rev.head? == some ' ') && outside x then
      if x.flow > 0 then throw (.multiline n)
      return ⟨rev.reverse, c :: cs, x, false⟩
    if c == '#' && x.mode == .node then throw (.multiline n)
    if x.mode == .double && c == '\\' then throw (.escape n)
    if (x.mode == .closed || x.mode == .singleEnd) && c != ' ' &&
        !(x.mode == .singleEnd && c == '\'') &&
        !(c == ':' && colonBoundary x cs) && !(x.flow > 0 && (c == ',' || c == ']' || c == '}')) then
      throw (.multiline n)
    if x.mode == .node then
      if c == '&' || c == '*' then throw (.anchorOrAlias n)
      if c == '!' then throw (.tag n)
      if c == '?' && (x.flow > 0 || spaceOrEnd cs) then throw (.complexKey n)
      if mergeKeyStart x (c :: cs) then throw (.mergeKey n)
      if c == '|' || c == '>' then
        if x.flow > 0 then throw (.blockIndicator n)
        let tail := match cs with | '+' :: rest | '-' :: rest => rest | _ => cs
        let tail := tail.dropWhile (· == ' ')
        if !tail.isEmpty && tail.head? != some '#' then throw (.blockIndicator n)
        return ⟨rev.reverse ++ c :: cs.take (cs.length - tail.length), tail, x, true⟩
    scan n cs (c :: rev) (advance x c cs)

def dashStart : List Char → Bool
  | '-' :: cs => spaceOrEnd cs
  | _ => false

private def ordinary (st : State) (l : RawLine) : Except Refusal (State × Line) := do
  if l.body.isEmpty then return (st, .blank)
  if isComment l then return (st, .comment)
  if l.indent == 0 && (l.body.head? == some '%' ||
      (l.body.take 3 == ['-', '-', '-'] || l.body.take 3 == ['.', '.', '.']) &&
        spaceOrEnd (l.body.drop 3)) then throw (.marker l.number)
  if let some (origin, owner) := st.plain then
    if (match owner with | .entry col => decide (l.indent > col) | .standalone col => decide (l.indent ≥ col)) then
      throw (.multiline origin)
  let s ← scan l.number l.body [] {}
  let columns := entryColumns l.body l.indent none
  let owner := if s.context.mapping then columns.1 else columns.2
  let scalarOwner := if s.context.mapping || dashStart l.body then PlainOwner.entry owner else
    match st.pending with
    | some parent => if parent < l.indent then .entry parent else .standalone 0
    | none => .standalone 0
  let plain := if s.context.mode == .plain && s.context.flow == 0 && !s.block then
    some (l.number, scalarOwner) else none
  let pending := if s.context.mode == .node && s.context.flow == 0 && !s.block then some owner else none
  return (⟨if s.block then some owner else none, none, plain, pending⟩,
    .content l.indent (dashStart l.body) s.kept s.cut)

def step (st : State) (l : RawLine) : Except Refusal (State × Line) :=
  match st.block with
  | none => ordinary st l
  | some col =>
    if l.body.isEmpty then .ok (st, .block (List.replicate l.indent ' ')) else
    if l.indent ≤ col then ordinary { st with block := none } l else
    match st.contentIndent with
    | some content => if l.indent < content then .error (.indent l.number)
      else .ok (st, .block (List.replicate l.indent ' ' ++ l.body))
    | none => .ok ({ st with contentIndent := some l.indent },
      .block (List.replicate l.indent ' ' ++ l.body))

theorem step_comment (st : State) (l : RawLine) (hb : st.block = none) (hc : isComment l) :
    step st l = .ok (st, .comment) := by
  have hn : l.body.isEmpty = false := by
    cases h : l.body with
    | nil => simp [isComment, h] at hc
    | cons c cs => simp
  simp [step, hb, ordinary, hn, hc]; rfl

theorem step_block_ends (st : State) (l : RawLine) (col : Nat)
    (hb : st.block = some col) (hn : l.body ≠ []) (hi : l.indent ≤ col) :
    step st l = step { st with block := none } l := by
  have he : l.body.isEmpty = false := by cases h : l.body <;> simp_all
  simp [step, hb, he, hi]

inductive Corresponds : Nat → Option Nat → List (List Char) → List (Nat × Line) → Prop where
  | nil : Corresponds n block [] []
  | cons : linePartition raw (sourceStep block raw).1 line = true →
      Corresponds (n + 1) (sourceStep block raw).2 rest ls →
      Corresponds n block (raw :: rest) ((n, line) :: ls)

private def readLines : List (List Char) → Nat → State → Option Nat → Except Refusal (List (Nat × Line))
  | [], _, _, _ => .ok []
  | raw :: rest, n, st, block =>
    match step st (rawLine n raw) with
    | .error err => .error err
    | .ok (st', line) =>
      if linePartition raw (sourceStep block raw).1 line then
        match readLines rest (n + 1) st' (sourceStep block raw).2 with
        | .error err => .error err
        | .ok tail => .ok ((n, line) :: tail)
      else .error (.multiline n)

private def chars : List Char → Nat → Except Refusal Unit
  | [], _ => .ok ()
  | c :: cs, n => if allowedChar c then chars cs (if c == '\n' then n + 1 else n)
    else .error (.char n c)

def lex (s : List Char) : Except Refusal (List (Nat × Line)) :=
  match chars s 1 with
  | .error err => .error err
  | .ok _ => readLines (physicalLines s) 1 {} none

private theorem chars_allowed {s : List Char} {n : Nat} {u : Unit}
    (h : chars s n = .ok u) : ∀ c ∈ s, allowedChar c = true := by
  induction s generalizing n with
  | nil => simp
  | cons a as ih =>
    simp only [chars] at h
    split at h
    next ha =>
      intro c hm
      simp only [List.mem_cons] at hm
      rcases hm with rfl | hm
      · exact ha
      · exact ih h c hm
    next => cases h

theorem lex_chars {s : List Char} {ls : List (Nat × Line)} (h : lex s = .ok ls) :
    ∀ c ∈ s, allowedChar c = true := by
  unfold lex at h
  cases hc : chars s 1 with
  | error err => simp [hc] at h
  | ok u => exact chars_allowed hc

private theorem readLines_partition {raws : List (List Char)} {n : Nat} {st : State} {block : Option Nat}
    {ls : List (Nat × Line)} (h : readLines raws n st block = .ok ls) : Corresponds n block raws ls := by
  induction raws generalizing n st ls block with
  | nil => simp [readLines] at h; subst ls; exact .nil
  | cons raw rest ih =>
    simp only [readLines] at h
    cases hs : step st (rawLine n raw) with
    | error err => simp [hs] at h
    | ok pair =>
      rcases pair with ⟨st', line⟩
      simp only [hs] at h
      split at h
      next good =>
        cases hr : readLines rest (n + 1) st' (sourceStep block raw).2 with
        | error err => simp [hr] at h
        | ok tail =>
          simp [hr] at h
          subst ls
          exact .cons good (ih hr)
      next => cases h

theorem lex_lines {s : List Char} {ls : List (Nat × Line)} (h : lex s = .ok ls) :
    Corresponds 1 none (physicalLines s) ls := by
  unfold lex at h
  cases hc : chars s 1 with
  | error err => simp [hc] at h
  | ok u => exact readLines_partition (by simpa [hc] using h)

theorem lex_line_count {s : List Char} {ls : List (Nat × Line)} (h : lex s = .ok ls) :
    ls.length = (physicalLines s).length := by
  suffices ∀ {n block raws ls}, Corresponds n block raws ls → ls.length = raws.length from this (lex_lines h)
  intro n block raws ls hp
  induction hp with
  | nil => rfl
  | cons _ _ ih => simp [ih]

theorem lex_drops_only_comments {s : List Char} {ls : List (Nat × Line)}
    (h : lex s = .ok ls) : ∀ e ∈ ls, DropsOnlyComment s e := by
  have hp := lex_lines h
  suffices ∀ {n block raws ls}, Corresponds n block raws ls →
      ∀ e ∈ ls, ∃ src ∈ numbered n block raws,
        src.number = e.1 ∧ linePartition src.raw src.inBlock e.2 = true by
    exact this hp
  intro n block raws ls hp
  induction hp with
  | nil => simp
  | @cons raw block line n rest ls head tail ih =>
    intro entry hm
    simp only [List.mem_cons] at hm
    rcases hm with rfl | hm
    · exact ⟨⟨n, raw, (sourceStep block raw).1⟩, by simp [numbered], rfl, head⟩
    · obtain ⟨src, hr, hn, hc⟩ := ih entry hm
      exact ⟨src, by simp [numbered, hr], hn, hc⟩

end MitosGate.Yaml
