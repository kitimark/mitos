/-!
# Facts

A fact is a claim an extractor makes about one source file: the file *provides* or *requires*
an identity, and the claim is anchored to a span of the file.

Spans are UTF-8 byte offsets, the positions `String.Pos.Raw` uses. They are read over
`String.toList` with structural recursion, so model examples stay checkable with `decide`;
`Span.text_toByteArray` and `Span.text_isValid` tie them to the bytes of the `String` itself.
-/

namespace Mitos

/-- Whether a fact says the file offers an identity or needs one. -/
inductive FactKind where
  | provides
  | requires
  deriving DecidableEq, Repr

/-- When a requirement applies. A dev or test dependency must never be reported as a runtime one,
so the resolver carries the scope of the requiring fact onto its edges unchanged. -/
inductive Scope where
  | runtime
  | dev
  | test
  | build
  deriving DecidableEq, Repr

/-- A global identity, e.g. `{ kind := "npm", key := "@jellyfin/sdk" }`. -/
structure Identity where
  kind : String
  key  : String
  deriving DecidableEq, Repr

/-- The number of bytes in the UTF-8 encoding of `cs`. -/
def utf8Len (cs : List Char) : Nat :=
  (cs.map Char.utf8Size).sum

/-- Split `cs` after its first `n` UTF-8 bytes. The result is `none` when byte `n` is not a
character boundary of `cs`: it falls inside a character or past the end. -/
def splitBytes : Nat → List Char → Option (List Char × List Char)
  | 0, cs => some ([], cs)
  | _ + 1, [] => none
  | n + 1, c :: cs =>
    if c.utf8Size ≤ n + 1 then
      (splitBytes (n + 1 - c.utf8Size) cs).map fun (pre, post) => (c :: pre, post)
    else none

/-- A span of a source file: a UTF-8 byte offset and a length in bytes. -/
structure Span where
  start : Nat
  len   : Nat
  deriving DecidableEq, Repr

/-- The characters of `src` whose UTF-8 bytes are exactly the span. The result is `none` when
either end of the span is not a character boundary of `src`, so a span is valid for a source
exactly when its text is `some`. -/
def Span.text (sp : Span) (src : List Char) : Option (List Char) := do
  let (_, rest) ← splitBytes sp.start src
  let (t, _) ← splitBytes sp.len rest
  pure t

/-- One claim about one source file. -/
structure Fact where
  kind  : FactKind
  ident : Identity
  span  : Span
  scope : Scope := .runtime
  deriving DecidableEq, Repr

@[simp] theorem utf8Len_nil : utf8Len [] = 0 := rfl

@[simp] theorem utf8Len_cons (c : Char) (cs : List Char) :
    utf8Len (c :: cs) = c.utf8Size + utf8Len cs := by
  simp [utf8Len]

@[simp] theorem utf8Len_append (as bs : List Char) :
    utf8Len (as ++ bs) = utf8Len as + utf8Len bs := by
  simp [utf8Len]

@[simp] theorem utf8Len_reverse (cs : List Char) : utf8Len cs.reverse = utf8Len cs := by
  simp [utf8Len, List.sum_reverse]

/-- `splitBytes` cuts exactly at byte `n`: it returns the unique split whose first part encodes
to `n` bytes. -/
theorem splitBytes_eq_some {n : Nat} {cs pre post : List Char} :
    splitBytes n cs = some (pre, post) ↔ pre ++ post = cs ∧ utf8Len pre = n := by
  induction cs generalizing n pre with
  | nil =>
    cases n <;> cases pre <;> simp [splitBytes, eq_comm, Char.utf8Size_pos, Nat.ne_of_gt]
  | cons c cs ih =>
    cases n with
    | zero =>
      cases pre with
      | nil => simp [splitBytes, eq_comm]
      | cons d pre => have := d.utf8Size_pos; simp [splitBytes]; omega
    | succ n =>
      cases pre with
      | nil => simp [splitBytes]
      | cons d pre =>
        simp only [splitBytes, List.cons_append, List.cons.injEq, utf8Len_cons]
        constructor
        · intro h
          split at h
          · obtain ⟨⟨p, q⟩, hpq, he⟩ := Option.map_eq_some_iff.1 h
            simp only [Prod.mk.injEq, List.cons.injEq] at he
            obtain ⟨⟨rfl, rfl⟩, rfl⟩ := he
            obtain ⟨h1, h2⟩ := ih.1 hpq
            exact ⟨⟨rfl, h1⟩, by omega⟩
          · simp at h
        · rintro ⟨⟨rfl, rfl⟩, hn⟩
          split
          · rw [ih.2 ⟨rfl, by omega⟩]; rfl
          · omega

/-- **What a span denotes.** A span's text is `t` exactly when the source is `pre ++ t ++ post`
with `pre` taking `sp.start` bytes and `t` taking `sp.len` bytes. -/
theorem Span.text_eq_some {sp : Span} {src t : List Char} :
    sp.text src = some t ↔
      ∃ pre post, src = pre ++ t ++ post ∧ utf8Len pre = sp.start ∧ utf8Len t = sp.len := by
  constructor
  · intro h
    simp only [Span.text, Option.pure_def, Option.bind_eq_bind] at h
    obtain ⟨⟨pre, rest⟩, h1, h⟩ := Option.bind_eq_some_iff.1 h
    obtain ⟨⟨t', post⟩, h2, h⟩ := Option.bind_eq_some_iff.1 h
    cases h
    obtain ⟨rfl, hpre⟩ := splitBytes_eq_some.1 h1
    obtain ⟨rfl, ht⟩ := splitBytes_eq_some.1 h2
    exact ⟨pre, post, by simp, hpre, ht⟩
  · rintro ⟨pre, post, rfl, hpre, ht⟩
    simp only [Span.text, Option.pure_def, Option.bind_eq_bind, List.append_assoc,
      splitBytes_eq_some.2 ⟨rfl, hpre⟩, splitBytes_eq_some.2 ⟨rfl, ht⟩, Option.bind_some]

/-- `utf8Len` is Lean's own byte size of the string the characters form. -/
theorem utf8ByteSize_ofList (cs : List Char) : (String.ofList cs).utf8ByteSize = utf8Len cs := by
  induction cs with
  | nil => rfl
  | cons c cs ih => simp [String.utf8ByteSize_append, String.utf8ByteSize_singleton, ih]

/-- **Spans are the file's bytes.** The text of a span, encoded as UTF-8, is exactly the bytes
`[sp.start, sp.start + sp.len)` of the source string. -/
theorem Span.text_toByteArray {sp : Span} {s : String} {t : List Char}
    (h : sp.text s.toList = some t) :
    s.toByteArray.extract sp.start (sp.start + sp.len) = (String.ofList t).toByteArray := by
  obtain ⟨pre, post, hs, hpre, ht⟩ := Span.text_eq_some.1 h
  have hs' : s = String.ofList pre ++ String.ofList t ++ String.ofList post := by
    rw [← String.ofList_toList (s := s), hs]; simp [String.ofList_append, String.append_assoc]
  subst hs'
  have hA : (String.ofList pre).toByteArray.size = sp.start := by
    rw [String.size_toByteArray, utf8ByteSize_ofList, hpre]
  have hB : (String.ofList t).toByteArray.size = sp.len := by
    rw [String.size_toByteArray, utf8ByteSize_ofList, ht]
  have e := ByteArray.extract_append_size_add' (i := 0) (j := sp.len)
    (b := (String.ofList t).toByteArray ++ (String.ofList post).toByteArray) hA.symm
  rw [Nat.add_zero, ByteArray.extract_append_eq_left hB.symm] at e
  rw [String.toByteArray_append, String.toByteArray_append, ByteArray.append_assoc, e]

/-- **Spans sit on character boundaries.** Both ends of a span that has text are valid positions
of the source string. -/
theorem Span.text_isValid {sp : Span} {s : String} {t : List Char}
    (h : sp.text s.toList = some t) :
    (String.Pos.Raw.mk sp.start).IsValid s ∧
      (String.Pos.Raw.mk (sp.start + sp.len)).IsValid s := by
  obtain ⟨pre, post, hs, hpre, ht⟩ := Span.text_eq_some.1 h
  have hs' : s = String.ofList pre ++ String.ofList t ++ String.ofList post := by
    rw [← String.ofList_toList (s := s), hs]; simp [String.ofList_append, String.append_assoc]
  rw [hs']
  constructor
  · refine String.Pos.Raw.isValid_iff_exists_append.2
      ⟨String.ofList pre, String.ofList t ++ String.ofList post,
        by simp [String.append_assoc], ?_⟩
    simp [String.Pos.Raw.ext_iff, utf8ByteSize_ofList, hpre]
  · refine String.Pos.Raw.isValid_iff_exists_append.2
      ⟨String.ofList pre ++ String.ofList t, String.ofList post, rfl, ?_⟩
    simp [String.Pos.Raw.ext_iff, String.utf8ByteSize_append, utf8ByteSize_ofList, hpre, ht]

end Mitos
