import L4YAML.Parser.Composition

open L4YAML L4YAML.TokenParser

def main : IO Unit := do
  for (name, input) in [
    ("empty-explicit-key", "? a\n?\n: b\n"),
    ("primary-tag-dot", "!foo.bar value\n"),
    ("folded-empty-keep", "k: >+\n\n"),
    ("duplicate-chomp", "k: |++\n  x\n"),
    ("duplicate-indent", "k: |22\n  x\n"),
    ("literal-empty-clip", "k: |\n\n")] do
    IO.println s!"{name}: {repr (parseYamlSingle input)}"
  for (name, input) in [
    ("mapping-inline-comment", "---\na: 1 # keep\n---\nb: 2\n"),
    ("inter-document-comment", "---\na\n# keep\n---\nb\n")] do
    match parseYamlWithComments input with
    | .error e => IO.println s!"{name}: error {repr e}"
    | .ok docs => IO.println s!"{name}: {repr (docs.map fun d => d.comments.map fun (_, c) => c.text)}"
