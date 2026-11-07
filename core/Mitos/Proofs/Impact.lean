import Mitos.Impl.Impact

/-!
# P1-004: impact analysis is exactly reverse reachability

* Soundness: every repo the worklist marks is reachable, because each marking step follows an
  edge out of `x` or out of a repo already marked.
* Completeness: when the worklist stops, every edge out of `x` or a marked repo has been used
  (no remaining edge fires), so the marked set is closed under `Affects`.
-/

namespace Mitos.Proofs
open Mitos Mitos.Impl

theorem fires_iff {x : String} {seen : List String} {e : Edge} :
    fires x seen e = true ↔ e.dst = x ∨ e.dst ∈ seen := by
  simp [fires]

theorem impactGo_sound (es : List Edge) (x : String) :
    ∀ rest seen, (∀ e ∈ rest, e ∈ es) → (∀ y ∈ seen, Affects es x y) →
      ∀ y ∈ impactGo x rest seen, Affects es x y := by
  intro rest seen
  fun_induction impactGo x rest seen with
  | case1 rest seen _ => intro _ hseen; exact hseen
  | case2 rest seen e h _ ih =>
    intro hrest hseen
    apply ih
    · intro e' he'; exact hrest e' (List.mem_of_mem_erase he')
    · intro y hy
      simp only [List.mem_cons] at hy
      rcases hy with rfl | hy
      · have hstep : Affects es e.dst e.src := .step (hrest e (List.mem_of_find?_eq_some h))
        rcases fires_iff.mp (List.find?_some h) with hd | hd
        · exact hd ▸ hstep
        · exact .trans (hseen _ hd) hstep
      · exact hseen y hy

/-- No edge out of `x` or out of an output repo leads outside the output. -/
def Closed (es : List Edge) (x : String) (out : List String) : Prop :=
  ∀ e ∈ es, (e.dst = x ∨ e.dst ∈ out) → e.src ∈ out

theorem impactGo_closed (es : List Edge) (x : String) :
    ∀ rest seen, (∀ e ∈ es, e ∈ rest ∨ e.src ∈ seen) → Closed es x (impactGo x rest seen) := by
  intro rest seen
  fun_induction impactGo x rest seen with
  | case1 rest seen h =>
    intro hinv e he hfire
    rcases hinv e he with hr | hs
    · have := List.find?_eq_none.mp h e hr
      exact absurd (fires_iff.mpr hfire) this
    · exact hs
  | case2 rest seen e h _ ih =>
    intro hinv
    apply ih
    intro e' he'
    rcases hinv e' he' with hr | hs
    · by_cases hee : e' = e
      · exact .inr (hee ▸ List.mem_cons_self)
      · exact .inl ((List.mem_erase_of_ne hee).mpr hr)
    · exact .inr (List.mem_cons_of_mem _ hs)

theorem affects_closed {es : List Edge} {x : String} {out : List String}
    (hc : Closed es x out) : ∀ {a b}, Affects es a b → (a = x ∨ a ∈ out) → b ∈ out := by
  intro a b hab
  induction hab with
  | step he => intro ha; exact hc _ he ha
  | trans _ _ ih1 ih2 => intro ha; exact ih2 (.inr (ih1 ha))

theorem impact_correct : Spec.ImpactCorrect impact := by
  intro es x y
  constructor
  · intro hy
    exact impactGo_sound es x es [] (fun _ h => h) (by simp) y hy
  · intro hxy
    exact affects_closed (impactGo_closed es x es [] (fun e he => .inl he)) hxy (.inl rfl)

end Mitos.Proofs
