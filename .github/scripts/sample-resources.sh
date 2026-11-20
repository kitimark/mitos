#!/usr/bin/env bash
set -euo pipefail

usage='usage: sample-resources.sh before|during|after'

resource_line() {
  free -m | awk '/^Mem:/ {printf "mem used %sM, available %sM", $3, $7} /^Swap:/ {printf ", swap used %sM", $3}'
  df -h --output=avail / | awk 'NR == 2 {printf ", disk free %s", $1}'
  ps -eo rss=,comm= --sort=-rss | awk 'NR <= 3 {printf ", %s %dM", $2, $1 / 1024}'
}

[ $# -eq 1 ] || { echo "$usage" >&2; exit 2; }
case $1 in
  before)
    nproc
    free -m
    swapon --show
    df -h
    ;;
  during)
    while :; do echo "resources $(date -u +%T): $(resource_line)"; sleep 10 >/dev/null 2>&1; done
    ;;
  after)
    free -m
    df -h
    sudo -n dmesg | grep -i -E 'oom|out of memory' | tail -n 20 || true
    ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac
