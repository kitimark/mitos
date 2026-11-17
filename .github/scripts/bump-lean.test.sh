#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/bump-lean.sh
version=v4.36.0-rc2
candidate=leanprover/lean4:$version
old=leanprover/lean4:v4.35.0
rev_old=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
rev_bad=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

command -v jq >/dev/null 2>&1 || { printf 'FAIL jq is not installed\n' >&2; exit 1; }
[ -x "$script" ] || { printf 'FAIL %s is not executable\n' "$script" >&2; exit 1; }

pass=0
fail=0

git_package() {
  local rev=$1 inherited=$2
  printf '{"url":"https://github.com/leanprover-community/mathlib4","type":"git","subDir":null,"scope":"","rev":"%s","name":"mathlib","inputRev":"v4.35.0","inherited":%s,"configFile":"lakefile.lean"}' \
    "$rev" "$inherited"
}

write_manifest() {
  local path=$1 rev=$2 inherited=$3 packages_dir=$4 extra=$5
  mkdir -p "$(dirname "$path")"
  if [ -n "$extra" ]; then
    printf '{"version":"1.3.0","packagesDir":"%s","packages":[%s,%s],"name":"fixture"}\n' \
      "$packages_dir" "$extra" "$(git_package "$rev" "$inherited")" >"$path"
  else
    printf '{"version":"1.3.0","packagesDir":"%s","packages":[%s],"name":"fixture"}\n' \
      "$packages_dir" "$(git_package "$rev" "$inherited")" >"$path"
  fi
}

seed() {
  local fx=$1 mathlib=$2 acme_rev=$3
  local ws
  for ws in . examples/acme eval/score eval/mutants eval/diff eval/extra eval/yaml-oracle .lake/packages/decoy core/.lake/packages/mathlib; do
    mkdir -p "$fx/$ws"
  done
  printf '%s\n' "$old" >"$fx/lean-toolchain"
  for ws in examples/acme eval/score eval/mutants eval/diff eval/extra; do
    printf '%s\n' "$old" >"$fx/$ws/lean-toolchain"
  done
  printf '%s\n' 'leanprover/lean4:v4.32.0' >"$fx/eval/yaml-oracle/lean-toolchain"
  printf '%s\n' 'leanprover/lean4:v4.0.0' >"$fx/.lake/packages/decoy/lean-toolchain"
  printf '%s\n' "$old" >"$fx/core/.lake/packages/mathlib/lean-toolchain"
  if [ "$mathlib" = yes ]; then
    cat >"$fx/core/lakefile.toml" <<'EOF'
name = "mitos-core"

[[require]]
name = "other"
path = "../other"
rev = "keep-me"

[[require]] # mathlib
git = "https://github.com/leanprover-community/mathlib4"
rev = "v4.35.0" # pin
name = "mathlib" # proof dependency

[[require]]
name = "after"
path = "../after"
rev = "leave-me"
EOF
  else
    printf 'name = "mitos-core"\n' >"$fx/core/lakefile.toml"
  fi
  cat >"$fx/lakefile.toml" <<'EOF'
name = "mitos"

[[require]]
name = "mitos-core"
path = "core"
EOF
  for ws in examples/acme eval/score eval/mutants eval/diff; do
    cat >"$fx/$ws/lakefile.toml" <<'EOF'
name = "workspace"

[[require]]
name = "mitos-core"
path = "../../core"
EOF
  done
  write_manifest "$fx/core/lake-manifest.json" "$rev_old" false ".lake/packages" ""
  write_manifest "$fx/lake-manifest.json" "$rev_old" true "core/.lake/packages" \
    '{"type":"path","name":"mitos-core","dir":"core"}'
  write_manifest "$fx/examples/acme/lake-manifest.json" "$acme_rev" true "../../core/.lake/packages" \
    '{"type":"path","name":"mitos-core","dir":"../../core"}'
  write_manifest "$fx/eval/score/lake-manifest.json" "$rev_old" true "../../core/.lake/packages" \
    '{"type":"path","name":"acme","dir":"../../examples/acme"}'
  write_manifest "$fx/eval/mutants/lake-manifest.json" "$rev_old" true "../../core/.lake/packages" \
    '{"type":"path","name":"mitos","dir":"../.."}'
  write_manifest "$fx/eval/diff/lake-manifest.json" "$rev_old" true "../../core/.lake/packages" \
    '{"type":"path","name":"acme","dir":"../../examples/acme"}'
}

install_stubs() {
  local stubs=$1 mode=$2 present=$3
  cat >"$stubs/git" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "\$GIT_LOG"
if [ "\$1" = ls-remote ] && [ "\$2" = --tags ]; then
  if [ "\$GIT_TAG_PRESENT" = 1 ]; then
    printf '0123456789abcdef0123456789abcdef01234567\\t%s\\n' "\$4"
  fi
  exit 0
fi
printf 'stub git: unexpected %s\\n' "\$*" >&2
exit 99
EOF
  cat >"$stubs/lake" <<EOF
#!/usr/bin/env bash
printf '%s\\t%s\\t%s\\n' "\$PWD" "\${MATHLIB_NO_CACHE_ON_UPDATE-}" "\$*" >> "\$LAKE_LOG"
if [ "\$1" = update ] && [ "\${2:-}" = mathlib ]; then
  case $mode in
    agree)
      printf '%s\\n' 'leanprover/lean4:from-lake' > lean-toolchain
      mkdir -p .lake/packages/mathlib
      printf '%s\\n' "$candidate" > .lake/packages/mathlib/lean-toolchain
      ;;
    mismatch)
      printf '%s\\n' 'leanprover/lean4:from-lake' > lean-toolchain
      mkdir -p .lake/packages/mathlib
      printf '%s\\n' 'leanprover/lean4:v4.0.0' > .lake/packages/mathlib/lean-toolchain
      ;;
  esac
  exit 0
fi
if [ "\$1" = update ] && [ "\$#" -eq 1 ]; then
  exit 0
fi
if [ "\$1" = exe ] && [ "\$2" = mitos-gate ] && [ "\$3" = lock ] && [ "\$4" = --check ]; then
  printf '%s\\n' 'statements.lock up to date (1 declarations)'
  exit 0
fi
printf 'stub lake: unexpected %s\\n' "\$*" >&2
exit 99
EOF
  chmod +x "$stubs/git" "$stubs/lake"
  export GIT_TAG_PRESENT=$present
}

snapshot() {
  local dir=$1 out=$2
  ( cd "$dir" && find . -print | sort | while IFS= read -r p; do
      if [ -f "$p" ]; then
        printf '%s %s\n' "$(sha256sum "$p")" "$p"
      else
        printf 'dir %s\n' "$p"
      fi
    done ) >"$out"
}

run_bump() {
  local fx=$1 stubs=$2
  shift 2
  ( cd "$fx" && PATH="$stubs:$PATH" "$script" "$@" )
}

prepare() {
  local mathlib=$1 acme_rev=$2 mode=$3 present=$4
  fx=$(mktemp -d)
  stubs=$(mktemp -d)
  trap 'rm -rf "$fx" "$stubs"' EXIT
  export LAKE_LOG=$stubs/lake.log GIT_LOG=$stubs/git.log
  : >"$LAKE_LOG"
  : >"$GIT_LOG"
  seed "$fx" "$mathlib" "$acme_rev"
  install_stubs "$stubs" "$mode" "$present"
}

assert_toolchains() {
  local fx=$1 ws
  for ws in lean-toolchain examples/acme/lean-toolchain eval/score/lean-toolchain \
      eval/mutants/lean-toolchain eval/diff/lean-toolchain eval/extra/lean-toolchain \
      eval/yaml-oracle/lean-toolchain; do
    [ "$(cat "$fx/$ws")" = "$candidate" ] || { printf 'toolchain not rewritten: %s\n' "$ws" >&2; return 1; }
  done
  [ "$(cat "$fx/.lake/packages/decoy/lean-toolchain")" = 'leanprover/lean4:v4.0.0' ]
}

assert_update_order() {
  local log=$1 fx=$2
  awk -F '\t' '
    $3 ~ /^update/ {
      if ($2 != "1") bad = 1
      print $1 " " $3
    }
    END { exit bad ? 1 : 0 }
  ' "$log" >"$log.order"
  printf '%s\n' \
    "$fx/core update mathlib" \
    "$fx update" \
    "$fx/examples/acme update" \
    "$fx/eval/score update" \
    "$fx/eval/mutants update" \
    "$fx/eval/diff update" >"$log.want"
  cmp -s "$log.want" "$log.order"
}

case_tag_exists() {
  local out code
  prepare yes "$rev_old" agree 1
  set +e
  out=$(run_bump "$fx" "$stubs" "$version" 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
  assert_toolchains "$fx"
  grep -q 'rev = "v4.36.0-rc2"' "$fx/core/lakefile.toml"
  grep -qxF '[[require]] # mathlib' "$fx/core/lakefile.toml"
  grep -q 'name = "mathlib" # proof dependency' "$fx/core/lakefile.toml"
  grep -q 'rev = "keep-me"' "$fx/core/lakefile.toml"
  grep -q 'rev = "leave-me"' "$fx/core/lakefile.toml"
  if grep -q 'rev = "v4.35.0"' "$fx/core/lakefile.toml"; then
    return 1
  fi
  [ ! -s "$LAKE_LOG" ]
  set +e
  out=$(run_bump "$fx" "$stubs" --lock 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
  assert_update_order "$LAKE_LOG" "$fx"
  printf '%s\n' "$out" | grep -qx 'update core: lake update mathlib'
  printf '%s\n' "$out" | grep -qx 'lock: unchanged'
  [ ! -e "$fx/core/lean-toolchain" ]
  [ "$(cat "$fx/core/.lake/packages/mathlib/lean-toolchain")" = "$candidate" ]
  ! grep -E 'exe mitos-gate lock($| [^-])' "$LAKE_LOG" >/dev/null
}

case_tag_missing() {
  local out code before after
  prepare yes "$rev_old" leave 0
  before=$stubs/before
  after=$stubs/after
  snapshot "$fx" "$before"
  set +e
  out=$(run_bump "$fx" "$stubs" "$version" 2>&1)
  code=$?
  set -e
  snapshot "$fx" "$after"
  [ "$code" -eq 3 ] || { printf 'exit %s\n%s\n' "$code" "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -qx "mathlib has no tag $version yet"
  cmp -s "$before" "$after"
  [ ! -s "$LAKE_LOG" ]
}

case_no_mathlib() {
  local out code before_lake
  prepare no "$rev_bad" leave 1
  cp "$fx/core/lakefile.toml" "$stubs/lakefile"
  set +e
  out=$(run_bump "$fx" "$stubs" "$version" 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
  assert_toolchains "$fx"
  cmp -s "$stubs/lakefile" "$fx/core/lakefile.toml"
  [ ! -s "$GIT_LOG" ]
  [ ! -s "$LAKE_LOG" ]
  before_lake=$stubs/manifests
  snapshot "$fx" "$before_lake"
  set +e
  out=$(run_bump "$fx" "$stubs" --lock 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
  [ ! -s "$LAKE_LOG" ]
  snapshot "$fx" "$stubs/after-lock"
  cmp -s "$before_lake" "$stubs/after-lock"
  ! printf '%s\n' "$out" | grep -q 'git entries differ'
}

case_manifest_disagrees() {
  local out code
  prepare yes "$rev_bad" leave 1
  set +e
  out=$( { run_bump "$fx" "$stubs" "$version" && run_bump "$fx" "$stubs" --lock; } 2>&1 )
  code=$?
  set -e
  [ "$code" -eq 1 ] || { printf 'exit %s\n%s\n' "$code" "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -qx 'examples/acme/lake-manifest.json git entries differ from core/lake-manifest.json'
  ! grep $'\t'"exe " "$LAKE_LOG" >/dev/null
}

case_phase1_never_calls_lake() {
  local out code
  prepare yes "$rev_old" agree 1
  set +e
  out=$(run_bump "$fx" "$stubs" "$version" 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
  [ ! -s "$LAKE_LOG" ]
  grep -q 'ls-remote --tags' "$GIT_LOG"
  assert_toolchains "$fx"
}

case_predicate_selects_yaml_oracle() {
  local out code
  prepare yes "$rev_old" leave 1
  set +e
  out=$(run_bump "$fx" "$stubs" "$version" 2>&1)
  code=$?
  set -e
  [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; return 1; }
  [ "$(cat "$fx/eval/yaml-oracle/lean-toolchain")" = "$candidate" ]
  [ "$(cat "$fx/.lake/packages/decoy/lean-toolchain")" = 'leanprover/lean4:v4.0.0' ]
  [ "$(cat "$fx/eval/extra/lean-toolchain")" = "$candidate" ]
}

case_package_mismatch() {
  local out code
  prepare yes "$rev_old" mismatch 1
  set +e
  out=$( { run_bump "$fx" "$stubs" "$version" && run_bump "$fx" "$stubs" --lock; } 2>&1 )
  code=$?
  set -e
  [ "$code" -eq 1 ] || { printf 'exit %s\n%s\n' "$code" "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -q '^mathlib: lean-toolchain is leanprover/lean4:v4.0.0, candidate is leanprover/lean4:v4.36.0-rc2$'
  ! grep $'\t'"exe " "$LAKE_LOG" >/dev/null
}

check_workflow() {
  local nightly=$root/.github/workflows/nightly.yml
  local ci=$root/.github/workflows/ci.yml
  local canary phase1 setup lockstep
  canary=$(awk 'BEGIN { p = 0 } /^  canary:/ { p = 1 } p' "$nightly")
  printf '%s\n' "$canary" | grep -q 'for f in lean-toolchain examples/acme/lean-toolchain eval/mutants/lean-toolchain' \
    && { printf 'canary still rewrites three toolchain files\n' >&2; return 1; }
  phase1=$(printf '%s\n' "$canary" | awk '/bump-lean\.sh "\$VERSION"/ { print NR; exit }')
  setup=$(printf '%s\n' "$canary" | awk '/\.\/\.github\/actions\/setup/ { print NR; exit }')
  lockstep=$(printf '%s\n' "$canary" | awk '/bump-lean\.sh --lock/ { print NR; exit }')
  if [ -z "$phase1" ] || [ -z "$setup" ] || [ -z "$lockstep" ]; then
    printf 'canary is missing a bump phase\n' >&2
    return 1
  fi
  if [ "$phase1" -ge "$setup" ] || [ "$setup" -ge "$lockstep" ]; then
    printf 'canary phases are out of order\n' >&2
    return 1
  fi
  printf '%s\n' "$canary" | grep -q 'waiting for Mathlib' \
    || { printf 'canary has no waiting summary\n' >&2; return 1; }
  printf '%s\n' "$canary" | grep -q 'Early warning, not a failure of main' \
    || { printf 'canary dropped the FAILED summary\n' >&2; return 1; }
  printf '%s\n' "$canary" | grep -q 'lake build' \
    || { printf 'canary dropped lake build\n' >&2; return 1; }
  grep -q 'bump-lean.test.sh' "$ci" || { printf 'ci.yml does not run the bump test\n' >&2; return 1; }
}

run_case() {
  local name=$1 status
  shift
  set +e
  ( set -euo pipefail; "$@" )
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    printf 'ok %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL %s\n' "$name" >&2
    fail=$((fail + 1))
  fi
}

assert_harness_fails_closed() {
  local before_fail=$fail before_pass=$pass
  swallow() {
    false
    true
  }
  run_case harness swallow >/dev/null 2>&1
  [ "$fail" -eq $((before_fail + 1)) ]
  fail=$before_fail
  pass=$before_pass
}

check_workflow
assert_harness_fails_closed
run_case "tag exists" case_tag_exists
run_case "tag missing" case_tag_missing
run_case "no mathlib require" case_no_mathlib
run_case "manifest disagrees" case_manifest_disagrees
run_case "phase 1 never calls lake" case_phase1_never_calls_lake
run_case "predicate selects yaml-oracle" case_predicate_selects_yaml_oracle
run_case "package toolchain mismatch" case_package_mismatch
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
