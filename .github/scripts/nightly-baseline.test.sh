#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/temp"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_WORK/calls"
route=$2
if [ "$route" = -X ]; then route=$4; fi
if [ "$route" = --paginate ]; then route=$3; fi
case $route in
  repos/owner/repo/actions/workflows/nightly.yml/runs)
    [ "${FAIL_API:-}" != runs ] || exit 9
    export STUB_ARGS="$*"
    python3 - <<'PY'
import json,os
runs=[]
for n,path,branch,repo in [(99,'nightly','main','owner/repo'),(98,'ci','main','owner/repo'),(97,'nightly','topic','owner/repo'),(96,'nightly','main','fork/repo'),(95,'nightly','main','owner/repo'),(94,'nightly','main','owner/repo')]:
 runs.append(dict(id=n,path=f'.github/workflows/{path}.yml',head_branch=branch,head_repository=dict(full_name=repo),status='completed',conclusion='failure'))
if os.environ.get('PAGINATE') and 'page=1' in os.environ['STUB_ARGS'].split():
 runs=[dict(id=n,path='.github/workflows/ci.yml') for n in range(1000,1100)]
if os.environ.get('EMPTY'): runs=[]
print(json.dumps(dict(workflow_runs=runs)))
PY
    ;;
  repos/owner/repo/actions/runs/95/artifacts?per_page=100)
    [ "${FAIL_API:-}" != artifacts ] || exit 9
    if [ -n "${MALFORMED:-}" ]; then echo '{broken'; else
      echo '{"artifacts":[{"id":195,"name":"scorecard-numbers","expired":true}]}'
    fi ;;
  repos/owner/repo/actions/runs/94/artifacts?per_page=100)
    if [ -n "${NO_ARTIFACT:-}" ]; then echo '{"artifacts":[]}'; else
      echo '{"artifacts":[{"id":194,"name":"scorecard-numbers","expired":false}]}'
    fi ;;
  repos/owner/repo/actions/artifacts/194/zip)
    [ "${FAIL_API:-}" != download ] || exit 9
    cat "$STUB_WORK/base.zip" ;;
  *) echo "unexpected route: $route" >&2; exit 8 ;;
esac
STUB
chmod +x "$work/bin/gh"
python3 - "$work/base.zip" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'w') as z: z.writestr('numbers.tsv','fixture\ttoy\n')
PY
run() {
  rm -rf "$work/temp/base"
  : > "$work/calls"
  status=0
  PATH="$work/bin:$PATH" STUB_WORK="$work" GITHUB_REPOSITORY=owner/repo GITHUB_RUN_ID=99 \
    RUNNER_TEMP="$work/temp" "$@" "$root/.github/scripts/nightly-baseline.sh" > "$work/out" 2>&1 || status=$?
}
expect() { [ "$status" -eq "$1" ] || { cat "$work/out"; exit 1; }; echo "ok   $2"; }
run env; expect 0 'newest eligible artifact, including a failed nightly'
grep -q 'nightly run 94, artifact 194' "$work/out"
[ "$(cat "$work/temp/base/numbers.tsv")" = $'fixture\ttoy' ]
for id in 99 98 97 96; do
  if grep -q "runs/$id/artifacts" "$work/calls"; then exit 1; fi
done
run env PAGINATE=1; expect 0 'run pagination continues to the next page'
grep -q 'page=2' "$work/calls"
run env EMPTY=1; expect 0 'no previous nightly is not an error'
[ ! -e "$work/temp/base/numbers.tsv" ]
run env NO_ARTIFACT=1; expect 0 'no unexpired artifact is not an error'
for fail in runs artifacts download; do
  run env FAIL_API="$fail"; expect 9 "API $fail error fails closed"
  [ ! -e "$work/temp/base/numbers.tsv" ]
done
run env MALFORMED=1; [ "$status" -ne 0 ]; echo 'ok   malformed artifact API response fails closed'
[ ! -e "$work/temp/base/numbers.tsv" ]
for kind in extra duplicate symlink; do
  python3 - "$work/base.zip" "$kind" <<'PY'
import sys,zipfile,stat
with zipfile.ZipFile(sys.argv[1], 'w') as z:
 if sys.argv[2]=='symlink':
  entry=zipfile.ZipInfo('numbers.tsv'); entry.external_attr=(stat.S_IFLNK | 0o777)<<16
  z.writestr(entry,'target')
 else:
  z.writestr('numbers.tsv','fixture\ttoy\n')
  z.writestr('extra' if sys.argv[2]=='extra' else 'numbers.tsv','bad')
PY
  run env; [ "$status" -ne 0 ]; echo "ok   $kind artifact fails closed"
  [ ! -e "$work/temp/base/numbers.tsv" ]
done
printf 'invalid archive' > "$work/base.zip"
run env; [ "$status" -ne 0 ]; echo 'ok   corrupt artifact fails closed'
[ ! -e "$work/temp/base/numbers.tsv" ]
echo 'nightly-baseline: done'
