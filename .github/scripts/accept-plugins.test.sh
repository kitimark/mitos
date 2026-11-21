#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/lake" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$LAKE_LOG"
[ "$1 $2 $3" = "exe mitos-gate accept" ] || exit 9
case " $* " in *" --paranoid "*) ;; *) exit 8 ;; esac
plugin=; record=false
while [ $# -gt 0 ]; do
  case $1 in --plugin) plugin=$2; shift ;; --record) record=true ;; esac
  shift
done
if [ "$plugin" = "${REJECT:-}" ]; then echo "VERDICT: REJECTED"; exit 1; fi
if $record; then printf '{"plugin": "%s", "core": "%s"}\n' "$plugin" "${CORE:-c1}" > "examples/acme/accepted/$plugin.json"; fi
echo "VERDICT: ACCEPTED"
STUB
chmod +x "$work/bin/lake"

fresh() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/.github/scripts" "$work/repo/examples/acme/Plugins" "$work/repo/examples/acme/accepted"
  cp "$root/.github/scripts/accept-plugins.sh" "$work/repo/.github/scripts/"
  for p in ToyRequire GoMod; do
    : > "$work/repo/examples/acme/Plugins/$p.lean"
    printf '{"plugin": "%s", "core": "c1"}\n' "$p" > "$work/repo/examples/acme/accepted/$p.json"
  done
  git -C "$work/repo" init -q
  git -C "$work/repo" add -A
  git -C "$work/repo" -c user.name=t -c user.email=t@t commit -qm base
  : > "$work/lake.log"
}
run() {
  status=0
  (cd "$work/repo" && PATH="$work/bin:$PATH" LAKE_LOG="$work/lake.log" "$@" \
    .github/scripts/accept-plugins.sh "$mode") > "$work/out" 2>&1 || status=$?
}
expect() {
  [ "$status" = "$1" ] || { cat "$work/out" >&2; fail "$2: exit $status, wanted $1"; }
  [ -z "${3:-}" ] || grep -qF -- "$3" "$work/out" || { cat "$work/out" >&2; fail "$2: no '$3'"; }
  ok "$2"
}

mode=--record
fresh; run env; expect 0 "A1 both plugins accepted with --paranoid --record, records unchanged"
[ "$(grep -c -- '--paranoid --record$' "$work/lake.log")" = 2 ] || fail "A1: not two --paranoid --record calls"
fresh; run env CORE=c2; expect 1 "A2 a record that differs from the gate's is red" "is not what accept --record writes"
fresh; git -C "$work/repo" rm -q examples/acme/accepted/GoMod.json; run env; expect 1 "A3 a deleted record is red" "accepted/ holds records for [ToyRequire ]"
fresh; : > "$work/repo/examples/acme/Plugins/Evil.lean"; run env; expect 1 "A4 an extra plugin is red before any accept" "Plugins/ holds [Evil GoMod ToyRequire ]"
[ ! -s "$work/lake.log" ] || fail "A4: an accept ran"
fresh; echo '{}' > "$work/repo/examples/acme/accepted/Evil.json"; run env; expect 1 "A5 an orphan record is red" "accepted/ holds records for"
fresh; : > "$work/repo/examples/acme/accepted/.GoMod.json.1.tmp"; run env; expect 1 "A6 a temp file in accepted/ is red" "not a record"
fresh; run env REJECT=GoMod; expect 1 "A7 a rejected plugin is red" "VERDICT: REJECTED"
mode=--no-record
fresh; run env CORE=c2; expect 0 "A8 --no-record passes no --record and checks no record"
grep -q -- '--record' "$work/lake.log" && fail "A8: --record was passed"
mode=--bogus
fresh; run env; expect 2 "A9 an unknown mode is a usage error" "usage:"

direct=$(grep -n 'mitos-gate accept' "$root"/.github/workflows/*.yml || true)
[ -z "$direct" ] || fail "A10 a workflow runs mitos-gate accept itself: $direct"
for f in ci.yml nightly.yml; do
  grep -q 'accept-plugins.sh --record' "$root/.github/workflows/$f" || fail "A10 $f does not run accept-plugins.sh --record"
done
grep -q 'accept-plugins.sh --no-record' "$root/.github/workflows/nightly.yml" || fail "A10 the canary does not run accept-plugins.sh --no-record"
ok "A10 every workflow accepts through accept-plugins.sh"
mode=--record
fresh; ln -s GoMod.lean "$work/repo/examples/acme/Plugins/Evil.lean"; run env
expect 1 "A11 an extra symlink plugin is red before any accept" "nonregular Lean entry"
[ ! -s "$work/lake.log" ] || fail "A11: an accept ran"
echo "accept-plugins: done"
