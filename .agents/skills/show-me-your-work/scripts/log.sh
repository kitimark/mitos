#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
	printf 'usage: log.sh <logfile> <phase> <decision> <why> <evidence> <result>\n' >&2
	exit 1
fi

logfile="$1"
shift

logdir="$(dirname "$logfile")"
if [ -n "$logdir" ] && [ "$logdir" != "." ] && [ ! -d "$logdir" ]; then
	mkdir -p "$logdir"
fi

append_row() {
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$logfile"
}

flatten_to_one_line() {
	printf '%s' "$1" | tr '\t\n\r' '   '
}

defuse_formula() {
	case "$1" in
		=*|+*|-*|@*) printf "'%s" "$1" ;;
		*) printf '%s' "$1" ;;
	esac
}

cell() {
	defuse_formula "$(flatten_to_one_line "$1")"
}

if [ ! -s "$logfile" ]; then
	append_row ts phase decision why evidence result
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
append_row "$ts" "$(cell "$1")" "$(cell "$2")" "$(cell "$3")" "$(cell "$4")" "$(cell "$5")"
