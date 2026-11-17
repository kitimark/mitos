#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
real=$root/.lake/build/bin/mitos-gate
bundle=$(mktemp) || exit 1
trap 'rm -f "$bundle"' EXIT
curl --disable --fail --silent --show-error --location --connect-timeout 15 --max-time 60 \
  https://raw.githubusercontent.com/actions/create-github-app-token/64ab729a6294000f5aa4a4bc0b73d1f32bc45510/dist/main.cjs \
  --output "$bundle" || { echo "FAIL pinned action bundle download"; exit 1; }
node "$root/gate/app-token-input-contract.test.cjs" "$real" "$root" "$bundle" || exit 1
echo "4 passed, 0 failed"
