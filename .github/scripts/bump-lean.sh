#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

script_dir=$(cd "$(dirname "$0")" && pwd)

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

load_predicate() {
  local src def
  src=$script_dir/install-toolchains.sh
  [ -f "$src" ] || die "install-toolchains.sh is missing"
  def=$(awk '
    /^toolchain_files_to_install\(\) \{/ { capture = 1 }
    capture { print }
    capture && /^\}/ { exit }
  ' "$src")
  [ -n "$def" ] || die "toolchain_files_to_install is missing from install-toolchains.sh"
  eval "$def"
  declare -F toolchain_files_to_install >/dev/null \
    || die "toolchain_files_to_install did not load"
}

mathlib_state() {
  local src=core/lakefile.toml
  if [ ! -e "$src" ]; then
    printf 'absent\n'
    return 0
  fi
  if [ -L "$src" ] || [ ! -f "$src" ]; then
    printf 'core/lakefile.toml is not a regular file\n' >&2
    return 1
  fi
  awk '
    /^\[\[require\]\][[:space:]]*$/ { in_req = 1; next }
    /^\[\[/ { in_req = 0; next }
    in_req && /^name[[:space:]]*=[[:space:]]*"mathlib"[[:space:]]*$/ { seen++ }
    END {
      if (seen > 1) exit 2
      if (seen == 1) print "required"
      else print "absent"
    }
  ' "$src"
}

rewrite_program() {
  cat <<'AWK'
/^\[\[require\]\][[:space:]]*$/ { in_req = 1; print; next }
/^\[\[/ { in_req = 0; print; next }
in_req && /^name[[:space:]]*=[[:space:]]*"mathlib"[[:space:]]*$/ { in_math = 1; seen++; print; next }
in_math && /^rev[[:space:]]*=[[:space:]]*"/ {
  print "rev = \"" ver "\""
  replaced++
  in_math = 0
  next
}
{ print }
END { if (seen != 1 || replaced != 1) exit 2 }
AWK
}

version_ok() {
  [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]
}

tag_present() {
  local version=$1 listing ref
  ref=refs/tags/$version
  printf 'mathlib tag check: https://github.com/leanprover-community/mathlib4 %s\n' "$ref"
  if ! listing=$(GIT_TERMINAL_PROMPT=0 git ls-remote --tags \
      https://github.com/leanprover-community/mathlib4 "$ref"); then
    die "git ls-remote failed for $ref"
  fi
  printf '%s\n' "$listing"
  printf '%s\n' "$listing" | awk -v ref="$ref" '
    BEGIN { found = 0 }
    {
      n = split($0, a, "\t")
      if (n == 2 && a[1] ~ /^[0-9a-fA-F]+$/ && (a[2] == ref || a[2] == ref "^{}")) found = 1
    }
    END { exit found ? 0 : 1 }
  '
}

write_toolchains() {
  local version=$1 n=0 f
  while IFS= read -r -d '' f; do
    if [ -L "$f" ] || [ ! -f "$f" ]; then
      die "refusing to write $f"
    fi
    printf 'leanprover/lean4:%s\n' "$version" >"$f"
    n=$((n + 1))
  done < <(toolchain_files_to_install)
  [ "$n" -gt 0 ] || die "no lean-toolchain file found"
}

set_mathlib_rev() {
  local version=$1 src=core/lakefile.toml tmp status
  tmp=$(mktemp "$src.XXXXXX")
  set +e
  rewrite_program | awk -v ver="$version" -f - "$src" >"$tmp"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    rm -f "$tmp"
    die "core/lakefile.toml mathlib rev cannot be set"
  fi
  mv "$tmp" "$src"
}

phase_bump() {
  local version=$1 state status=0
  version_ok "$version" || die "bad version: $version"
  load_predicate
  state=$(mathlib_state) || die "core/lakefile.toml has more than one mathlib require"
  case $state in
    absent) ;;
    required)
      if ! tag_present "$version"; then
        printf 'mathlib has no tag %s yet\n' "$version"
        exit 3
      fi
      ;;
    *) die "core/lakefile.toml mathlib state is $state" ;;
  esac
  if [ "$state" = required ]; then
    set +e
    rewrite_program | awk -v ver="$version" -f - core/lakefile.toml >/dev/null
    status=$?
    set -e
    [ "$status" -eq 0 ] || die "core/lakefile.toml mathlib rev cannot be set"
  fi
  write_toolchains "$version"
  if [ "$state" = required ]; then
    set_mathlib_rev "$version"
  fi
}

lake_update() {
  local dir=$1
  shift
  if [ -L "$dir" ] || [ ! -d "$dir" ]; then
    die "missing workspace $dir"
  fi
  printf 'update %s: lake %s\n' "$dir" "$*"
  ( cd "$dir" && MATHLIB_NO_CACHE_ON_UPDATE=1 lake "$@" )
}

git_entries() {
  jq -e -S -c '
    if (.packages | type) != "array" then
      error("packages is not an array")
    else
      [ .packages[]
        | select(.type == "git")
        | del(.inherited)
      ]
      | if any(.[]; (.name | type) != "string" or (.url | type) != "string"
            or (.rev | type) != "string" or (.inputRev | type) != "string") then
          error("git entry missing a field")
        else
          sort_by(.name, .url, .rev, .inputRev)
        end
    end
  ' "$1"
}

check_manifests() {
  local core_entries got bad=0 f
  core_entries=$(git_entries core/lake-manifest.json) \
    || die "core/lake-manifest.json git entries are unreadable"
  for f in \
    lake-manifest.json \
    examples/acme/lake-manifest.json \
    eval/score/lake-manifest.json \
    eval/mutants/lake-manifest.json \
    eval/diff/lake-manifest.json
  do
    if [ -L "$f" ] || [ ! -f "$f" ]; then
      die "$f is missing"
    fi
    got=$(git_entries "$f") || die "$f git entries are unreadable"
    if [ "$got" != "$core_entries" ]; then
      printf '%s git entries differ from core/lake-manifest.json\n' "$f" >&2
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] || exit 1
}

git_require_names() {
  awk '
    function flush() {
      if (in_req && git != "" && name != "") print name
      in_req = 0
      git = ""
      name = ""
    }
    /^\[\[require\]\][[:space:]]*$/ { flush(); in_req = 1; next }
    /^\[\[/ { flush(); next }
    in_req && /^name[[:space:]]*=[[:space:]]*"/ {
      name = $0
      sub(/^name[[:space:]]*=[[:space:]]*"/, "", name)
      sub(/".*$/, "", name)
    }
    in_req && /^git[[:space:]]*=/ { git = 1 }
    END { flush() }
  ' "$1"
}

check_packages() {
  local candidate file ws pkg tc got
  if [ -L lean-toolchain ] || [ ! -f lean-toolchain ]; then
    die "lean-toolchain is missing"
  fi
  candidate=$(tr -d '\r' <lean-toolchain)
  version_ok "${candidate#leanprover/lean4:}" \
    || die "lean-toolchain is not a candidate pin"
  candidate=leanprover/lean4:${candidate#leanprover/lean4:}
  for file in \
    core/lakefile.toml \
    lakefile.toml \
    examples/acme/lakefile.toml \
    eval/score/lakefile.toml \
    eval/mutants/lakefile.toml \
    eval/diff/lakefile.toml
  do
    if [ -L "$file" ] || [ ! -f "$file" ]; then
      die "$file is missing"
    fi
    case $file in
      lakefile.toml) ws=. ;;
      *) ws=${file%/lakefile.toml} ;;
    esac
    while IFS= read -r pkg; do
      [ -n "$pkg" ] || continue
      case $pkg in
        *[!A-Za-z0-9._-]*) die "bad package name $pkg" ;;
      esac
      tc=$ws/.lake/packages/$pkg/lean-toolchain
      if [ ! -f "$tc" ] || [ -L "$tc" ]; then
        printf '%s: lean-toolchain missing\n' "$pkg" >&2
        exit 1
      fi
      got=$(tr -d '\r' <"$tc")
      if [ "$got" != "$candidate" ]; then
        printf '%s: lean-toolchain is %s, candidate is %s\n' "$pkg" "$got" "$candidate" >&2
        exit 1
      fi
    done < <(git_require_names "$file")
  done
}

check_lock() {
  local status=0 out n
  set +e
  out=$(lake exe mitos-gate lock --check 2>&1)
  status=$?
  set -e
  printf '%s\n' "$out"
  if [ "$status" -eq 0 ]; then
    printf 'lock: unchanged\n'
    return 0
  fi
  n=$(printf '%s\n' "$out" | grep -cE '^[+-] ' || true)
  printf 'lock: %s lines change (needs spec-approved)\n' "$n"
  return 1
}

phase_lock() {
  local state had=0
  state=$(mathlib_state) || die "core/lakefile.toml has more than one mathlib require"
  case $state in
    required) ;;
    absent) return 0 ;;
    *) die "core/lakefile.toml mathlib state is $state" ;;
  esac
  command -v jq >/dev/null 2>&1 || die "jq is not installed"
  if [ -e core/lean-toolchain ] || [ -L core/lean-toolchain ]; then
    had=1
  fi
  lake_update core update mathlib
  lake_update . update
  lake_update examples/acme update
  lake_update eval/score update
  lake_update eval/mutants update
  lake_update eval/diff update
  if [ "$had" -eq 0 ] && [ -e core/lean-toolchain ]; then
    if [ -L core/lean-toolchain ] || [ ! -f core/lean-toolchain ]; then
      die "core/lean-toolchain is not a regular file"
    fi
    rm -f core/lean-toolchain
  fi
  check_manifests
  check_packages
  check_lock
}

case ${1:-} in
  --lock)
    [ "$#" -eq 1 ] || die "usage: bump-lean.sh --lock"
    phase_lock
    ;;
  *)
    [ "$#" -eq 1 ] || die "usage: bump-lean.sh <version>"
    phase_bump "$1"
    ;;
esac
