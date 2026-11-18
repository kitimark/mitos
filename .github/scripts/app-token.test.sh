#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
real=$root/.lake/build/bin/mitos-gate
"$real" workflow pins "$root" || { echo "FAIL decoded workflow authority pins"; exit 1; }
"$root/gate/app-token-input-contract.sh" || exit 1
echo "5 passed, 0 failed"
