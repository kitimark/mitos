#!/usr/bin/env bash
set -u

say() { printf 'usage-sum: %s\n' "$1"; }
die() { say "$1" >&2; exit 1; }

[ $# -ge 1 ] || { say "usage: usage-sum.sh <file.jsonl | directory>..." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is not installed"

files=()
for arg in "$@"; do
  if [ -d "$arg" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$arg" -type f -name '*.jsonl' | sort)
  elif [ -f "$arg" ]; then
    files+=("$arg")
  else
    die "no such file or directory: $arg"
  fi
done

# A transcript repeats a message's usage on every content block of that message.
sums='
  [ inputs | fromjson? | select(type == "object" and .type == "assistant")
    | select((.message.usage | type) == "object" and .message.model != "<synthetic>")
    | {id: (.message.id // ("line" + (input_line_number | tostring))), u: .message.usage} ]
  | unique_by(.id)
  | if length == 0 then empty else
      [length,
       (map(.u.input_tokens // 0) | add),
       (map(.u.output_tokens // 0) | add),
       (map(.u.cache_read_input_tokens // 0) | add),
       (map(.u.cache_creation_input_tokens // 0) | add)] | @tsv
    end'

rows=$(mktemp) || die "mktemp failed"
trap 'rm -f "$rows"' EXIT
for f in "${files[@]}"; do
  line=$(jq -R -n -r "$sums" <"$f") || die "jq failed on $f"
  [ -n "$line" ] || continue
  dir=$(basename "$(dirname "$f")")
  case $dir in wf_*) wf=$dir ;; *) wf=- ;; esac
  printf '%s\t%s\t%s\n' "$f" "$wf" "$line" >>"$rows"
done
[ -s "$rows" ] || die "no usage found"

awk '
  function out(label, c, i, o, r, w) {
    printf "%-60s %6d %10d %10d %14d %14d\n", label, c, i, o, r, w
  }
  BEGIN {
    FS = "\t"
    printf "%-60s %6s %10s %10s %14s %14s\n", "journal", "calls", "input", "output", "cache-read", "cache-create"
  }
  {
    out($1, $3, $4, $5, $6, $7)
    for (k = 3; k <= 7; k++) tot[k] += $k
    if ($2 != "-") {
      if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 }
      for (k = 3; k <= 7; k++) wfs[$2, k] += $k
    }
  }
  END {
    for (j = 1; j <= n; j++) {
      w = order[j]
      out("workflow " w, wfs[w, 3], wfs[w, 4], wfs[w, 5], wfs[w, 6], wfs[w, 7])
    }
    out("total", tot[3], tot[4], tot[5], tot[6], tot[7])
  }' "$rows"
