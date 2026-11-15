#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u
script="$(cd "$(dirname "$0")" && pwd)/carry.sh"
failed=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

g() { git -C "$1" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "${@:2}"; }
sha() { printf "$1%.0s" $(seq 40); }

# A real remote for acme/widgets with main and a branch of two commits, and a clone whose origin
# URL carries a credential that the script must never print.
mkdir -p "$work/remotes/acme"
git init -q --bare -b main "$work/remotes/acme/widgets.git"
git init -q -b main "$work/seed"
echo one >"$work/seed/f.txt"
g "$work/seed" add -A
g "$work/seed" commit -qm base
g "$work/seed" remote add origin "$work/remotes/acme/widgets.git"
g "$work/seed" push -q origin main 2>/dev/null
g "$work/seed" checkout -q -b feature
echo two >>"$work/seed/f.txt"
g "$work/seed" commit -qam first
c1=$(g "$work/seed" rev-parse HEAD)
echo three >>"$work/seed/f.txt"
g "$work/seed" commit -qam second
c2=$(g "$work/seed" rev-parse HEAD)
g "$work/seed" push -q origin feature 2>/dev/null
git clone -q "$work/remotes/acme/widgets.git" "$work/clone"
secret_url="http://x-access-token:SECRET123@127.0.0.1:1234/git/acme/widgets.git"
g "$work/clone" config "url.$work/remotes/.insteadOf" "http://x-access-token:SECRET123@127.0.0.1:1234/git/"
g "$work/clone" remote set-url origin "$secret_url"

mkdir "$work/bin" "$work/f"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >>"$FAKE_DIR/calls"
echo >>"$FAKE_DIR/calls"
[ "${1:-}" = api ] || exit 1
shift
route=
while [ $# -gt 0 ]; do
  case $1 in
    -*) shift ;;
    *) route=$1; shift ;;
  esac
done
[ "${FAKE_MODE:-}" = fail ] && { echo "gh: HTTP 502" >&2; exit 1; }
[ -n "${FAKE_FAIL:-}" ] && [[ $route == *"$FAKE_FAIL"* ]] && { echo "gh: HTTP 500" >&2; exit 1; }
f=$FAKE_DIR/f
case $route in
  repos/acme/widgets/pulls/86) cat "$f/pr.json" ;;
  "repos/acme/widgets/activity?ref=refs/heads/"*"&direction=desc&per_page=100")
    echo "${route#*ref=}" >"$FAKE_DIR/activity.ref"
    cat "$f/activity.json" ;;
  *) echo "unexpected $route" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

# main's tool as the library makes it, with a stub lake that builds a stub gate.
cat >"$work/bin/lake" <<'EOF'
#!/usr/bin/env bash
echo build >>"$FAKE_DIR/lake.log"
mkdir -p .lake/build/bin
cp "$FAKE_DIR/gate-stub" .lake/build/bin/mitos-gate
chmod +x .lake/build/bin/mitos-gate
EOF
chmod +x "$work/bin/lake"
cat >"$work/gate-stub" <<'EOF'
#!/usr/bin/env bash
{ pwd; printf '%s\n' "$*"; } >"$FAKE_DIR/gate.call"
cat >"$FAKE_DIR/gate.stdin"
[ -n "${GATE_WHY:-}" ] && echo "$GATE_WHY" >&2
exit "${GATE_EXIT:-0}"
EOF
: >"$work/lake.log"
path="$work/bin:/usr/bin:/bin"
[ "$(PATH=$path type -P gh)" = "$work/bin/gh" ] || { echo "FAIL  gh is not the fake"; exit 1; }

pr() {
  jq -n --arg h "$1" --arg r "$2" --arg repo "${3:-acme/widgets}" \
    '{number:86, head:{sha:$h, ref:$r, repo:(if $repo == "null" then null else {full_name:$repo} end)}}' >"$work/f/pr.json"
}
activity() {
  jq -n --arg b "$1" --arg a "$2" \
    '[[{timestamp:"2026-11-09T10:00:00Z", activity_type:"force_push", actor:{login:"mitos-pr-updater[bot]"}, before:$b, after:$a}]]' \
    >"$work/f/activity.json"
}
pr "$c2" feature
activity "$c1" "$c2"

envs() {
  env -u GH_HOST -u GITHUB_TOKEN -u MITOS_MAIN_TOOL PATH="$path" FAKE_DIR="$work" \
    CLAUDE_PROJECT_DIR="$work/clone" GH_TOKEN=dummy HTTPS_PROXY=http://127.0.0.1:9 \
    https_proxy=http://127.0.0.1:9 "$@"
}
run() {
  rm -f "$work/gate.call" "$work/gate.stdin"
  out=$(cd "$work/clone" && envs "$script" "$@" 2>"$work/stderr")
  code=$?
  err=$(cat "$work/stderr")
  printf '%s\n%s\n' "$out" "$err" >>"$work/all"
}
check() {
  if [ "$2" = "$3" ]; then echo "ok    $1"; else
    echo "FAIL  $1"; printf '      got:  %q\n      want: %q\n' "$2" "$3"; failed=1
  fi
}
is() {
  check "$1: standard output" "$out" "$2"
  check "$1: standard error" "$err" "$3"
  check "$1: exit" "$code" "$4"
}
builds() { grep -c build "$work/lake.log"; }

run --no-build 86 "$c1"
is "--no-build with nothing built is an error" "" "carry: main's tool is not built at $(g "$work/clone" rev-parse --short=7 origin/main)" 2
check "--no-build builds nothing" "$(builds)" 0
check "--no-build asks the gate nothing" "$([ -e "$work/gate.call" ] && echo asked || echo no)" no

run 86 "$c1"
is "the first use builds main's tool and answers" "carry #86: ${c1:0:7} covers ${c2:0:7}" "" 0
check "one build" "$(builds)" 1
tool_dir=$(g "$work/clone" rev-parse --path-format=absolute --git-common-dir)/mitos-main-tool
{ echo "$tool_dir"; echo "carry origin/main $c1 $c2"; } >"$work/want.call"
check "carry is asked in main's checkout, from the commit to the head" "$(cat "$work/gate.call")" "$(cat "$work/want.call")"
check "the pushes go in as TSV" "$(cat "$work/gate.stdin")" \
  "$(printf '2026-11-09T10:00:00Z\tforce_push\tmitos-pr-updater[bot]\t%s\t%s' "$c1" "$c2")"
check "the pushes are the branch's" "$(cat "$work/activity.ref")" "refs/heads/feature&direction=desc&per_page=100"

run --no-build 86 "$c1"
is "--no-build with the tool built answers" "carry #86: ${c1:0:7} covers ${c2:0:7}" "" 0
check "still one build" "$(builds)" 1

GATE_EXIT=1 GATE_WHY="the content ids differ" run 86 "$c1"
is "a commit that does not cover the head: the tool's reason is passed on" \
  "carry #86: ${c1:0:7} does not cover ${c2:0:7}" "carry: the content ids differ" 1
GATE_EXIT=1 GATE_WHY=$'one\ntwo\nthree\nfour' run 86 "$c1"
check "at most three lines of the reason" "$err" $'carry: one\ncarry: two\ncarry: three'
GATE_EXIT=3 run 86 "$c1"
is "a tool that does not answer is an error" "" "carry: mitos-gate carry did not answer" 2
GATE_EXIT=124 run 86 "$c1"
is "a timeout says so" "" "carry: mitos-gate carry timed out" 2

usage="carry: usage: carry.sh [--no-build] <pr> <commit>"
run
is "no arguments: usage" "" "$usage" 2
run 86
is "no commit: usage" "" "$usage" 2
run 86 "${c1:0:7}"
is "a short commit: usage" "" "$usage" 2
run abc "$c1"
is "a PR that is not a number: usage" "" "$usage" 2
run 0 "$c1"
is "PR 0: usage" "" "$usage" 2
run 86 "$c1" extra
is "a third argument: usage" "" "$usage" 2
run --other 86 "$c1"
is "an unknown flag: usage" "" "$usage" 2
run 86 "$(sha A)"
is "an upper-case commit: usage" "" "$usage" 2

pr "$c2" a..b
run 86 "$c1"
is "a branch name with two dots is refused" "" "carry: PR #86 has a branch name this script does not put in a route" 2
pr "$c2" -feature
run 86 "$c1"
is "a branch name that starts with a dash is refused" "" "carry: PR #86 has a branch name this script does not put in a route" 2
pr "$c2" 'fea ture;x'
run 86 "$c1"
is "a branch name with odd characters is refused" "" "carry: PR #86 has a branch name this script does not put in a route" 2
pr "$c2" feature other/widgets
run 86 "$c1"
is "a fork is not carried" "" "carry: PR #86 is from another repository" 2
pr "$c2" feature null
run 86 "$c1"
is "a deleted fork is not carried" "" "carry: PR #86 is from another repository" 2
echo '{"number":86,"head":{"sha":"$(touch PWNED)","ref":"feature","repo":{"full_name":"acme/widgets"}}}' >"$work/f/pr.json"
run 86 "$c1"
is "a head that is not a commit SHA is refused" "" "carry: PR #86 has no head commit" 2
pr "$c2" feature

out=$(cd "$work/clone" && envs FAKE_MODE=fail "$script" 86 "$c1" 2>&1); code=$?
check "GitHub fails: the line" "$out" "carry: cannot read PR #86"
out=$(cd "$work/clone" && envs FAKE_FAIL=activity "$script" 86 "$c1" 2>&1); code=$?
check "the pushes cannot be read: the line" "$out" "carry: cannot read the pushes of PR #86"
check "the pushes cannot be read: exit" "$code" 2
echo '{"not":"pages"}' >"$work/f/activity.json"
run 86 "$c1"
is "pushes of the wrong shape are an error" "" "carry: cannot read the pushes of PR #86" 2
activity "$c1" "$c2"

run 86 "$(sha e)"
is "a commit the remote lacks is an error, not a no" "" "carry: cannot fetch feature and eeeeeee" 2
pr "$c2" gone
run 86 "$c1"
is "a branch the remote lacks is an error" "" "carry: cannot fetch gone and ${c1:0:7}" 2
pr "$c2" feature

run 86 "$c1"
is "back to a covered head" "carry #86: ${c1:0:7} covers ${c2:0:7}" "" 0
out=$(cd "$work/clone" && envs MITOS_MAIN_TOOL="$work/elsewhere" "$script" --no-build 86 "$c1" 2>&1); code=$?
check "MITOS_MAIN_TOOL is said out loud" "$(head -n 1 <<<"$out")" \
  "carry: MITOS_MAIN_TOOL is set, so the tool is not the one this clone keeps"
check "a tool that is not built there is an error" "$code" 2

check "one build after every case" "$(builds)" 1
if grep -q -e SECRET123 -e 127.0.0.1:1234 "$work/all"; then
  echo "FAIL  the origin URL was printed"; failed=1
else echo "ok    the origin URL is never printed"; fi
if grep -q -e ' -X' -e ' --method' -e ' -f ' -e ' -F ' "$work/calls" || grep -v '^api ' "$work/calls" | grep -q .; then
  echo "FAIL  a call was not a gh api read"; failed=1
else echo "ok    every call is a gh api read ($(wc -l <"$work/calls") calls)"; fi

echo "carry: done"
exit "$failed"
