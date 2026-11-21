#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
version=$(tr -d '[:space:]' < "$root/eval/diff/.go-version")
case $version in
  1.24.7) sha256=da18191ddb7db8a9339816f3e2b54bdded8047cdc2a5d67059478f8d1595c43f ;;
  *) echo "::error::install-go.sh pins no SHA256 for go$version; a Go bump adds it here with eval/diff/.go-version" >&2; exit 1 ;;
esac
archive=go$version.linux-amd64.tar.gz
url=https://go.dev/dl/$archive
attempts=5
delay="${INSTALL_RETRY_DELAY:-10}"
dest=${RUNNER_TEMP:-/tmp}/go-$version

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=1
until curl -sSfL --connect-timeout 30 --max-time 300 -o "$tmp/$archive" "$url"; do
  if [ "$n" -ge "$attempts" ]; then
    echo "::error::download of $url failed after $attempts attempts"
    exit 1
  fi
  echo "download failed (attempt $n of $attempts); retrying in $((delay * n))s."
  sleep $((delay * n))
  n=$((n + 1))
done
echo "$sha256  $tmp/$archive" | sha256sum -c -
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmp/$archive" -C "$dest"
got=$(GOTOOLCHAIN=local "$dest/go/bin/go" env GOVERSION)
[ "$got" = "go$version" ] || { echo "::error::the archive holds $got, not go$version"; exit 1; }
echo "$dest/go/bin" >> "${GITHUB_PATH:-/dev/null}"
