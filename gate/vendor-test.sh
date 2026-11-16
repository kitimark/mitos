#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
vendor=gate/vendor/l4yaml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'vendor: %s\n' "$*" >&2; exit 1; }

[ -d "$vendor" ] && [ ! -L gate/vendor ] || fail "$vendor is missing or linked"
linked=$(find gate/vendor -type l -print -quit)
[ -z "$linked" ] || fail "symlink $linked"
unusual=$(find "$vendor" ! -type f ! -type d -print -quit)
[ -z "$unusual" ] || fail "nonregular file $unusual"
for name in PIN MANIFEST; do
  [ -f "$vendor/$name" ] || fail "$vendor/$name is missing"
done
mapfile -t pin < "$vendor/PIN"
[ "${#pin[@]}" -eq 5 ] || fail "$vendor/PIN must have five lines"
[[ ${pin[0]} == url=https://github.com/nasa-jpl/L4YAML && ${pin[1]} =~ ^rev=[0-9a-f]{40}$ &&
   ${pin[2]} =~ ^branch=[A-Za-z0-9._/-]+$ && ${pin[3]} == toolchain="$(cat lean-toolchain)" &&
   ${pin[4]} == entry=L4YAML.Parser.Composition ]] || fail "$vendor/PIN has invalid fields"
entry=${pin[4]#entry=}
[ -f "$vendor/LICENSE" ] || fail "$vendor/LICENSE is missing"
branch=${pin[2]#branch=}
git check-ref-format "refs/heads/$branch" >/dev/null 2>&1 || fail "$vendor/PIN has an invalid branch"
previous=
while read -r hash path extra || [ -n "${hash:-}${path:-}${extra:-}" ]; do
  [[ $hash =~ ^[0-9a-f]{40}$ && -z $extra &&
     ( $path == LICENSE || $path =~ ^L4YAML/([A-Za-z0-9_]+/)*[A-Za-z0-9_]+\.lean$ ) ]] \
    || fail "$vendor/MANIFEST has an unsafe row for $path"
  [[ -z $previous || $previous < $path ]] || fail "$vendor/MANIFEST is unsorted or duplicates $path"
  previous=$path
  [ -f "$vendor/$path" ] && [ ! -x "$vendor/$path" ] || fail "$vendor/$path is missing or executable"
  [ "$(git hash-object --no-filters "$vendor/$path")" = "$hash" ] || fail "$vendor/$path blob differs"
  printf '%s\n' "$path" >> "$work/expected"
done < "$vendor/MANIFEST"
[ "$(wc -l < "$work/expected")" -eq 20 ] || fail "$vendor/MANIFEST must list 20 files"
find "$vendor" -type f ! -path "$vendor/PIN" ! -path "$vendor/MANIFEST" \
  | sed "s|^$vendor/||" | sort > "$work/actual"
diff -u "$work/expected" "$work/actual" || fail "$vendor file set differs"
metadata=$(find gate/vendor \( -name lean-toolchain -o -name 'lakefile.*' -o -name lake-manifest.json \) -print -quit)
[ -z "$metadata" ] || fail "forbidden build metadata $metadata"

printf '%s\n' "$entry" > "$work/pending"
: > "$work/closure"
while [ -s "$work/pending" ]; do
  module=$(head -n 1 "$work/pending")
  sed '1d' "$work/pending" > "$work/next"
  mv "$work/next" "$work/pending"
  path=${module//./\/}.lean
  if grep -qxF "$path" "$work/closure"; then continue; fi
  [ -f "$vendor/$path" ] || fail "import closure needs $vendor/$path"
  printf '%s\n' "$path" >> "$work/closure"
  awk '
    function bad() { print FILENAME ":" NR ": unsupported import header" > "/dev/stderr"; exit 1 }
    {
      line = ""
      for (i = 1; i <= length($0); i++) {
        pair = substr($0, i, 2)
        if (depth) {
          if (pair == "/-") { depth++; i++ }
          else if (pair == "-/") { depth--; i++ }
        } else if (pair == "--") break
        else if (pair == "/-") { depth++; i++ }
        else line = line substr($0, i, 1)
      }
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (!line || line == "module") next
      if (line ~ /^(public[ \t]+)?(meta[ \t]+)?import[ \t]+[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$/) {
        n = split(line, words, /[ \t]+/)
        if (words[n] ~ /^L4YAML\./) print words[n]
        else if (words[n] != "Lean" && words[n] != "Lean.Elab.Declaration") bad()
      } else if (line ~ /^(module|prelude|public|meta|import)([ \t]|$)/) bad()
      else exit
    }
    END { if (depth) { print FILENAME ": unterminated header comment" > "/dev/stderr"; exit 1 } }
  ' "$vendor/$path" >> "$work/pending" || fail "cannot read imports in $vendor/$path"
done
sort "$work/closure" > "$work/closed"
sed '/^LICENSE$/d' "$work/expected" > "$work/modules"
diff -u "$work/modules" "$work/closed" || fail "$vendor import closure differs"

while read -r path; do
  grep -nE '(^|-/)[[:space:]]*((public|private|protected|noncomputable|meta|scoped|local)[[:space:]]+)*(initialize|builtin_initialize|syntax|macro|macro_rules|elab|elab_rules|run_cmd|#eval|notation|infixl|declare_syntax_cat)([[:space:]:]|$)|(^|-/)[[:space:]]*@\[[^]]*(macro|elab|csimp)|^[[:space:]]*(csimp|command_elab|term_elab)([[:space:]]|\])' "$vendor/$path" \
    | sed "s|^|$path:|" || [ "$?" -eq 1 ]
done < "$work/modules" > "$work/startup"
cat > "$work/startup.expected" <<'STARTUP'
L4YAML/CapstoneAttr.lean:46:initialize capstoneAttr : TagAttribute ←
L4YAML/CapstoneAttr.lean:73:elab "#capstones" : command => do
L4YAML/CapstoneAttr.lean:84:elab "#assert_capstone_axioms" : command => do
L4YAML/Init.lean:40:syntax (name := lemmaCmd) (priority := default + 1) declModifiers
L4YAML/Init.lean:45:@[macro lemmaCmd] meta def expandLemma : Macro := fun stx =>
L4YAML/Spec/YamlSpec.lean:93:initialize yamlSpecExt :
L4YAML/Spec/YamlSpec.lean:111:syntax (name := yaml_spec) "yaml_spec" str (num str)? : attr
L4YAML/Spec/YamlSpec.lean:114:initialize registerBuiltinAttribute {
L4YAML/Spec/YamlSpec.lean:137:elab "#yaml_spec_coverage" : command => do
STARTUP
diff -u "$work/startup.expected" "$work/startup" || fail "$vendor startup inventory differs"
lake build L4YAML
printf 'vendor: %s modules, bytes and startup inventory checked\n' "$(wc -l < "$work/modules")"
