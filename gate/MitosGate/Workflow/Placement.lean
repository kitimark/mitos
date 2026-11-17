import MitosGate.Yaml

namespace MitosGate.Workflow

private def identifierChar (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z') || ('0' ≤ c && c ≤ '9') || c == '_'

private def lowerAscii (c : Char) : Char :=
  if 'A' ≤ c && c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

def mentionsNeeds (cs : List Char) : Bool := go cs []
where
  go : List Char → List Char → Bool
    | [], word => word.reverse == "needs".toList
    | c :: cs, word =>
      if identifierChar c then go cs (lowerAscii c :: word)
      else word.reverse == "needs".toList || go cs []

def allowedAt : List Yaml.Seg → Bool
  | [.key "env", .key _] => true
  | [.key "jobs", .key _, .key "env", .key _] => true
  | [.key "jobs", .key _, .key "steps", .idx _, .key "env", .key _] => true
  | [.key "jobs", .key _, .key "if"] => true
  | [.key "jobs", .key _, .key "needs"] => true
  | [.key "jobs", .key _, .key "needs", .idx _] => true
  | _ => false

def codeAt : List Yaml.Seg → Bool
  | [.key "jobs", .key _, .key "steps", .idx _, .key "run"] => true
  | [.key "jobs", .key _, .key "steps", .idx _, .key "with", .key input] =>
    input.toList.map lowerAscii == "script".toList
  | _ => false

def leafPlacementOk (leaf : Yaml.Leaf) : Bool :=
  match leaf.value with
  | .text s => (!mentionsNeeds s.toList || allowedAt leaf.path) &&
      (!codeAt leaf.path || !Base.Text.hasSub Yaml.exprTok s.toList)
  | _ => true

def placementOk (d : Yaml.Doc) : Bool := d.leaves.all leafPlacementOk

theorem placementOk_iff (d : Yaml.Doc) : placementOk d = true ↔
    ∀ p s, d.scalarAt? p = some (.text s) →
      (mentionsNeeds s.toList = true → allowedAt p = true) ∧
      (codeAt p = true → Base.Text.hasSub Yaml.exprTok s.toList = false) := by
  simp only [placementOk, List.all_eq_true]
  constructor
  · intro h p s hs
    have := h ⟨p, .text s⟩ ((d.mem_leaves_iff _).mpr hs)
    cases hn : mentionsNeeds s.toList <;> cases hc : codeAt p <;>
      simp_all [leafPlacementOk]
  · intro h leaf hm
    cases leaf with
    | mk p value =>
      cases value with
      | text s =>
        have := h p s ((d.mem_leaves_iff _).mp hm)
        cases hn : mentionsNeeds s.toList <;> cases hc : codeAt p <;>
          simp_all [leafPlacementOk]
      | emptyMap => rfl
      | emptySeq => rfl

theorem placement_sound (hr : Yaml.read src = .ok d) (hp : placementOk d = true) :
    Base.Text.count Yaml.exprTok src.toList = (d.leaves.map Yaml.Leaf.exprCount).sum ∧
    (∀ p s, d.scalarAt? p = some (.text s) →
      (mentionsNeeds s.toList = true → allowedAt p = true) ∧
      (codeAt p = true → Base.Text.hasSub Yaml.exprTok s.toList = false)) ∧
    (Base.Text.hasSub Yaml.exprTok src.toList = true →
      ∃ p s, d.scalarAt? p = some (.text s) ∧
        Base.Text.hasSub Yaml.exprTok s.toList = true ∧ codeAt p = false) := by
  have hc := Yaml.read_conserves hr
  have hleaves := (placementOk_iff d).mp hp
  refine ⟨hc, hleaves, ?_⟩
  intro hsrc
  have hn : Base.Text.count Yaml.exprTok src.toList ≠ 0 := by
    intro hz
    have := (Base.Text.count_eq_zero_iff (by decide : Yaml.exprTok ≠ [])).mp hz
    simp_all
  have hsum : 0 < (d.leaves.map Yaml.Leaf.exprCount).sum := by omega
  obtain ⟨n, hm, hn⟩ := List.sum_pos_iff_exists_pos_nat.mp hsum
  obtain ⟨leaf, hm, he⟩ := List.mem_map.mp hm
  cases leaf with
  | mk p value =>
    cases value with
    | emptyMap => simp [Yaml.Leaf.exprCount] at he; omega
    | emptySeq => simp [Yaml.Leaf.exprCount] at he; omega
    | text s =>
      have hs := (d.mem_leaves_iff _).mp hm
      have hx : Base.Text.hasSub Yaml.exprTok s.toList = true := by
        cases hx : Base.Text.hasSub Yaml.exprTok s.toList
        · have hz := (Base.Text.count_eq_zero_iff (by decide : Yaml.exprTok ≠ [])).mpr hx
          simp [Yaml.Leaf.exprCount, hz] at he
          omega
        · rfl
      refine ⟨p, s, hs, hx, ?_⟩
      cases hcode : codeAt p
      · rfl
      · have := (hleaves p s hs).2 hcode
        simp_all

example : mentionsNeeds "toJSON(needs)".toList = true := by decide +kernel
example : mentionsNeeds "NEEDS.x".toList = true := by decide +kernel
example : mentionsNeeds "needs.decide[format('{0}puts','out')]".toList = true := by decide +kernel
example : mentionsNeeds "fromJSON(toJSON(needs)).decide.outputs.answers".toList = true := by decide +kernel
example : mentionsNeeds "unneeds-x".toList = false := by decide +kernel
example : mentionsNeeds "needs_x".toList = false := by decide +kernel
example : mentionsNeeds "needs2".toList = false := by decide +kernel
example : mentionsNeeds "2needs".toList = false := by decide +kernel
example : mentionsNeeds "_needs".toList = false := by decide +kernel
example : mentionsNeeds "nEeDs".toList = true := by decide +kernel

private def runPath : List Yaml.Seg :=
  [.key "jobs", .key "a", .key "steps", .idx 0, .key "run"]

private def scriptPath : List Yaml.Seg :=
  [.key "jobs", .key "a", .key "steps", .idx 0, .key "with", .key "script"]

example : leafPlacementOk ⟨runPath, .text "echo a#${{ needs.d.outputs.p }}"⟩ = false := by decide +kernel
example : leafPlacementOk ⟨scriptPath, .text "needs.d.outputs.p"⟩ = false := by decide +kernel
example : leafPlacementOk ⟨runPath, .text "echo ${{ env.X }}"⟩ = false := by decide +kernel
example : leafPlacementOk ⟨scriptPath, .text "${{ env.X }}"⟩ = false := by decide +kernel
example : leafPlacementOk ⟨[.key "env", .key "X"], .text "${{ needs.a.outputs.x }}"⟩ = true := by decide +kernel
example : leafPlacementOk ⟨runPath, .text "echo $X"⟩ = true := by decide +kernel
example : allowedAt [.key "ENV", .key "X"] = false := by decide +kernel
example : allowedAt [.key "jobs", .key "a", .key "needs", .idx 0] = true := by decide +kernel
example : allowedAt [.key "jobs", .key "a", .key "needs", .key "x"] = false := by decide +kernel
example : allowedAt [.key "env", .key "X", .key "nested"] = false := by decide +kernel
example : allowedAt [.key "jobs", .key "a", .key "steps", .idx 0, .key "if"] = false := by decide +kernel
example : allowedAt [.key "jobs", .key "a", .key "if"] = true := by decide +kernel
example : allowedAt [.key "jobs", .key "a", .key "env", .key "X"] = true := by decide +kernel
example : allowedAt [.key "jobs", .key "a", .key "steps", .idx 0, .key "env", .key "X"] = true := by decide +kernel
example : leafPlacementOk ⟨scriptPath, .text "${{ steps.a.outputs.x }}"⟩ = false := by decide +kernel
example : leafPlacementOk ⟨[.key "jobs", .key "a", .key "steps", .idx 0, .key "with", .key "SCRIPT"],
    .text "${{ github.event.comment.body }}"⟩ = false := by decide +kernel
example : leafPlacementOk ⟨[.key "jobs", .key "a", .key "steps", .idx 0, .key "with", .key "sCrIpT"],
    .text "${{ env.X }}"⟩ = false := by decide +kernel
example : codeAt [.key "jobs", .key "a", .key "steps", .idx 0, .key "with", .key "value"] = false := by decide +kernel
example : codeAt [.key "JOBS", .key "a", .key "steps", .idx 0, .key "run"] = false := by decide +kernel
example : codeAt [.key "jobs", .key "a", .key "steps", .idx 0, .key "RUN"] = false := by decide +kernel
example : leafPlacementOk ⟨[.key "env", .key "X"], .text "needs"⟩ = true := by decide +kernel

private def indirectionFixture : Yaml.Doc :=
  ⟨.map [("env", .map [("X", .text "${{ needs.a.outputs.x }}")]),
    ("jobs", .map [("a", .map [("steps", .seq [
      .map [("run", .text "echo ${{ env.X }}")]])])])], by decide +kernel⟩

example : placementOk indirectionFixture = false := by decide +kernel

private def shellEnvFixture : Yaml.Doc :=
  ⟨.map [("env", .map [("X", .text "${{ needs.a.outputs.x }}")]),
    ("jobs", .map [("a", .map [("steps", .seq [
      .map [("run", .text "echo $X")]])])])], by decide +kernel⟩

example : placementOk shellEnvFixture = true := by decide +kernel

end MitosGate.Workflow
