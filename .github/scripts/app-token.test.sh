#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=.github/scripts/land-workflow.lib.sh
source "$root/.github/scripts/land-workflow.lib.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() {
  echo "FAIL $1"
  shift
  for line in "$@"; do echo "  | $line"; done
  fail=$((fail + 1))
}
problems=()
start() { problems=(); }
note() { problems+=("$@"); }
finish() { if [ ${#problems[@]} = 0 ]; then ok "$1"; else bad "$1" "${problems[@]}"; fi; }

for wf in "$root"/.github/workflows/*.yml; do
  awk -v file="$wf" '
    /^jobs:$/ { jobs=1;next }
    jobs && /^  [A-Za-z0-9_-]+:/ { job=$1; sub(/:$/, "", job) }
    /uses: actions\/create-github-app-token/ { print file "|" job "|" NR "|" $0 }
  ' "$wf"
done >"$tmp/mints"
[ -s "$tmp/mints" ] || { echo "FAIL no app token mint found"; exit 1; }

start
while IFS='|' read -r wf job number pin; do
  [[ $pin =~ uses:\ actions/create-github-app-token@[0-9a-f]{40}([[:space:]]|$) ]] \
    || note "$wf:$number has no immutable commit pin: $pin"
done <"$tmp/mints"
finish every-mint-is-pinned-to-a-commit

start
while IFS='|' read -r wf job number pin; do
  mint=$(awk -v line="$number" 'NR == line { inside=1; print;next }
    inside && /^      - / { exit } inside { print }' "$wf")
  permissions=$(grep -E '^[[:space:]]*permission-' <<<"$mint")
  [ -n "$permissions" ] || note "$wf:$number does not narrow the token"
  while IFS= read -r input; do
    [[ $input =~ ^\ {10}permission-(contents|pull-requests|workflows|administration):\ (read|write)$ ]] \
      || note "$wf:$number has an unsupported permission input: $input"
  done <<<"$permissions"
  [ "$(grep -c 'permission-' <<<"$mint")" = "$(wc -l <<<"$permissions")" ] \
    || note "$wf:$number has a permission input outside with"
  ! grep -qE 'skip-token-revoke|^[[:space:]]*(owner|repositories):' <<<"$mint" \
    || note "$wf:$number broadens the installation or keeps its token"
done <"$tmp/mints"
finish every-mint-names-its-permissions

start
while IFS='|' read -r wf job number pin; do
  block=$(job_block "$wf" "$job")
  [ "$(grep -c '^    environment: trusted$' <<<"$block")" = 1 ] \
    || note "$wf:$number mints outside trusted"
done <"$tmp/mints"
finish every-mint-is-in-trusted

start
updater=$(job_block "$root/.github/workflows/update-prs.yml" rebase)
permissions=$(grep -E '^          permission-' <<<"$updater" | sort)
[ "$permissions" = '          permission-contents: write
          permission-pull-requests: write
          permission-workflows: write' ] || note "updater permissions: $permissions"
[ "$(grep -cF 'uses: actions/create-github-app-token@' <<<"$updater")" = 1 ] \
  || note "updater does not have exactly one mint"
for pin in '          private-key: ${{ secrets.PR_UPDATER_APP_KEY }}' \
  '          app-id: ${{ vars.PR_UPDATER_APP_ID }}' \
  '          token: ${{ steps.app.outputs.token }}' \
  '          GH_TOKEN: ${{ steps.app.outputs.token }}'; do
  grep -qxF "$pin" <<<"$updater" || note "updater does not use [$pin]"
done
grep -qE 'uses: actions/checkout@[0-9a-f]{40}([[:space:]]|$)' <<<"$updater" \
  || note "updater checkout is not pinned"
grep -qxF '        run: .github/scripts/app-token.test.sh' "$root/.github/workflows/ci.yml" \
  || note "ci does not run this test"
finish the-updater-mints-what-it-pushes-with

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
