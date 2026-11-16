#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/yaml-oracle.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

needle='=VAL "echo ${{ needs.decide.outputs.pr }}'
rev=$(sed -n 's/^L4YAML_REV=//p' "$script")
tc=$(tr -d '\n' <"$root/eval/yaml-oracle/lean-toolchain")
got=$("$script" version)
[ "$got" = "L4YAML ${rev:0:12} on $tc" ] || fail "version is [$got]"
ok "version names the pin and the toolchain file"

cat >"$work/good" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$needle'
exit 0
EOF
chmod +x "$work/good"
if ! "$script" check "$work/good" >"$work/good.out" 2>"$work/good.err"; then
  cat "$work/good.out" "$work/good.err" >&2
  fail "decoded Shape D was rejected"
fi
n=$(find "$root/.github/workflows" -name '*.yml' | wc -l)
n=$((n))
grep -F -x -q "yaml-oracle: $n workflows accepted" "$work/good.out" \
  || fail "accepted count is not $n"
grep -F -q "$needle" "$work/good.out" || fail "Shape D line missing from the log"
ok "decoded Shape D is accepted"

first=$(find "$root/.github/workflows" -name '*.yml' -print | LC_ALL=C sort | head -n 1)
first=${first#"$root/"}
cat >"$work/bad" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$work/bad"
status=0
"$script" check "$work/bad" >"$work/bad.out" 2>"$work/bad.err" || status=$?
[ "$status" -eq 1 ] || fail "rejected workflow exited $status"
grep -F -q "$first" "$work/bad.err" || fail "rejection did not name $first"
ok "a rejected workflow is named"

cat >"$work/enc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '=VAL "echo ${{ \x6eeeds.decide.outputs.pr }}'
exit 0
EOF
chmod +x "$work/enc"
status=0
"$script" check "$work/enc" >"$work/enc.out" 2>"$work/enc.err" || status=$?
[ "$status" -eq 1 ] || fail "still-encoded Shape D exited $status"
grep -F -q 'Shape D still encoded' "$work/enc.err" || fail "still-encoded Shape D was not named"
ok "still-encoded Shape D is rejected"

status=0
"$script" check "$work/missing" >"$work/miss.out" 2>"$work/miss.err" || status=$?
[ "$status" -eq 2 ] || fail "missing binary exited $status"
ok "a missing binary exits 2"

echo "yaml-oracle: done"
