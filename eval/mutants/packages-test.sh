#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
cd "$root"
export PATH="${HOME}/.elan/bin:${PATH}"
case=${1:-src_dst_swapped}
exe="$root/eval/mutants/.lake/build/bin/mitos-mutants"
missing="core's packages are not resolved: run cd core && lake build first"

lake --dir eval/mutants build >/dev/null

result_of() {
  awk -v c="$case" '$1 == c { print $2; exit }' "$1"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pkg_hash() {
  tar -C "$1" -cf - . | sha256sum | awk '{print $1}'
}

tmp=$(mktemp -d)
trap 'git -C "$root" worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
rm -rf .lake/mutants
"$exe" "$case" > "$tmp/plain.out" 2> "$tmp/plain.err"
test -s "$tmp/plain.out"
if jq -e '.packages | length > 0' core/lake-manifest.json >/dev/null; then
  grep -qxE 'packages: (symlink|hardlink|copy)' "$tmp/plain.err" \
    || fail "baseline stderr: $(cat "$tmp/plain.err")"
  test "$(grep -cvE '^$' "$tmp/plain.err")" = 1 \
    || fail "baseline stderr: $(cat "$tmp/plain.err")"
else
  if [ -s "$tmp/plain.err" ]; then
    fail "no-packages run wrote to stderr: $(cat "$tmp/plain.err")"
  fi
fi
plain=$(result_of "$tmp/plain.out")
test -n "$plain"
git -C "$tmp" init -q -b main toy
mkdir -p "$tmp/toy"
printf '%s\n' 'def toy : Nat := 0' > "$tmp/toy/ToyPkg.lean"
printf '%s\n' 'name = "toypkg"' '' '[[lean_lib]]' 'name = "ToyPkg"' > "$tmp/toy/lakefile.toml"
cp lean-toolchain "$tmp/toy/lean-toolchain"
git -C "$tmp/toy" add ToyPkg.lean lakefile.toml lean-toolchain
git -C "$tmp/toy" -c user.email=packages-test@mitos.local -c user.name=packages-test commit -q -m toy
rev=$(git -C "$tmp/toy" rev-parse HEAD)

git -C "$root" worktree add --detach "$tmp/wt" HEAD >/dev/null
printf '\n[[require]]\nname = "toypkg"\ngit = "%s"\nrev = "%s"\n' "$tmp/toy" "$rev" >> "$tmp/wt/core/lakefile.toml"
python3 - "$tmp/wt" << 'PY'
import pathlib, sys
wt = pathlib.Path(sys.argv[1])

def insert_import(path, needle):
    text = path.read_text()
    updated = text.replace(needle, needle + "import ToyPkg\n", 1)
    if updated == text:
        sys.exit(f"replacement missed in {path}: no {needle!r}")
    path.write_text(updated)

insert_import(wt / "core/Challenge/Resolver.lean", "import Mitos.Core.Spec\n")
insert_import(wt / "core/Mitos/Proofs/Impact.lean", "import Mitos.Impl.Impact\n")
PY
lake_step() {
  if ! ( cd "$1" && shift && "$@" ) > "$tmp/lake.log" 2>&1; then
    cat "$tmp/lake.log" >&2
    fail "$* in $1"
  fi
}
lake_update() {
  MATHLIB_NO_CACHE_ON_UPDATE=1 lake_step "$@"
  if grep -q 'cache get' "$tmp/lake.log"; then
    fail "$* ran the Mathlib cache hook"
  fi
}
lake_update "$tmp/wt/core" lake update
lake_update "$tmp/wt" lake update
lake_update "$tmp/wt/eval/mutants" lake update
lake_step "$tmp/wt/core" lake build
test -d "$tmp/wt/core/.lake/packages/toypkg"
before=$(pkg_hash "$tmp/wt/core/.lake/packages")
rm -rf "$tmp/wt/.lake/mutants"
( cd "$tmp/wt" && "$exe" "$case" > "$tmp/with.out" 2> "$tmp/with.err" )
after=$(pkg_hash "$tmp/wt/core/.lake/packages")
test "$before" = "$after" || fail "core packages tree changed ($before -> $after)"
with=$(result_of "$tmp/with.out")
test "$plain" = "$with" || fail "verdict $with, wanted $plain"
plain_summary=$(grep -E '^mutants: ' "$tmp/plain.out" | sed -E 's/ \([0-9]+s\)$//')
with_summary=$(grep -E '^mutants: ' "$tmp/with.out" | sed -E 's/ \([0-9]+s\)$//')
test "$plain_summary" = "$with_summary" || fail "summary '$with_summary', wanted '$plain_summary'"
grep -q 'control (unmutated core, approved Challenge and proofs): ACCEPTED' "$tmp/with.out" || fail "control was not accepted"
grep -q '^packages: \(symlink\|hardlink\|copy\)$' "$tmp/with.err" || fail "no package link line: $(cat "$tmp/with.err")"
fetched=$(find "$tmp/wt/.lake/mutants" -name '*.log' -exec grep -il -e cloning -e 'materializing new dependency' -e 'fetching revision' {} + || true)
test -z "$fetched" || fail "a run fetched a package: $fetched"
echo "packages-test: $case $plain, $(tr -d '\n' < "$tmp/with.err"), tree unchanged"

rm -rf "$tmp/wt/core/.lake/packages/toypkg" "$tmp/wt/.lake/mutants"
set +e
( cd "$tmp/wt" && "$exe" "$case" > "$tmp/miss.out" 2> "$tmp/miss.err" )
rc=$?
set -e
test "$rc" = 2 || fail "missing package exit $rc, wanted 2"
got=$(cat "$tmp/miss.err")
test "$got" = "$missing" || fail "missing package said $(printf %q "$got")"
test ! -e "$tmp/wt/.lake/mutants/challenge.log" || fail "missing package started a run"
test ! -s "$tmp/miss.out" || fail "missing package wrote stdout"
echo "packages-test: missing package stops before any run"
