#!/usr/bin/env bash
set -euo pipefail
if ! command -v python3 >/dev/null 2>&1; then
  echo 'workflow-diff: missing python3' >&2
  exit 2
fi
exec python3 -I "${BASH_SOURCE[0]%/*}/workflow_leaves.py" --diff "$@"
