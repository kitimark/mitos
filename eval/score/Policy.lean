import Score

open Score Mitos

namespace Policy

def sampleFact (kind : String) : Located :=
  { id := 0, repo := "lib", rev := "fixture", path := "go.mod",
    fact := { kind := .provides, ident := { kind, key := "example.com/lib" },
              span := { start := 0, len := 1 }, scope := .runtime },
    origin := .extractor "GoMod" }

def sampleLabel (kind : String) : RepoKey :=
  { requiringRepo := "app", providingRepo := "lib",
    ident := { kind, key := "example.com/lib" }, scope := .runtime }

theorem absent_kind_is_reported :
    absentLabelKind [sampleFact "go-module"] [sampleLabel "go-mod"] = some "go-mod" := by
  decide

theorem present_kind_is_accepted :
    absentLabelKind [sampleFact "go-module"] [sampleLabel "go-module"] = none := by
  decide

theorem first_absent_kind_wins :
    absentLabelKind [sampleFact "go-module"]
      [sampleLabel "go-module", sampleLabel "go-mod", sampleLabel "typo"] = some "go-mod" := by
  decide

theorem empty_labels_have_no_absent_kind :
    absentLabelKind [sampleFact "go-module"] [] = none := by
  decide

def monoFiles : List SourceFile := [
  { repo := "mono", path := "go.mod",
    text := "module example.com/mono\n" },
  { repo := "mono", path := "tools/go.mod",
    text := "module example.com/mono/tools\n\nrequire example.com/mono v1.0.0\n" }
]

def selfLabel : RepoKey :=
  { requiringRepo := "mono", providingRepo := "mono",
    ident := { kind := "go-module", key := "example.com/mono" }, scope := .runtime }

def showCard (files : List SourceFile) (labels : List RepoKey) (name : String) : String :=
  match score files labels with
  | .ok c => c.render name
  | .error e => e

-- Kernel `decide` exceeds the recursion limit on `score` and `render`.
theorem labelled_same_repo_dependency_is_a_hit :
    showCard monoFiles [selfLabel] "self" =
      "### Scorecard: fixture `self`\n\n3 facts (1 requirements, 2 provisions), 1 repo-level edges predicted, 1 hand-labelled, 0 requirements unresolved.\n\n| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n|---|---|---|---|---|---|---|---|\n| go-module/runtime | 1 | 1 | 1 | 0 | 0 | 1.00 (1/1) | 1.00 (1/1) |\n\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n|---|---|---|---|---|---|\n| go-module/runtime | confirmed | 1 | 1 | 0 | 1.00 (1/1) |\n| go-module/runtime | inferred | 0 | 0 | 0 | n/a |\n" := by
  native_decide

theorem unlabelled_same_repo_dependency_is_a_false_positive :
    showCard monoFiles [] "self" =
      "### Scorecard: fixture `self`\n\n3 facts (1 requirements, 2 provisions), 1 repo-level edges predicted, 0 hand-labelled, 0 requirements unresolved.\n\n| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n|---|---|---|---|---|---|---|---|\n| go-module/runtime | 1 | 0 | 0 | 1 | 0 | 0.00 (0/1) | n/a |\n\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n|---|---|---|---|---|---|\n| go-module/runtime | confirmed | 1 | 0 | 1 | 0.00 (0/1) |\n| go-module/runtime | inferred | 0 | 0 | 0 | n/a |\n\nFalse positives (predicted, not labelled):\n- `mono` → `mono` (go-module/runtime `example.com/mono`), confirmed\n" := by
  native_decide

def typoLabel : RepoKey :=
  { requiringRepo := "mono", providingRepo := "mono",
    ident := { kind := "go-mod", key := "example.com/mono" }, scope := .runtime }

theorem absent_label_kind_is_an_error :
    showCard monoFiles [typoLabel] "self" =
      "label kind \"go-mod\" is not among the extracted facts" := by
  native_decide

def libOnly : List SourceFile := [
  { repo := "lib", path := "go.mod", text := "module example.com/lib\n" }
]

def missLabel : RepoKey :=
  { requiringRepo := "app", providingRepo := "lib",
    ident := { kind := "go-module", key := "example.com/lib" }, scope := .runtime }

theorem label_of_a_present_kind_stays_a_miss :
    showCard libOnly [missLabel] "miss" =
      "### Scorecard: fixture `miss`\n\n1 facts (0 requirements, 1 provisions), 0 repo-level edges predicted, 1 hand-labelled, 0 requirements unresolved.\n\n| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n|---|---|---|---|---|---|---|---|\n| go-module/runtime | 0 | 1 | 0 | 0 | 1 | n/a | 0.00 (0/1) |\n\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n|---|---|---|---|---|---|\n| go-module/runtime | confirmed | 0 | 0 | 0 | n/a |\n| go-module/runtime | inferred | 0 | 0 | 0 | n/a |\n\nMisses (labelled, not predicted):\n- `app` → `lib` (go-module/runtime `example.com/lib`)\n" := by
  native_decide

def ignoredFiles : List SourceFile := [
  { repo := "app", path := ".hidden/go.mod",
    text := "module example.com/hidden\n\nrequire example.com/cli v1.0.0\n" },
  { repo := "app", path := "_scratch/go.mod",
    text := "module example.com/scratch\n\nrequire example.com/util v1.0.0\n" },
  { repo := "app", path := "testdata/go.mod",
    text := "module example.com/testdata\n\nrequire example.com/lib v1.0.0\n" },
  { repo := "cli", path := "go.mod", text := "module example.com/cli\n" },
  { repo := "lib", path := "go.mod", text := "module example.com/lib\n" },
  { repo := "util", path := "go.mod", text := "module example.com/util\n" }
]

def ignoredLabels : List RepoKey := [
  { requiringRepo := "app", providingRepo := "cli",
    ident := { kind := "go-module", key := "example.com/cli" }, scope := .runtime },
  { requiringRepo := "app", providingRepo := "util",
    ident := { kind := "go-module", key := "example.com/util" }, scope := .runtime },
  { requiringRepo := "app", providingRepo := "lib",
    ident := { kind := "go-module", key := "example.com/lib" }, scope := .runtime }
]

theorem go_mod_under_testdata_dot_and_underscore_is_scored :
    showCard ignoredFiles ignoredLabels "ignored" =
      "### Scorecard: fixture `ignored`\n\n9 facts (3 requirements, 6 provisions), 3 repo-level edges predicted, 3 hand-labelled, 0 requirements unresolved.\n\n| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n|---|---|---|---|---|---|---|---|\n| go-module/runtime | 3 | 3 | 3 | 0 | 0 | 1.00 (3/3) | 1.00 (3/3) |\n\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n|---|---|---|---|---|---|\n| go-module/runtime | confirmed | 3 | 3 | 0 | 1.00 (3/3) |\n| go-module/runtime | inferred | 0 | 0 | 0 | n/a |\n" := by
  native_decide

end Policy
