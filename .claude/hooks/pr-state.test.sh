#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/pr-state.sh"
failed=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A scratch repo whose origin carries a token, to prove the URL is parsed and never printed.
git init -q "$work/repo"
git -C "$work/repo" remote add origin "http://x-access-token:SECRET123@127.0.0.1:1234/git/acme/widgets.git"

# A fake gh on PATH. FAKE_MODE picks the behaviour; every call is logged to $work/calls.
mkdir "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/calls"
case "$FAKE_MODE" in
  fail) echo "gh: HTTP 401" >&2; exit 1 ;;
  sleep) sleep 30; exit 0 ;;
  badjson) echo "<html>not json</html>"; exit 0 ;;
esac
[ "$1" = api ] || exit 1
case "$2" in
  repos/acme/widgets/pulls\?state=open*) cat "$FAKE_DIR/open.json" ;;
  repos/acme/widgets/pulls\?state=closed*) cat "$FAKE_DIR/closed.json" ;;
  repos/acme/widgets/branches/main) cat "$FAKE_DIR/main.json" ;;
  repos/acme/widgets/actions/workflows/ci.yml/runs*) cat "$FAKE_DIR/ci.json" ;;
  *) echo "unexpected route $2" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

recent=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
older=$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ)
old=$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
cat >"$work/open.json" <<EOF
[
 {"number":45,"draft":false,"head":{"sha":"9c9db92897db266388f95ee3228d19eaf709372a"},
  "labels":[{"name":"spec-approved"},{"name":"needs-rebase"}],"assignees":[{"login":"kitimark"}]},
 {"number":21,"draft":true,"head":{"sha":"3cccb1b00000000000000000000000000000000"},
  "labels":[],"assignees":[]}
]
EOF
cat >"$work/closed.json" <<EOF
[
 {"number":30,"closed_at":"$older","merged_at":null,"head":{"sha":"bbbbbbb1111111111111111111111111111111"}},
 {"number":44,"closed_at":"$recent","merged_at":"$recent","head":{"sha":"04fcb83aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},
 {"number":9,"closed_at":"$old","merged_at":"$old","head":{"sha":"ccccccc2222222222222222222222222222222"}}
]
EOF
echo '{"commit":{"sha":"46e9998b2b66c0214b286759035fd2b501c463d1"}}' >"$work/main.json"
echo '{"workflow_runs":[{"status":"completed","conclusion":"success","head_sha":"46e9998b2b66c0214b286759035fd2b501c463d1"}]}' >"$work/ci.json"

run() { # mode -> sets out, code
  out=$(FAKE_MODE=$1 FAKE_DIR=$work CLAUDE_PROJECT_DIR=$work/repo PATH="$work/bin:$PATH" "$hook" 2>/dev/null </dev/null)
  code=$?
}

expect() { # name, substring that must appear in $out
  if grep -qF -- "$2" <<<"$out"; then echo "ok    $1"; else echo "FAIL  $1: missing '$2'"; failed=1; fi
}
reject() { # name, substring that must not appear in $out
  if grep -qF -- "$2" <<<"$out"; then echo "FAIL  $1: found '$2'"; failed=1; else echo "ok    $1"; fi
}
exit0() {
  if [ "$code" -eq 0 ]; then echo "ok    $1: exit 0"; else echo "FAIL  $1: exit $code"; failed=1; fi
}

: >"$work/calls"
run ok
exit0 "canned state"
expect "header" "GitHub state (read "
expect "header says trust" "trust this over memory):"
expect "open PR with labels and assignee" "open #45 head 9c9db92 ready labels=spec-approved,needs-rebase assignees=kitimark"
expect "draft PR with no labels" "open #21 head 3cccb1b draft labels=- assignees=-"
expect "merged PR within 24h" "merged #44 at ${recent:0:16}Z head 04fcb83"
expect "closed PR within 24h" "closed #30 at ${older:0:16}Z head bbbbbbb"
reject "PR older than 24h is left out" "#9 "
expect "main and ci" "main 46e9998; latest ci run on main: completed/success head 46e9998"
reject "origin credentials are not printed" "SECRET123"
if [ "$(grep -c . <<<"$out")" -le 25 ]; then echo "ok    at most 25 lines"; else echo "FAIL  too long"; failed=1; fi
if [ "$(grep -c '^api ' "$work/calls")" -eq 4 ]; then echo "ok    four gh api calls"; else echo "FAIL  calls: $(cat "$work/calls")"; failed=1; fi
if grep -q graphql "$work/calls"; then echo "FAIL  used graphql"; failed=1; else echo "ok    no graphql"; fi
if [ "$(grep -c "^open " <<<"$out")" -eq 2 ]; then echo "ok    open lines"; else echo "FAIL  open lines"; failed=1; fi

# More than 10 open PRs: ten lines and a note.
jq -n '[range(1;12) | {number:., draft:false, head:{sha:"abcdef0123456789"}, labels:[], assignees:[]}]' >"$work/open.json"
run ok
exit0 "eleven open PRs"
if [ "$(grep -c "^open #" <<<"$out")" -eq 10 ]; then echo "ok    capped at 10 open lines"; else echo "FAIL  cap"; failed=1; fi
expect "more-than-10 note" "open PRs: more than 10"

# No PRs at all.
echo '[]' >"$work/open.json"; echo '[]' >"$work/closed.json"
run ok
exit0 "empty repo"
expect "no open PRs" "open PRs: none"
expect "no recent closes" "closed or merged in the last 24h: none"

run fail
exit0 "gh fails"
expect "unavailable line" "GitHub state unavailable: gh api for"
if [ "$(grep -c . <<<"$out")" -eq 1 ]; then echo "ok    gh failure: one line"; else echo "FAIL  gh failure: $out"; failed=1; fi

run badjson
exit0 "bad JSON"
expect "bad JSON line" "GitHub state unavailable: unexpected JSON from gh"

start=$SECONDS
run sleep
exit0 "gh hangs"
expect "timeout line" "GitHub state unavailable: gh api for"
if [ $((SECONDS - start)) -lt 15 ]; then echo "ok    timeout path took $((SECONDS - start))s"; else echo "FAIL  too slow"; failed=1; fi

# No gh at all: a PATH with only the tools the script needs besides gh.
mkdir "$work/nogh"
for t in bash git jq sed date mktemp rm timeout grep cat touch; do ln -s "$(command -v "$t")" "$work/nogh/$t"; done
out=$(CLAUDE_PROJECT_DIR=$work/repo PATH="$work/nogh" "$hook" 2>/dev/null </dev/null); code=$?
exit0 "gh not installed"
expect "no gh line" "GitHub state unavailable: gh is not installed"

# Not a git repo with an origin.
out=$(FAKE_MODE=ok FAKE_DIR=$work CLAUDE_PROJECT_DIR=$work PATH="$work/bin:$PATH" "$hook" 2>/dev/null </dev/null); code=$?
exit0 "no origin"
expect "no origin line" "GitHub state unavailable: no origin remote"

exit "$failed"
