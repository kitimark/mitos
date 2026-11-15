#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u
lib="$(cd "$(dirname "$0")" && pwd)/lib/main-tool.sh"
failed=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

g() { git -C "$1" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "${@:2}"; }

git init -q --bare -b main "$work/origin.git"
git init -q -b main "$work/seed"
mkdir -p "$work/seed/gate" "$work/seed/core" "$work/seed/docs"
for f in gate/a.txt core/b.txt docs/x.txt lakefile.toml lake-manifest.json lean-toolchain; do echo one >"$work/seed/$f"; done
g "$work/seed" add -A
g "$work/seed" commit -qm base
g "$work/seed" remote add origin "$work/origin.git"
g "$work/seed" push -q origin main 2>/dev/null
git clone -q "$work/origin.git" "$work/clone"
proj=$work/clone

mkdir "$work/bin"
cat >"$work/bin/lake" <<'EOF'
#!/usr/bin/env bash
echo "build $(date +%s.%N)" >>"$LAKE_LOG"
[ -e "${HOLDER_ALIVE:-/nonexistent}" ] && echo overlap >>"$LAKE_LOG"
sleep "${LAKE_SLEEP:-0}"
[ -n "${LAKE_FAIL:-}" ] && exit 1
mkdir -p .lake/build/bin
printf '#!/bin/sh\n' >.lake/build/bin/mitos-gate
chmod +x .lake/build/bin/mitos-gate
EOF
chmod +x "$work/bin/lake"
export LAKE_LOG=$work/lake.log
: >"$LAKE_LOG"
builds() { grep -c '^build' "$LAKE_LOG"; }

path_with="$work/bin:/usr/bin:/bin"
path_without="/usr/bin:/bin"

mt() {
  local p=$1 mode=$2 at=${3:-}
  (cd "$proj" && env PATH="$p" CLAUDE_PROJECT_DIR="$proj" bash -c '
    source "$1"
    dir=$(main_tool_dir) || exit 9
    main_tool "$2" "$dir" "$3" 2>"$4"
  ' _ "$lib" "$mode" "$at" "$work/err") >"$work/stdout" 2>/dev/null
  code=$?
}
last_err() { tail -n 1 "$work/err" 2>/dev/null; }
check() {
  local what=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then echo "ok   $what"; else
    echo "FAIL $what"; printf '     got:  %q\n     want: %q\n' "$got" "$want"; failed=1
  fi
}
silent() { check "$1: nothing on standard output" "$(cat "$work/stdout")" ""; }
move_main() {
  echo "$RANDOM" >>"$work/seed/$1"
  g "$work/seed" add -A
  g "$work/seed" commit -qm "move $1"
  g "$work/seed" push -q origin main 2>/dev/null
}

common=$(git -C "$proj" rev-parse --path-format=absolute --git-common-dir)
dir="$common/mitos-main-tool"
tool_dir() { (cd "$proj" && env CLAUDE_PROJECT_DIR="$proj" bash -c 'source "$1"; main_tool_dir' _ "$lib"); }
check "main_tool_dir is a folder in the git directory" "$(tool_dir)" "$dir"
check "MITOS_MAIN_TOOL replaces it" \
  "$(cd "$proj" && env MITOS_MAIN_TOOL=/x/y CLAUDE_PROJECT_DIR="$proj" bash -c 'source "$1"; main_tool_dir' _ "$lib")" "/x/y"
check "main_tool_bin is the binary in the folder" \
  "$(bash -c 'source "$1"; main_tool_bin /p' _ "$lib")" "/p/.lake/build/bin/mitos-gate"
check "main_tool_dir outside a clone fails" \
  "$(cd "$work" && env CLAUDE_PROJECT_DIR="$work" bash -c 'source "$1"; main_tool_dir || echo failed' _ "$lib" 2>/dev/null)" "failed"

git -C "$proj" fetch -q origin
main1=$(git -C "$proj" rev-parse origin/main)

mt "$path_with" ready
check "ready with nothing built: exit 1" "$code" 1
check "ready with nothing built names main" "$(last_err)" "main's tool is not built at ${main1:0:7}"
silent "ready with nothing built"
check "ready never builds" "$(builds)" 0

mt "$path_without" ensure
check "ensure without lake: exit 1" "$code" 1
check "ensure without lake says so" "$(last_err)" "lake is not installed"
silent "ensure without lake"

mt "$path_with" ensure
check "ensure builds: exit 0" "$code" 0
silent "ensure that builds"
check "ensure builds once" "$(builds)" 1
check "ensure stamps the commit it built" "$(cat "$dir/.lake/main-tool.built")" "$main1"
check "the checkout is at main" "$(git -C "$dir" rev-parse HEAD)" "$main1"
check "git status of the clone does not show the checkout" "$(git -C "$proj" status --porcelain)" ""
mt "$path_with" ready "$main1"
check "ready after the build: exit 0" "$code" 0

mt "$path_with" ensure
check "ensure at the same commit builds nothing" "$(builds)" 1

move_main docs/x.txt
main2=$(git -C "$proj" ls-remote origin refs/heads/main | cut -f1)
mt "$path_with" ensure
check "ensure after a move of main off the tool inputs: exit 0" "$code" 0
check "that move needs no build" "$(builds)" 1
check "that move leaves the checkout where it was" "$(git -C "$dir" rev-parse HEAD)" "$main1"
check "that move leaves the stamp where it was" "$(cat "$dir/.lake/main-tool.built")" "$main1"
mt "$path_with" ready "$main2"
check "ready at the moved main: exit 0" "$code" 0

move_main gate/a.txt
main3=$(git -C "$proj" ls-remote origin refs/heads/main | cut -f1)
git -C "$proj" fetch -q origin
mt "$path_with" ready "$main3"
check "ready after a move of main that touches gate/: exit 1" "$code" 1
check "ready names the new main" "$(last_err)" "main's tool is not built at ${main3:0:7}"
check "ready builds nothing" "$(builds)" 1

LAKE_FAIL=1 mt "$path_with" ensure
check "a failed build: exit 1" "$code" 1
case $(last_err) in
  "the build at ${main3:0:7} failed, see "*) echo "ok   a failed build names the commit and its log" ;;
  *) echo "FAIL a failed build names the commit and its log: $(last_err)"; failed=1 ;;
esac
silent "a failed build"
check "a failed build leaves no stamp" "$([ -e "$dir/.lake/main-tool.built" ] && echo stamp || echo none)" none
mt "$path_with" ready "$main3"
check "ready fails after the failed build, though an old binary is there" "$code" 1
check "an old binary is there" "$([ -x "$dir/.lake/build/bin/mitos-gate" ] && echo yes || echo no)" yes

mt "$path_with" ensure
check "ensure after the failure builds again: exit 0" "$code" 0
check "the second try is the third build" "$(builds)" 3
check "the checkout moved to main" "$(git -C "$dir" rev-parse HEAD)" "$main3"
check "the stamp names main" "$(cat "$dir/.lake/main-tool.built")" "$main3"

git -C "$proj" remote set-url origin "$work/nowhere.git"
mt "$path_with" ready "$main3"
check "ready with a commit does not fetch" "$code" 0
mt "$path_with" ready
check "ready with no commit fetches, and fails when it cannot: exit 1" "$code" 1
check "that failure says why" "$(last_err)" "cannot fetch origin main"
silent "a failed fetch"
mt "$path_with" ensure
check "ensure that cannot fetch: exit 1" "$code" 1
check "ensure that cannot fetch says why" "$(last_err)" "cannot fetch origin main"
git -C "$proj" remote set-url origin "$work/origin.git"

mt "$path_with" bogus
check "an unknown mode: exit 1" "$code" 1
check "an unknown mode says so" "$(last_err)" "main_tool takes ensure or ready"
silent "an unknown mode"
mt "$path_with" ready not-a-commit
check "a commit that is not a SHA: exit 1" "$code" 1
check "a commit that is not a SHA says so" "$(last_err)" "main is not a commit"
silent "a bad commit"
nodir=$(cd "$proj" && env PATH="$path_with" CLAUDE_PROJECT_DIR="$proj" bash -c 'source "$1"; main_tool ensure "" 2>&1 >/dev/null; echo "exit $?"' _ "$lib")
check "no folder: one reason, exit 1" "$nodir" "main_tool takes the folder main_tool_dir prints
exit 1"

git -C "$proj" worktree add -q --detach "$work/other" "$main3"
check "another worktree of the clone shares the checkout" \
  "$(cd "$work/other" && env CLAUDE_PROJECT_DIR="$work/other" bash -c 'source "$1"; main_tool_dir' _ "$lib")" "$dir"

twice=$(cd "$proj" && env PATH="$path_with" CLAUDE_PROJECT_DIR="$proj" bash -c '
  source "$1"
  dir=$(main_tool_dir)
  main_tool ensure "$dir" 2>/dev/null || exit 1
  first=$MAIN_TOOL_FD
  main_tool ensure "$dir" 2>/dev/null || exit 1
  [ "$first" = "$MAIN_TOOL_FD" ] && echo same
' _ "$lib")
check "a second call in one process reuses the lock" "$twice" same
inside=$(cd "$proj" && env PATH="$path_with" CLAUDE_PROJECT_DIR="$proj" bash -c '
  source "$1"
  dir=$(main_tool_dir)
  x=$(main_tool ensure "$dir" 2>/dev/null; echo "${MAIN_TOOL_FD:-unset}")
  echo "${MAIN_TOOL_FD:-unset}"
' _ "$lib")
check "the same call inside \$(...) leaves no lock in the caller" "$inside" unset

move_main gate/a.txt
main4=$(git -C "$proj" ls-remote origin refs/heads/main | cut -f1)
: >"$LAKE_LOG"
touch "$work/holder.alive"
(cd "$proj" && env PATH="$path_with" CLAUDE_PROJECT_DIR="$proj" bash -c '
  source "$1"
  dir=$(main_tool_dir)
  main_tool ready "$dir" "$2" 2>/dev/null || exit 1
  sleep 3
  rm -f "$3"
' _ "$lib" "$main3" "$work/holder.alive") &
holder=$!
sleep 1
HOLDER_ALIVE=$work/holder.alive mt "$path_with" ensure
wait "$holder"
check "a build waits for a caller that still runs the binary: exit 0" "$code" 0
check "the build ran once" "$(builds)" 1
check "the build began after the caller was done" "$(grep -c overlap "$LAKE_LOG")" 0
check "the stamp names the new main" "$(cat "$dir/.lake/main-tool.built")" "$main4"

move_main gate/a.txt
main5=$(git -C "$proj" ls-remote origin refs/heads/main | cut -f1)
: >"$LAKE_LOG"
(LAKE_SLEEP=4 mt "$path_with" ensure; echo "$code" >"$work/first.code") &
first=$!
for _ in $(seq 1 50); do grep -q '^build' "$LAKE_LOG" && break; sleep 0.1; done
MAIN_TOOL_READY_WAIT=1 mt "$path_with" ready "$main5"
check "ready does not wait out a build: exit 1" "$code" 1
check "ready says the checkout is busy" "$(last_err)" "the checkout is busy"
silent "a busy ready"
mt "$path_with" ensure
second=$code
wait "$first"
check "ensure waits out another caller's build: exit 0" "$second" 0
check "the first caller built: exit 0" "$(cat "$work/first.code")" 0
check "two callers, one build" "$(builds)" 1
check "the stamp names main" "$(cat "$dir/.lake/main-tool.built")" "$main5"

move_main gate/a.txt
: >"$LAKE_LOG"
(LAKE_SLEEP=2 mt "$path_with" ensure; echo "$code" >"$work/a.code") &
pa=$!
(LAKE_SLEEP=2 mt "$path_with" ensure; echo "$code" >"$work/b.code") &
pb=$!
wait "$pa" "$pb"
check "two stale callers at once: both exit 0" "$(cat "$work/a.code")$(cat "$work/b.code")" 00
check "two stale callers at once build once" "$(builds)" 1

echo "main-tool: done"
exit "$failed"
