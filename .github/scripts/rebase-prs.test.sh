#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

script="$(cd "$(dirname "$0")" && pwd)/rebase-prs.sh"
failed=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

bare=$root/origin.git
work=$root/work
git init -q --bare "$bare"
git -C "$bare" config uploadpack.allowReachableSHA1InWant true
git -C "$bare" symbolic-ref HEAD refs/heads/main
git init -q -b main "$work"
git -C "$work" config user.email test@example.com
git -C "$work" config user.name test

echo base >"$work/shared.txt"
echo base >"$work/other.txt"
git -C "$work" add shared.txt other.txt
git -C "$work" commit -q -m c0
c0=$(git -C "$work" rev-parse HEAD)

git -C "$work" checkout -q -b pr-conflict
echo pr >"$work/shared.txt"
git -C "$work" commit -q -am conflict
conflict=$(git -C "$work" rev-parse HEAD)

git -C "$work" checkout -q -b pr-behind "$c0"
echo pr >"$work/pr-only.txt"
git -C "$work" add pr-only.txt
git -C "$work" commit -q -m behind
behind=$(git -C "$work" rev-parse HEAD)

git -C "$work" checkout -q main
echo main >"$work/shared.txt"
echo main >"$work/main-only.txt"
git -C "$work" add main-only.txt
git -C "$work" commit -q -am 'main moves'
main=$(git -C "$work" rev-parse HEAD)

git -C "$work" checkout -q -b pr-ahead
echo ahead >"$work/ahead.txt"
git -C "$work" add ahead.txt
git -C "$work" commit -q -m ahead
ahead=$(git -C "$work" rev-parse HEAD)

git -C "$work" checkout -q -b pr-same "$main"
git -C "$work" remote add origin "$bare"
git -C "$work" push -q origin main pr-conflict pr-behind pr-ahead pr-same

mkdir -p "$root/bin"
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_DIR/calls"
cmd=$1
shift
case "$cmd" in
  label) exit 0 ;;
  api)
    method=GET route=
    while [ $# -gt 0 ]; do
      case $1 in
        --silent | --paginate | --slurp) shift ;;
        -H) shift 2 ;;
        -X) method=$2; shift 2 ;;
        -*) echo "unexpected flag $1" >&2; exit 1 ;;
        *) route=$1; shift ;;
      esac
    done
    printf '%s %s\n' "$method" "$route" >>"$FAKE_DIR/routes"
    case "$route" in
      *"/stacks"*) printf '%s\n' '[[{"pull_requests":[{"number":90}]}]]' ;;
      *) echo "unexpected api $route" >&2; exit 1 ;;
    esac
    ;;
  pr)
    sub=$1
    shift
    case "$sub" in
      list) cat "$FAKE_DIR/prs.json" ;;
      comment) exit 0 ;;
      edit)
        n=$1
        if [[ " $* " == *" --remove-label needs-rebase "* ]]; then
          printf 'remove %s\n' "$n" >>"$FAKE_DIR/routes"
          if [ "${FAKE_MODE:-}" = fail ] && [ "$n" = 1 ]; then
            echo "gh: HTTP 500" >&2
            exit 1
          fi
          if [ "$n" = 2 ]; then
            echo "gh: Label does not exist (HTTP 404)" >&2
            exit 1
          fi
        fi
        exit 0
        ;;
      *) echo "unexpected pr $sub" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unexpected $cmd" >&2; exit 1 ;;
esac
EOF
chmod +x "$root/bin/gh"

lab() {
  jq -n --args '[ $ARGS.positional[] | {name:.} ]' "$@"
}
one() {
  local n=$1 ref=$2 oid=$3 draft=$4 cross=$5 base=$6 labels=$7
  jq -n --argjson n "$n" --arg ref "$ref" --arg oid "$oid" --argjson draft "$draft" \
    --argjson cross "$cross" --arg base "$base" --argjson labels "$labels" \
    '{number:$n,headRefName:$ref,headRefOid:$oid,baseRefName:$base,isDraft:$draft,isCrossRepository:$cross,labels:$labels}'
}

{
  one 1 pr-ahead "$ahead" false false main "$(lab needs-rebase spec-approved)"
  one 2 pr-same "$main" false false main "$(lab needs-rebase)"
  one 3 pr-same "$main" false false main "$(lab follow-up)"
  one 4 pr-conflict "$conflict" false false main "$(lab needs-rebase bug)"
  one 5 pr-conflict "$conflict" false false main "$(lab bug)"
  one 6 pr-behind "$behind" false false main "$(lab needs-rebase)"
  one 7 pr-same "$main" true false main "$(lab needs-rebase)"
  one 8 pr-same "$main" false true main "$(lab needs-rebase)"
  one 9 pr-same "$main" false false main "$(lab no-auto-rebase needs-rebase)"
  one 90 pr-same "$main" false false main "$(lab needs-rebase)"
  one 11 pr-same "$main" false false feature "$(lab needs-rebase)"
} | jq -s '.' >"$root/prs.json"

tip() { git -C "$bare" rev-parse "refs/heads/$1"; }
before_main=$(tip main)
before_ahead=$(tip pr-ahead)
before_same=$(tip pr-same)
before_conflict=$(tip pr-conflict)
before_behind=$(tip pr-behind)

run_offline() {
  : >"$root/calls"
  : >"$root/routes"
  env -u GH_TOKEN -u GITHUB_TOKEN PATH="$root/bin:/usr/bin:/bin" FAKE_DIR="$root" FAKE_MODE="${1:-}" \
    HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
    bash -c 'cd "$1" && exec bash "$2"' bash "$work" "$script"
}

check() {
  local name=$1 want=$2 got=$3
  if [ "$got" = "$want" ]; then
    echo "ok  $name"
  else
    echo "FAIL  $name"
    echo "  want: $want"
    echo "  got:  $got"
    failed=1
  fi
}

deleted() { grep -c "^remove $1$" "$root/routes" || true; }
added() { grep -c "pr edit $1 --add-label needs-rebase" "$root/calls" || true; }

set +e
run_offline >"$root/out" 2>"$root/err"
rc=$?
set -e
check "up to date run exits 0" 0 "$rc"
if [ "$rc" != 0 ]; then echo "--- out ---"; cat "$root/out"; echo "--- err ---"; cat "$root/err"; fi

check "ahead PR loses needs-rebase" 1 "$(deleted 1)"
check "identical PR tolerates an absent label" 1 "$(deleted 2)"
check "unlabelled up-to-date PR is not edited" 0 "$(deleted 3)"
check "conflicting labelled PR keeps needs-rebase" 0 "$(deleted 4)"
check "conflicting labelled PR is not labelled again" 0 "$(added 4)"
check "conflicting unlabelled PR gains needs-rebase" 1 "$(added 5)"
check "conflicting unlabelled PR is not unlabelled" 0 "$(deleted 5)"
check "rebased PR loses needs-rebase" 1 "$(deleted 6)"
check "draft is skipped" 0 "$(deleted 7)"
check "fork is skipped" 0 "$(deleted 8)"
check "no-auto-rebase is skipped" 0 "$(deleted 9)"
check "stacked PR is skipped" 0 "$(deleted 90)"
check "PR on another base is skipped" 0 "$(deleted 11)"

if grep -q 'spec-approved\|follow-up\|bug' "$root/routes"; then
  echo "FAIL  a delete names another label"
  cat "$root/routes"
  failed=1
else
  echo "ok  deletes name only needs-rebase"
fi
if grep -q 'pr comment 5 ' "$root/calls"; then
  echo "ok  a new conflict is commented"
else
  echo "FAIL  a new conflict is commented"
  failed=1
fi
if grep -Eq 'pr comment (1|2|3|4|6|7|8|9|90|11) ' "$root/calls"; then
  echo "FAIL  a comment was posted on a PR that was not newly flagged"
  grep 'pr comment' "$root/calls"
  failed=1
else
  echo "ok  no extra comments"
fi

check "main did not move" "$before_main" "$(tip main)"
check "ahead branch did not move" "$before_ahead" "$(tip pr-ahead)"
check "identical branch did not move" "$before_same" "$(tip pr-same)"
check "conflicting branch did not move" "$before_conflict" "$(tip pr-conflict)"
if git -C "$bare" merge-base --is-ancestor "$main" "$(tip pr-behind)" \
  && [ "$(tip pr-behind)" != "$before_behind" ]; then
  echo "ok  clean-behind PR was rebased onto main"
else
  echo "FAIL  clean-behind PR was rebased onto main"
  failed=1
fi

set +e
run_offline fail >"$root/out" 2>"$root/err"
rc=$?
set -e
check "a failed label delete fails the run" 1 "$rc"
if grep -q 'could not remove needs-rebase from #1' "$root/out"; then
  echo "ok  the failed delete is reported"
else
  echo "FAIL  the failed delete is reported"
  failed=1
fi
check "the other up-to-date PR is still cleared" 1 "$(deleted 2)"

exit "$failed"
