#!/usr/bin/env bash
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bash "$root/.claude/hooks/pr-state.test.sh"
