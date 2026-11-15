#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
d=$tmp/d
okmod=$'module example.com/app\n\nrequire example.com/lib v1.2.0\n'
okjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/lib","Version":"v1.2.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'
quotedmod=$'module example.com/app\n\nrequire (\n\texample.com/lib v1.2.0\n)\n\nrequire "example.com/q" v1.2.0\n'
quotedjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/lib","Version":"v1.2.0"},{"Path":"example.com/q","Version":"v1.2.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'
pairmod=$'module example.com/app\n\nrequire (\n\texample.com/a v1.0.0\n\texample.com/b v1.0.0\n)\n'
swappedjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/b","Version":"v1.0.0"},{"Path":"example.com/a","Version":"v1.0.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'

fresh() {
  rm -rf "$d"
  mkdir -p "$d/cases"
  echo 1.24.7 > "$d/.go-version"
  : > "$d/triage.tsv"
  : > "$d/pins.tsv"
}
pin() {
  mkdir -p "$d/cases/$1"
  printf '%s' "$2" > "$d/cases/$1/module.mod"
  printf '%s' "$3" > "$d/cases/$1/module.json"
  printf '%s\tex.com/%s\tv1.0.0\th1:x\t-\tMIT\n' "$1" "$1" >> "$d/pins.tsv"
}
expect() {
  want=$1 needle=$2
  shift 2
  got=0
  lake --dir eval/diff exe mitos-diff "$d" "$@" > "$tmp/out" 2> "$tmp/err" || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $needle: exit $got, wanted $want" >&2
    cat "$tmp/out" "$tmp/err" >&2
    exit 1
  fi
  if ! grep -qF -- "$needle" "$tmp/out" "$tmp/err"; then
    echo "FAIL: no '$needle' in the output" >&2
    cat "$tmp/out" "$tmp/err" >&2
    exit 1
  fi
  echo "ok: exit $want, $needle"
}

fresh; pin ok "$okmod" "$okjson"
expect 0 "Stale triage lines: none."

fresh; pin quoted "$quotedmod" "$quotedjson"
expect 1 "$(printf 'quoted\tonly-in-go\trequire\texample.com/q\t#?')"

printf 'quoted\tonly-in-go\trequire\texample.com/q\t#7\n' > "$d/triage.tsv"
expect 0 "(#7)"

fresh; pin ok "$okmod" "$okjson"
printf 'ok\tonly-in-go\trequire\texample.com/gone\t#7\n' > "$d/triage.tsv"
expect 1 "Stale triage lines, which match no mismatch"

fresh; pin pair "$pairmod" "$swappedjson"
expect 1 "require: shared paths in another order"

fresh; pin ok "$okmod" "$okjson"; rm "$d/cases/ok/module.json"
expect 2 "module.json"

fresh; pin ok "$okmod" "$okjson"
printf 'ok\tsideways\trequire\tx\t#1\n' > "$d/triage.tsv"
expect 2 "triage.tsv:1"

fresh; pin ok "$okmod" "$okjson"; mkdir "$d/cases/stray"
expect 2 "cases/ holds"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/go" <<'GO'
#!/usr/bin/env bash
if [ "$1 $2" = "env GOVERSION" ]; then echo "${FAKE_GO_VERSION:-go1.24.7}"; exit 0; fi
if grep -q reject-me "$4"; then echo "go: errors parsing $4: unknown block type: ignore" >&2; exit 1; fi
printf '%s' "$FAKE_GO_JSON"
GO
chmod +x "$tmp/bin/go"
export FAKE_GO_JSON="$okjson"

fresh; pin ok "$okmod" '{}'
PATH="$tmp/bin:$PATH" FAKE_GO_VERSION=go1.25.0 expect 2 "--refresh needs go1.24.7" --refresh
[ "$(cat "$d/cases/ok/module.json")" = '{}' ] || { echo "FAIL: --refresh wrote with the wrong Go" >&2; exit 1; }

fresh; pin ok "$okmod" '{}'; pin bad $'module example.com/bad\nreject-me\n' '{}'
PATH="$tmp/bin:$PATH" expect 2 "bad: go1.24.7 rejects ex.com/bad@v1.0.0" --refresh

fresh; pin ok "$okmod" '{}'
PATH="$tmp/bin:$PATH" expect 0 "Stale triage lines: none." --refresh
[ "$(cat "$d/cases/ok/module.json")" = "$okjson" ] || { echo "FAIL: --refresh did not write Go's bytes" >&2; exit 1; }

cp "$here/check-pins.sh" "$tmp/check-pins.sh"
mkdir -p "$tmp/cases"
cp -r "$here/cases/cobra" "$tmp/cases/cobra"
awk -F'\t' '$1 == "cobra"' "$here/pins.tsv" > "$tmp/pins.tsv"
awk -F'\t' '$1 == "cobra"' "$here/licences.tsv" > "$tmp/licences.tsv"
"$tmp/check-pins.sh" > /dev/null
echo "ok: check-pins.sh accepts a pin as committed"
printf '\n' >> "$tmp/cases/cobra/module.mod"
if "$tmp/check-pins.sh" 2> "$tmp/err"; then echo "FAIL: check-pins.sh accepted a changed module.mod" >&2; exit 1; fi
grep -qF "module.mod hashes to" "$tmp/err"
echo "ok: check-pins.sh refuses a changed module.mod"
cp "$here/cases/cobra/module.mod" "$tmp/cases/cobra/module.mod"
sed -i 's/\tApache-2.0$/\tGPL-3.0/' "$tmp/pins.tsv"
if "$tmp/check-pins.sh" 2> "$tmp/err"; then echo "FAIL: check-pins.sh accepted GPL-3.0" >&2; exit 1; fi
grep -qF "licence GPL-3.0" "$tmp/err"
echo "ok: check-pins.sh refuses a licence outside the four"
rm "$tmp/pins.tsv"
got=0
"$tmp/check-pins.sh" 2> "$tmp/err" || got=$?
[ "$got" = 2 ] || { echo "FAIL: check-pins.sh exited $got for a missing pins.tsv, wanted 2" >&2; exit 1; }
grep -qF "cannot read pins.tsv" "$tmp/err"
echo "ok: check-pins.sh refuses a missing pins.tsv"
awk -F'\t' '$1 == "cobra"' "$here/pins.tsv" | sed 's/\tApache-2.0$/\tGPL-3.0/' | tr -d '\n' > "$tmp/pins.tsv"
got=0
"$tmp/check-pins.sh" 2> "$tmp/err" || got=$?
[ "$got" = 1 ] || { echo "FAIL: check-pins.sh exited $got for a last row with no newline, wanted 1" >&2; exit 1; }
grep -qF "licence GPL-3.0" "$tmp/err"
echo "ok: check-pins.sh checks a last row with no newline"

mixedjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/b","Version":"v1.0.0"},{"Path":"example.com/a","Version":"v1.0.0"},{"Path":"example.com/c","Version":"v1.0.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'
fresh; pin mixed "$pairmod" "$mixedjson"
expect 1 "require: shared paths in another order"
grep -qF "require \`example.com/c\`: only in Go" "$tmp/out"
printf 'mixed\tonly-in-go\trequire\texample.com/c\t#7\n' > "$d/triage.tsv"
expect 1 "$(printf 'mixed\torder\trequire\t-\t#?')"
printf 'mixed\torder\trequire\t-\t#8\n' >> "$d/triage.tsv"
expect 0 "Stale triage lines: none."

pinexpect() {
  local want=$1 needle=$2 got=0
  "$tmp/check-pins.sh" 2> "$tmp/err" || got=$?
  [ "$got" = "$want" ] || { echo "FAIL: $needle: exit $got, wanted $want" >&2; exit 1; }
  grep -qF "$needle" "$tmp/err"
  echo "ok: exit $want, $needle"
}
awk -F'\t' '$1 == "cobra"' "$here/pins.tsv" > "$tmp/pins.tsv"
printf 'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n' > "$tmp/cases/cobra/LICENSE"
pinexpect 1 "LICENSE differs from reviewed source"
sed -i 's/\tApache-2.0$/\tMIT/' "$tmp/pins.tsv"
pinexpect 1 "pin does not match reviewed licence metadata"
cp -r "$here/cases/grpc" "$tmp/cases/grpc"
awk -F'\t' '$1 == "grpc"' "$here/pins.tsv" > "$tmp/pins.tsv"
awk -F'\t' '$1 == "grpc"' "$here/licences.tsv" > "$tmp/licences.tsv"
rm "$tmp/cases/grpc/NOTICE"
pinexpect 1 "no NOTICE"
printf 'changed notice\n' > "$tmp/cases/grpc/NOTICE"
pinexpect 1 "NOTICE differs from reviewed source"
: > "$tmp/pins.tsv"
pinexpect 2 "pins.tsv has no pins"
printf '# header only\n' > "$tmp/pins.tsv"
pinexpect 2 "pins.tsv has no pins"
awk -F'\t' '$1 == "grpc"' "$here/pins.tsv" > "$tmp/pins.tsv"
cat "$tmp/licences.tsv" >> "$tmp/licences.tsv.copy"
cat "$tmp/licences.tsv.copy" >> "$tmp/licences.tsv"
pinexpect 2 "malformed or duplicate licence row"
: > "$tmp/licences.tsv"
pinexpect 1 "no reviewed licence row"
awk -F'\t' '$1 == "grpc" || $1 == "cobra"' "$here/licences.tsv" > "$tmp/licences.tsv"
cp "$here/cases/grpc/NOTICE" "$tmp/cases/grpc/NOTICE"
pinexpect 1 "reviewed licence row has no pin"
