#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
online=false
case "${1:-}" in
  "") ;;
  --online) online=true ;;
  *) echo "usage: check-pins.sh [--online]" >&2; exit 2 ;;
esac
for tool in sha256sum openssl base64; do
  command -v "$tool" > /dev/null || { echo "check-pins.sh: needs $tool" >&2; exit 2; }
done
if $online && ! command -v curl > /dev/null; then
  echo "check-pins.sh: --online needs curl" >&2
  exit 2
fi
status=0
problem() { echo "$1: $2" >&2; status=1; }
[ -r pins.tsv ] || { echo "check-pins.sh: cannot read pins.tsv" >&2; exit 2; }
[ -r licences.tsv ] || { echo "check-pins.sh: cannot read licences.tsv" >&2; exit 2; }
declare -A modules versions spdx licence_urls licence_hashes notice_urls notice_hashes used
while IFS=$'\t' read -r c m v l lu lh nu nh extra || [ -n "$c" ]; do
  case $c in ''|'#'*) continue ;; esac
  case $c in *[!a-zA-Z0-9_-]*) echo "check-pins.sh: bad licence case $c" >&2; exit 2 ;; esac
  if [ -n "${modules[$c]+listed}" ] || [ -n "$extra" ] ||
      [ -z "$m" ] || [ -z "$v" ] || [ -z "$l" ] ||
      [ -z "$lu" ] || [ -z "$lh" ] || [ -z "$nu" ] || [ -z "$nh" ]; then
    echo "check-pins.sh: malformed or duplicate licence row for $c" >&2; exit 2
  fi
  modules[$c]=$m; versions[$c]=$v; spdx[$c]=$l
  licence_urls[$c]=$lu; licence_hashes[$c]=$lh; notice_urls[$c]=$nu; notice_hashes[$c]=$nh
done < licences.tsv
check_source() {
  local c=$1 name=$2 url=$3 hash=$4 actual
  if [ ! -s "cases/$c/$name" ]; then problem "$c" "no $name"; return; fi
  actual=$(sha256sum < "cases/$c/$name" | cut -d' ' -f1)
  [ "$actual" = "$hash" ] || problem "$c" "$name differs from reviewed source $url"
  if $online; then
    if actual=$(curl -sSf --retry 3 "$url" | sha256sum | cut -d' ' -f1); then
      [ "$actual" = "$hash" ] || problem "$c" "$name source differs from reviewed hash: $url"
    else problem "$c" "cannot fetch $name source: $url"; fi
  fi
}
count=0
while IFS=$'\t' read -r c m v h _ l || [ -n "$c" ]; do
  case $c in ''|'#'*) continue ;; esac
  case $c in *[!a-zA-Z0-9_-]*) echo "check-pins.sh: bad pin case $c" >&2; exit 2 ;; esac
  count=$((count + 1))
  if [ -z "${modules[$c]+listed}" ]; then problem "$c" "no reviewed licence row"; continue; fi
  used[$c]=yes
  if [ "$m" != "${modules[$c]}" ] || [ "$v" != "${versions[$c]}" ] || [ "$l" != "${spdx[$c]}" ]; then
    problem "$c" "pin does not match reviewed licence metadata"
  fi
  f=cases/$c/module.mod
  if [ ! -f "$f" ]; then problem "$c" "no module.mod"; continue; fi
  got="h1:$(printf '%s  go.mod\n' "$(sha256sum < "$f" | cut -d' ' -f1)" | openssl dgst -sha256 -binary | base64)"
  [ "$got" = "$h" ] || problem "$c" "pins.tsv says $h, module.mod hashes to $got"
  if $online; then
    sum=$(curl -sSf --retry 3 "https://sum.golang.org/lookup/$m@$v" | grep -F "$m $v/go.mod " | cut -d' ' -f3)
    [ "$sum" = "$h" ] || problem "$c" "pins.tsv says $h, sum.golang.org says $sum"
  fi
  check_source "$c" LICENSE "${licence_urls[$c]}" "${licence_hashes[$c]}"
  if [ "${notice_urls[$c]}" != - ]; then
    check_source "$c" NOTICE "${notice_urls[$c]}" "${notice_hashes[$c]}"
  elif [ "${notice_hashes[$c]}" != - ]; then
    problem "$c" "NOTICE hash without a source URL"
  fi
  case $l in
    Apache-2.0|BSD-2-Clause|BSD-3-Clause|MIT) ;;
    *) problem "$c" "licence $l is not one of the four the design allows; the owner decides" ;;
  esac
  case $m in
    *[A-Z]*) problem "$c" "module path has an upper-case letter, which the proxy escapes" ;;
  esac
done < pins.tsv
[ "$count" -gt 0 ] || { echo "check-pins.sh: pins.tsv has no pins" >&2; exit 2; }
for c in "${!modules[@]}"; do
  [ -n "${used[$c]+checked}" ] || problem "$c" "reviewed licence row has no pin"
done
exit "$status"
