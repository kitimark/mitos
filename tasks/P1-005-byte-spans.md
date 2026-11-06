# tasks/P1-005-byte-spans.md

phase: 1
goal: Spans are checked UTF-8 byte ranges of the source; `Anchored` accepts a span only when it
  sits on character boundaries and its bytes are exactly the identity key.
statement: Mitos.Span.text, Mitos.Anchored, Mitos.lines, Mitos.mem_lines (changed);
  Mitos.utf8Len, Mitos.splitBytes, Mitos.splitBytes_eq_some, Mitos.Span.text_eq_some,
  Mitos.Span.text_toByteArray, Mitos.Span.text_isValid, Mitos.Spec.Adequacy.{byte_span_anchored,
  char_span_not_anchored, mid_char_span_not_anchored} (new)
touches: core/Mitos/Core/{Fact,Lines,Obligations}.lean, core/Mitos/Core/Spec/Adequacy.lean,
  statements.lock, examples/acme/{Models,Plugins}/ToyRequire.lean, examples/acme/models.lock,
  examples/acme/accepted/ToyRequire.json, eval/cheats/*/{Plugins,Models}/ToyRequire.lean
must_not_touch: gate/, core/Challenge/, core/comparator.json, eval/cheats/*/expect, eval/cheats/run.sh
checks: build, imports, lock, core lake check, acme build, accept-toy, cheats
budget: 40 iterations · 3h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Phase 0 spans were character offsets into `String.toList` (`docs/process.md`, Findings).
  Real tools report UTF-8 byte offsets, and Lean's own `String.Pos.Raw` is a byte offset, so a
  character offset is wrong as soon as a file contains a non-ASCII character.
- This is a spec change: it changes what `Anchored` means and what every extractor must prove.
  It needs the `spec-approved` label. The toy plugin and the cheat corpus are migrated in the
  same PR so `main` never has an obligation the honest plugin cannot meet.

## Design

**Data shape.** `Span` keeps two `Nat` fields, `start` and `len`, now counted in UTF-8 bytes.
A fact does not carry its source, so a span cannot be valid by construction; validity is a
property of a span *and* a source, decided by `Span.text`.

**What "checked" means.** `Span.text sp src : Option (List Char)` is `some t` exactly when
`src = pre ++ t ++ post` with `pre` encoding to `sp.start` bytes and `t` to `sp.len` bytes
(`Span.text_eq_some`). A span whose start or end falls inside a character, or past the end of
the file, has no text, so no fact can be anchored by it. `Anchored` requires
`f.span.text s.toList = some f.ident.key.toList`.

Two bridge theorems tie this to Lean's `String`:
- `Span.text_toByteArray`: the UTF-8 bytes of the text are exactly bytes
  `[start, start + len)` of `s.toByteArray`.
- `Span.text_isValid`: both ends are valid `String.Pos.Raw` positions of `s`.

**Shapes considered.** On Lean 4.35, `decide` evaluates all three on small literals (checked:
`"é sdk".toUTF8.extract 3 6 = "sdk".toUTF8`, `String.Pos.Raw.extract "é sdk" ⟨3⟩ ⟨6⟩ = "sdk"` and
`¬ (String.Pos.Raw.mk 1).IsValid "é sdk"` all close by `decide`), so the choice turns on proofs
and on what the locked statement depends on.

| Shape | Boundary check | Proofs in the line layer and plugins | Locked meaning depends on |
|---|---|---|---|
| A. `Span.text` slices `s.toUTF8` (`ByteArray`), compared with `key.toUTF8` | needs a separate predicate: an empty key's bytes match inside a character | `ByteArray.extract` and append arithmetic, while `lines` works on characters | `String.toByteArray`, `List.utf8Encode` |
| B. `String.Pos.Raw` positions; text via `Pos.Raw.extract`, validity via `Pos.Raw.IsValid` | `Pos.Raw.IsValid` | `String` internals (`Pos.Raw.isValid_iff_exists_append`, extract lemmas) | the `String` API, whose lemmas this toolchain shows renamed in late 2025 (deprecations dated 2025-10-30 and 2025-11-24) |
| C. byte offsets read over `List Char` with `Char.utf8Size` (**chosen**) | built in: `Span.text` is `none` off a boundary | list algebra after one lemma, `Span.text_eq_some` | `List`, `Char.utf8Size` |

C keeps structural recursion (the Phase 0 finding), keeps plugin proofs in list algebra, and
pins meaning to definitions that are small and stable. The two bridge theorems prove it agrees
with A and B on every span that has text. `String.Pos.Raw` as the field type was also
considered, to brand the offsets; it adds wrapping in every plugin and in `lines` without
making any invalid span unrepresentable, so the fields stay `Nat` and the docstrings say bytes.

**Line layer.** `lines` stays structurally recursive; the next line's offset is
`o + utf8Len cur + 1` (a newline is one byte). `mem_lines` now states
`Span.text ⟨o, utf8Len l⟩ s = some l`: every line is the text of the byte span at its offset.

**Adequacy.** In `"é sdk"`, `é` is two bytes. `Spec.Adequacy` proves that an extractor citing
`sdk` at bytes `⟨3, 3⟩` is anchored, that one citing the Phase 0 character span `⟨2, 3⟩` is
not, and that one citing an empty key at `⟨1, 0⟩` (inside `é`) is not. The toy model gains a
`decide`-checked example where the second line starts at byte 11, character 10.

## Review notes
- `statements.lock` does not show the change to `lines.go`. A structurally recursive
  definition's locked value is `fun … => List.brecOn … lines.go._f …`; its body lives in the
  auxiliary `lines.go._f`, which the lock skips as an internal name. `lines.go` changed from
  `o + cur.length + 1` to `o + utf8Len cur + 1`, and its hash on `main` and on this branch is
  the same (`bdce89cb…`). The same holds for `splitBytes`. Their meaning is still pinned here by
  locked theorem types: `splitBytes_eq_some` and `Span.text_eq_some` characterize `splitBytes`
  and `Span.text` exactly, and `mem_lines` states what every line of `lines` is. Closing the gap
  in `gate/MitosGate/Lock.lean` (hash the auxiliary `_f` and `match_` bodies with their parent)
  is a separate gate change.
- `examples/acme/accepted/ToyRequire.json` was refreshed with `accept … --paranoid --record`,
  the way P1-001 refreshed it after its core change.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] every cheat case fails at its expected gate, comparator-only results unchanged
- [ ] owner adds `spec-approved`
- [ ] run-log record written (ops/runs/)
