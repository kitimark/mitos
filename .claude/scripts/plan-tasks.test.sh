#!/usr/bin/env bash
# Every plan row whose Issue cell links an issue has a task file with a design (#220).
#
# A row is a table row of a `plan/phase-N.md` table whose last header cell is `Issue`, with a link
# to `/issues/<n>` in that cell. Its task file is `tasks/<id>-*.md` or `tasks/<id>.md`. The file is
# valid when its `## Design` block holds something beyond the lines `tasks/TEMPLATE.md` ships, or
# when a line says `Design: n/a (<reason>)`.
#
# Rows that have no valid file yet are listed in `.claude/scripts/plan-tasks.pending`, one id per
# line (`#` starts a comment). The list can only shrink: a listed row that now has a valid file
# fails, and so does a listed id that is no linked row. A linked row that is not listed fails
# until its file is written. The Architect writes the files (kitimark-mode, Plan-time designs).
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=${PLAN_TASKS_ROOT:-$(cd "$here/../.." && pwd)}
pending_rel=.claude/scripts/plan-tasks.pending

# Linked rows of the plan files under $1, one id per line.
linked_rows() {
  local f
  for f in "$1"/plan/phase-*.md; do
    [ -f "$f" ] || continue
    awk '
      /^\|/ {
        line = $0
        if (!intable) {
          intable = 1
          last = line
          sub(/[ \t]*\|[ \t]*$/, "", last)
          sub(/^.*\|[ \t]*/, "", last)
          isplan = (last == "Issue")
          next
        }
        if (!isplan || line ~ /^\|[ \t]*-/) next
        id = line
        sub(/^\|[ \t]*/, "", id)
        sub(/[ \t]*\|.*$/, "", id)
        cell = line
        sub(/[ \t]*\|[ \t]*$/, "", cell)
        sub(/^.*\|/, "", cell)
        if (cell ~ /\]\(https:\/\/github\.com\/[^)]*\/issues\/[0-9]+\)/) print id
        next
      }
      { intable = 0 }
    ' "$f"
  done
}

# The non-blank lines of a file's `## Design` block, one per line.
design_block() {
  awk '
    /^## / { indesign = ($0 == "## Design"); next }
    indesign && $0 !~ /^[ \t]*$/ { print }
  ' "$1"
}

# Succeeds when task file $2 holds a design, given the template at $1.
valid_file() {
  local template=$1 file=$2 extra
  grep -qE '^Design: n/a \(.+\)[[:space:]]*$' "$file" && return 0
  extra=$(design_block "$file" | grep -vxFf <(design_block "$template"))
  [ -n "$extra" ]
}

# Succeeds when some task file of row $3 under $2 is valid, given the template at $1.
row_valid() {
  local template=$1 tree=$2 id=$3 f
  for f in "$tree/tasks/$id".md "$tree/tasks/$id"-*.md; do
    [ -f "$f" ] || continue
    valid_file "$template" "$f" && return 0
  done
  return 1
}

# Prints each problem under tree $1 and succeeds only when there is none.
check() {
  local tree=$1 template=$1/tasks/TEMPLATE.md id bad=0 line
  local -a rows=() pending=()
  [ -f "$template" ] || { echo "$tree/tasks/TEMPLATE.md is missing"; return 1; }
  mapfile -t rows < <(linked_rows "$tree")
  if [ -f "$tree/$pending_rel" ]; then
    while IFS= read -r line; do
      line=${line%%#*}
      line=${line//[[:space:]]/}
      [ -n "$line" ] && pending+=("$line")
    done <"$tree/$pending_rel"
  fi
  [ "${#rows[@]}" -gt 0 ] || { echo "no plan row with an issue link was found"; return 1; }

  for id in "${rows[@]}"; do
    if ! [[ $id =~ ^P[0-9]+-[0-9]+[a-z]?$ ]]; then
      echo "row '$id' has an issue link but no task id of the form P<phase>-<nnn>"
      bad=1
    fi
  done
  if [ "${#pending[@]}" -gt 0 ]; then
    while IFS= read -r id; do
      echo "$id is listed twice in $pending_rel"
      bad=1
    done < <(printf '%s\n' "${pending[@]}" | sort | uniq -d)
  fi

  for id in "${rows[@]}"; do
    if [ "${#pending[@]}" -gt 0 ] && printf '%s\n' "${pending[@]}" | grep -qxF "$id"; then
      if row_valid "$template" "$tree" "$id"; then
        echo "$id has a task file with a design now: remove it from $pending_rel"
        bad=1
      fi
    elif ! row_valid "$template" "$tree" "$id"; then
      echo "$id links an issue but has no tasks/$id-*.md with a Design block or 'Design: n/a (<reason>)'"
      bad=1
    fi
  done
  for id in ${pending[@]+"${pending[@]}"}; do
    printf '%s\n' "${rows[@]}" | grep -qxF "$id" || {
      echo "$id is in $pending_rel but is no plan row with an issue link: remove it"
      bad=1
    }
  done
  return "$bad"
}

# PLAN_TASKS_ROOT checks another tree and skips the self-test.
if [ -n "${PLAN_TASKS_ROOT:-}" ]; then
  check "$root"
  exit $?
fi

failed=0
if out=$(check "$root"); then
  echo "ok   the tree: every linked row has a design or is pending"
else
  echo "FAIL the tree"
  echo "$out"
  failed=1
fi

# Negative cases on a small scratch tree, so the real plan files stay untouched.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
t=$work/t

fresh() {
  rm -rf "$t"
  mkdir -p "$t/plan" "$t/tasks" "$t/.claude/scripts"
  cp "$root/tasks/TEMPLATE.md" "$t/tasks/TEMPLATE.md"
  cat >"$t/plan/phase-9.md" <<'PLAN'
# Phase 9

| # | Task | Kind | Issue |
|---|---|---|---|
| P9-001 | A task with `a | b` in it | impl | [#1](https://github.com/o/r/issues/1) |
| P9-002 | Landed | impl | none, landed in [#2](https://github.com/o/r/pull/2) |
| P9-003 | Another | impl | [#3](https://github.com/o/r/issues/3) |

| Wave | Runs at once | Waits for |
|---|---|---|
| P9-004 | x | [#4](https://github.com/o/r/issues/4) |
PLAN
  printf '# tasks/P9-001-a.md\n\n## Design\nA real design.\n\n## Done when\n' >"$t/tasks/P9-001-a.md"
  printf '# tasks/P9-003-b.md\n\ngoal: x\nDesign: n/a (a script with no design choice)\n' >"$t/tasks/P9-003-b.md"
  : >"$t/$pending_rel"
}

expect() {
  local name=$1 want=$2 out
  if out=$(check "$t"); then
    if [ "$want" = ok ]; then echo "ok   $name"; else echo "FAIL $name was accepted"; failed=1; fi
  elif [ "$want" = fail ]; then
    echo "ok   $name rejected: $(echo "$out" | head -1)"
  else
    echo "FAIL $name was rejected"
    echo "$out"
    failed=1
  fi
}

fresh
expect "valid design and n/a reason" ok

fresh
rm "$t/tasks/P9-001-a.md"
expect "a linked row with no file" fail

fresh
printf '# t\n\n## Design\n\n## Done when\n' >"$t/tasks/P9-001-a.md"
expect "an empty Design block" fail

fresh
sed -n '/^## Design$/,/^## Done when$/p' "$t/tasks/TEMPLATE.md" | sed '$d' >"$t/tasks/P9-001-a.md"
expect "the template's Design block unfilled" fail

fresh
printf 'Design: n/a ()\n' >"$t/tasks/P9-003-b.md"
expect "an n/a with no reason" fail

fresh
echo P9-001 >"$t/$pending_rel"
expect "a listed row that gained a valid file" fail

fresh
rm "$t/tasks/P9-001-a.md"
echo 'P9-001  # waits' >"$t/$pending_rel"
expect "a listed row with no file" ok

fresh
printf '# t\n\n## Design\n\n' >"$t/tasks/P9-001-a.md"
echo P9-001 >"$t/$pending_rel"
expect "a listed row with an empty Design" ok

fresh
echo P9-007 >"$t/$pending_rel"
expect "a listed id that is no row" fail

fresh
echo P9-002 >"$t/$pending_rel"
expect "a listed id whose row has no issue link" fail

fresh
echo P9-004 >"$t/$pending_rel"
expect "a listed id from a table without an Issue column" fail

fresh
printf 'P9-001\nP9-001\n' >"$t/$pending_rel"
expect "a duplicate listing" fail

fresh
mv "$t/tasks/P9-003-b.md" "$t/tasks/P9-0030-b.md"
expect "a file of another id with the same prefix" fail

exit "$failed"
