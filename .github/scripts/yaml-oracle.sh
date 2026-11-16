#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
pkg=$root/eval/yaml-oracle
L4YAML_URL=https://github.com/nasa-jpl/L4YAML
L4YAML_REV=122064d0c853be8d6c2f4cd255c6fcd67acc4ae8
SHAPE_D_INPUT='run: "echo ${{ \x6eeeds.decide.outputs.pr }}"'
SHAPE_D_NEEDLE='=VAL "echo ${{ needs.decide.outputs.pr }}'
SHAPE_D_ENCODED='\x6eeeds'

version_line() {
  local tc
  tc=$(tr -d '\n' <"$pkg/lean-toolchain")
  printf 'L4YAML %s on %s' "${L4YAML_REV:0:12}" "$tc"
}

require_clean_pin() {
  local head porcelain
  head=''
  porcelain=dirty
  if [ -d "$pkg/src/.git" ]; then
    head=$(git -C "$pkg/src" rev-parse HEAD 2>/dev/null || true)
    porcelain=$(git -C "$pkg/src" status --porcelain 2>/dev/null || printf 'unreadable')
  fi
  if [ "$head" = "$L4YAML_REV" ] && [ -z "$porcelain" ]; then
    return 0
  fi
  rm -rf "$pkg/src"
  git init -q "$pkg/src"
  git -C "$pkg/src" fetch -q --depth 1 "$L4YAML_URL" "$L4YAML_REV"
  git -C "$pkg/src" checkout -q --detach FETCH_HEAD
  head=$(git -C "$pkg/src" rev-parse HEAD)
  porcelain=$(git -C "$pkg/src" status --porcelain)
  if [ "$head" != "$L4YAML_REV" ] || [ -n "$porcelain" ]; then
    printf '::error::yaml-oracle checkout is not %s\n' "$L4YAML_REV" >&2
    exit 1
  fi
}

install_pinned_toolchain() {
  local tc attempts delay n
  export PATH="$HOME/.elan/bin:$PATH"
  attempts=5
  delay=${INSTALL_RETRY_DELAY:-10}
  tc=$(tr -d '\n' <"$pkg/lean-toolchain")
  n=1
  until elan toolchain install "$tc"; do
    if [ "$n" -ge "$attempts" ]; then
      printf '::error::elan toolchain install %s failed after %s attempts\n' "$tc" "$attempts" >&2
      exit 1
    fi
    printf 'elan toolchain install %s failed (attempt %s of %s); retrying in %ss.\n' \
      "$tc" "$n" "$attempts" "$((delay * n))"
    sleep $((delay * n))
    n=$((n + 1))
  done
}

cmd_build() {
  local bin
  [ "$#" -eq 0 ]
  require_clean_pin
  install_pinned_toolchain
  bin=$pkg/.lake/build/bin/l4yaml-event
  ( cd "$pkg" && lake build l4yaml-event )
  [ -x "$bin" ]
}

cmd_version() {
  [ "$#" -eq 0 ]
  version_line
  printf '\n'
}

cmd_check() {
  local bin file rel status n out line
  if [ "$#" -ne 1 ] || [ ! -f "$1" ] || [ ! -x "$1" ]; then
    exit 2
  fi
  bin=$1
  printf 'yaml-oracle: %s\n' "$(version_line)"
  n=0
  while IFS= read -r -d '' file; do
    rel=${file#"$root/"}
    status=0
    "$bin" <"$file" >/dev/null || status=$?
    if [ "$status" -ne 0 ]; then
      printf '::error::yaml-oracle: %s rejected\n' "$rel" >&2
      exit 1
    fi
    printf 'yaml-oracle: accepted %s\n' "$rel"
    n=$((n + 1))
  done < <(find "$root/.github/workflows" -name '*.yml' -print0 | LC_ALL=C sort -z)
  if [ "$n" -eq 0 ]; then
    echo '::error::yaml-oracle: no workflows' >&2
    exit 1
  fi
  status=0
  out=$(printf '%s\n' "$SHAPE_D_INPUT" | "$bin") || status=$?
  if [ "$status" -ne 0 ]; then
    printf '::error::yaml-oracle: Shape D exited %s\n' "$status" >&2
    exit 1
  fi
  if printf '%s\n' "$out" | grep -qF "$SHAPE_D_ENCODED"; then
    echo '::error::yaml-oracle: Shape D still encoded' >&2
    exit 1
  fi
  line=$(printf '%s\n' "$out" | grep -F -m 1 "$SHAPE_D_NEEDLE" || true)
  if [ -z "$line" ]; then
    echo '::error::yaml-oracle: Shape D missing decoded value' >&2
    exit 1
  fi
  printf 'yaml-oracle: Shape D decodes to needs: %s\n' "$line"
  printf 'yaml-oracle: %s workflows accepted\n' "$n"
}

usage() {
  echo 'usage: yaml-oracle.sh build|check BIN|version' >&2
  exit 1
}

cmd=${1-}
if [ "$#" -gt 0 ]; then
  shift
fi
case $cmd in
  build) cmd_build "$@" ;;
  check) cmd_check "$@" ;;
  version) cmd_version "$@" ;;
  *) usage ;;
esac
