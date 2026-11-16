#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
lake build MitosGate.Yaml.View >/dev/null
lake env lean --run gate/YamlViewProperty.lean
