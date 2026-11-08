#!/usr/bin/env bash
# Install elan unless the restored cache already has it, and put it on the PATH of later steps.
#
# Run this after the cache restore. A cache hit needs no download. On a miss, fetch the pinned
# release tarball (up to 5 attempts, waiting 10, 20, 30 and 40 s, because a GitHub outage returns
# 5xx for minutes), check its SHA-256, and run the installer inside it. Fails closed: a failed
# download or a wrong checksum fails the step.
#
# To bump elan: set ELAN_VERSION, download the tarball once and set ELAN_SHA256 to
#   sha256sum elan-x86_64-unknown-linux-gnu.tar.gz
set -euo pipefail

ELAN_VERSION="v4.2.4"
ELAN_SHA256="42b94d4244e8353142c456ec0e4ca6528fd898a6c604d4059f494e706e431f63"
ELAN_ARCHIVE="elan-x86_64-unknown-linux-gnu.tar.gz"
ELAN_URL="https://github.com/leanprover/elan/releases/download/${ELAN_VERSION}/${ELAN_ARCHIVE}"
attempts=5
delay="${INSTALL_RETRY_DELAY:-10}"

if [ -x "$HOME/.elan/bin/elan" ] && "$HOME/.elan/bin/elan" --version >/dev/null 2>&1; then
  echo "elan found in $HOME/.elan (cache hit): no download."
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "elan missing or not working: downloading ${ELAN_VERSION}."
  n=1
  until curl -sSfL --connect-timeout 30 --max-time 180 -o "$tmp/$ELAN_ARCHIVE" "$ELAN_URL"; do
    if [ "$n" -ge "$attempts" ]; then
      echo "::error::download of $ELAN_URL failed after $attempts attempts"
      exit 1
    fi
    echo "download failed (attempt $n of $attempts); retrying in $((delay * n))s."
    sleep $((delay * n))
    n=$((n + 1))
  done
  echo "$ELAN_SHA256  $tmp/$ELAN_ARCHIVE" | sha256sum -c -
  tar -xzf "$tmp/$ELAN_ARCHIVE" -C "$tmp" elan-init
  "$tmp/elan-init" -y --default-toolchain none
fi

echo "$HOME/.elan/bin" >> "${GITHUB_PATH:-/dev/null}"
