#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
if [ -d "$HOME/.elan/bin" ]; then
  export PATH="$HOME/.elan/bin:$PATH"
fi
cd "$root"
lake build mitos-gate >/dev/null || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
out="$tmp/out"
sentinel="$tmp/init-sentinel"

export GIT_AUTHOR_NAME=lock-test
export GIT_AUTHOR_EMAIL=lock-test@example.com
export GIT_COMMITTER_NAME=lock-test
export GIT_COMMITTER_EMAIL=lock-test@example.com

pass=0
fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; if [ -f "$out" ]; then sed 's/^/  | /' "$out"; fi; fail=$((fail + 1)); }

body() { grep -v '^#' "$1" | grep -v '^$' | sort; }

run_at() {
  local dir=$1
  shift
  lock_ec=0
  (
    cd "$dir" || exit 99
    eval "$(lake env bash -c 'printf "export LEAN_PATH=%q\nexport PATH=%q\n" "$LEAN_PATH" "$PATH"')"
    "$bin" "$@"
  ) >"$out" 2>&1 || lock_ec=$?
}

repo_env() {
  eval "$(cd "$root" && lake env bash -c 'printf "export LEAN_PATH=%q\nexport PATH=%q\n" "$LEAN_PATH" "$PATH"')"
}

remote="$tmp/remote"
ws="$tmp/ws"
git init -q "$remote"
cp "$root/lean-toolchain" "$remote/lean-toolchain"
cat >"$remote/lakefile.toml" <<'EOF'
name = "toyext"
defaultTargets = ["ToyExt"]

[[lean_lib]]
name = "ToyExt"
globs = ["ToyExt", "ToyExt.+"]
EOF

write_toy() {
  mkdir -p "$remote/ToyExt"
  cat >"$remote/ToyExt.lean" <<EOF
namespace ToyExt

def box (n : Nat) : Nat := n + $1

theorem box_ge (n : Nat) : box n ≥ n := by
$2

private def helper (n : Nat) : Nat := n + $3

def wrapped (n : Nat) : Nat := helper n

end ToyExt
EOF
  cat >"$remote/ToyExt/Axiom.lean" <<'EOF'
namespace ToyExt.Axiom

axiom boom : Nat

end ToyExt.Axiom
EOF
  cat >"$remote/ToyExt/Unsafe.lean" <<'EOF'
namespace ToyExt

unsafe def danger (n : Nat) : Nat := n

end ToyExt
EOF
  cat >"$remote/ToyExt/Opaque.lean" <<'EOF'
namespace ToyExt.Opaque

private opaque hidden : Nat

def usesHidden : Nat := hidden

end ToyExt.Opaque
EOF
  cat >"$remote/ToyExt/InitWrite.lean" <<EOF
initialize probe : Unit ← do
  IO.FS.writeFile "$sentinel" "ran"
EOF
}

write_spec() {
  cat >"$ws/core/Mitos/Core/Spec.lean" <<EOF
import ToyExt
$1

namespace Mitos.Core.Spec

def used : Nat := ToyExt.box 0

def usedThm : ToyExt.box 0 ≥ 0 := ToyExt.box_ge 0

def usedWrap : Nat := ToyExt.wrapped 0
$2
end Mitos.Core.Spec
EOF
}

publish() {
  write_toy "$1" "$2" "$3"
  git -C "$remote" add -A
  git -C "$remote" -c commit.gpgsign=false commit -q -m "toy $1 $3"
  rev=$(git -C "$remote" rev-parse HEAD)
}

sync_build() {
  if [ ! -f "$ws/core/lakefile.toml" ]; then
    return 1
  fi
  sed -i "s/rev = \".*\"/rev = \"$rev\"/" "$ws/core/lakefile.toml"
  if ! (cd "$ws/core" && lake update toyext >"$tmp/lake.out" 2>&1); then
    cat "$tmp/lake.out" >"$out"
    return 1
  fi
  if ! (cd "$ws" && lake update >"$tmp/lake.out" 2>&1); then
    cat "$tmp/lake.out" >"$out"
    return 1
  fi
  if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
    cat "$tmp/lake.out" >"$out"
    return 1
  fi
}

setup_ws() {
  mkdir -p "$ws/core/Mitos/Core"
  cp "$root/lean-toolchain" "$ws/lean-toolchain"
  cp "$root/lean-toolchain" "$ws/core/lean-toolchain"
  cat >"$ws/lakefile.toml" <<'EOF'
name = "toy-root"

[[require]]
name = "toy-core"
path = "core"
EOF
  cat >"$ws/core/lakefile.toml" <<EOF
name = "toy-core"
packagesDir = "../.lake/packages"
defaultTargets = ["ToyCore"]

[[require]]
name = "toyext"
git = "file://$remote"
rev = "$rev"

[[lean_lib]]
name = "ToyCore"
globs = ["Mitos.Core.+"]
EOF
  write_spec "" ""
  sync_build
}

proof_long='  unfold box
  have h := Nat.le_add_right n (n + 1)
  exact Nat.le_add_right n _'
proof_short='  unfold box
  exact Nat.le_add_right n _'

if grep -n -E 'loadExts|enableInitializersExecution' \
    "$root/gate/MitosGate/Lock.lean" "$root/gate/Main.lean" >"$out"; then
  bad "lock never names loadExts or enableInitializersExecution"
else
  : >"$out"
  ok "lock never names loadExts or enableInitializersExecution"
fi

publish 1 "$proof_short" 2
if ! setup_ws; then
  bad "toy workspace builds from a file:// package"
  echo "$pass passed, $fail failed"
  exit 1
fi
ok "toy workspace builds from a file:// package"
rm -f "$sentinel"

write_spec "" ""
if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "spec build"
  echo "$pass passed, $fail failed"
  exit 1
fi
rm -f "$sentinel"
run_at "$ws" lock
cp "$ws/statements.lock" "$tmp/base.lock"
if [ "$lock_ec" = 0 ] && grep -q '^ext def ToyExt.box ' "$tmp/base.lock" \
    && grep -q '^ext theorem ToyExt.box_ge ' "$tmp/base.lock" \
    && grep -q '^ext def ToyExt.wrapped ' "$tmp/base.lock" \
    && grep -q '^def Mitos.Core.Spec.used ' "$tmp/base.lock" \
    && ! grep -q 'helper' "$tmp/base.lock" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "a spec definition using a toy definition gives ext lines"
else
  bad "a spec definition using a toy definition gives ext lines"
fi

publish 3 "$proof_short" 2
if ! sync_build; then bad "rebuild after a toy definition body change"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/body.lock"
  gone=$(comm -23 <(body "$tmp/base.lock") <(body "$tmp/body.lock"))
  added=$(comm -13 <(body "$tmp/base.lock") <(body "$tmp/body.lock"))
  if [ "$lock_ec" = 0 ] && [ "$(printf '%s\n' "$gone" | grep -c .)" = 1 ] \
      && [ "$(printf '%s\n' "$added" | grep -c .)" = 1 ] \
      && printf '%s\n' "$gone" | grep -q '^ext def ToyExt.box ' \
      && printf '%s\n' "$added" | grep -q '^ext def ToyExt.box ' \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a toy definition body change moves only its ext line"
  else
    {
      echo "exit $lock_ec"
      echo "removed: $gone"
      echo "added: $added"
      cat "$out"
    } >"$tmp/show"
    cp "$tmp/show" "$out"
    bad "a toy definition body change moves only its ext line"
  fi
fi

publish 1 "$proof_long" 2
if ! sync_build; then bad "rebuild after a toy theorem proof change"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/proof.lock"
  if [ "$lock_ec" = 0 ] && cmp -s "$tmp/base.lock" "$tmp/proof.lock" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a toy theorem proof change moves nothing"
  else
    diff -u "$tmp/base.lock" "$tmp/proof.lock" >"$out" || true
    bad "a toy theorem proof change moves nothing"
  fi
fi

publish 1 "$proof_short" 5
if ! sync_build; then bad "rebuild after a toy private helper change"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/help.lock"
  gone=$(comm -23 <(body "$tmp/base.lock") <(body "$tmp/help.lock"))
  added=$(comm -13 <(body "$tmp/base.lock") <(body "$tmp/help.lock"))
  if [ "$lock_ec" = 0 ] && [ "$(printf '%s\n' "$gone" | grep -c .)" = 1 ] \
      && [ "$(printf '%s\n' "$added" | grep -c .)" = 1 ] \
      && printf '%s\n' "$gone" | grep -q '^ext def ToyExt.wrapped ' \
      && printf '%s\n' "$added" | grep -q '^ext def ToyExt.wrapped ' \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a toy private helper change moves the referencing line"
  else
    {
      echo "exit $lock_ec"
      echo "removed: $gone"
      echo "added: $added"
    } >"$out"
    bad "a toy private helper change moves the referencing line"
  fi
fi

publish 1 "$proof_short" 2
if ! sync_build; then bad "restore the toy package"; else ok "restore the toy package"; fi

commit_color() {
  mkdir -p "$remote/ToyExt"
  cat >"$remote/ToyExt/Color.lean" <<EOF
namespace ToyExt

inductive Color
$1

end ToyExt
EOF
  git -C "$remote" add -A
  git -C "$remote" -c commit.gpgsign=false commit -q -m "color"
  rev=$(git -C "$remote" rev-parse HEAD)
}

commit_color '| red | green'
write_spec $'import ToyExt.Color\n' $'def usedColor : ToyExt.Color := ToyExt.Color.red\n'
if ! sync_build; then bad "a reached toy inductive gives ext lines for its constructors"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/color.lock"
  if [ "$lock_ec" = 0 ] \
      && grep -q '^ext inductive ToyExt.Color .* ctors=ToyExt.Color.red,ToyExt.Color.green$' "$tmp/color.lock" \
      && grep -q '^ext ctor ToyExt.Color.red .* cidx=0$' "$tmp/color.lock" \
      && grep -q '^ext ctor ToyExt.Color.green .* cidx=1$' "$tmp/color.lock" \
      && ! grep -q 'Color.blue' "$tmp/color.lock" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a reached toy inductive gives ext lines for its constructors"
  else
    bad "a reached toy inductive gives ext lines for its constructors"
  fi
fi

commit_color '| red | green | blue'
if ! sync_build; then bad "adding a toy constructor changes the lock"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/color2.lock"
  added=$(comm -13 <(body "$tmp/color.lock") <(body "$tmp/color2.lock"))
  if [ "$lock_ec" = 0 ] && ! cmp -s "$tmp/color.lock" "$tmp/color2.lock" \
      && printf '%s\n' "$added" | grep -q '^ext ctor ToyExt.Color.blue ' \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "adding a toy constructor changes the lock"
  else
    {
      echo "exit $lock_ec"
      echo "added: $added"
    } >"$out"
    bad "adding a toy constructor changes the lock"
  fi
fi

commit_color '| blue | green | red'
if ! sync_build; then bad "reordering toy constructors changes the lock"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/color3.lock"
  if [ "$lock_ec" = 0 ] && ! cmp -s "$tmp/color2.lock" "$tmp/color3.lock" \
      && grep -q '^ext inductive ToyExt.Color .* ctors=ToyExt.Color.blue,ToyExt.Color.green,ToyExt.Color.red$' "$tmp/color3.lock" \
      && grep -q '^ext ctor ToyExt.Color.red .* cidx=2$' "$tmp/color3.lock" \
      && grep -q '^ext ctor ToyExt.Color.blue .* cidx=0$' "$tmp/color3.lock" \
      && grep -q 'ctors=ToyExt.Color.red,ToyExt.Color.green,ToyExt.Color.blue$' "$tmp/color2.lock" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "reordering toy constructors changes the lock"
  else
    bad "reordering toy constructors changes the lock"
  fi
fi

write_spec $'import ToyExt.Axiom\n' $'noncomputable def usedBoom : Nat := ToyExt.Axiom.boom\n'
if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "a reached toy axiom is refused"
else
  run_at "$ws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'axiom' "$out" && grep -q 'boom' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a reached toy axiom is refused"
  else
    bad "a reached toy axiom is refused"
  fi
fi

write_spec $'import ToyExt.Unsafe\n' $'unsafe def usedDanger : Nat := ToyExt.danger 0\n'
if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "a reached toy unsafe definition is refused"
else
  run_at "$ws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'unsafe' "$out" && grep -q 'danger' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a reached toy unsafe definition is refused"
  else
    bad "a reached toy unsafe definition is refused"
  fi
fi

write_spec $'import ToyExt.Opaque\n' $'def usedHidden : Nat := ToyExt.Opaque.usesHidden\n'
if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "a reached unlisted toy opaque is refused"
else
  run_at "$ws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'opaque' "$out" && grep -q 'hidden' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a reached unlisted toy opaque is refused"
  else
    bad "a reached unlisted toy opaque is refused"
  fi
fi

write_spec $'import ToyExt.InitWrite\n' ""
if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "a toy initialize that writes a file leaves no file after lock"
else
  rm -f "$sentinel"
  run_at "$ws" lock
  if [ "$lock_ec" = 0 ] && [ ! -e "$sentinel" ] && ! grep -q 'uncaught exception' "$out"; then
    ok "a toy initialize that writes a file leaves no file after lock"
  else
    echo "exit $lock_ec sentinel_exists=$([ -e "$sentinel" ] && echo yes || echo no)" >"$out"
    bad "a toy initialize that writes a file leaves no file after lock"
  fi
fi

badremote="$tmp/badremote"
badws="$tmp/badws"
git init -q "$badremote"
cp "$root/lean-toolchain" "$badremote/lean-toolchain"
mkdir -p "$badremote/Mitos/Core"
cat >"$badremote/lakefile.toml" <<'EOF'
name = "badname"
defaultTargets = ["BadName"]

[[lean_lib]]
name = "BadName"
globs = ["Mitos.Core.+"]
EOF
cat >"$badremote/Mitos/Core/X.lean" <<'EOF'
def planted : Nat := 1
EOF
cat >"$badremote/Mitos/Core/Spec.lean" <<'EOF'
import Mitos.Core.X

def usedPlant : Nat := planted
EOF
git -C "$badremote" add -A
git -C "$badremote" -c commit.gpgsign=false commit -q -m "plant Mitos.Core.X"
badrev=$(git -C "$badremote" rev-parse HEAD)
mkdir -p "$badws/core"
cp "$root/lean-toolchain" "$badws/lean-toolchain"
cp "$root/lean-toolchain" "$badws/core/lean-toolchain"
cat >"$badws/lakefile.toml" <<'EOF'
name = "toy-root"

[[require]]
name = "toy-core"
path = "core"
EOF
cat >"$badws/core/lakefile.toml" <<EOF
name = "toy-core"
packagesDir = "../.lake/packages"
defaultTargets = ["Dummy"]

[[require]]
name = "badname"
git = "file://$badremote"
rev = "$badrev"

[[lean_lib]]
name = "Dummy"
EOF
cat >"$badws/core/Dummy.lean" <<'EOF'
import Mitos.Core.Spec
EOF
bad_built=0
if (cd "$badws/core" && lake update badname >"$tmp/lake.out" 2>&1) \
    && (cd "$badws" && lake update >"$tmp/lake.out" 2>&1) \
    && (cd "$badws/core" && lake build >"$tmp/lake.out" 2>&1); then
  bad_built=1
fi
if [ "$bad_built" = 1 ]; then
  cp "$root/statements.lock" "$badws/statements.lock"
  run_at "$badws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'Mitos.Core.X' "$out" && grep -q 'badname' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a toy module named Mitos.Core.X is refused"
  else
    bad "a toy module named Mitos.Core.X is refused"
  fi
else
  cat "$tmp/lake.out" >"$out"
  bad "a toy module named Mitos.Core.X is refused"
fi

pin() {
  local rev=$1
  cat <<EOF
{"version":"1.3.0","packagesDir":".lake/packages","packages":[{"type":"git","name":"toyext","url":"file:///pkg","rev":"$rev","scope":"","inherited":false,"configFile":"lakefile.toml","manifestFile":"lake-manifest.json"}],"name":"toy","lakeDir":".lake","fixedToolchain":false}
EOF
}
mandir="$tmp/manifests"
mkdir -p "$mandir/core"
pin aaa >"$mandir/lake-manifest.json"
pin bbb >"$mandir/core/lake-manifest.json"
cp "$root/statements.lock" "$mandir/statements.lock"
repo_env
lock_ec=0
(cd "$mandir" && "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'toyext' "$out" && grep -q 'disagree' "$out"; then
  ok "root and core manifests that differ exit 1"
else
  bad "root and core manifests that differ exit 1"
fi

pin aaa >"$mandir/core/lake-manifest.json"
mkdir -p "$mandir/core/Mitos"
cp -R "$root/core/Mitos/Core" "$mandir/core/Mitos/Core"
lock_ec=0
(cd "$mandir" && "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 0 ] && grep -q 'statements.lock up to date' "$out"; then
  ok "identical git pins agree"
else
  bad "identical git pins agree"
fi

printf '{not json' >"$mandir/lake-manifest.json"
lock_ec=0
(cd "$mandir" && "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'not JSON' "$out"; then
  ok "a manifest that is not JSON is refused"
else
  bad "a manifest that is not JSON is refused"
fi

pin aaa >"$mandir/lake-manifest.json"
rm "$mandir/core/lake-manifest.json"
lock_ec=0
(cd "$mandir" && "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'cannot be read' "$out"; then
  ok "a missing manifest is refused"
else
  bad "a missing manifest is refused"
fi

mkdir -p "$mandir/core"
python3 - "$mandir/lake-manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
j = json.load(open(p))
del j["packages"][0]["rev"]
json.dump(j, open(p, "w"))
PY
pin aaa >"$mandir/core/lake-manifest.json"
lock_ec=0
(cd "$mandir" && "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'toyext' "$out"; then
  ok "a git package without a rev is refused"
else
  bad "a git package without a rev is refused"
fi

repo_env
before=$(sha256sum "$root/statements.lock")
lock_ec=0
(cd "$root" && "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
after=$(sha256sum "$root/statements.lock")
if [ "$lock_ec" = 0 ] && [ "$before" = "$after" ] && grep -q 'statements.lock up to date' "$out"; then
  ok "on main the lock is byte-identical"
else
  bad "on main the lock is byte-identical"
fi

copy="$tmp/maincopy"
mkdir -p "$copy/core/Mitos"
cp "$root/statements.lock" "$copy/statements.lock"
cp "$root/lake-manifest.json" "$copy/lake-manifest.json"
cp "$root/core/lake-manifest.json" "$copy/core/lake-manifest.json"
cp -R "$root/core/Mitos/Core" "$copy/core/Mitos/Core"
repo_env
lock_ec=0
(cd "$copy" && "$bin" lock >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 0 ] && cmp -s "$root/statements.lock" "$copy/statements.lock"; then
  ok "lock writes the same statements.lock on main"
else
  bad "lock writes the same statements.lock on main"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
