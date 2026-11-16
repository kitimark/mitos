#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
mkdir -p "$work/clean/gate/vendor" "$work/clean/.github/scripts" "$work/bin" "$work/upstream"
cp -a "$root/gate/vendor/l4yaml" "$work/clean/gate/vendor/"
cp "$root/gate/vendor-test.sh" "$work/clean/gate/"
cp "$root/.github/scripts/vendor-provenance.sh" "$work/clean/.github/scripts/"
cp "$root/lean-toolchain" "$work/clean/"
cp -a "$root/gate/vendor/l4yaml/L4YAML" "$root/gate/vendor/l4yaml/LICENSE" "$work/upstream/"
cp "$root/lean-toolchain" "$work/upstream/"
git -C "$work/upstream" init -q -b v4.35.0
git -C "$work/upstream" add .
git -C "$work/upstream" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm fixture
rev=$(git -C "$work/upstream" rev-parse HEAD)
sed -i "s/^rev=.*/rev=$rev/" "$work/clean/gate/vendor/l4yaml/PIN"
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" "url.$work/upstream.insteadOf" https://github.com/nasa-jpl/L4YAML
cat > "$work/bin/lake" <<'LAKE'
#!/usr/bin/env bash
[ "$*" = 'build L4YAML' ] || exit 1
printf 'library build requested\n'
LAKE
chmod +x "$work/bin/lake"
export PATH="$work/bin:$PATH"
reset_case() {
  rm -rf "$work/case"
  cp -a "$work/clean" "$work/case"
  vendor=$work/case/gate/vendor/l4yaml
}
rehash() {
  local path=$1 hash
  hash=$(git hash-object --no-filters "$vendor/$path")
  sed -i "s|^[0-9a-f]* $path$|$hash $path|" "$vendor/MANIFEST"
}
expect() {
  local script=$1 expected=$2 message=$3 status=0
  shift 3
  "$work/case/$script" "$@" > "$work/out" 2>&1 || status=$?
  [ "$status" -eq "$expected" ] || { cat "$work/out" >&2; fail "$script exited $status, wanted $expected"; }
  grep -Fq "$message" "$work/out" || { cat "$work/out" >&2; fail "$script did not name $message"; }
}
offline=gate/vendor-test.sh
online=.github/scripts/vendor-provenance.sh
reset_case
expect "$offline" 0 '19 modules'
expect "$online" 0 '20 files equal upstream'
for path in L4YAML/Parser/Composition.lean LICENSE; do
  reset_case
  printf 'x' >> "$vendor/$path"
  expect "$offline" 1 "$path"
  expect "$online" 1 "$path"
  rehash "$path"
  expect "$online" 1 "$path"
done
reset_case
rm "$vendor/L4YAML/Parser/Fuel.lean"
expect "$offline" 1 L4YAML/Parser/Fuel.lean
reset_case
printf 'extra\n' > "$vendor/extra"
expect "$offline" 1 extra
reset_case
mkfifo "$vendor/fifo"
expect "$offline" 1 fifo
expect "$online" 1 fifo
reset_case
rm "$vendor/LICENSE"
ln -s /dev/null "$vendor/LICENSE"
expect "$offline" 1 LICENSE
expect "$online" 1 LICENSE
for name in PIN MANIFEST; do
  reset_case
  mv "$vendor/$name" "$work/$name"
  ln -s "$work/$name" "$vendor/$name"
  expect "$offline" 1 "$name"
  expect "$online" 1 "$name"
done
reset_case
chmod +x "$vendor/LICENSE"
expect "$offline" 1 LICENSE
expect "$online" 1 LICENSE
reset_case
sed -i '8i public meta import L4YAML.Missing' "$vendor/L4YAML/Parser/Composition.lean"
rehash L4YAML/Parser/Composition.lean
expect "$offline" 1 L4YAML/Missing.lean
reset_case
sed -i '8i public meta import /- outer /- nested -/ -/ L4YAML.Parser.State -- extra edge' "$vendor/L4YAML/Parser/Composition.lean"
rehash L4YAML/Parser/Composition.lean
expect "$offline" 0 '19 modules'
reset_case
sed -i '8i public import all L4YAML.Parser.State' "$vendor/L4YAML/Parser/Composition.lean"
rehash L4YAML/Parser/Composition.lean
expect "$offline" 1 'unsupported import header'
for command in 'run_cmd IO.println "x"' '#eval 1' 'notation "extra" => True' 'infixl:60 "~extra~" => Nat.add' 'declare_syntax_cat extra' '/- prefix -/ initialize pure ()' 'builtin_initialize pure ()' 'macro_rules' 'elab_rules' '@[csimp] theorem extra : True := True.intro'; do
  reset_case
  printf '\n%s\n' "$command" >> "$vendor/L4YAML/Parser/Composition.lean"
  rehash L4YAML/Parser/Composition.lean
  expect "$offline" 1 'startup inventory differs'
done
reset_case
printf '\n@[\ncsimp] theorem extra : True := True.intro\n' >> "$vendor/L4YAML/Parser/Composition.lean"
rehash L4YAML/Parser/Composition.lean
expect "$offline" 1 'startup inventory differs'
reset_case
sed -i 's/initialize capstoneAttr/initialize changedAttr/' "$vendor/L4YAML/CapstoneAttr.lean"
rehash L4YAML/CapstoneAttr.lean
expect "$offline" 1 L4YAML/CapstoneAttr.lean
for name in lean-toolchain lakefile.toml lakefile.lean lake-manifest.json; do
  reset_case
  mkdir -p "$work/case/gate/vendor/other/nested"
  touch "$work/case/gate/vendor/other/nested/$name"
  expect "$offline" 1 "$name"
done
for row in '0000000000000000000000000000000000000000 ../escape.lean' '0000000000000000000000000000000000000000 /absolute.lean'; do
  reset_case
  printf '%s\n' "$row" > "$vendor/MANIFEST"
  expect "$offline" 1 'unsafe row'
  expect "$online" 1 'unsafe row'
done
reset_case
head -n 1 "$vendor/MANIFEST" >> "$vendor/MANIFEST"
expect "$offline" 1 'unsorted or duplicates'
expect "$online" 1 'unsorted or duplicates'
reset_case
printf '0000000000000000000000000000000000000000 ../escape.lean' >> "$vendor/MANIFEST"
expect "$offline" 1 'unsafe row'
expect "$online" 1 'unsafe row'
for branch in bad..name /leading trailing/; do
  reset_case
  sed -i "s|^branch=.*|branch=$branch|" "$vendor/PIN"
  expect "$offline" 1 'invalid branch'
  expect "$online" 1 'invalid branch'
done
reset_case
sed -i '1c url=$(touch SHOULD_NOT_EXIST)' "$vendor/PIN"
expect "$offline" 1 'invalid fields'
expect "$online" 1 'invalid fields'
[ ! -e "$work/case/SHOULD_NOT_EXIST" ] || fail 'PIN was executed'
reset_case
GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=none expect "$online" 2 'cannot fetch'
TMPDIR="$work/missing" expect "$online" 2 'cannot create temporary directory'

printf 'leanprover/lean4:v4.32.0\n' > "$work/upstream/lean-toolchain"
git -C "$work/upstream" add lean-toolchain
git -C "$work/upstream" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm toolchain
changed_rev=$(git -C "$work/upstream" rev-parse HEAD)
reset_case
sed -i "s/^rev=.*/rev=$changed_rev/" "$vendor/PIN"
expect "$online" 1 'upstream lean-toolchain differs'
cp "$root/lean-toolchain" "$work/upstream/lean-toolchain"
chmod +x "$work/upstream/LICENSE"
git -C "$work/upstream" add .
git -C "$work/upstream" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm mode
changed_rev=$(git -C "$work/upstream" rev-parse HEAD)
reset_case
sed -i "s/^rev=.*/rev=$changed_rev/" "$vendor/PIN"
expect "$online" 1 LICENSE
git -C "$work/upstream" checkout -q --orphan unrelated "$rev"
git -C "$work/upstream" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm unrelated
orphan_rev=$(git -C "$work/upstream" rev-parse HEAD)
git -C "$work/upstream" checkout -q v4.35.0
reset_case
sed -i "s/^rev=.*/rev=$orphan_rev/" "$vendor/PIN"
expect "$online" 1 'not on upstream branch'
reset_case
expect "$online" 0 'equal upstream'
branch_tip=$(git -C "$work/upstream" rev-parse v4.35.0)
git -C "$work/upstream" update-ref refs/heads/v4.35.0 "$orphan_rev"
expect "$online" 1 'not on upstream branch'
git -C "$work/upstream" update-ref -d refs/heads/v4.35.0
expect "$online" 2 'cannot fetch'
git -C "$work/upstream" update-ref refs/heads/v4.35.0 "$branch_tip"

reset_case
git -C "$work/case" init -q
git -C "$work/case" add .
git -C "$work/case" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm base
base=$(git -C "$work/case" rev-parse HEAD)
touch "$work/case/unrelated"
git -C "$work/case" add unrelated
git -C "$work/case" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm unrelated
head=$(git -C "$work/case" rev-parse HEAD)
EVENT_NAME=pull_request BASE_SHA=$base HEAD_SHA=$head GIT_ALLOW_PROTOCOL=none expect "$online" 0 'vendor unchanged' --if-changed
EVENT_NAME=push BEFORE_SHA=$base HEAD_SHA=$head GIT_ALLOW_PROTOCOL=none expect "$online" 0 'vendor unchanged' --if-changed
EVENT_NAME=push BEFORE_SHA=0000000000000000000000000000000000000000 HEAD_SHA=$head expect "$online" 0 'equal upstream' --if-changed
EVENT_NAME=pull_request BASE_SHA=$base HEAD_SHA=ffffffffffffffffffffffffffffffffffffffff expect "$online" 2 'Not a valid' --if-changed
printf 'x' >> "$vendor/LICENSE"
git -C "$work/case" add gate/vendor
git -C "$work/case" -c user.name=vendor-test -c user.email=vendor-test@invalid commit -qm tamper
changed=$(git -C "$work/case" rev-parse HEAD)
EVENT_NAME=pull_request BASE_SHA=$base HEAD_SHA=$changed expect "$online" 1 LICENSE --if-changed
EVENT_NAME=push BEFORE_SHA=$head HEAD_SHA=$changed expect "$online" 1 LICENSE --if-changed
EVENT_NAME=pull_request BASE_SHA=$base HEAD_SHA=$head GIT_ALLOW_PROTOCOL=none expect "$online" 0 'vendor unchanged' --if-changed
printf 'vendor-provenance: offline attacks, upstream comparison and CI selection passed\n'
