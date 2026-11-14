import MitosGate.Speech

namespace MitosGate.Snapshot

open Speech (lead blank digit)

inductive Start
  | blank
  | heading
  | runsPastHeadings
  | unsupported
  | text
  deriving DecidableEq, Repr

def atx (r : List Char) : Option Nat :=
  let (n, rest) := Speech.span '#' r
  if 1 ≤ n ∧ n ≤ 6 ∧ rest.head?.all (fun c => c == ' ' || c == '\t') then some n else none

def fenced (r : List Char) : Bool := "```".toList.isPrefixOf r || "~~~".toList.isPrefixOf r

def underline (r : List Char) : Bool :=
  !(Speech.trim r).isEmpty && ((Speech.trim r).all (· == '=') || (Speech.trim r).all (· == '-'))

def bullet : List Char → Option (List Char)
  | c :: r =>
    if c == '-' || c == '*' || c == '+' then some r
    else
      match (c :: r).dropWhile digit with
      | d :: r' =>
        if digit c && ((c :: r).takeWhile digit).length ≤ 9 && (d == '.' || d == ')') then some r'
        else none
      | [] => none
  | [] => none

def inItem : Start → Start
  | .blank | .text => .text
  | .runsPastHeadings => .runsPastHeadings
  | _ => .unsupported

def startIn : Nat → List Char → Start
  | 0, _ => .unsupported
  | n + 1, l =>
    if blank l then .blank
    else
      match lead l with
      | none => .unsupported
      | some r =>
        if atx r == some 2 then .heading
        else if r.head? == some '<' || fenced r then .runsPastHeadings
        else if (atx r).isSome || underline r || r.head? == some '>' then .unsupported
        else
          match bullet r with
          | some [] => .text
          | some (' ' :: c) => inItem (startIn n c)
          | some ('\t' :: _) => .unsupported
          | _ => .text

def start (l : List Char) : Start := startIn (l.length + 1) l

namespace Fixture

def starts (ls : List String) : List Start := ls.map (start ·.toList)

theorem twoHashesAfterThreeSpacesAtMostAreAHeading :
    starts ["## x", "   ## x", "##\tx", "##", "## x ##"] =
      [.heading, .heading, .heading, .heading, .heading] := by decide +kernel
theorem anIndentedHeadingIsCode :
    starts ["    ## x", "\t## x", "  \t## x"] = [.unsupported, .unsupported, .unsupported] := by
  decide +kernel
theorem otherLevelsAndUnderlinesAreUnsupported :
    starts ["# x", "### x", "####### x", "---", "=== ", "> ## x"] =
      [.unsupported, .unsupported, .text, .unsupported, .unsupported, .unsupported] := by
  decide +kernel
theorem htmlAndFencesRunPastHeadings :
    starts ["<!--", "<div>", "   <pre>", "```", "~~~ x", "- ```", "1. <!--", "2) - ~~~"] =
      [.runsPastHeadings, .runsPastHeadings, .runsPastHeadings, .runsPastHeadings,
        .runsPastHeadings, .runsPastHeadings, .runsPastHeadings, .runsPastHeadings] := by
  decide +kernel
theorem anItemOfCodeOrATabIsUnsupported : starts ["-     ## x", "-\tx", "- ## x", "- > x"] =
    [.unsupported, .unsupported, .unsupported, .unsupported] := by decide +kernel
theorem theLiveLinesAreText :
    starts ["| #7 a | `x` | green | PASS |", "|---|---|---|---|", "- #6 merged 11:23 UTC.",
      "Merged in the last 24 hours (newest first):", "**Your queue:** x", "#7 b | x", "##x",
      "2026-11-14 x", "1234567890. x", "-", "- ", "*"] =
      [.text, .text, .text, .text, .text, .text, .text, .text, .text, .unsupported, .unsupported,
        .text] := by
  decide +kernel
theorem blankLines : starts ["", "  \t "] = [.blank, .blank] := by decide +kernel

end Fixture

end MitosGate.Snapshot
