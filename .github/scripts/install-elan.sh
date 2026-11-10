#!/usr/bin/env bash
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
