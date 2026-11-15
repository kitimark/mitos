#!/usr/bin/env bash
# Shard assignment for the cheat corpus. N lives here. Shard k runs the cases
# whose LC_ALL=C index i satisfies i % N == k.
#
# The aggregator does not trust that function alone. It requires the cases the
# shards recorded, the ones they actually ran, to equal the directory list. A
# case the function drops is absent from every shard record and the run fails.
set -euo pipefail

N=3

die() { printf '%s\n' "$*" >&2; exit 1; }

repo_root() {
  (cd "$(dirname "$0")/../.." && pwd)
}

list_cases() {
  local dir=$1
  [ -d "$dir" ] || die "no cheat directory $dir"
  find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | LC_ALL=C awk '/^[^.]/ { print }' \
    | LC_ALL=C sort
}

shard_names() {
  local dir=$1 k=$2 i=0 name
  [[ $k =~ ^[0-9]+$ ]] || die "shard $k is not an index"
  [ "$k" -lt "$N" ] || die "shard $k is outside 0..$((N - 1))"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ $((i % N)) -eq "$k" ]; then
      printf '%s\n' "$name"
    fi
    i=$((i + 1))
  done < <(list_cases "$dir")
}

cmd_check() {
  local dir=$1 name k n
  local -a all=() seen=()
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    all+=("$name")
  done < <(list_cases "$dir")
  [ "${#all[@]}" -gt 0 ] || die "no cheat cases in $dir"
  for ((k = 0; k < N; k++)); do
    n=0
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      n=$((n + 1))
      seen+=("$name")
    done < <(shard_names "$dir" "$k")
    if [ "$n" -eq 0 ]; then
      die "shard $k would be empty, and mitos-gate cheats with no names runs the whole corpus"
    fi
  done
  local dups got want
  dups=$(printf '%s\n' "${seen[@]}" | LC_ALL=C sort | uniq -d)
  [ -z "$dups" ] || die "a case is in more than one shard: $dups"
  got=$(printf '%s\n' "${seen[@]}" | LC_ALL=C sort)
  want=$(printf '%s\n' "${all[@]}" | LC_ALL=C sort)
  [ "$got" = "$want" ] || die "partition does not match the case directory"
}

timing_has_both() {
  local file=$1 name=$2
  awk -F '\t' -v c="$name" '
    $1 == c && $2 == "full" { f = 1 }
    $1 == c && $2 == "comparator" { m = 1 }
    END { exit !(f && m) }
  ' "$file"
}

table_row_ok() {
  local file=$1 name=$2
  awk -v c="$name" '
    FNR > 1 && $1 == c {
      found = 1
      if ($0 ~ /<-- FAIL/) bad = 1
    }
    END { exit !(found && !bad) }
  ' "$file"
}

aggregate() {
  local shards=$1 merged=$2 dir=$3
  local checks=${CHECKS:-} shres=${SHARDS:-}
  local k dir_k exit_line expected got name
  local -a union=()
  if [ "$checks" != success ] || [ "$shres" != success ]; then
    die "refusing corpus: checks=${checks:-unset} shards=${shres:-unset}"
  fi
  cmd_check "$dir"
  rm -rf "$merged"
  mkdir -p "$merged"
  : >"$merged/timing.rows"
  for ((k = 0; k < N; k++)); do
    dir_k=$shards/cheat-shard-logs-$k
    [ -d "$dir_k" ] || die "missing shard $k logs"
    [ -f "$dir_k/shard-exit" ] || die "shard $k recorded no exit status"
    exit_line=$(tr -d '\r' <"$dir_k/shard-exit")
    [ "$exit_line" = 0 ] || die "shard $k exited $exit_line"
    [ -f "$dir_k/shard-cases" ] || die "shard $k recorded no case list"
    expected=$(shard_names "$dir" "$k")
    got=$(cat "$dir_k/shard-cases")
    if [ "$expected" != "$got" ]; then
      diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$got") >&2 || true
      die "shard $k case list is not the partition"
    fi
    [ -f "$dir_k/timing.tsv" ] || die "shard $k has no timing.tsv"
    [ -f "$dir_k/table.txt" ] || die "shard $k has no table"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      union+=("$name")
      timing_has_both "$dir_k/timing.tsv" "$name" || die "shard $k timing.tsv drops $name"
      [ -f "$dir_k/$name.full.log" ] || die "shard $k has no full log for $name"
      [ -f "$dir_k/$name.comparator.log" ] || die "shard $k has no comparator log for $name"
      cp "$dir_k/$name.full.log" "$dir_k/$name.comparator.log" "$merged/"
      table_row_ok "$dir_k/table.txt" "$name" || die "shard $k table drops $name or marks it failed"
    done <"$dir_k/shard-cases"
    cp "$dir_k/table.txt" "$merged/shard-$k-table.txt"
    awk -F '\t' -v s="$k" 'NR > 1 && NF { print $0 "\t" s }' "$dir_k/timing.tsv" >>"$merged/timing.rows"
  done
  local all_sorted union_sorted dups timing_header table_header count row
  all_sorted=$(list_cases "$dir")
  union_sorted=$(printf '%s\n' "${union[@]}" | LC_ALL=C sort)
  dups=$(printf '%s\n' "${union[@]}" | LC_ALL=C sort | uniq -d)
  [ -z "$dups" ] || die "a case ran in more than one shard: $dups"
  if [ "$all_sorted" != "$union_sorted" ]; then
    diff -u <(printf '%s\n' "$all_sorted") <(printf '%s\n' "$union_sorted") >&2 || true
    die "shard case lists do not cover the case directory"
  fi
  {
    printf 'case\tmode\tstart_ms\tend_ms\texit\ttimed_out\tshard\n'
    LC_ALL=C sort "$merged/timing.rows"
  } >"$merged/timing.tsv"
  rm -f "$merged/timing.rows"
  timing_header=$(awk 'NR == 1 { print; exit }' "$merged/timing.tsv")
  [ "$timing_header" = $'case\tmode\tstart_ms\tend_ms\texit\ttimed_out\tshard' ] \
    || die "timing.tsv header is not one line"
  table_header=$(awk 'NR == 1 { print; exit }' "$shards/cheat-shard-logs-0/table.txt")
  printf '%s\n' "$table_header"
  count=0
  while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    row=$(awk -v c="$name" 'FNR > 1 && $1 == c { print; exit }' "$merged"/shard-*-table.txt)
    [ -n "$row" ] || die "no table row for $name"
    printf '%s\n' "$row"
    count=$((count + 1))
  done <<<"$all_sorted"
  printf '\ncheat corpus: all %s cases behave as expected\n' "$count"
}

usage() {
  die "usage: cheat-partition.sh n|cases [dir]|shard K [dir]|check [dir]|aggregate SHARDS MERGED [dir]"
}

dir_or() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$(repo_root)/eval/cheats"
  fi
}

main() {
  local cmd=${1:-}
  case "$cmd" in
    n) printf '%s\n' "$N" ;;
    cases) list_cases "$(dir_or "${2:-}")" ;;
    shard)
      [ -n "${2:-}" ] || usage
      shard_names "$(dir_or "${3:-}")" "$2"
      ;;
    check) cmd_check "$(dir_or "${2:-}")" ;;
    aggregate)
      if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
        usage
      fi
      aggregate "$2" "$3" "$(dir_or "${4:-}")"
      ;;
    *) usage ;;
  esac
}

main "$@"
