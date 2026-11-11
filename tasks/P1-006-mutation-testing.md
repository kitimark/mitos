# tasks/P1-006-mutation-testing.md

phase: 1
goal: Every mutant of the resolver and impact analysis in `eval/mutants/` that names theorems
  (`breaks=`) breaks each of them, shown by the sandboxed `lake comparator` about the mutant's own
  definitions; a realistic mutant the theorems miss is kept as a known gap (`survives=`) for the
  owner; cheat cases (`rejects=`) show that a refutation or a gap counts only for the mutant's own
  definitions and the approved statements, and that a case's Lean text runs no code, declares no
  syntax and declares no name a generated statement could resolve to while Lean elaborates it; the
  nightly job checks all three (Phase 1 exit criterion 3, which stays open while a known gap does).
statement: none (tooling task); proves the runner's own logic in `eval/mutants/Mutants/`
touches: eval/mutants/, .github/workflows/nightly.yml, tasks/P1-006-mutation-testing.md,
  ops/runs/
must_not_touch: statements.lock, models.lock, core/, gate/, eval/cheats/, examples/,
  docs/process.md, .github/workflows/ci.yml, plan/ (the plan holds no status; it lives in #30)
checks: build, imports, lock, core lake check, comparator --paranoid, mitos-lint-test,
  eval/mutants build, the full mutant run (default and --paranoid), actionlint
budget: 30 iterations · 4h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Issue #30. Prior attempt: #9, closed without a merge. It had twelve mutants as full copies of
  the implementation files, a `Refute.lean` per mutant and a bash runner. This task keeps its
  idea (a mutant counts as caught only when the comparator accepts a proof that a Challenge
  theorem is false for it) and its refutations, and changes the rest (below).
- `docs/process.md` lists mutation testing as a nightly check (L3), and its tripwire "a mutation
  of our code still passes a theorem" means the theorem is too weak: a spec question for the
  owner.

## Design

**Why refutations.** A mutant whose proofs no longer build is not evidence that a theorem sees the
bug: a correct refactor also breaks proofs, usually in a helper lemma. So a mutant counts as
caught only when the sandboxed `lake comparator` accepts a proof that a named Challenge theorem is
false for it, as a kernel term, with standard axioms only.

**The runs.** Before anything is built, the lint (below, `Mutants.Lint`) reads every Lean text the
case wrote or changed, and a case it finds anything in is refused. Then each case gets up to three
comparator runs, each in a fresh copy of `core/` sources (no build outputs), removed afterwards
(`Mutants.Verdict`):

1. **holes:** the core with the case's edits under `Mitos/Impl/` and nothing else: no
   `Mitos/Proofs/`, no file of the case. The approved Challenge and definition holes, no theorem,
   and a generated solution module that imports every `Mitos/Impl/` module. It must accept: the
   mutant's implementation builds from the approved core alone, and declares every approved hole
   publicly with its approved type.
2. **gate:** the approved `core/comparator.json`, Challenge and solution module on the mutated
   core. This is what the PR gate would do with the bug.
3. After an acceptance, **values:** the approved Challenge with the holes as values (below). A
   `survives=` case is a known gap only if this accepts: the gate's acceptance is then about the
   mutant's own definitions.
   After a rejection, for a `breaks=` case, **refutation:** a Challenge generated from
   `core/Challenge/Resolver.lean` with each named theorem negated
   (`theorem _root_.Mitos.Refute.<t> : ¬ (<approved statement, each name as _root_.<name>>)`, round
   4 below), the holes as values and the approved permitted axioms. It must accept: each named
   theorem is proved false for the mutant's own definitions.

A control run first judges the unmutated core as run 2 does, and must accept, so a rejection comes
from the mutant and not from the workspace.

### Binding a refutation to the mutant

**The premise that failed.** Two fixes for "a refutation about code the case wrote itself" failed
review on #86, and both assumed one premise:

> The case's `Refute.lean` can share a Lean environment with the mutated core, and a check on that
> environment stops it from standing in for a definition hole.

- Fix 1 also judged the refutation on the unmutated core and required a rejection there. A
  `Refute.lean` whose own `impact` uses a helper that builds only on the mutant beat it.
- Fix 2 made the solution module import every `Mitos/Impl/` module before the case's file, so that
  a second declaration of a hole clashed. A mutant that makes `def resolve` `private` beat it: the
  case then declares a public `Mitos.Impl.resolve` of its own without a clash.

The comparator compares a definition hole by its name and type only, and the case controls both
the mutated core and the code in the solution's environment. So no check on that environment can
tell which declaration is the hole.

**Test of the premise.** Round 1's runner (a08b51b) reports the private-hole cheat and the known
gap with a private hole (`cheat_private_hole`, `cheat_hide_gap`) REFUTED, and also an
implementation that imports the case's module and one that reads it with `include_str`. It reports
a caught bug whose proof repair declares its own resolver (`cheat_proofs_own_hole`) as a known
gap. Directly with `lake comparator`, on the known gap's mutant with a `Refute.lean` that declares
its own `Mitos.Impl.resolve` (`cheat_own_hole`): with the holes as definition holes it is accepted
(`Your solution is okay!`); with the holes as values it is rejected (`Const does not match between
challenge and target 'Mitos.Impl.resolve'`).

**The premise this design makes true.**

> In every run that counts a mutant (refutation, values), each definition hole is compared by
> value with the public declaration of the mutated `Mitos/Impl/` modules; and those modules build,
> and declare every approved hole publicly with its approved type, in a workspace that holds only
> the approved core and the mutant's implementation edits.

- **Holes as values.** The generated Challenges drop the approved hole lines
  (`def Mitos.Impl.resolve : … := sorry`) and import every `Mitos/Impl/` module of the mutated core
  instead, and their configurations name no definition holes. A hole is then an ordinary constant
  of the Challenge, and the comparator requires the solution's to be identical: the same type, the
  same value, and every constant it uses identical too. Whatever the case declares or imports, a
  hole that is not the mutant's is rejected. The case's `Refute.lean` is written as
  `Mitos.Proofs.RefuteCase`. The generated solution module `Mitos.Proofs.Refute` imports it and
  nothing else, and proves `Mitos.Refute.holes`, which names every hole, so every hole is compared
  in every refutation run, also one the named theorems do not mention.
- **The hole run** shows that the values compared are the mutant's: the implementation builds with
  no file of the case present, and it declares each hole publicly, so a `private` hole stops there.
  `Mutants.holeCore_spec` proves that the hole run's core holds only paths of the approved core
  outside `Mitos/Proofs/`, and that each file outside `Mitos/Impl/` is the approved one;
  `Mutants.holeCore_impl`, that its `Mitos/Impl/` files are the other runs'. The hole run alone does
  not show that the implementation reads no file of the case: an `include_str` inside
  `first | … | …` builds without the file, and that is the lint's job (round 3, below).
- **The values run** binds the gate's acceptance the same way, so a known gap whose proof repair
  declares a resolver of its own is not a known gap (review on #86, opus m2).

**Options considered.**
- Chosen: isolation in the form the comparator supports itself, the comparison by value, with the
  hole run for the workspace that holds no file of the case. It removes the case's ability to
  supply a different hole, instead of blocking known tricks one by one.
- A generated module that imports only `Mitos/Impl/` and names each hole, imported by the solution:
  it still binds by name, inside an environment the case shares. An implementation that imports or
  reads the case's file defeats it unless more checks are added.
- Refusing edits that touch `import`, `private`, `namespace`, `end` or a hole's `def` line: a list
  of known tricks. `protected`, `export`, a macro or `include_str` is not on it.
- `--challenge-from-export` from a workspace without the case's file: `lake comparator` has no
  export-only mode, so the runner would need its own `bwrap` sandbox around `lake build` and
  `leanexport`, a second sandbox to trust. The hole run gets that workspace from the comparator's
  own sandbox.
- Round 1's import binding is gone. It rested on the failed premise, and a case that it rejects (by
  a clash) would not pin the comparison by value.

### The case's Lean text: the lint (round 3)

**What failed.** Round 2's design was sound for the holes but took a case's Lean text as inert.
Both reviews of f1f5dad found a REFUTED for code the case wrote, through code that runs or
rewrites syntax while Lean elaborates:
- an implementation edit adding ``macro_rules | `(Mitos.Spec.AssumptionsExact $x) => `(False)``:
  the refutation Challenge imports the implementation before the approved statement lines, so the
  macro rewrites the statement, and `fun h => h` refutes it, for a correct implementation as for
  the known gap, also with `--paranoid` (opus B1);
- `def resolve := by (first | exact (let _ := include_str "../Proofs/RefuteCase.lean"; bogus) | exact real)`:
  the hole and gate runs, without the case's file, build the real resolver, and the refutation
  run, with it, the bogus one (sonnet B1);
- `import Lean` and a `run_cmd` that declares a bogus `resolve` when the case's file exists (opus
  m1), and a `macro_rules` twisting `¬` (sonnet m1).

The root cause: the manifests' `replace=` texts and `Refute.lean` are untrusted Lean source, and
Lean runs code while it elaborates source.

**The premise this round makes true.**

> Every Lean text a case wrote or changed (each `replace=` text, each file its edits change, and
> its `Refute.lean`) imports only the approved core and the implementation, contains only
> declarations that Lean's built-in code elaborates, and runs no code of the case and declares no
> syntax while Lean elaborates it. So the mutated implementation elaborates the same in every run,
> whatever other files the run holds, and the generated Challenges that import it state exactly the
> approved statements.

**The lint** (`Mutants.Lint`), before any build, in every run of the runner (and in `--prepare`):
an allow-list read from Lean's own parse, with the syntax of `Init` alone, which is all the approved
core and the implementation see:
- imports only under `Mitos.Core` and `Mitos.Impl` (`Mitos.Proofs` too in a known gap's proof
  repair), plain `import`s, no `module` or `prelude`;
- commands only a module doc, `namespace`, `section`, `end`, `open`, and `def`, `theorem`, `abbrev`
  and `example` declarations; so no `macro`, `syntax`, `notation`, `elab`, `run_cmd`, `#eval` or
  any other `#` command, `initialize`, `instance`, `attribute`, `set_option`, `open … in`;
- no attribute anywhere (`@[…]`);
- no token with a component on gate 1's token-component rules, taken from `gate/MitosGate/Lint.lean`
  (`include_str` from `Rule.fixed`, and `banned`: `macro_rules`, `Lean`, `native_decide`, `sorry`, …), nor `by_elab` or
  `run_tac`, the forms that run code inside an allowed declaration (`runsCodeInTerm`), nor
  `set_option` or `attribute` inside a declaration either (`commandsInTerm`); and no `#` token.
  `Mutants.Lint.bans` is those components and these, with round 4's `deriving` (`addsInstance`) and
  round 5's `with_decl_name` (`declaresNestedAbsolute`). A term-level `open … in` stays
  allowed, for a namespace under `Mitos` only (round 4): `Init` declares scoped syntax that `open`
  switches on (`open Int` adds `-[n+1]`), which the lint's parse would not see.

A text Lean's parser cannot read to the end is refused. Each `replace=` text is also checked as
plain text, without Lean's parser: no `#`, no `@[`, no banned word standing alone. The lint allows
`private` and ordinary declarations: they run nothing, and the hole run and the comparison by value
judge what they declare, so the cheat cases that pin those checks (`cheat_private_hole`,
`cheat_own_hole`, `cheat_proofs_own_hole`) still reach them.

**Options considered.**
- Chosen: the lint, as an allow-list. It removes the class at its root, code the case wrote that
  runs while Lean elaborates, instead of the ways such code was seen to fake a result. The
  allow-list is short because the approved implementation, its proofs and every committed
  refutation need nothing else; gate 1's ban list is reused, not copied.
- An Impl-free anchor run (opus fix a): also judge each refutation against a Challenge that does not
  import the implementation. It fixes what the statement means, but not what the implementation
  elaborates to in each run (sonnet B1), and every refutation would need a fourth comparator run.
- A ban-list of the commands seen so far: the next one not on it (`by_elab`, an `@[macro]`
  attribute) would get through.
- Every run's workspace holding the same files (sonnet's structural point): the hole run's job is a
  workspace without the case's files, so it cannot hold them; and with the lint it is not needed.
  An implementation that passes the lint elaborates from its own text and the modules it imports,
  which the lint limits to the approved core and the implementation; those texts are the same in
  every run (`holeCore_impl` for the hole run; the other runs share one mutated core), and the lint
  leaves no way to read any other file. So the files a run adds cannot reach it.

**What this does not cover.** Lean's built-in elaborators for the allowed commands, tactics such as
`decide` and `simp`, and the parser are trusted, as they are for the gate. The lint parses with
`Init`'s syntax and none of its scoped syntax. That is the syntax Lean parses a case's text with
because the approved core declares none, a text that passes adds none, and, since round 4, a text
that passes enters and opens only namespaces under `Mitos`, so it switches on none of `Init`'s
scoped syntax. Round 3 said this without the last condition, and it was false: `open Int` or
`namespace Int` switches on `-[n+1]` (review on #86, round 3, opus B2).

### Names in the generated statements (round 4)

**What failed.** Round 3's premise ended with "the generated Challenges that import it state exactly
the approved statements", because the implementation declares no syntax. A statement's names are
part of what it states too, and Lean resolves them against every declaration in scope, the
implementation's included. Lean elaborates `theorem Mitos.Refute.<t> : <stmt>` inside namespace
`Mitos.Refute`, so `Mitos.Spec.X` in it resolves first to `Mitos.Refute.Mitos.Spec.X`, then to
`Mitos.Mitos.Spec.X`, and only then to `Mitos.Spec.X`. An implementation edit adding
`def Mitos.Refute.Mitos.Spec.AssumptionsExact (_ : Mitos.Resolver) : Prop := False` made the
refutation Challenge state `¬ False`: the known gap and a correct implementation were REFUTED, also
with `--paranoid` (review on #86, round 3, opus B1). The same route points `Mitos.Impl.resolve`, in
the statement and in `Mitos.Refute.holes` alike, at a shadow resolver, so the comparison by value
checks the shadow; and the values run's statements, elaborated in namespace `Mitos.Proofs`, can be
redirected the same way.

**The premise that failed.**

> A generated line means what the approved line means, as long as nothing in scope declares
> syntax.

**The premise this round makes true.**

> Every name in every statement the runner generates resolves to the declaration of exactly that
> name, whatever the case declares.

Round 4 also claimed that every name a case declares lies in a namespace the case owns. That was
false for nested names, and round 5 (below) drops it.

**Decision: both parts, each closing the shadow class at a different point.**
- **The statements** (`Mutants.Challenge`). Every theorem the runner generates (each negation,
  `Mitos.Refute.holes`, the values run's theorems and the solution module's proof of the holes) is
  declared as `_root_.Mitos.Refute.<t>` or `_root_.Mitos.Proofs.<t>`, so Lean elaborates it in the
  root namespace, where a dotted name is looked up exactly; and `qualify` writes each name in it as
  `_root_.<name>`. `qualify` takes only a statement that is a list of names under `Mitos`
  separated by single spaces, as all eight approved ones are, and the runner stops (exit 2) on any
  other, rather than qualify a statement it does not understand. `_root_.` alone would not be
  enough, and the root namespace is what makes the lookup exact: inside `Mitos.Refute`, Lean tries
  `Mitos.Refute._root_.Mitos.Spec.X` first. `Mutants.Resolution` checks both facts about Lean at
  every build, so a toolchain that changes them fails the canary.
- **The lint** (`Mutants.Lint`), as defence in depth. It follows `namespace`, `section` and `end`
  as Lean does (`walk`), and refuses a top-level `def`, `theorem` or `abbrev` named outside the
  case's own namespaces: under `Mitos.Impl` in an implementation file, under `Mitos.Refute` in a
  `Refute.lean`, under `Mitos` in a proof repair; `_root_` only as its leading component. It does
  not read names declared inside a declaration (`let rec`, `where`; round 5). A `namespace` or an
  `open` (command, term or tactic) must name a namespace under `Mitos`, which holds no scoped
  syntax: that makes the lint's parse Lean's (B2 above). `deriving` is banned, the one allowed form
  that would add an instance, which instance resolution in a module that imports the text could
  pick up.
- A `Refute.lean` may also declare an approved definition hole (`Mitos.Impl.resolve`). That is the
  attack the hole run and the comparison by value reject, and `cheat_own_hole`,
  `cheat_private_hole` and `cheat_hide_gap` pin those checks only if the lint lets them through;
  refusing them at the lint would leave those checks with no case. A `Refute.lean` is imported by
  no Challenge, only by the solution module, whose statements the comparator compares with the
  Challenge's. Likewise a proof repair may declare under `Mitos.Impl` (`cheat_proofs_own_hole`).

**Options considered.**
- Chosen: both parts. The statements part does not depend on the lint's reading of Lean's parse,
  which is not proved; the lint part also fixes B2, and refuses a top-level shadow in every file,
  not only the generated ones (not a nested one, round 5).
- The statements part alone: it leaves B2, and a shadow in a file other than a generated one.
- The lint part alone: the binding would rest on the lint's reading of scopes, which is unproved
  code, for a check whose failure fakes a REFUTED.
- Comparing each generated statement with one elaborated without the implementation (opus's third
  option): one more elaboration or comparator run per case, to detect what the two parts prevent.
- `_root_.` names inside the namespace, without declaring at the root: not enough, as above.

**Test of the premise.** The round-3 runner (131cc15) reports each new case below REFUTED, one run
each, default kernel: the four shadows (fake) and the two scoped-syntax cases (genuine refutations
of `src_dst_swapped`, which only the lint stops). With the lint's name rules off and the absolute
names on, the four shadows are rejected at the refutation run (`Challenge and solution theorem
statement do not match`), so the statements part closes the class alone; the two scoped-syntax
cases are REFUTED, so the namespace and `open` rules are pinned by them.

### Nested names (round 5)

**What failed.** Round 4's second premise, "every name a case declares lies in a namespace the
case owns". The lint reads only the names of top-level `def`, `theorem` and `abbrev` commands.
`with_decl_name% N (let rec x … ; …)` declares `N.x` with `N` absolute, so an implementation edit
declared `Mitos.Refute.Mitos.Spec.AssumptionsExact := False` and passed the lint; and Lean declares
a `let rec` or `where` named `_root_.X` as `<decl>._root_.X` (review on #86, round 4, opus B1). No
case came back REFUTED: the root-declared, absolute statements did not resolve to the shadow, and
the refutation run rejected it on the statement mismatch. This is the second time the premise that
the lint can list every name a case declares has failed.

**Decision.** The guarantee rests on the statements part alone (round 4 above, checked by
`Mutants.Resolution` at every build). The lint's name rules stay as defence in depth, and they
check only the names of top-level declarations, and `namespace`s and `open`s. Nested
names are not read, and no `let rec` or `where` tracking is added: it would rest the claim on more
unproved reading of Lean's parse, for a class the statements part already closes. `with_decl_name`
is banned, as the token `with_decl_name%` (`bannedComponent`: a banned word followed by `%`) and as
a plain word in a `replace=` text, since it is the form that puts nested names under any namespace;
`cheat_with_decl_name` pins the ban.

### Block comments in the Challenge (round 6)

**What failed.** `Mutants.Challenge` said its reader of the approved Challenge fails closed, but it
took a block comment to end only when a line ended with the closer, and did not nest. Lean ends a
comment at its first closer and nests one opened inside it. So on `/- note -/ open Foo` the reader
stayed in the comment while Lean ran `open Foo`, and the reader kept the lines after it verbatim: a
hole line stayed (compared by type only) and a theorem line stayed un-negated. With a nested
comment, or an opener in the middle of a hole line, it read a theorem that Lean reads as a comment,
and it negated that statement although the approved Challenge does not make it (review on #86 by
CodeRabbit at 24b19e4). A string literal or an escaped name (`«`) in a hole line does the same,
since Lean reads both on past the line's end (found in this round). Each needs an owner edit of the
approved Challenge, which has one comment (`/-!` to `-/`, nothing else on those lines) and reads
the same before and after the fix.

**Decision.** The reader follows Lean's comments or refuses the line, with a clear error. Inside a
comment it takes a line only if the line holds no opener, and no closer but in its last two
characters; a line that opens a comment, only if the same holds after the opener and the closer does
not come right after the opener (`/--/` does not close, because Lean skips the character after an
opener); any other line, only if it is a line comment or holds neither, nor a `"` or a `«`.
`readLine_comments` proves that on every line the reader takes, `leanScan`, a transcription of Lean's
`Lean.Parser.finishCommentBlock`, ends where the reader goes on. The transcription is not proved;
`Mutants.CommentProbe` checks its premises against Lean at every build, one theorem each: code
after a closer is read (`afterClose_is_code`), comments nest (`nested_does_not_close`), and the
character after an opener is skipped, for `/-` and `/--` (`opener_skips_next_char`,
`doc_opener_skips_next_char`). The scratch inputs of
the review, and five more, are `#guard`s: the reader at 24b19e4 accepts all nine, the new one
refuses them.

### Definition hole lines (round 7)

**What failed.** The reader took a line for a definition hole when it started with `def ` and ended
with ` := sorry`, whatever came between. Lean reads `def f : T := 0 -- := sorry` as `f := 0`, the
`:= sorry` being a line comment, and `def f : T := 0 where g : T := sorry` the same way, the
`sorry` being the value of `f.g`. The reader dropped such a line as a hole, so the generated
Challenges took `f` from the mutated implementation and lost the value `0` the approved Challenge
states; `Mutants.Challenge`'s doc said no line that could change a statement is dropped (review on
#86 by CodeRabbit at e852fd5, which named the line comment; the `where` and tactic forms were found
in this round). Each needs an owner edit of the approved Challenge, whose two hole lines read the
same before and after the fix.

**Decision.** A hole line must also hold no `--` anywhere and no `:=` before its final ` := sorry`
(`holeLine`), so the value Lean reads is the `sorry`; any other `def` line is refused, with the
reader's error. This also refuses a hole with a default argument (`(x : T := v)`), which the approved
Challenge does not have. `readLine_hole` proves that every line the reader takes as a hole is outside
a comment and is one `holeLine` takes. Four `#guard`s pin it: the line comment after a value and
after the type, a `where`, and a tactic with its own `:= sorry`; the reader at e852fd5 takes all
four as holes, the new one refuses them.

### Definition hole lines (round 8)

**What failed.** Round 7's fix assumed that a `def` line with no `--` and no `:=` before its final
` := sorry` has the `sorry` as its value. Lean's declaration value has three forms
(`Lean.Parser.Command.declVal`): `:= expr`, equations (`| pat => expr`, with an optional `where`),
and structure fields after `where`. `holeLine` ruled out only the first. So the reader took these
lines for holes and dropped them, although Lean reads another value (`rfl` proves `f = fun _ => 0`):
`def Mitos.Impl.f : Nat → Nat | _ => 0 where g : Nat := sorry`, the same with
`| _ => by exact 0 <;> have x : Nat := sorry`, the first on the approved `impact` type, and
`def Mitos.Impl.c : Mitos.S where b := sorry`, whose other fields keep their defaults. With the
first added to a copy of the approved Challenge, `--prepare` at debeac7 exited 0 and dropped it
(review on #86 by the opus verifier at debeac7, B1). Each needs an owner edit of the approved
Challenge. The verifier also found that `readLine_hole` was cited for "the value Lean reads is its
`sorry`", while it proved only a fact about the line's text (m1).

**Premise.** Rounds 6, 7 and 8 each refused one more Lean form the reader misread. The premise
"refuse the forms we know are dangerous" kept failing, because Lean has more forms than a list
names.

**Decision.** A positive form (`holeForm`). A hole line is exactly `def <name> : <type> := sorry`,
where `qualName` takes the name, every character of the type is an ASCII letter or digit, `_`, `.`,
a space or `→` (`typeChar`), and its words, between single spaces, are `→`, `List`, `String` or
names under `Mitos` (`typeWord`). Any other line that starts with `def ` stops the runner with the
reader's error, as before. These are the words the approved Challenge's two holes use:
`Mitos.Resolver`, `List`, `Mitos.Edge`, `String` and `→`. (Round 8 also allowed `Nat`, only for the
`#guard`s' scratch holes; the no-comments round removed it, and those holes now have the type
`String`.) It has no parenthesis, `×` or comma, which the
approved Challenge does not need; a Challenge that needs them stops the runner until the reader
takes them. A word list instead of "identifiers except keywords" keeps the form positive at the
word level too: no keyword can be a word, because every allowed word is fixed or under `Mitos`.

`readLine_hole` (replaced) proves that every line the reader takes as a hole is outside a comment,
kept as it is, and exactly this form, through `holeForm_spec`; it says so and no more (m1). That
Lean reads the value of such a line as its `sorry` is a fact about Lean's parser
(`Lean.Parser.Command.definition`, pinned v4.35.0), not proved: Lean reads `def`, the name and
`: <type>` (no binder, since `:` follows the name), the type up to the ` := ` (no character that
starts a binder, comment, string, equation, `:=` or tactic block), and then the value `:= sorry`,
the `declValSimple` form; no word is a keyword (below), so no contract clause (`given`, `requires`,
`ensures`) comes first. The line ends with the `sorry`, and the reader takes the next line only as
a blank, a comment, an import, a hole or a theorem, so no `termination_by`, `where` or `deriving`
continues the declaration. Since round 9 the cross-check also requires, at every run, each hole's
value as Lean built it to be exactly `sorry` of its type. The one premise about keywords is checked:
`Mutants.Tokens` fails the build if a token of Lean's syntax or of `Mitos.Core` holds whitespace or
is a `typeWord` other than `→`. Its probe in this round found `Type`, `Sort`, `Prop` and `StateRefT`
among the tokens of a name's shape, which is why the allowed words are a list and not "capitalised
names". Lean's non-reserved keywords are not tokens; in the pinned toolchain's source every one
starts with a lower-case letter, and every allowed word starts with a capital or is `→` (read from
the source, not checked at build). The token table checked is that of Lean's command syntax plus
`Mitos.Core`, which holds every token the approved Challenge, importing only `Mitos.Core`, is read
with; a Challenge with another import is outside the check.

**Considered.** Asking Lean's own parser, at run time, whether each hole's value is exactly
`sorry`. That needs the Challenge's imports loaded in the runner and proves nothing about the
reader; the positive form is provable, and the one fact about Lean it needs is checked at build.

**Pinned.** Four `#guard`s refuse the verifier's forms, which the reader at debeac7 reads as holes;
more refuse keywords and Lean's name-shaped tokens as words, the characters that start other
syntax, an empty word, a name outside `Mitos` and a binder; two accept the approved Challenge's
two holes, with their names and types. Every earlier `#guard` stays as it was, round 6's and
round 7's refused forms included. The approved Challenge reads to the same 23 lines, 2 of them
holes, with the reader at debeac7 and the new one.

**Import lines (CodeRabbit at e9fa024).** CodeRabbit's review of this round's first head found the
same gap in import lines: the reader took any line that starts with `import ` for an import and
kept it. Lean's `import` takes one module name and reads what follows it as another import or as
commands after the header, so `import Mitos.Core namespace Mitos.Refute` put every generated
statement inside that namespace, against `Mutants.Challenge`'s doc, which said the generated files
have no `namespace` or `open`, and `import Mitos.Core theorem Mitos.Proofs.t : …` hid a theorem
the reader neither negates nor drops. CodeRabbit marked it minor; I judged it blocking as B1,
because a doc line of this PR was false for such a Challenge, and fixed it the same positive way:
an import line is exactly `import <module>`, each component a `qualPart` (`importForm`).
`readLine_imp` proves that every line read as an import is exactly that. Three `#guard`s refuse
the forms above (the reader at e9fa024 takes all three), and one accepts two plain imports; the
approved Challenge's `import Mitos.Core` reads as before.

### Lean cross-check (round 9)

**What failed.** The reader read a doc comment otherwise than Lean (present since e852fd5). Lean
reads `/--` and `/-!` as tokens and skips the whitespace and `--` line comments after them before
the comment's text begins (`docComment` is `"/--" >> ppSpace >> commentBody`, `moduleDoc` is
`"/-!" >> commentBody`). So after a line `/--`, a line `-- -/` is a line comment, and the doc
comment runs on to the next closer. The reader took that `-/` as the end, so on the lines
`/--`, `-- -/`, `theorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry`,
`-- -/` it read a theorem that Lean reads as doc text; with a `breaks=decoy` case, `--prepare` at
1265f31 exited 0 and wrote a negated theorem the approved Challenge does not state. The reverse
shape, a hole line in such a comment, was dropped as a hole that Lean never declares (review on
#86, round 9, the opus verifier at 1265f31, B1). Each needs an owner edit of the approved
Challenge.

**Premise.** Rounds 6, 7, 8 and 9 each found one more Lean form that the hand-written line reader
misreads: block comments, a `:= sorry` in a comment, equations and `where`, doc comment openers.
Emulating Lean's lexer by hand keeps failing, so this round adds no lexer rule. Round 8 rejected
asking Lean at run time ("proves nothing about the reader"); that was the wrong question. The
reader need not be proved right if every misread that changes what a generated Challenge states
stops the runner, and Lean is the one reader that cannot misread its own syntax. This round's
cross-check alone does not stop every such misread: it compares declarations, and a command that
declares nothing changes none (round 10, below).

**Decision.** `Mutants.CrossCheck`. Before it prepares or judges anything, the runner builds the
approved Challenge module (`lake build Challenge.Resolver`) in a fresh copy of the approved core,
loads it as Lean built it (`Lean.importModules`, `ModuleData`), and compares it with the reader's
lines (`problems`). Any difference stops the runner with exit 2 and names each difference. It
requires:

1. Lean's constants of the module, all of them (no auxiliary name is filtered out, so a `where`
   or a `match` stops the runner), are exactly the reader's theorems and holes: the same names,
   each name starting on the line the reader read it from and at its column (Lean's selection
   range), each theorem's statement a constant applied to constants named by the statement's
   words, and each hole a safe definition whose value is exactly `sorry` of its type
   (`sorryAx T s`, or the labeled `sorryAx (τ → T) s tag` that `sorry` elaborates to here).
2. The holes the reader read are exactly `definition_names` of `core/comparator.json` (this
   covers m3).
3. The module's imports are `Init` and the reader's import lines.

The positions are what the root's brief did not ask for: without them, a theorem Lean declares
from a line the reader keeps as a comment, and a same-named one the reader reads where Lean sees a
comment, would match by name and statement. `problems_nil` proves what an empty result means:
Lean's declarations are exactly `expected` (each a theorem or hole line at its line,
`mem_expected`), the holes are exactly the configured ones, and the imports are exactly `Init` and
the reader's. `readLines_getElem?` proves the reader's line at index `i` is its reading of source
line `i + 1`, and `holeName_of_holeForm` that the hole name compared is the one `holeForm` took.
Lean's side (`declOf`: the constants, their positions, the `sorry`) is not proved.

**Probes.** So that the check cannot go blind unnoticed, the same `lake build` builds three scratch
Challenge modules, and the comparison must find each one's known misread, every run: the decoy
(`undeclared Mitos.Proofs.decoy`), the reverse with `def Mitos.Impl.extra : String := sorry`
(`undeclared Mitos.Impl.extra`), and round 8's value hole
`def Mitos.Impl.f : Nat → Nat | _ => 0 where g : Nat := sorry` (`differs Mitos.Impl.f`, value not
`sorry`, and `unread Mitos.Impl.f.g`). The first two lists of lines are what `readChallenge`
reads (a `#guard`); the value line the reader refuses, so that probe reads it as a hole, as a
looser reader would. On the approved Challenge the runner prints
`challenge (reader against Lean's build): AGREE on 10 declarations, 3 probes caught`.

**The reader.** Its lexer stays as it is. It reads comments as `leanScan` does, which is not all
of how Lean reads them; it is a fast first pass, and the cross-check is what stops the runner on a
misread that changes a declaration (round 10 adds the checks for a misread that changes none).
Round 9 reworded the reader's docs to say only this, and m1's sentence on rounds 7 and 8; the
no-comments round removed those docs, and this file keeps what they said.

**Evidence** (one local run each, default kernel; the check does not depend on `--paranoid`).
`--prepare decoy_case` on a copy of the repository whose approved Challenge holds, before the
`resolve` hole: the decoy (exit 2, `the reader read Mitos.Proofs.decoy, a theorem stating
Mitos.Spec.Sound Mitos.Impl.resolve, at line 14, column 8; Lean declares nothing of that name`, no
workspace written); the same after a `/-!` opener (exit 2, the same); the reverse (exit 2,
`Mitos.Impl.extra ... Lean declares nothing of that name`, and not in `definition_names`); round
8's value line (exit 2, the reader's error, before the check). On the approved Challenge it agrees
and goes on (exit 1 there only because `decoy_case` names a theorem the Challenge does not state).
With the check switched off in three ways in a scratch build, the probes stop the runner: `sorryOf`
always true (exit 2, the value probe's `differs Mitos.Impl.f` missing), no positions read (exit 2,
every approved theorem and hole differs), and no `unread` problems (the build fails on a
`#guard`).

**Cost.** 4.4 to 5.5 s per runner run (9 local runs: one `lake build` of the approved core's
`Mitos.Core`, the Challenge and three probes in a fresh workspace, about 3 s, and four imports).
The full run of the cases took 879 s with `--paranoid` (41 cases, round 4, one local run), so the
check adds under 1%.

**Considered.** One more lexer rule for doc comment openers: the brief rules it out, and rounds 6
to 9 show why. Filtering auxiliary names (`match_`, `proof_`, `_private`): the approved
Challenge's module holds none, and a filter is one more list that can miss, so every constant must
be read. Elaborating the Challenge in the runner's own process instead of `lake build`: faster, but
it would read `Mitos.Core` from the repository's build outputs, which the runner never trusts.

### Output check (round 10)

**What failed.** Round 9's cross-check compares what the approved Challenge declares, and a command
that declares nothing changes no declaration. Between the two hole lines, the lines `/-!`, `-- -/`,
`/-- x -/` and `-- -/ variable (h : False) in include h in` are four comment lines to the reader,
but Lean skips the line comment after the module doc's opener, nests the doc comment, and ends the
module doc at the closer on the fourth line, so `variable (h : False) in include h in` is code that
prefixes the `impact` hole, whose value stays `sorry`. The cross-check agreed. The refutation
Challenge drops the hole lines and the theorems not named, so there the prefix lands on
`theorem _root_.Mitos.Refute.resolve_total`, which then states `False → ¬ Total resolve`, and a case
whose `Refute.lean` proved that by `h.elim` was judged REFUTED, exit 0; on the real Challenge it is
REJECTED, exit 1. A hidden trailing `namespace Mitos.Impl` or `#exit` passed too (review on #86,
round 10, the opus verifier at a528c7e, B1). Reproduced at a528c7e: `r10_b1  REFUTED`, exit 0.

**Premise (attacked a second time).** Rounds 6 to 9 each tried to make the reading of the input
match Lean: lexer rules, then a cross-check of the declarations. Each round a verifier found Lean
syntax that changes meaning without the reader seeing it. The invariant that matters is about the
output: every Challenge the runner judges with states exactly the approved statements. So this
round checks the output with Lean, and also asks Lean's parser about the input, so that no hidden
command is left at all.

**Decision.** `Mutants.Output`, run after the cross-check and before anything is prepared or judged;
any difference stops the runner with exit 2 and names it.

1. **The output check** (`outProblems`). The runner computes, as it writes them
   (`refutationGen`, `valuesGen`), the texts of every Challenge it will judge with for the cases it
   runs or prepares: the values Challenge, and the refutation Challenge of each distinct `breaks=`
   list (11 for the whole corpus). In the cross-check's workspace (a fresh copy of the approved core)
   a second `lake build` builds each one as a module of its own, and the runner loads it as Lean
   built it. Its constants (all of them, as in round 9) must be exactly the theorems it must
   declare, each a theorem with no universe parameter whose type, as an `Expr`, is: `Not T` for
   `Mitos.Refute.<n>`, and `T` for `Mitos.Proofs.<n>` in the values Challenge, where `T` is the type
   of the theorem `Mitos.Proofs.<n>` of the approved Challenge module as Lean built it; and for
   `Mitos.Refute.holes`, `(h₁, h₂) = (h₁, h₂)` over the configured holes, as `Meta.mkAppM` and
   `Meta.mkEq` build it in the approved Challenge's environment. Types are compared with `==`
   (`Expr.eqv`: structural, binder names ignored) after every universe level is normalized: no
   unfolding, no definitional equality. Its imports must be `Init`, the implementation modules and
   the approved imports. `refutationGen_names` proves that the names it checks in a refutation
   Challenge are the names the refutation run's configuration gives the comparator
   (`refutationNames`), and `prepare` writes no Challenge text the check did not pass (it throws,
   so the case is INVALID). `outProblems_nil` proves what an empty result means.
2. **The parse check** (`parseProblems`). Lean's parser (`MitosGate.Lint.parse`), with the syntax of
   the modules the approved Challenge imports (`importModules … (loadExts := true)`), reads its
   header and commands. Every command must be a module doc or exactly one of the reader's hole or
   theorem lines (a declaration starting at column 0 of that line, whose text is the whole line);
   every such line must be one; the header must import exactly the reader's import lines, in order,
   each plain. `parseProblems_nil` proves what an empty result means: the lines the reader keeps as
   comments or blanks hold no command. A declaration doc comment starts its command before the
   line, so a hole or theorem may have none (the approved Challenge has none).

**What it proves, and what it does not.** With the three checks passing, Lean's parse of the
approved Challenge has no command but module docs and the reader's lines; Lean declares exactly the
reader's theorems and holes (round 9); and each generated Challenge, as Lean builds it with the
approved implementation, declares exactly the theorems its run compares, each of exactly the
intended type. Not checked by them: the case's own runs import the mutated `Mitos/Impl/` modules,
not the approved ones, because the runner never builds a case's code outside the comparator's
sandbox (Binding a refutation to the mutant, above); that the mutated implementation changes nothing in how the generated text
elaborates rests, as before, on the lint and the absolute names (rounds 2 to 5). The parse check is
what removes a hidden command in the approved Challenge whose effect could depend on the
implementation or on the module name (each generated text is built as a module of its own name, not
`Challenge.Mutant`). The parse uses the syntax of the Challenge's imports; a command of the
Challenge that declares syntax is itself a command, which the parse check refuses.

**Probes.** Every run, the parse check must find its known problem in five scratch sources: B1, a
trailing hidden `namespace Mitos.Impl`, a trailing hidden `#exit`, and round 9's decoy and reverse.
The output check must find its known problem in the refutation Challenges generated, for
`breaks=resolve_total`, from two scratch approved Challenges built in the same workspace: B1
(`differs Mitos.Refute.resolve_total`) and the trailing `#exit` (`missing Mitos.Refute.holes`). A
trailing hidden `namespace` changes no constant of a generated Challenge, whose declarations are all
named with `_root_`, so the output check rightly finds nothing there (below). With `sameType`
always true in a scratch build, the runner exits 2 (`the output check missed a known misread in
Challenge/OutputProbeB1.lean`); with the parse reading only declarations, it exits 2 (`the parse
check missed a known misread in probe b1`).

**Evidence** (one local run each, default kernel). Each shape inserted into a copy of the
repository's approved Challenge, with the case `r10_b1` (`breaks=resolve_total`, `Refute.lean`
proving `(h : False) → ¬ Spec.Total Impl.resolve` by `h.elim`), against the runner and against
scratch builds with checks switched off:

| shape | runner | output check alone | parse check alone | cross-check alone (round 9) |
|---|---|---|---|---|
| B1 | exit 2, parse: `in` command at line 16 | exit 2, values Challenge: `Mitos.Proofs.resolve_sound` differs | exit 2 | REFUTED, exit 0 |
| trailing `namespace Mitos.Impl` | exit 2, parse: `namespace` command | no difference; REJECTED, exit 1 (the true result) | exit 2 | REJECTED, exit 1 |
| trailing `#exit` | exit 2, parse: `exit` command | exit 2, `Mitos.Refute.holes` missing | exit 2 | REJECTED, exit 1 |
| round 9 decoy | exit 2, cross-check (round 9's message) | exit 2, a generated Challenge does not build (unterminated comment) | exit 2 | exit 2 |
| round 9 reverse | exit 2, cross-check | exit 2, a generated Challenge does not build | exit 2 | exit 2 |
| round 8 value line | exit 2, the reader refuses it | the same | the same | the same |

A decoy after a module doc's opener with a `breaks=decoy` case, so that every generated Challenge
builds: output check alone, exit 2, `the values Challenge: the approved Challenge as Lean built it
declares no Mitos.Proofs.decoy`. On the approved Challenge: `AGREE on 10 declarations, 3 probes
caught`, `AGREE on 11 commands, 5 probes caught`, `11 state what they must, 2 probes caught` (all
42 cases, `--prepare`).

**Cost.** 12.4 to 13.2 s per runner run for all three checks over the whole corpus (3 local runs,
`--prepare` of all 42 cases: two `lake build`s and about 20 imports), against 4.4 to 5.5 s for
round 9's check alone; 879 s was the full run with `--paranoid` (round 4), so under 2%.

**Considered.** Loading the generated Challenge as the comparator built it in the case's workspace:
it imports the case's code, and the runner never loads a case's `.olean` outside the sandbox. A
second comparator run per case, judging the generated Challenge against a clean reference with
`sorryAx` permitted: it would check the sandboxed build, but doubles the comparator runs and still
needs this check for the reference. Dropping the comment lines from the generated Challenges: it
would remove hidden code from the output instead of stopping on it, and leaves the approved
Challenge's own hidden commands unseen. m1 (each `differs` reported twice): the stop message now
lists each difference once (`eraseDups`); `CrossCheck.problems` itself is unchanged, since changing
it would take its proof and a `#guard` with it.

### Comments cut (no-comments round)

**What changed.** The owner's `/no-comments` pass cut the runner's comments and module docs, keeping
a few docstrings and `Mutants.Tokens`'s doc. What the cut docs said that matters is in this file:
what is proved and what is not (The rest, below), and the facts about Lean's parser (rounds 6 to
10). Seven places were reshaped so that the code says what a comment said, with no change in
behaviour:
- `Mutants.leanTypeNames` is `List` and `String`. `Nat` was there only for the `#guard`s' scratch
  holes; those 23 `#guard`s and the reverse probe now use `String` and are otherwise unchanged.
- `Mutants.CommentProbe` is a module of its own, one theorem per Lean fact (round 6).
- `Mutants.Lint.bans` is gate 1's list and four lists named by their reason (round 3): the same
  list, in the same order.
- `Mutants.Output.hiddenVariableSource` (was `b1Source`) is named after its trick, as
  `trailingSource` is.
- The status refutations' `str` is `strNoLiterals` (String literals and the replay kernels, below).
- `rejectionEvidence` in `Main.lean` gives the evidence lines the case loop printed, through named
  predicates (`isPanic`, `isFileError`, `isLogError`, `isCheatCase`, `unexpectedRejection`).
- `CrossCheck.thmDecl`, `holeDecl`, `holeName` and `importNames` take their columns and drops from
  `"theorem ".length`, `"def ".length` and `"import ".length`.

**Evidence** (one local run each, default kernel). The full corpus: all 42 cases as expected, 20
refuted, 2 known gaps, 20 cheat cases rejected (457 s); the four renamed refutations also with
`--paranoid`. The shapes of rounds 9 and 10 in copies of the approved Challenge (the hidden
`variable … in include … in`, a trailing `namespace` and `#exit`, the decoy and the reverse) stop
`--prepare` with exit 2, and the runner prints the same as the 38ff9f1 runner on each and on the
approved Challenge, which still reads to 23 lines, 2 of them holes. The diff against 38ff9f1
removes no `#guard` or theorem but those re-added with the renames above, and
`CommentProbe.probes`, split into four.

### Cases

`eval/mutants/cases/<name>/` holds a manifest `mutant` (`why=`, `breaks=` or `survives=`, an
optional `rejects=`, and `file=`/`find=`/`replace=` edits) and, for `breaks=`, `Refute.lean`.
The manifest holds one `key=value` per line, the value being everything after the first `=`,
spaces included; empty lines are skipped, and `file=` (a path under `core/`) sets the file for the
`find=`/`replace=` pairs after it. Edits instead of copies of the implementation files (#9 copied
them): the manifest shows the bug as a one-line diff, and when `core/Mitos/Impl/` changes, a
mutant whose text no longer occurs
exactly once fails as INVALID instead of silently testing an old copy. A `breaks=` case may edit
only `Mitos/Impl/`. A `survives=` case records a known gap: its gate run and its values run must
accept, with proof repairs under `Mitos/Proofs/` where a proof needs one, which shows the mutant
meets every Challenge theorem.

A case with `rejects=<stage>` is a **cheat case**: its claim must not be counted, and the named
stage must reject it after every earlier one let it through. Each pins one check: without that
check the claim is counted or the case is rejected elsewhere, so the run fails. The column
"without" is the result with that check switched off in a scratch copy of the runner (one run
each, default kernel):

| Case | The cheat | Rejected at, with | Without | Round 2 runner |
|---|---|---|---|---|
| `cheat_impl_macro` | no bug; the implementation's `macro_rules` turns `AssumptionsExact _` into `False` (opus B1) | lint: `macro_rules` | lint: REFUTED | REFUTED |
| `cheat_impl_macro_gap` | the known gap, plus that `macro_rules` (opus B1) | lint: `macro_rules` | lint: REFUTED | REFUTED |
| `cheat_include_str_first` | the known gap, plus `resolve := by first \| exact (… include_str …; bogus) \| exact real` (sonnet B1) | lint: `include_str` | lint: REFUTED | REFUTED |
| `cheat_impl_run_cmd` | the known gap, plus `import Lean` and a `run_cmd` that declares a bogus `resolve` when the case's file exists (opus m1) | lint: `import Lean`, `run_cmd` | lint: REFUTED | REFUTED |
| `cheat_refute_macro` | `Refute.lean` reads `¬ _` as `True` with a local `macro_rules` | lint: `macro_rules` in `Refute.lean` | lint: rejected at refutation (statement mismatch) | rejected |
| `cheat_include_str` | the known gap, plus a `resolve` that turns bogus when `include_str` finds the case's file | lint: `include_str` | lint: rejected at holes (`no such file or directory`) | rejected at holes |
| `cheat_impl_imports_case` | `Mitos/Impl/Resolve.lean` imports the case's module and takes `resolve` from it | lint: `import Mitos.Proofs.RefuteCase` | lint: rejected at holes (`bad import`) | rejected at holes |
| `cheat_native_decide` | proves `False` with `native_decide` on an `implemented_by` lie | lint: `@[implemented_by]`, `native_decide` in `Refute.lean` | lint: rejected at refutation (`Illegal axiom`) | rejected |
| `cheat_own_hole` | the known gap as `breaks=`; `Refute.lean` declares its own `Mitos.Impl.resolve` and does not import the real one | refutation: `Const does not match … 'Mitos.Impl.resolve'` | holes by type: REFUTED | rejected |
| `cheat_private_hole` | `private def resolve`; `Refute.lean` declares a public one | holes: the exporter finds no `Mitos.Impl.resolve` | hole run: rejected at refutation instead | rejected |
| `cheat_hide_gap` | the known gap, plus `private def resolve` and an own resolver | holes: as above | hole run: rejected at refutation instead | rejected |
| `cheat_proofs_own_hole` | `src_dst_swapped` as a known gap; the proof repair declares a correct resolver of its own | values: `Const does not match … 'Mitos.Impl.mkEdge'` | values run: SURVIVED | rejected |
| `cheat_namespace_shadow` | refutes a shadow `Mitos.Refute.Impl.resolve` | refutation: statement mismatch | (the comparator's own check) | rejected |

The first five are new in round 3; the next three were rejected at a later stage before the lint
ran first, and the lint now rejects them too. The rows below them are round 2's, unchanged; their
"without" results are round 2's (one run each), whose runner they still describe, since the lint
passes those cases. Round 1's runner (a08b51b) reported `cheat_private_hole`, `cheat_hide_gap`,
`cheat_impl_imports_case` and `cheat_include_str` REFUTED and `cheat_proofs_own_hole` as a known
gap.

Round 4 adds six, all rejected at the lint. "Without" is the result with the lint's name rules off
(no scope or `open` read) and the absolute names on; "Round 3 runner" is 131cc15's (one run each,
default kernel):

| Case | The cheat | Rejected at, with | Without | Round 3 runner |
|---|---|---|---|---|
| `cheat_impl_shadow_gap` | the known gap as `breaks=`; the implementation declares `Mitos.Refute.Mitos.Spec.AssumptionsExact := False` and a clashing `Mitos.Proofs.resolve_sound` (opus B1) | lint: names outside `Mitos.Impl` | refutation: statement mismatch | REFUTED |
| `cheat_impl_shadow_nobug` | no bug, the same two declarations (opus B1) | lint: as above | refutation: statement mismatch | REFUTED |
| `cheat_impl_shadow_theorem` | `src_dst_swapped` claimed to break `StatusHonest`; the implementation declares `Mitos.Refute.Mitos.Spec.StatusHonest := False` (opus B1) | lint: as above | refutation: statement mismatch | REFUTED |
| `cheat_impl_shadow_resolve` | `src_dst_swapped` claimed to break `AssumptionsExact`; the implementation declares a shadow resolver `Mitos.Mitos.Impl.resolve`, which the statement and `Mitos.Refute.holes` named | lint: as above | refutation: statement mismatch | REFUTED |
| `cheat_open_scoped` | a `Refute.lean` with `open Int`, so Lean reads `-[1+1]` as `Int.negSucc 1` and the lint as `-` of a list (opus B2) | lint: `open Int` | REFUTED (a genuine refutation) | REFUTED |
| `cheat_namespace_scoped` | the same with `namespace Int` | lint: `namespace Int` | REFUTED (a genuine refutation) | REFUTED |

Round 5 adds one, rejected at the lint. "Without" is the round-4 runner (98f2548, without the ban;
one run, default kernel):

| Case | The cheat | Rejected at, with | Without |
|---|---|---|---|
| `cheat_with_decl_name` | the known gap as `breaks=`; the implementation declares `Mitos.Refute.Mitos.Spec.AssumptionsExact := False` through `with_decl_name%` and a `let rec` (round 4, opus B1) | lint: `with_decl_name%`, and `with_decl_name` in the `replace=` text | refutation: statement mismatch |

### The rest

**Lean first.** The runner is a small Lake package, `eval/mutants/` (`lean_exe mitos-mutants`),
outside the root package so `gate/` and the root `lakefile.toml` are unchanged and the parallel
`mitos-gate cheats` work does not conflict. It requires the root package only to import gate 1's
lint (`MitosGate.Lint`). Its pure logic is proved, and the package builds with `warningAsError`, so
a `sorry` fails it:
- `Mutants.Edit`: an edit applies only where its text occurs exactly once, and replaces that
  occurrence and nothing else (`splitOnce_eq_some_iff`, `applyEdit_eq_some_iff`); edits add and
  remove no file (`applyEdits_paths`), and files no edit names are unchanged (`applyEdits_lookup`).
- `Mutants.Manifest`: `parse` returns only valid manifests (`parse_valid`): a `breaks=` case edits
  only `Mitos/Impl/` (`valid_breaks_impl`), no case edits outside `Mitos/Impl/` and
  `Mitos/Proofs/` (`valid_area`, `inArea_head`), and a `rejects=` run fits the claim
  (`Stage.fits`: `refutation` needs `breaks=`, `values` needs `survives=`).
- `Mutants.Lint`: a source with no finding parses to the end, imports only under the kind's
  prefixes, holds only allowed commands, no attribute and no token outside `tokenOk`, enters and
  opens only namespaces under `Mitos`, and gives each top-level declaration only a name its kind
  may have (`Kind.declOk`), as `walk` follows its scopes (`problems_eq_nil_iff`; `walk` itself is
  checked by `#guard`s); a token passes only if no component is a banned word or one followed by
  `%` (`tokenOk_iff`); a `replace=` text the plain-text check passes holds no `#`, no `@[`, and no
  banned word standing alone (`replaceProblems_banned`, from `mem_words`); every file an edit
  changes is linted (`mem_targets`). Reading a source with Lean's parser is not proved, and names
  declared inside a declaration are not read.
- `Mutants.Challenge`: `qualify` accepts a statement exactly when it is a list of names under
  `Mitos`, and writes each as `_root_.<name>` (`qualify_eq_some`, `qualName_mitos`); the refutation
  Challenge holds only imports of the implementation modules, the approved Challenge's import and
  comment lines, root-declared negations of named Challenge statements, qualified, and
  `Mitos.Refute.holes`, each named theorem stated exactly once and its negation there
  (`mem_refutation`, `refutation_once`, `refutation_states`); the approved Challenge by value holds
  each approved theorem, root-declared and qualified, and nothing else of theirs
  (`mem_approvedByValue`, `approvedByValue_states`); neither holds a definition hole line. The hole run's core holds no file
  under `Mitos/Proofs/` and only the implementation edited (`holeCore_spec`). The reader refuses
  any Challenge line that could change a statement's meaning if dropped (`open`, `namespace`, a
  multi-line statement), and on every line it takes, `leanScan` (Lean's scan of a comment's text)
  ends where the reader goes on (`readLine_comments`, from `commentLine_scan` and
  `openerLine_scan`); `leanScan` transcribes Lean's lexer without proof, and `Mutants.CommentProbe`
  checks its premises at build. It is not all of how Lean reads a comment (a doc comment's opener,
  round 9), so the reader is a first pass and `Mutants.CrossCheck` stops the runner when it
  misreads. Every line it takes as a definition hole is exactly
  `def <name> : <type> := sorry` with a name under `Mitos` and a type of `typeChar`s and
  `typeWord`s (`readLine_hole`, `holeForm_spec`); that Lean reads its value as the `sorry` is not
  proved, and `Mutants.Tokens` checks at build that no Lean token is a word such a line may hold
  but `→`. Every line it takes as an import is exactly `import <module>` (`readLine_imp`). The
  hole run's `Mitos/Impl/` files are the other runs' (`holeCore_impl`).
- `Mutants.CrossCheck`: when the comparison of the reader's lines with the Challenge as Lean built
  it finds nothing, Lean's declarations are exactly the reader's theorems and holes, each at the
  line it was read from, with the read statement or a `sorry` value, the holes are exactly the
  configured ones, and the imports are exactly `Init` and the reader's (`problems_nil`,
  `mem_expected`, `readLines_getElem?`, `holeName_of_holeForm`). Reading the constants, their
  positions and the `sorry` from Lean's build is not proved; three probes check it at every run.
- `Mutants.Verdict`: the run passes exactly when the control is accepted, every case is judged
  exactly once and meets its expectation (`passes_iff`). Then every `breaks=` case passed the lint,
  had its hole run accepted, its gate run rejected and its refutation accepted (`passes_refuted`);
  every `survives=` case passed the lint and had its hole, gate and values runs accepted
  (`passes_survived`); every cheat case was rejected at its stage and counted neither as refuted
  nor as surviving (`passes_rejects`); and the lint refused only cheat cases that expect it, with
  no comparator run (`passes_refused`).
- `Mutants.Implied`: `Total` follows from `Complete` and `UnresolvedExact`, and `RetractExact`
  from `Sound`, `Complete` and `AssumptionsExact`. So no mutant can break either alone.
- `Mutants.Resolution`: Lean's name resolution as the generated statements rely on it (a dotted
  name is exact at the root; `_root_.` alone is not enough inside a namespace), checked at build.

The file I/O, the process calls and the printing in `Main.lean` are not proved.

**String literals and the replay kernels.** The status refutations build in Lean with string
literals, but the comparator rejected them: with `decide`, Lean's kernel could not reduce the
replayed `decide` term to `true`, and with `simp` (as #9 did), lean4lean failed on `loc` with
`unknown constant 'Char.ofNat'`: the export declared `loc`, with its literals, before
`Char.ofNat`. Those four refutations therefore write their strings with `String.ofList`
(`strNoLiterals ['a']`), which makes the export declare it first; with `decide` they then pass all
five kernels under `--paranoid`. The other refutations pass all five with literals (`decide`, and
`decide +kernel` for impact). Which constants the export holds matters too: with only `resolve`'s
definition in it, Lean's replay kernel could not reduce the `decide` in `src_dst_swapped`'s
refutation, and with `impact`'s as well it could (bisected to `List.get!Internal`, which `impact`
uses). Round 1 had both holes in every export because they were definition holes; now
`Mitos.Refute.holes` keeps them there. If a toolchain changes any of this, the nightly canary shows
it.

**CI.** Nightly only (`nightly.yml`, job `full`, with `--paranoid`, and the canary without it), as
the check matrix in `docs/process.md` already says. A local run of the 41 cases took 879 s
with `--paranoid` (one run, round 4; round 3's 35 cases took 751 s): 25 to 43 s for a refuted case
(three comparator runs), 36 and 48 s for the two known gaps, about 6 s for a cheat case the hole
run stops, and under 0.1 s for one the lint refuses (the lint and `--prepare` of all 41 cases,
Lean's syntax loaded once, take under 1 s). On the nightly runner, round 1's 21 cases with two runs each
took 263 s with `--paranoid` (a `workflow_dispatch` run at 2ff0df3); the latest dispatch of this
branch is reported on #86. That is too slow to add to every PR's `gate` for a check whose result
changes only when `core/Mitos/Impl/`, the Challenge or the cases change.

**Not in this task.** A scheduler: the cases run one after another. The `mitos-gate cheats`
runner being built in parallel has a job scheduler this runner could reuse later.

## Done when
- [x] every `breaks=` case is refuted, every `survives=` case survives and every cheat case is
      rejected at its run, locally, default and `--paranoid`
- [x] each of the eight Challenge theorems is broken by some mutant; `Total` and `RetractExact`
      only together with another theorem, as `Mutants.Implied` proves they must be
- [x] the runner fails on an INVALID case, a mutant that survives unexpectedly, a refutation that
      is not accepted, and a cheat case that is counted or rejected at another run
- [x] each check of the binding is pinned: a cheat case turns the run red without it
- [x] a case's Lean text is linted before any build; the four ways round 2's reviews faked a
      REFUTED are cheat cases rejected at the lint, and REFUTED without it
- [x] every generated statement is declared at the root with absolute names; a case names its
      top-level declarations only in its own namespaces, and enters and opens only namespaces
      under `Mitos` (nested names are not read, and `with_decl_name%` is banned); round 3's
      namespace shadows and scoped `open` are cheat cases rejected at the lint, REFUTED on the
      round-3 runner
- [x] the runner stops when its reading of the approved Challenge differs from the Challenge as
      Lean built it (declarations, their lines, statements, `sorry` values, definition holes,
      imports); round 9's decoy and its reverse stop `--prepare`, and three probes keep the check
      from going blind
- [x] the runner stops when Lean's parse of the approved Challenge holds a command that is no
      module doc and no line the reader read, or when a Challenge it generates, as Lean builds it,
      declares other theorems than its run compares or states other than the approved statements;
      round 10's hidden `variable … in`, trailing `namespace` and trailing `#exit` stop it, and
      seven probes keep the two checks from going blind
- [x] all `checks` pass locally
- [x] run-log record written (ops/runs/)
- [ ] the owner decides the known gaps `assumptions_dedupe_dropped` and `edges_duplicated`
      (list multiplicity: strengthen the spec, or rule multiplicity out of scope; #101)
