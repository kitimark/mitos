#!/usr/bin/env bash
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
lake build MitosGate.Snapshot.LegacyFixtures
