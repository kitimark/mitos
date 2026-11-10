#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.elan/bin:$PATH"
attempts=5
delay="${INSTALL_RETRY_DELAY:-10}"

toolchains=$(find . -name lean-toolchain -not -path '*/.lake/*' -print0 \
  | while IFS= read -r -d '' f; do cat "$f"; echo; done | sed '/^[[:space:]]*$/d' | sort -u)

[ -n "$toolchains" ] || { echo "::error::no lean-toolchain file found"; exit 1; }

for tc in $toolchains; do
  n=1
  until elan toolchain install "$tc"; do
    if [ "$n" -ge "$attempts" ]; then
      echo "::error::elan toolchain install $tc failed after $attempts attempts"
      exit 1
    fi
    echo "elan toolchain install $tc failed (attempt $n of $attempts); retrying in $((delay * n))s."
    sleep $((delay * n))
    n=$((n + 1))
  done
done
