#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 gate/workflow-select-check.py "$PWD/.lake/build/bin/mitos-gate"
