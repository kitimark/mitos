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

behind_branch() {
  git -C "$work" checkout -q -b "$1" "${2:-$c0}"
  echo pr >"$work/$1.txt"
  git -C "$work" add "$1.txt"
  git -C "$work" commit -q -m "$1"
  git -C "$work" rev-parse HEAD
}
behind=$(behind_branch pr-behind)
other=$(behind_branch pr-other)
locked=$(behind_branch pr-locked)
raced=$(behind_branch pr-raced-listed)
raced_moved=$(behind_branch pr-raced "$raced")

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
branches=(main pr-conflict pr-behind pr-other pr-locked pr-raced pr-ahead pr-same)
git -C "$work" push -q origin "${branches[@]}"

cat >"$bare/hooks/update" <<'EOF'
#!/bin/sh
if [ "$1" = refs/heads/pr-locked ]; then
  echo "pr-locked takes no push" >&2
  exit 1
fi
EOF
chmod +x "$bare/hooks/update"

mkdir -p "$root/bin"
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_DIR/calls"
cmd=$1
shift
case "$cmd" in
  label) exit 0 ;;
  api)
    method=GET route= filter=.
    while [ $# -gt 0 ]; do
      case $1 in
        --silent | --paginate | --slurp) shift ;;
        -H) shift 2 ;;
        -X) method=$2; shift 2 ;;
        --jq) filter=$2; shift 2 ;;
        -*) echo "unexpected flag $1" >&2; exit 1 ;;
        *) route=$1; shift ;;
      esac
    done
    printf '%s %s\n' "$method" "$route" >>"$FAKE_DIR/routes"
    case "$route" in
      *"/stacks"*)
        case "${FAKE_MODE:-}" in
          stacks-down) echo "gh: HTTP 500" >&2; exit 1 ;;
          stacks-odd) printf '%s\n' '{"message":"moved"}' ;;
          *)
            printf '%s\n' '[[{"pull_requests":[{"number":90}]},
              {"open":false,"pull_requests":[{"number":91,"state":"closed"}]}]]'
            ;;
        esac
        ;;
      'repos/{owner}/{repo}/pulls/'*)
        n=${route##*/}
        [[ $n =~ ^[0-9]+$ ]] || { echo "unexpected api $route" >&2; exit 1; }
        later=.
        reads=$(grep -c -F -x "GET $route" "$FAKE_DIR/routes")
        if [ "${FAKE_MODE:-}" = head-moves ] && [ "$reads" -gt 1 ]; then
          later='.head.sha = "ffffffffffffffffffffffffffffffffffffffff"'
        fi
        if ! jq -e --argjson n "$n" "first(.[] | select(.number == \$n)) | $later" \
            "$FAKE_DIR/prs.json" >"$FAKE_DIR/answer.json" 2>/dev/null; then
          printf '%s\n' '{"message":"Not Found","status":"404"}'
          echo "gh: Not Found (HTTP 404)" >&2
          exit 1
        fi
        jq -r "$filter" "$FAKE_DIR/answer.json"
        ;;
      *) echo "unexpected api $route" >&2; exit 1 ;;
    esac
    ;;
  pr)
    sub=$1
    shift
    case "$sub" in
      comment) exit 0 ;;
      edit)
        n=$1
        if [[ " $* " == *" --remove-label needs-rebase "* ]]; then
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
  local n=$1 ref=$2 oid=$3 labels=$4 change=${5:-.}
  jq -n --argjson n "$n" --arg ref "$ref" --arg oid "$oid" --argjson labels "$labels" \
    '{number: $n, state: "open", draft: false, labels: $labels,
      base: {ref: "main", repo: {full_name: "owner/mitos"}},
      head: {ref: $ref, sha: $oid, repo: {full_name: "owner/mitos"}}} | '"$change"
}

{
  one 1 pr-ahead "$ahead" "$(lab needs-rebase spec-approved)"
  one 2 pr-same "$main" "$(lab needs-rebase)"
  one 3 pr-same "$main" "$(lab follow-up)"
  one 4 pr-conflict "$conflict" "$(lab needs-rebase bug)"
  one 5 pr-conflict "$conflict" "$(lab bug)"
  one 6 pr-behind "$behind" "$(lab needs-rebase)"
  one 7 pr-other "$other" "$(lab needs-rebase)" '.draft = true'
  one 8 pr-other "$other" "$(lab needs-rebase)" '.head.repo.full_name = "someone/mitos"'
  one 9 pr-other "$other" "$(lab no-auto-rebase needs-rebase)"
  one 90 pr-other "$other" "$(lab needs-rebase)"
  one 91 pr-other "$other" "$(lab needs-rebase)"
  one 11 pr-other "$other" "$(lab needs-rebase)" '.base.ref = "feature"'
  one 13 pr-other "$other" "$(lab needs-rebase)" '.state = "closed"'
  one 14 pr-other "$other" "$(lab)"
  one 15 pr-raced "$raced" "$(lab)"
  one 16 pr-other "$other" "$(lab needs-rebase)" '.head.repo = null'
  one 17 pr-locked "$locked" "$(lab)"
  one 18 pr-other "$other" "$(lab)" '.head.sha = "pr-other"'
} | jq -s '.' >"$root/prs.json"

tip() { git -C "$bare" rev-parse "refs/heads/$1"; }
declare -A start
for b in "${branches[@]}"; do start[$b]=$(tip "$b"); done

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

run() {
  local mode=$1 b
  shift
  for b in "${branches[@]}"; do git -C "$bare" update-ref "refs/heads/$b" "${start[$b]}"; done
  : >"$root/calls"
  : >"$root/routes"
  env -u GH_TOKEN -u GITHUB_TOKEN -u PR_NUMBER PATH="$root/bin:/usr/bin:/bin" FAKE_DIR="$root" \
    FAKE_MODE="$mode" HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 "$@" \
    bash -c 'cd "$1" && exec bash "$2"' bash "$work" "$script" >"$root/out" 2>"$root/err"
  rc=$?
}

called() { grep -c -E -- "$1" "$root/calls"; }
moved() {
  local b list=
  for b in "${branches[@]}"; do
    [ "$(tip "$b")" = "${start[$b]}" ] || list="$list $b"
  done
  printf '%s' "${list# }"
}
errors() { grep '^::' "$root/out"; }

refused() {
  local name=$1 error=$2 calls=$3
  check "$name: the run fails" 1 "$rc"
  check "$name: it says why" "$error" "$(errors)"
  check "$name: no branch moved" "" "$(moved)"
  check "$name: label and comment calls" "$calls" \
    "$(grep -E '^pr (edit|comment) ' "$root/calls" | cut -d' ' -f1-4)"
}

bad_input() {
  local name=$1
  shift
  run "" "$@"
  refused "$name" "::error::PR_NUMBER is not a pull request number; nothing was rebased" ""
  check "$name: no call to GitHub" "" "$(cat "$root/calls")"
}
bad_input "no input"
bad_input "an empty input" PR_NUMBER=
for bad in abc 6abc 0 06 -6 "6 14" "6;14" '$(id)' 12345678 " 6"; do
  bad_input "input '$bad'" PR_NUMBER="$bad"
done
bad_input "a second line that is a workflow command" PR_NUMBER="$(printf '6\n::warning::injected')"
check "a bad input stops the script before its first git command" test "$(git -C "$work" config user.name)"

run "" PR_NUMBER=6
check "the named behind PR: the run passes" 0 "$rc"
check "the named behind PR: only its branch moved, so another behind PR is left alone" pr-behind "$(moved)"
if git -C "$bare" merge-base --is-ancestor "$main" "$(tip pr-behind)" \
  && [ "$(git -C "$bare" rev-parse "$(tip pr-behind)^")" = "$main" ] \
  && [ -z "$(git -C "$bare" diff "$behind" "$(tip pr-behind)" -- pr-behind.txt)" ]; then
  echo "ok  the named behind PR: its one commit now sits on main"
else
  echo "FAIL  the named behind PR: its one commit now sits on main"
  failed=1
fi
check "the named behind PR: it loses needs-rebase, with the full arguments" \
  "pr edit 6 --remove-label needs-rebase" "$(grep -E '^pr (edit|comment) ' "$root/calls")"
check "the named behind PR: no pull request is listed" 0 "$(called '^pr list')"
check "the named behind PR: only it is read" 'GET repos/{owner}/{repo}/pulls/6' \
  "$(grep /pulls/ "$root/routes" | sort -u)"
check "the named behind PR: no error line" "" "$(errors)"

run "" PR_NUMBER=3
check "an up-to-date PR: the run passes" 0 "$rc"
check "an up-to-date PR: no branch moved" "" "$(moved)"
check "an up-to-date PR: it is not edited" 0 "$(called '^pr (edit|comment) ')"
check "an up-to-date PR: no error line" "" "$(errors)"

run "" PR_NUMBER=1
check "an ahead PR with a stale label: the run passes" 0 "$rc"
check "an ahead PR with a stale label: no branch moved" "" "$(moved)"
check "an ahead PR with a stale label: it loses needs-rebase, with the full arguments" \
  "pr edit 1 --remove-label needs-rebase" "$(grep -E '^pr (edit|comment) ' "$root/calls")"

run "" PR_NUMBER=2
check "an identical PR: an absent label is tolerated" 0 "$rc"
check "an identical PR: the removal was tried" 1 "$(called '^pr edit 2 --remove-label needs-rebase$')"

run head-moves PR_NUMBER=1
check "a head moved during the run: the run passes" 0 "$rc"
check "a head moved during the run: needs-rebase is kept" 0 "$(called '^pr (edit|comment) ')"
check "a head moved during the run: it was read twice" 2 "$(grep -c '/pulls/1$' "$root/routes")"

run fail PR_NUMBER=1
check "a failed label delete fails the run" 1 "$rc"
if grep -q 'could not remove needs-rebase from #1' "$root/out"; then
  echo "ok  the failed delete is reported"
else
  echo "FAIL  the failed delete is reported"
  failed=1
fi

run "" PR_NUMBER=5
refused "a new conflict" "::error::#5 (pr-conflict): conflicts with main; labelled needs-rebase" \
  "$(printf '%s\n' 'pr edit 5 --add-label' 'pr comment 5 --body')"
check "a new conflict: the label is needs-rebase" 1 "$(called '^pr edit 5 --add-label needs-rebase$')"

run "" PR_NUMBER=4
refused "a known conflict" "::error::#4 (pr-conflict): conflicts with main; labelled needs-rebase" ""

run "" PR_NUMBER=7
refused "a draft" "::error::#7 is a draft; it was not rebased" ""
run "" PR_NUMBER=8
refused "a fork" "::error::#8 comes from a fork; it was not rebased" ""
run "" PR_NUMBER=16
refused "a fork whose repository is gone" "::error::#16 comes from a fork; it was not rebased" ""
run "" PR_NUMBER=9
refused "no-auto-rebase" "::error::#9 has the no-auto-rebase label; it was not rebased" ""
run "" PR_NUMBER=90
refused "a stacked PR" "::error::#90 is in a stack; it was not rebased" ""
run "" PR_NUMBER=91
refused "a PR in a stack that the list calls closed" "::error::#91 is in a stack; it was not rebased" ""
run "" PR_NUMBER=11
refused "a PR on another base" "::error::#11 is not based on main; it was not rebased" ""
run "" PR_NUMBER=13
refused "a closed PR" "::error::#13 is not open; it was not rebased" ""

run "" PR_NUMBER=15
check "a branch pushed during the run: it starts ahead of the head the script read" \
  "$raced_moved" "${start[pr-raced]}"
refused "a branch pushed during the run" \
  "::error::#15 (pr-raced): branch moved during this run; it was not rebased" ""

run "" PR_NUMBER=17
refused "a refused push" "::error::#17 (pr-locked): push refused; labelled needs-rebase" \
  "$(printf '%s\n' 'pr edit 17 --add-label' 'pr comment 17 --body')"

run "" PR_NUMBER=999
refused "an unknown PR" "::error::could not read #999; it was not rebased" ""
run "" PR_NUMBER=18
refused "a head that is not a commit" "::error::could not read #18; it was not rebased" ""
run stacks-down PR_NUMBER=6
refused "a stack list that cannot be read" "::error::could not read the stack list; #6 was not rebased" ""
run stacks-odd PR_NUMBER=6
refused "a stack list of another shape" "::error::could not read the stack list; #6 was not rebased" ""

exit "$failed"
