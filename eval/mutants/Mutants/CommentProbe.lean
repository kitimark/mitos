namespace Mutants.CommentProbe

/- a -/ def afterClose : Nat := 1
/- /- -/ def nested : Nat := 1 -/
def nested : Nat := 2
/-/
def skipped : Nat := 1
-/
def skipped : Nat := 2
/--/
def skippedDoc : Nat := 1
-/
def skippedDoc : Nat := 2

theorem afterClose_is_code : afterClose = 1 := rfl
theorem nested_does_not_close : nested = 2 := rfl
theorem opener_skips_next_char : skipped = 2 := rfl
theorem doc_opener_skips_next_char : skippedDoc = 2 := rfl

end Mutants.CommentProbe
