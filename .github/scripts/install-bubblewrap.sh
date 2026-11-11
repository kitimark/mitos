#!/usr/bin/env bash
# Installs bubblewrap from a .deb pinned by its sha256, so that the gate does not need Ubuntu's
# mirrors to resolve (they did not on 2026-11-11). Sources, in order: the actions/cache copy, the
# first mirror that serves the pinned file, then apt-get. A file that does not match the pin is
# refused, so no host is trusted. To bump the pin, copy Version and SHA256 of bubblewrap from
# Ubuntu's signed index (dists/noble-updates/InRelease, then main/binary-amd64/Packages.gz).
# Tests set BWRAP_MIRRORS and BWRAP_DEB_DIR in place of the mirror list and the cache folder.
set -euo pipefail

BWRAP_VERSION="0.9.0-1ubuntu0.3"
BWRAP_SHA256="2461f1beee9cb04c8942739fe1a2b37e7b7c2a3d518f0779dc75f9245baa3094"
deb="bubblewrap_${BWRAP_VERSION}_amd64.deb"
pool="pool/main/b/bubblewrap/$deb"
dir="${BWRAP_DEB_DIR:-$HOME/.cache/bubblewrap-deb}"
mirrors=(https://azure.archive.ubuntu.com/ubuntu https://mirrors.edge.kernel.org/ubuntu
  https://mirrors.mit.edu/ubuntu https://archive.ubuntu.com/ubuntu)
if [ -n "${BWRAP_MIRRORS:-}" ]; then read -r -a mirrors <<< "$BWRAP_MIRRORS"; fi

if [ "${1:-}" = --cache-key ]; then
  echo "key=bubblewrap-deb-${BWRAP_VERSION}-${BWRAP_SHA256}"
  echo "dir=$dir"
  exit 0
fi

installed=$(dpkg-query -W -f='${db:Status-Status} ${Version}' bubblewrap 2>/dev/null || true)
if [ "${installed%% *}" = installed ] \
  && dpkg --compare-versions "${installed#* }" ge "$BWRAP_VERSION"; then
  echo "bubblewrap ${installed#* } is installed (pin $BWRAP_VERSION): nothing to do."
  exit 0
fi

matches_pin() {
  [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$BWRAP_SHA256" ]
}

from=
if [ -f "$dir/$deb" ]; then
  if matches_pin "$dir/$deb"; then
    from="the actions/cache copy $dir/$deb"
  else
    echo "::warning::the cached $deb does not match the pinned sha256; deleted it."
    rm -f "$dir/$deb"
  fi
fi

if [ -z "$from" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  for mirror in "${mirrors[@]}"; do
    url="$mirror/$pool"
    if ! curl -sSfL --retry 3 --retry-delay 5 --connect-timeout 15 --max-time 120 \
      -o "$tmp/$deb" "$url"; then
      echo "download of $url failed; trying the next mirror."
      continue
    fi
    if ! matches_pin "$tmp/$deb"; then
      echo "::warning::$url served a file that does not match the pinned sha256; refused it."
      rm -f "$tmp/$deb"
      continue
    fi
    mkdir -p "$dir"
    mv "$tmp/$deb" "$dir/$deb"
    from="mirror $url"
    break
  done
fi

if [ -n "$from" ]; then
  echo "Installing $deb from $from (sha256 matches the pin)."
  sudo dpkg -i "$dir/$deb"
else
  echo "::warning::no cache copy or mirror gave the pinned $deb; falling back to apt-get."
  if ! { sudo apt-get update -q && sudo apt-get install -y -q bubblewrap; }; then
    echo "::error::bubblewrap not installed: the cache, every mirror and apt-get failed."
    exit 1
  fi
fi
bwrap --version
