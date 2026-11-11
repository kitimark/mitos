#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

script="$(cd "$(dirname "$0")" && pwd)/clear-needs-rebase.sh"
failed=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/f"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_DIR/calls"
cmd=$1
shift
case "$cmd" in
  api)
    method=GET route=
    while [ $# -gt 0 ]; do
      case $1 in
        -X) method=$2; shift 2 ;;
        -*) echo "unexpected flag $1" >&2; exit 1 ;;
        *) route=$1; shift ;;
      esac
    done
    printf '%s %s\n' "$method" "$route" >>"$FAKE_DIR/routes"
    case "$method $route" in
      "GET repos/acme/widgets/pulls/5") cat "$FAKE_DIR/f/pr.json" ;;
      "GET repos/acme/widgets/compare/"*) cat "$FAKE_DIR/f/compare.json" ;;
      *) echo "unexpected $method $route" >&2; exit 1 ;;
    esac
    ;;
  pr)
    [ "${1:-}" = edit ] || { echo "unexpected pr $*" >&2; exit 1; }
    shift
    n=$1
    [[ " $* " == *" --repo acme/widgets "* && " $* " == *" --remove-label needs-rebase "* ]] \
      || { echo "unexpected pr edit $*" >&2; exit 1; }
    printf 'remove %s\n' "$n" >>"$FAKE_DIR/routes"
    case "${FAKE_MODE:-}" in
      delete-absent) echo "gh: Label does not exist (HTTP 404)" >&2; exit 1 ;;
      delete-fail) echo "gh: HTTP 500" >&2; exit 1 ;;
    esac
    exit 0
    ;;
  *) echo "unexpected $cmd $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"
path="$work/bin:/usr/bin:/bin"

A=$(python3 -c 'print("a"*40)')
B=$(python3 -c 'print("b"*40)')
C=$(python3 -c 'print("c"*40)')

event() {
  jq -n --arg repo acme/widgets --argjson n 5 --arg sha "$1" \
    '{repository:{full_name:$repo},pull_request:{number:$n,head:{sha:$sha}}}' >"$work/event.json"
}
pr() {
  jq -n --arg base "$1" --arg bsha "$2" --arg hsha "$3" --arg repo "$4" --argjson labels "$5" \
    '{base:{ref:$base,sha:$bsha},head:{sha:$hsha,repo:{full_name:$repo}},labels:$labels}' >"$work/f/pr.json"
}
labels() {
  jq -n --args '[ $ARGS.positional[] | {name:.} ]' "$@"
}
compare() {
  jq -n --arg s "$1" --argjson behind "$2" '{status:$s,behind_by:$behind,ahead_by:1}' >"$work/f/compare.json"
}

run() {
  : >"$work/calls"
  : >"$work/routes"
  env -u GH_TOKEN -u GITHUB_TOKEN PATH="$path" FAKE_DIR="$work" FAKE_MODE="${1:-}" \
    GITHUB_EVENT_PATH="$work/event.json" HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
    bash "$script" >"$work/out" 2>"$work/err"
}

expect_rc() {
  local name=$1 mode=$2 want=$3 rc
  run "$mode"
  rc=$?
  if [ "$rc" = "$want" ]; then
    echo "ok  $name"
  else
    echo "FAIL  $name (exit $rc, want $want)"
    echo "  out: $(cat "$work/out")"
    echo "  err: $(cat "$work/err")"
    failed=1
  fi
}

deleted() { grep -qx 'remove 5' "$work/routes"; }
compared() { grep -q '^GET repos/acme/widgets/compare/' "$work/routes"; }

expect_deleted() {
  local name=$1
  if deleted; then echo "ok  $name"; else echo "FAIL  $name (label was not removed)"; cat "$work/routes"; failed=1; fi
}
expect_kept() {
  local name=$1
  if deleted; then echo "FAIL  $name (label was removed)"; cat "$work/routes"; failed=1; else echo "ok  $name"; fi
}
expect_no_compare() {
  local name=$1
  if compared; then echo "FAIL  $name (compare was called)"; cat "$work/routes"; failed=1; else echo "ok  $name"; fi
}

need=$(labels needs-rebase spec-approved)
event "$A"
pr main "$B" "$A" acme/widgets "$need"
compare ahead 0
expect_rc "ahead removes the label" "" 0
expect_deleted "ahead calls delete for needs-rebase only"
if grep -qx "GET repos/acme/widgets/compare/main...$A" "$work/routes"; then
  echo "ok  ahead compares the base branch, not a sha"
else
  echo "FAIL  ahead compares the base branch, not a sha"
  cat "$work/routes"
  failed=1
fi
if grep -q 'spec-approved' "$work/calls"; then
  echo "FAIL  other labels are not named in any call"
  failed=1
else
  echo "ok  other labels are left alone"
fi

compare identical 0
expect_rc "identical removes the label" "" 0
expect_deleted "identical calls delete"

compare behind 4
expect_rc "behind keeps the label" "" 0
expect_kept "behind does not delete"

compare diverged 2
expect_rc "diverged keeps the label" "" 0
expect_kept "diverged does not delete"

compare ahead 0
expect_rc "already absent is success" delete-absent 0
expect_deleted "already absent still attempts the one delete"

expect_rc "delete failure is reported" delete-fail 1
if grep -q 'could not remove needs-rebase' "$work/err"; then
  echo "ok  delete failure is on stderr"
else
  echo "FAIL  delete failure is on stderr"
  failed=1
fi

compare weird 0
expect_rc "unknown status fails closed" "" 1
expect_kept "unknown status does not delete"

event "$A"
pr main "$B" "$C" acme/widgets "$need"
expect_rc "a newer head is left alone" "" 0
expect_kept "a newer head is not edited"
expect_no_compare "a newer head is not compared"

event "$A"
pr feature "$B" "$A" acme/widgets "$need"
expect_rc "a PR that does not target the base is left alone" "" 0
expect_kept "other base is not edited"
expect_no_compare "other base is not compared"

event "$A"
pr main "$B" "$A" other/fork "$need"
expect_rc "a fork PR is left alone" "" 0
expect_kept "a fork is not edited"
expect_no_compare "a fork is not compared"

only=$(labels spec-approved)
event "$A"
pr main "$B" "$A" acme/widgets "$only"
expect_rc "no needs-rebase label does nothing" "" 0
expect_kept "absent label is not deleted"
expect_no_compare "absent label is not compared"

D=$(python3 -c 'print("d"*40)')
event "$A"
pr main "$D" "$A" acme/widgets "$need"
compare behind 3
expect_rc "a stale base sha keeps the label" "" 0
expect_kept "a stale base sha does not delete"
if grep -qx "GET repos/acme/widgets/compare/main...$A" "$work/routes" && ! grep -q "$D" "$work/routes"; then
  echo "ok  a stale base sha is not the compare base"
else
  echo "FAIL  a stale base sha is not the compare base"
  cat "$work/routes"
  failed=1
fi

jq -n --arg sha 'not-a-sha' --argjson n 5 \
  '{repository:{full_name:"acme/widgets"},pull_request:{number:$n,head:{sha:$sha}}}' >"$work/event.json"
expect_rc "a bad head sha is refused" "" 1
expect_kept "a bad head sha makes no API call"
if [ ! -s "$work/routes" ]; then
  echo "ok  a bad head sha makes no request"
else
  echo "FAIL  a bad head sha makes no request"
  cat "$work/routes"
  failed=1
fi

# The workflow must stay on the trusted file. A pull_request trigger, or a
# checkout of the pull request head, would run untrusted code with a write token.
checkout_refs_ok() {
  python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()

def is_trusted(ref):
    s = ref.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "'\"":
        s = s[1:-1].strip()
    return re.sub(r"\s+", "", s) == "${{github.sha}}"

def folded(block, k, indent, rest):
    if rest not in {">", ">-", "|", "|-", ""}:
        return rest
    parts = []
    for nxt in block[k + 1 :]:
        if nxt.strip() == "":
            continue
        if len(nxt) - len(nxt.lstrip(" ")) <= indent:
            break
        parts.append(nxt.strip())
    return " ".join(parts)

def with_refs(block):
    head = re.match(r"^(\s*)-\s", block[0])
    if not head:
        return None
    key_indent = len(head.group(1)) + 2
    refs = []
    saw_with = False
    i = 0
    while i < len(block):
        line = block[i]
        dash = re.match(r"^(\s*)-\s+([A-Za-z0-9_-]+):\s*(.*)$", line)
        keym = re.match(r"^(\s*)([A-Za-z0-9_-]+):\s*(.*)$", line)
        key = rest = None
        if dash and len(dash.group(1)) + 2 == key_indent:
            key, rest = dash.group(2), dash.group(3).strip()
        elif keym and len(keym.group(1)) == key_indent:
            key, rest = keym.group(2), keym.group(3).strip()
        if key != "with":
            i += 1
            continue
        saw_with = True
        if rest != "":
            return None
        child_indent = None
        found = False
        j = i + 1
        while j < len(block):
            nxt = block[j]
            if nxt.strip() == "" or nxt.lstrip().startswith("#"):
                j += 1
                continue
            ind = len(nxt) - len(nxt.lstrip(" "))
            if ind <= key_indent:
                break
            child = re.match(r"^(\s*)([A-Za-z0-9_-]+):\s*(.*)$", nxt)
            if child:
                if child_indent is None:
                    child_indent = ind
                if ind == child_indent and child.group(2) == "ref":
                    refs.append(folded(block, j, ind, child.group(3).strip()))
                    found = True
            j += 1
        if not found:
            return None
        i = j
    return refs if saw_with else None

def step_end(start):
    base = len(re.match(r"^(\s*)-\s", lines[start]).group(1))
    j = start + 1
    while j < len(lines):
        line = lines[j]
        if line.strip() == "" or line.lstrip().startswith("#"):
            j += 1
            continue
        if len(line) - len(line.lstrip(" ")) <= base:
            break
        j += 1
    return j

saw = False
i = 0
while i < len(lines):
    if re.match(r"^\s*-\s", lines[i]):
        end = step_end(i)
        block = lines[i:end]
        if any(re.search(r"""uses:\s*['"]?actions/checkout@""", line) for line in block):
            saw = True
            refs = with_refs(block)
            if not refs or any(not is_trusted(ref) for ref in refs):
                sys.exit(1)
        i = end
    else:
        i += 1
sys.exit(0 if saw else 1)
PY
}
wf="$(cd "$(dirname "$0")/../workflows" && pwd)/clear-needs-rebase.yml"
if grep -q 'pull_request_target:' "$wf" && ! grep -Eq '^[[:space:]]*pull_request:' "$wf" \
  && checkout_refs_ok "$wf" \
  && grep -q 'ref: ${{ github.sha }}' "$wf" \
  && grep -q 'persist-credentials: false' "$wf"; then
  echo "ok  workflow checks out the default-branch commit, not the head"
else
  echo "FAIL  workflow checks out the default-branch commit, not the head"
  failed=1
fi
reject_second_checkout() {
  local ref=$1 label=$2
  if ! python3 - "$wf" "$work/head-checkout.yml" "$ref" <<'PY'
import sys
src, dst, ref = sys.argv[1:]
text = open(src).read()
needle = "          persist-credentials: false\n"
extra = (
    "      - uses: actions/checkout@v4\n"
    "        with:\n"
    f"          ref: {ref}\n"
)
if text.count(needle) != 1:
    raise SystemExit("expected one trusted checkout")
open(dst, "w").write(text.replace(needle, needle + "\n" + extra, 1))
PY
  then
    echo "FAIL  $label (could not build the workflow)"
    failed=1
  elif checkout_refs_ok "$work/head-checkout.yml"; then
    echo "FAIL  $label"
    failed=1
  else
    echo "ok  $label"
  fi
}
reject_second_checkout '${{ github.event.pull_request.head['"'"'sha'"'"'] }}' \
  "a second checkout of head['sha'] is rejected"
reject_second_checkout '${{ github.head_ref }}' \
  "a second checkout of github.head_ref is rejected"
reject_second_checkout 'refs/pull/${{ github.event.pull_request.number }}/head' \
  "a second checkout of refs/pull/N/head is rejected"
reject_second_checkout 'refs/pull/${{ github.event.pull_request.number }}/merge' \
  "a second checkout of refs/pull/N/merge is rejected"
reject_env_ref_before_with() {
  local ref=$1 label=$2
  if ! python3 - "$wf" "$work/head-checkout.yml" "$ref" <<'PY'
import sys
src, dst, ref = sys.argv[1:]
text = open(src).read()
needle = "          persist-credentials: false\n"
extra = (
    "      - uses: actions/checkout@v4\n"
    "        env:\n"
    "          ref: ${{ github.sha }}\n"
    "        with:\n"
    f"          ref: {ref}\n"
)
if text.count(needle) != 1:
    raise SystemExit("expected one trusted checkout")
open(dst, "w").write(text.replace(needle, needle + "\n" + extra, 1))
PY
  then
    echo "FAIL  $label (could not build the workflow)"
    failed=1
  elif checkout_refs_ok "$work/head-checkout.yml"; then
    echo "FAIL  $label"
    failed=1
  else
    echo "ok  $label"
  fi
}
reject_env_ref_before_with '${{ github.event.pull_request.head.sha }}' \
  "env.ref github.sha before an untrusted with.ref is rejected"

exit "$failed"
