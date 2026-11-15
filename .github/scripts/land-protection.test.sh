#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/land-protection.sh
wf=$root/.github/workflows/land-protection.yml
land=$root/.github/workflows/land.yml
source "$root/.github/scripts/land-workflow.lib.sh"
land_decide=$(job_block "$land" decide)
fetch=$root/gate/snapshot-fetch.sh
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is not installed"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() {
  echo "FAIL $1"
  shift
  for l in "$@"; do echo "  | $l"; done
  fail=$((fail + 1))
}
problems=()
start() { problems=(); }
note() { problems+=("$@"); }
finish() { if [ ${#problems[@]} = 0 ]; then ok "$1"; else bad "$1" "${problems[@]}"; fi; }

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[ "$*" = "api repos/owner/mitos/branches/main/protection" ] || { echo "stub gh: unexpected call" >&2; exit 64; }
case ${STUB_READ:-ok} in
  ok) echo '{"url":"u","enforce_admins":{"enabled":true},"required_status_checks":{"strict":true,"contexts":["gate"],"checks":[{"context":"gate","app_id":15368}]}}' ;;
  forbidden) echo '{"message":"Resource not accessible by integration","status":"403"}'; echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1 ;;
  list) echo '[]' ;;
  junk) echo 'not json' ;;
esac
EOF
chmod +x "$tmp/bin/gh"
want_protection='{"url":"u","enforce_admins":{"enabled":true},"required_status_checks":{"strict":true,"contexts":["gate"],"checks":[{"context":"gate","app_id":15368}]}}'

reader() {
  local name=$1
  shift
  dir=$tmp/runs/$name
  rm -rf "$dir"
  mkdir -p "$dir"
  code=0
  env -u GITHUB_REF -u GITHUB_RUN_ID -u GITHUB_RUN_ATTEMPT -u STUB_READ PATH="$tmp/bin:$PATH" \
    STUB_LOG="$dir/gh.log" GITHUB_REF=refs/heads/main GITHUB_RUN_ID=43683815630 GITHUB_RUN_ATTEMPT=1 \
    "$@" >"$dir/stdout" 2>"$dir/stderr" || code=$?
  calls=$(cat "$dir/gh.log" 2>/dev/null)
}
exits() { [ "$code" = "$1" ] || note "exit $code, expected $1" "stderr: $(cat "$dir/stderr")"; }
no_file() { [ -z "$(ls -A "$dir/out" 2>/dev/null)" ] || note "left files: $(ls -A "$dir/out")"; }

start
reader read "$script" owner/mitos "$tmp/runs/read/out"
exits 0
f=$dir/out/read.json
[ "$(grep -c '' "$f" 2>/dev/null)" = 1 ] || note "read.json is not one line"
jq -e --argjson p "$want_protection" 'keys_unsorted == ["v","repo","ref","run","attempt","read","protection"]
  and .v == 1 and .repo == "owner/mitos" and .ref == "refs/heads/main" and .run == 43683815630
  and .attempt == 1 and (.read | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  and .protection == $p' "$f" >/dev/null 2>&1 || note "read.json: $(cat "$f" 2>/dev/null)"
[ "$(ls -A "$dir/out")" = read.json ] || note "other files: $(ls -A "$dir/out")"
[ "$calls" = "api repos/owner/mitos/branches/main/protection" ] || note "gh calls: $calls"
grep -qE '^land-protection: read main.s protection at [0-9T:Z-]+$' "$dir/stdout" || note "stdout: $(cat "$dir/stdout")"
finish reader-writes-one-read-of-the-one-route

start
for kind in forbidden list junk; do
  reader "fail-$kind" STUB_READ="$kind" "$script" owner/mitos "$tmp/runs/fail-$kind/out"
  exits 1
  no_file
  [ "$calls" = "api repos/owner/mitos/branches/main/protection" ] || note "$kind: gh calls: $calls"
done
grep -qx "land-protection: the read of main's protection failed" "$tmp/runs/fail-forbidden/stderr" \
  || note "forbidden: stderr: $(cat "$tmp/runs/fail-forbidden/stderr")"
grep -qx "land-protection: main's protection is not a JSON object" "$tmp/runs/fail-list/stderr" \
  || note "list: stderr: $(cat "$tmp/runs/fail-list/stderr")"
finish a-failed-read-writes-nothing-and-is-red

start
for bad_env in GITHUB_REF=refs/heads/feature GITHUB_REF=refs/pull/7/merge GITHUB_REF=refs/tags/main GITHUB_REF= \
  'GITHUB_RUN_ID=12; id' GITHUB_RUN_ID= GITHUB_RUN_ATTEMPT=0 GITHUB_RUN_ATTEMPT=x; do
  reader bad-env "$bad_env" "$script" owner/mitos "$tmp/runs/bad-env/out"
  exits 2
  no_file
  [ -z "$calls" ] || note "gh was called for [$bad_env]"
  grep -qx "land-protection: ${bad_env%%=*} is not .*" "$dir/stderr" || note "stderr for [$bad_env]: $(cat "$dir/stderr")"
done
reader usage "$script" owner/mitos
exits 2
grep -qx 'land-protection: usage: land-protection.sh <owner/name> <dir>' "$dir/stderr" || note "usage: $(cat "$dir/stderr")"
reader bad-repo "$script" owner "$tmp/runs/bad-repo/out"
exits 2
reader dot-repo "$script" owner/.. "$tmp/runs/dot-repo/out"
exits 2
mkdir -p "$tmp/full" && echo x >"$tmp/full/x"
reader full "$script" owner/mitos "$tmp/full"
exits 2
grep -qx 'land-protection: the folder is not empty' "$dir/stderr" || note "full: $(cat "$dir/stderr")"
[ -z "$calls" ] || note "gh was called on a usage error"
finish only-a-run-on-main-reads

steps_of() { awk '/^    steps:$/ { on = 1; next } on { print }' "$1"; }
block() { awk -v h="$2" '$0 == h { on = 1; print; next } on && /^      - / { exit } on { print }' "$1"; }
if_of() { awk '/^    if: >-$/ { on = 1; print; next } on && /^    [a-z]/ { exit } on { print }' "$1"; }
on_of() { awk '/^on:$/ { on = 1; print; next } on && /^[a-z]/ { exit } on { print }' "$1"; }
joined=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$script")
mint=$(block "$wf" '      - name: Mint an app token that can only read administration')
want_mint='      - name: Mint an app token that can only read administration
        id: app
        uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547 # v1.12.0
        with:
          app-id: ${{ vars.PR_UPDATER_APP_ID }}
          private-key: ${{ secrets.PR_UPDATER_APP_KEY }}
          permission-administration: read'

start
[ "$mint" = "$want_mint" ] || note "the mint step is not the pinned one:" "$mint"
[ "$(grep -c 'permission-' "$wf")" = 1 ] || note "land-protection.yml names another permission- input"
! grep -nE 'skip-token-revoke|^[[:space:]]*(owner|repositories):' "$wf" \
  || note "the token is kept after the job or reaches past this repository"
[ "$(grep -o 'secrets\.[A-Za-z_]*' "$wf" | sort -u)" = secrets.PR_UPDATER_APP_KEY ] \
  || note "land-protection.yml names another secret"
[ "$(grep -c 'secrets\.' "$wf")" = 1 ] || note "the key is named outside the mint step"
[ "$(grep -c 'steps.app.outputs.token' "$wf")" = 1 ] \
  || note "the app token is used other than once"
grep -qxF '          GH_TOKEN: ${{ steps.app.outputs.token }}' "$wf" || note "the app token is not GH_TOKEN of a step"
! grep -nE 'github\.token|GITHUB_TOKEN|id-token|write' "$wf" || note "land-protection.yml names the workflow token or a write"
grep -qx 'permissions: {}' "$wf" || note "land-protection.yml has no top-level permissions: {}"
[ "$(grep -cE '^[[:space:]]*permissions:' "$wf")" = 2 ] || note "land-protection.yml has another permissions block"
[ "$(awk '/^    permissions:$/ { on = 1; next } on && !/^      / { exit } on { print }' "$wf")" = '      contents: read' ] \
  || note "the read job's workflow token may do more than read contents"
grep -qx '    environment: trusted' "$wf" || note "the read job is not in the trusted environment"
! grep -nE 'secrets\.|github-app-token|app-id|private-key|^[[:space:]]*environment:|id-token|write' <<<"$land_decide" \
  || note "land.yml decide names a secret, an app token, an environment or a write"
grep -qx '      actions: read' "$land" || note "land.yml's decide cannot read the reader's runs and artifacts"
finish the-key-sits-in-the-reader-and-not-in-decide

start
[ "$(grep -c '^  [a-z-]*:$' <(awk '/^jobs:$/ { on = 1; next } on' "$wf"))" = 1 ] || note "land-protection.yml has another job"
uses=$(grep -oE 'uses: [^ ]+' "$wf" | tr '\n' ' ')
[ "$uses" = "uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547 uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 " ] \
  || note "land-protection.yml uses other actions, or in another order: $uses"
checkout=$(block "$wf" '      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0')
[ "$checkout" = '      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          persist-credentials: false' ] || note "the checkout is not main's commit without credentials:" "$checkout"
runs=$(grep -E '^[[:space:]]*(- )?run:' "$wf" | sed -E 's/^[[:space:]]*(- )?run: //')
[ "$runs" = '.github/scripts/land-protection.sh "$GITHUB_REPOSITORY" "$RUNNER_TEMP/land-protection"' ] \
  || note "land-protection.yml runs other commands:" "$runs"
! grep -nE '^[[:space:]]*(- )?run:[[:space:]]*[|>]' "$wf" || note "a run: block spans lines"
! grep -nE '\$\{\{[^}]*github\.event' "$wf" || note "land-protection.yml reads event text"
order=$(steps_of "$wf" | grep -nE 'uses: actions/checkout|id: app|run: \.github/scripts/land-protection\.sh|uses: actions/upload-artifact' \
  | cut -d: -f1 | tr '\n' ' ')
sorted=$(tr ' ' '\n' <<<"$order" | grep . | sort -n | tr '\n' ' ')
[ "$order" = "$sorted" ] && [ "$(wc -w <<<"$order")" = 4 ] || note "the steps are not checkout, mint, read, upload"
upload=$(block "$wf" '      - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2')
[ "$upload" = '      - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          name: land-protection-${{ github.run_id }}-${{ github.run_attempt }}
          path: ${{ runner.temp }}/land-protection/read.json
          if-no-files-found: error
          retention-days: 1' ] || note "the upload is not the one snapshot-fetch.sh reads:" "$upload"
gh_lines=$(grep -wE 'gh' <<<"$joined" | grep -vE '^for tool in |^# ')
if [ "$(grep -c '' <<<"$gh_lines")" != 1 ] \
  || ! grep -qF 'timeout -k 5 120 gh api "repos/$repo/branches/main/protection" ' <<<"$gh_lines"; then
  note "land-protection.sh makes another gh call: $gh_lines"
fi
! grep -qE -- '(^|[[:space:]])(-X|-f|-F|--method|--field|--raw-field|--input|--paginate)([[:space:]=]|$)' <<<"$gh_lines" \
  || note "the gh call has a write flag"
! grep -nwE 'curl|wget|git' "$script" | grep -v '^[0-9]*:#' || note "land-protection.sh names curl, wget or git"
finish the-reader-reads-only-the-one-route

start
[ "$(on_of "$wf")" = "$(on_of "$land")" ] || note "land-protection.yml does not start on land.yml's events:" "$(on_of "$wf")"
[ -n "$(if_of "$land")" ] && [ "$(if_of "$wf")" = "$(if_of "$land")" ] \
  || note "the read job's if: is not decide's:" "$(if_of "$wf")"
! grep -qE '^  (pull_request|pull_request_target|workflow_call|schedule)' "$wf" || note "land-protection.yml starts on another event"
for pin in 'land-protection-$id-$attempt' 'unzip -p "$s/artifact.zip" read.json' \
  'actions/workflows/land-protection.yml/runs?branch=main' '.path == ".github/workflows/land-protection.yml"'; do
  grep -qF -- "$pin" "$fetch" || note "snapshot-fetch.sh does not read this workflow's artifact: no [$pin]"
done
grep -qxF '        run: .github/scripts/land-protection.test.sh' "$root/.github/workflows/ci.yml" \
  || note "ci.yml does not run this test"
finish the-reader-pairs-with-decide

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
