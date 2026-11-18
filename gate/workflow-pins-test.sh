#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null)
python3 -I "$root/gate/workflow-pins-check.py" "$root/.lake/build/bin/mitos-gate" "$root"
