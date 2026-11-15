#!/usr/bin/env bash

job_block() {
  awk -v job="$2" '
    $0 == "  " job ":" { inside = 1; print; next }
    inside && /^  [a-zA-Z0-9_-]+:/ { exit }
    inside { print }
  ' "$1"
}
