#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 -I "$root/gate/lake-no-cache-check.py" "$root"
