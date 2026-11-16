#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
lake build mitos-gate >/dev/null
bin="$root/.lake/build/bin/mitos-gate"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
expect() {
  local code=$1 pattern=$2 got=0
  shift 2
  "$bin" workflow "$@" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [[ $got != "$code" ]] || { [[ -n $pattern ]] && ! grep -Fq "$pattern" "$tmp/err"; } ||
      { [[ $code == 0 ]] && [[ -s "$tmp/err" ]]; }; then
    printf 'FAIL expected %s and %s, got %s\n' "$code" "$pattern" "$got"
    cat "$tmp/out" "$tmp/err"
    exit 1
  fi
  [[ ! -s "$tmp/out" ]]
}
for name in ci nightly clear-needs-rebase land-protection land update-prs; do
  expect 0 '' parse ".github/workflows/$name.yml"
done
expect 1 'owner-ping.yml:27: refused: anchor or alias' parse .github/workflows/owner-ping.yml
cp .github/workflows/ci.yml "$tmp/workflow.yml"
printf '\n# x: |\nshapeA: plain\nshapeB:\n  - name: |\n    run: echo ok\n' >>"$tmp/workflow.yml"
expect 0 '' parse "$tmp/workflow.yml"
for char in '\r' '\t' '\302\205' '\342\200\250' '\342\200\251'; do
  cp .github/workflows/ci.yml "$tmp/bad.yml"
  printf '\n# control%b\n' "$char" >>"$tmp/bad.yml"
  expect 1 'outside LF and printable ASCII' parse "$tmp/bad.yml"
done
printf 'run: "echo ${{ \\x6eeeds.decide.outputs.pr }}"\n' >"$tmp/escape.yml"
expect 1 ':1: refused: backslash escape in a double-quoted scalar' parse "$tmp/escape.yml"
cat .github/workflows/ci.yml "$tmp/escape.yml" >"$tmp/escape-copy.yml"
expect 1 'backslash escape in a double-quoted scalar' parse "$tmp/escape-copy.yml"
printf 'a: <<:x\n' >"$tmp/plain.yml"
expect 0 '' parse "$tmp/plain.yml"
for text in 'a: [#x]' 'a: {#x}' 'a: [b,#x]'; do
  printf '%s\n' "$text" >"$tmp/flow.yml"
  expect 1 ':1: refused: scalar runs onto the next line' parse "$tmp/flow.yml"
done
printf 'a: [x#y]\nb: #comment\n' >"$tmp/hash.yml"
expect 0 '' parse "$tmp/hash.yml"
expect 2 'workflow: cannot read' parse "$tmp/missing.yml"
expect 2 'usage:' parse
printf 'workflow tests passed\n'
