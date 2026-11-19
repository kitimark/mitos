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
cleanup_tool() {
  if [ -n "${tool_before:-}" ] && [ -f "$tool_before" ]; then
    local after="$tmp/tool-after"
    find "$tool_prefix" -print | sort >"$after"
    comm -13 "$tool_before" "$after" | awk '{ print length($0) "\t" $0 }' | sort -nr | cut -f2- |
      while IFS= read -r f; do
        rm -rf -- "$f"
      done
  fi
}
trap 'cleanup_tool; rm -rf "$tmp"' EXIT
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

commit_file() {
  local path=$1
  local msg=$2
  cat >"$remote/$path"
  git -C "$remote" add -A
  git -C "$remote" -c commit.gpgsign=false commit -q -m "$msg"
  rev=$(git -C "$remote" rev-parse HEAD)
}

expect_stale() {
  local name=$1
  local old=$2
  cp "$old" "$ws/statements.lock"
  run_at "$ws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'out of date' "$out" && ! grep -q 'uncaught exception' "$out"; then
    ok "$name"
  else
    bad "$name"
  fi
}

mkdir -p "$remote/ToyExt"
commit_file ToyExt/Card.lean "card two" <<'EOF'
namespace ToyExt

private inductive H
| left
| right

def Card : Type := H

end ToyExt
EOF
write_spec $'import ToyExt.Card\n' $'def usedCard : Prop := ∀ x y : ToyExt.Card, x = y\n'
if ! sync_build; then bad "a private toy inductive is pinned"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/card.lock"
  if [ "$lock_ec" = 0 ] && grep -q 'left' "$tmp/card.lock" && grep -q 'right' "$tmp/card.lock" \
      && grep -q '^ext inductive ' "$tmp/card.lock" && ! grep -q 'uncaught exception' "$out"; then
    ok "a private toy inductive is pinned"
  else
    bad "a private toy inductive is pinned"
  fi
fi

commit_file ToyExt/Card.lean "card one" <<'EOF'
namespace ToyExt

private inductive H
| left

def Card : Type := H

end ToyExt
EOF
if ! sync_build; then bad "dropping a private toy constructor changes the lock"; else
  rm -f "$sentinel"
  expect_stale "dropping a private toy constructor changes the lock" "$tmp/card.lock"
fi

commit_file ToyExt/Pair.lean "pair unit" <<'EOF'
namespace ToyExt

structure S where
  private mk ::
  x : Unit

end ToyExt
EOF
write_spec $'import ToyExt.Pair\n' $'def usedS : Prop := ∀ a b : ToyExt.S, a = b\n'
if ! sync_build; then bad "a private toy constructor is pinned"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/pair.lock"
  if [ "$lock_ec" = 0 ] && grep -q '^ext ctor ' "$tmp/pair.lock" && grep -q 'cidx=0' "$tmp/pair.lock" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a private toy constructor is pinned"
  else
    bad "a private toy constructor is pinned"
  fi
fi

commit_file ToyExt/Pair.lean "pair bool" <<'EOF'
namespace ToyExt

structure S where
  private mk ::
  x : Bool

end ToyExt
EOF
if ! sync_build; then bad "changing a private toy field changes the lock"; else
  rm -f "$sentinel"
  expect_stale "changing a private toy field changes the lock" "$tmp/pair.lock"
fi

commit_file ToyExt/Kw.lean "kw one" <<'EOF'
namespace ToyExt

def Kw : Nat := 1

end ToyExt
EOF
write_spec $'import ToyExt.Kw\n' $'private inductive W : Type\n| mk : ToyExt.Kw = 1 → W\ndef usedW : Prop := Nonempty W\n'
if ! sync_build; then bad "a package constant behind an unlisted spec constructor is pinned"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/kw.lock"
  if [ "$lock_ec" = 0 ] && grep -q '^ext def ToyExt.Kw ' "$tmp/kw.lock" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a package constant behind an unlisted spec constructor is pinned"
  else
    bad "a package constant behind an unlisted spec constructor is pinned"
  fi
fi

commit_file ToyExt/Kw.lean "kw two" <<'EOF'
namespace ToyExt

def Kw : Nat := 2

end ToyExt
EOF
if ! sync_build; then bad "bumping a package constant behind an unlisted spec constructor changes the lock"; else
  rm -f "$sentinel"
  expect_stale "bumping a package constant behind an unlisted spec constructor changes the lock" "$tmp/kw.lock"
fi

commit_file ToyExt/Hole.lean "hole one" <<'EOF'
import Lean
open Lean Meta Elab Term

namespace ToyExt

inductive Foo
| a
| b

private instance : Inhabited Foo := ⟨Foo.a⟩

private def privK : Nat := 1

elab "privKTerm" : term => do
  let n := mkPrivateNameCore `ToyExt.Hole `ToyExt.privK
  mkConst n

end ToyExt
EOF
write_spec $'import ToyExt.Hole\n' $'private inductive WI\n| mk : (default : ToyExt.Foo) = ToyExt.Foo.a → WI\ndef claimInst : Prop := Nonempty WI\nprivate inductive WK\n| mk : privKTerm = 1 → WK\ndef claimK : Prop := Nonempty WK\n'
if ! sync_build; then bad "an unlisted package definition behind an unlisted spec constructor is pinned"; else
  rm -f "$sentinel"
  run_at "$ws" lock
  cp "$ws/statements.lock" "$tmp/hole.lock"
  if [ "$lock_ec" = 0 ] && grep -q 'WI.mk' "$tmp/hole.lock" && grep -q 'WK.mk' "$tmp/hole.lock" \
      && ! grep -q 'instInhabitedFoo' "$tmp/hole.lock" && ! grep -q 'privK' "$tmp/hole.lock" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "an unlisted package definition behind an unlisted spec constructor is pinned"
  else
    {
      echo "exit $lock_ec"
      grep -E 'WI|WK|instInhabited|privK' "$tmp/hole.lock" || true
    } >"$out"
    bad "an unlisted package definition behind an unlisted spec constructor is pinned"
  fi
fi

commit_file ToyExt/Hole.lean "hole instance" <<'EOF'
import Lean
open Lean Meta Elab Term

namespace ToyExt

inductive Foo
| a
| b

private instance : Inhabited Foo := ⟨Foo.b⟩

private def privK : Nat := 1

elab "privKTerm" : term => do
  let n := mkPrivateNameCore `ToyExt.Hole `ToyExt.privK
  mkConst n

end ToyExt
EOF
if ! sync_build; then bad "bumping a private instance behind an unlisted spec constructor changes the lock"; else
  rm -f "$sentinel"
  expect_stale "bumping a private instance behind an unlisted spec constructor changes the lock" "$tmp/hole.lock"
fi

commit_file ToyExt/Hole.lean "hole privk" <<'EOF'
import Lean
open Lean Meta Elab Term

namespace ToyExt

inductive Foo
| a
| b

private instance : Inhabited Foo := ⟨Foo.a⟩

private def privK : Nat := 2

elab "privKTerm" : term => do
  let n := mkPrivateNameCore `ToyExt.Hole `ToyExt.privK
  mkConst n

end ToyExt
EOF
if ! sync_build; then bad "bumping a private definition behind an unlisted spec constructor changes the lock"; else
  rm -f "$sentinel"
  expect_stale "bumping a private definition behind an unlisted spec constructor changes the lock" "$tmp/hole.lock"
fi

write_spec '' $'private opaque hiddenSpec : Nat := 0\nprivate inductive HiddenW : Type\n| mk : hiddenSpec = 0 → HiddenW\ndef usedHiddenW : Prop := Nonempty HiddenW\n'
if ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "a reached unlisted spec opaque is refused"
else
  rm -f "$sentinel"
  run_at "$ws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'opaque' "$out" && grep -q 'hiddenSpec' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a reached unlisted spec opaque is refused"
  else
    bad "a reached unlisted spec opaque is refused"
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

mkdir -p "$ws/odd"
cat >"$ws/odd/lakefile.toml" <<'EOF'
name = "odd"
defaultTargets = ["Stray"]

[[lean_lib]]
name = "Stray"
EOF
cat >"$ws/odd/Stray.lean" <<'EOF'
def strayMarker : Nat := 1
EOF
cat >>"$ws/core/lakefile.toml" <<'EOF'

[[require]]
name = "odd"
path = "../odd"
EOF
write_spec $'import Stray\n' $'def usedStray : Nat := strayMarker\n'
if ! (cd "$ws/core" && lake update odd >"$tmp/lake.out" 2>&1) \
    || ! (cd "$ws" && lake update >"$tmp/lake.out" 2>&1) \
    || ! (cd "$ws/core" && lake build >"$tmp/lake.out" 2>&1); then
  cat "$tmp/lake.out" >"$out"
  bad "a module outside the toolchain, core, and packages is refused"
else
  run_at "$ws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'Stray' "$out" && grep -q 'not the toolchain' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a module outside the toolchain, core, and packages is refused"
  else
    bad "a module outside the toolchain, core, and packages is refused"
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

bdremote="$tmp/bdremote"
bdws="$tmp/bdws"
git init -q "$bdremote"
cp "$root/lean-toolchain" "$bdremote/lean-toolchain"
mkdir -p "$bdremote/Mitos/Core"
cat >"$bdremote/lakefile.toml" <<'EOF'
name = "builddir"
buildDir = "core/.lake/build"
defaultTargets = ["BadName"]

[[lean_lib]]
name = "BadName"
globs = ["Mitos.Core.+"]
EOF
cat >"$bdremote/Mitos/Core/X.lean" <<'EOF'
def planted : Nat := 1
EOF
cat >"$bdremote/Mitos/Core/Spec.lean" <<'EOF'
import Mitos.Core.X

def usedPlant : Nat := planted
EOF
git -C "$bdremote" add -A
git -C "$bdremote" -c commit.gpgsign=false commit -q -m "buildDir core"
bdrev=$(git -C "$bdremote" rev-parse HEAD)
mkdir -p "$bdws/core"
cp "$root/lean-toolchain" "$bdws/lean-toolchain"
cp "$root/lean-toolchain" "$bdws/core/lean-toolchain"
cat >"$bdws/lakefile.toml" <<'EOF'
name = "toy-root"

[[require]]
name = "toy-core"
path = "core"
EOF
cat >"$bdws/core/lakefile.toml" <<EOF
name = "toy-core"
packagesDir = "../.lake/packages"
defaultTargets = ["Dummy"]

[[require]]
name = "builddir"
git = "file://$bdremote"
rev = "$bdrev"

[[lean_lib]]
name = "Dummy"
EOF
cat >"$bdws/core/Dummy.lean" <<'EOF'
import Mitos.Core.Spec
EOF
bd_built=0
if (cd "$bdws/core" && lake update builddir >"$tmp/lake.out" 2>&1) \
   && (cd "$bdws" && lake update >"$tmp/lake.out" 2>&1) \
   && (cd "$bdws/core" && lake build >"$tmp/lake.out" 2>&1); then
  bd_built=1
fi
bd_olean=$(find "$bdws/.lake/packages/builddir" -path '*/core/.lake/build/lib/lean/Mitos/Core/X.olean' 2>/dev/null | head -1)
if [ "$bd_built" = 1 ] && [ -n "$bd_olean" ]; then
  cp "$root/statements.lock" "$bdws/statements.lock"
  run_at "$bdws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'Mitos.Core.X' "$out" && grep -q 'builddir' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a package buildDir under the package tree is refused for Mitos.Core"
  else
    bad "a package buildDir under the package tree is refused for Mitos.Core"
  fi
else
  cat "$tmp/lake.out" >"$out"
  echo "olean=$bd_olean" >>"$out"
  bad "a package buildDir under the package tree is refused for Mitos.Core"
fi

spoof_case() {
  local name=$1
  local builddir=$2
  local sremote="$tmp/spoof-remote-$name"
  local sws="$tmp/spoof-$name"
  spoof_built=0
  spoof_olean=""
  git init -q "$sremote"
  cp "$root/lean-toolchain" "$sremote/lean-toolchain"
  mkdir -p "$sremote/Mitos/Core"
  cat >"$sremote/lakefile.toml" <<EOF
name = "$name"
buildDir = "$builddir"
defaultTargets = ["BadName"]

[[lean_lib]]
name = "BadName"
roots = ["Mitos.Core.Plant"]
EOF
  cat >"$sremote/Mitos/Core/Plant.lean" <<'EOF'
def planted : Nat := 1
EOF
  git -C "$sremote" add -A
  git -C "$sremote" -c commit.gpgsign=false commit -q -m "spoof $name"
  local srev
  srev=$(git -C "$sremote" rev-parse HEAD)
  mkdir -p "$sws/core/Mitos/Core"
  cp "$root/lean-toolchain" "$sws/lean-toolchain"
  cp "$root/lean-toolchain" "$sws/core/lean-toolchain"
  cat >"$sws/lakefile.toml" <<'EOF'
name = "toy-root"

[[require]]
name = "toy-core"
path = "core"
EOF
  cat >"$sws/core/lakefile.toml" <<EOF
name = "toy-core"
packagesDir = "../.lake/packages"
defaultTargets = ["ToyCore"]

[[require]]
name = "$name"
git = "file://$sremote"
rev = "$srev"

[[lean_lib]]
name = "ToyCore"
roots = ["Mitos.Core.Spec"]
EOF
  cat >"$sws/core/Mitos/Core/Spec.lean" <<'EOF'
import Mitos.Core.Plant

namespace Mitos.Core.Spec

def usedPlant : Nat := planted

end Mitos.Core.Spec
EOF
  if (cd "$sws/core" && lake update "$name" >"$tmp/lake.out" 2>&1) \
      && (cd "$sws" && lake update >"$tmp/lake.out" 2>&1) \
      && (cd "$sws/core" && lake build >"$tmp/lake.out" 2>&1); then
    spoof_built=1
  fi
  spoof_olean=$(find "$sws" -path '*/Mitos/Core/Plant.olean' 2>/dev/null | head -1)
}

tool_prefix=$(cd "$root" && lean --print-prefix)
tool_before="$tmp/tool-before"
find "$tool_prefix" -print | sort >"$tool_before"
tws="$tmp/tws"
tpkg="$tws/toolspoof"
mkdir -p "$tpkg" "$tws/core/Mitos/Core"
tool_rel=$(realpath --relative-to="$tpkg" "$tool_prefix")
cat >"$tpkg/lakefile.toml" <<EOF
name = "toolspoof"
buildDir = "$tool_rel"
defaultTargets = ["ToolSpoof"]

[[lean_lib]]
name = "ToolSpoof"
EOF
cat >"$tpkg/ToolSpoof.lean" <<'EOF'
def toolMarker : Nat := 1
EOF
cp "$root/lean-toolchain" "$tws/lean-toolchain"
cp "$root/lean-toolchain" "$tws/core/lean-toolchain"
cat >"$tws/lakefile.toml" <<'EOF'
name = "toy-root"

[[require]]
name = "toy-core"
path = "core"
EOF
cat >"$tws/core/lakefile.toml" <<'EOF'
name = "toy-core"
packagesDir = "../.lake/packages"
defaultTargets = ["ToyCore"]

[[require]]
name = "toolspoof"
path = "../toolspoof"

[[lean_lib]]
name = "ToyCore"
globs = ["Mitos.Core.+"]
EOF
cat >"$tws/core/Mitos/Core/Spec.lean" <<'EOF'
import ToolSpoof

namespace Mitos.Core.Spec

def usedTool : Nat := toolMarker

end Mitos.Core.Spec
EOF
tool_built=0
if (cd "$tws/core" && lake update toolspoof >"$tmp/lake.out" 2>&1) \
    && (cd "$tws" && lake update >"$tmp/lake.out" 2>&1) \
    && (cd "$tws/core" && lake build >"$tmp/lake.out" 2>&1); then
  tool_built=1
fi
tool_olean="$tool_prefix/lib/lean/ToolSpoof.olean"
tool_trace="${tool_olean%.olean}.trace"
if [ "$tool_built" = 1 ] && { [ -f "$tool_olean.hash" ] || [ -f "$tool_trace" ]; }; then
  cp "$root/statements.lock" "$tws/statements.lock"
  run_at "$tws" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'ToolSpoof' "$out" && grep -q 'Lake .trace or .olean.hash' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a package buildDir aimed at the toolchain is refused"
  else
    bad "a package buildDir aimed at the toolchain is refused"
  fi
else
  cat "$tmp/lake.out" >"$out"
  echo "olean_hash=$([ -f "$tool_olean.hash" ] && echo yes || echo no) trace=$([ -f "$tool_trace" ] && echo yes || echo no)" >>"$out"
  bad "a package buildDir aimed at the toolchain is refused"
fi
cleanup_tool

spoof_case outbuild "../../../core/.lake/build"
if [ "$spoof_built" = 1 ] && printf '%s\n' "$spoof_olean" | grep -q '/core/.lake/build/' \
    && ! printf '%s\n' "$spoof_olean" | grep -q '/.lake/packages/'; then
  cp "$root/statements.lock" "$tmp/spoof-outbuild/statements.lock"
  run_at "$tmp/spoof-outbuild" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'Mitos.Core.Plant' "$out" && grep -q 'does not exist' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a package buildDir at core's build is refused"
  else
    bad "a package buildDir at core's build is refused"
  fi
else
  cat "$tmp/lake.out" >"$out"
  echo "olean=$spoof_olean built=$spoof_built" >>"$out"
  bad "a package buildDir at core's build is refused"
fi

spoof_case suffixbuild "../../../x/core/.lake/build"
if [ "$spoof_built" = 1 ] && printf '%s\n' "$spoof_olean" | grep -q '/x/core/.lake/build/'; then
  cp "$tmp/spoof-suffixbuild/core/.lake/build/lib/lean/Mitos/Core/Spec.olean" \
    "$(dirname "$spoof_olean")/Spec.olean"
  cp "$root/statements.lock" "$tmp/spoof-suffixbuild/statements.lock"
  run_at "$tmp/spoof-suffixbuild" lock --check
  if [ "$lock_ec" = 1 ] && grep -q 'Mitos.Core.Plant' "$out" && grep -q 'does not exist' "$out" \
      && ! grep -q 'uncaught exception' "$out"; then
    ok "a package buildDir whose path only ends like core's build is refused"
  else
    bad "a package buildDir whose path only ends like core's build is refused"
  fi
else
  cat "$tmp/lake.out" >"$out"
  echo "olean=$spoof_olean built=$spoof_built" >>"$out"
  bad "a package buildDir whose path only ends like core's build is refused"
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
cp "$root/core/Mitos/Core.lean" "$mandir/core/Mitos/Core.lean"
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
cp "$root/core/Mitos/Core.lean" "$copy/core/Mitos/Core.lean"
repo_env
lock_ec=0
(cd "$copy" && "$bin" lock >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 0 ] && cmp -s "$root/statements.lock" "$copy/statements.lock"; then
  ok "lock writes the same statements.lock on main"
else
  bad "lock writes the same statements.lock on main"
fi

relrepo="$tmp/relrepo"
relpayload="$tmp/relpayload"
relpkg="$tmp/relpkg"
relws="$tmp/relws"
mkdir -p "$relrepo/releases/download/v1" "$relpayload/lib/lean" "$relpkg" "$relws/core/Mitos/Core"
printf 'planted\n' >"$relpayload/planted.txt"
tar -czf "$relrepo/releases/download/v1/relpkg.tar.gz" -C "$relpayload" .
git init -q "$relpkg"
cp "$root/lean-toolchain" "$relpkg/lean-toolchain"
cat >"$relpkg/lakefile.toml" <<EOF
name = "relpkg"
buildDir = "../../../relout"
preferReleaseBuild = true
releaseRepo = "file://$relrepo"
buildArchive = "relpkg.tar.gz"
defaultTargets = ["RelPkg"]

[[lean_lib]]
name = "RelPkg"
EOF
cat >"$relpkg/RelPkg.lean" <<'EOF'
def relVal : Nat := 1
EOF
git -C "$relpkg" add -A
git -C "$relpkg" -c commit.gpgsign=false commit -q -m "relpkg"
git -C "$relpkg" tag v1
relrev=$(git -C "$relpkg" rev-parse HEAD)
cp "$root/lean-toolchain" "$relws/lean-toolchain"
cp "$root/lean-toolchain" "$relws/core/lean-toolchain"
cat >"$relws/lakefile.toml" <<'EOF'
name = "rel-root"

[[require]]
name = "rel-core"
path = "core"
EOF
cat >"$relws/core/lakefile.toml" <<EOF
name = "rel-core"
packagesDir = "../.lake/packages"
defaultTargets = ["RelCore"]

[[require]]
name = "relpkg"
git = "file://$relpkg"
rev = "$relrev"

[[lean_lib]]
name = "RelCore"
roots = ["Mitos.Core.Spec"]
EOF
cat >"$relws/core/Mitos/Core/Spec.lean" <<'EOF'
namespace Mitos.Core.Spec

def cleanSpec : Nat := 1

end Mitos.Core.Spec
EOF
if (cd "$relws/core" && env -u LAKE_NO_CACHE lake update relpkg >"$tmp/lake.out" 2>&1) \
    && (cd "$relws" && env -u LAKE_NO_CACHE lake update >"$tmp/lake.out" 2>&1) \
    && (cd "$relws/core" && LAKE_NO_CACHE=1 lake build relpkg >"$tmp/lake.out" 2>&1) \
    && (cd "$relws/core" && LAKE_NO_CACHE=1 lake build >"$tmp/lake.out" 2>&1) \
    && [ ! -f "$relws/relout/planted.txt" ]; then
  ok "LAKE_NO_CACHE=1 prevents a file:// releaseRepo package from unpacking a release archive"
else
  cat "$tmp/lake.out" >"$out"
  bad "LAKE_NO_CACHE=1 prevents a file:// releaseRepo package from unpacking a release archive"
fi

rm -rf "$relws/relout" "$relws/.lake/packages/relpkg/.lake"
if (cd "$relws/core" && env -u LAKE_NO_CACHE lake build relpkg >"$tmp/lake.out" 2>&1) \
    && [ -f "$relws/relout/planted.txt" ]; then
  ok "without LAKE_NO_CACHE a file:// releaseRepo package unpacks its release archive outside its tree"
else
  cat "$tmp/lake.out" >"$out"
  bad "without LAKE_NO_CACHE a file:// releaseRepo package unpacks its release archive outside its tree"
fi

run_at "$relws" lock
if [ "$lock_ec" = 1 ] && [ ! -f "$relws/statements.lock" ] \
    && grep -q 'relpkg' "$out" && grep -q 'outside' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock refuses to write statements.lock when a package LEAN_PATH entry escapes its tree"
else
  bad "lock refuses to write statements.lock when a package LEAN_PATH entry escapes its tree"
fi

cp "$root/statements.lock" "$relws/statements.lock"
run_at "$relws" lock --check
if [ "$lock_ec" = 1 ] && grep -q 'relpkg' "$out" && grep -q 'outside' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock --check refuses a package LEAN_PATH entry that escapes its tree via .."
else
  bad "lock --check refuses a package LEAN_PATH entry that escapes its tree via .."
fi

symws="$tmp/symws"
symout="$tmp/symout"
mkdir -p "$symws/core/Mitos" "$symws/.lake/packages/sympkg/.lake" "$symout/lib/lean"
cp "$root/statements.lock" "$symws/statements.lock"
pin aaa >"$symws/lake-manifest.json"
pin aaa >"$symws/core/lake-manifest.json"
cp -R "$root/core/Mitos/Core" "$symws/core/Mitos/Core"
cp "$root/core/Mitos/Core.lean" "$symws/core/Mitos/Core.lean"
ln -s "$symout" "$symws/.lake/packages/sympkg/.lake/build"
ln -s "$symout" "$symws/.lake/packages/symroot"
repo_env
base_lean_path=$LEAN_PATH

lock_ec=0
(cd "$symws" && LEAN_PATH="$symws/.lake/packages/sympkg/.lake/build/lib/lean:$base_lean_path" \
  "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'sympkg' "$out" && grep -q 'outside' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock --check refuses a package LEAN_PATH entry that escapes via a symlink"
else
  bad "lock --check refuses a package LEAN_PATH entry that escapes via a symlink"
fi

rm "$symws/.lake/packages/sympkg/.lake/build"
ln -s "$tmp/sym-missing" "$symws/.lake/packages/sympkg/.lake/build"
lock_ec=0
(cd "$symws" && LEAN_PATH="$symws/.lake/packages/sympkg/.lake/build/lib/lean:$base_lean_path" \
  "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'sympkg' "$out" && grep -q 'cannot be resolved' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock --check refuses a package LEAN_PATH entry through a dangling symlink"
else
  bad "lock --check refuses a package LEAN_PATH entry through a dangling symlink"
fi

lock_ec=0
(cd "$symws" && LEAN_PATH="$symws/.lake/packages/symroot/.lake/build/lib/lean:$base_lean_path" \
  "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'symroot' "$out" && grep -q 'outside' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock --check refuses a symlinked package root in LEAN_PATH"
else
  bad "lock --check refuses a symlinked package root in LEAN_PATH"
fi

lock_ec=0
(cd "$symws" && LEAN_PATH="core/../.lake/packages/symroot/.lake/build/lib/lean:$base_lean_path" \
  "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'symroot' "$out" && grep -q 'outside' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock --check refuses a symlinked package root reached via leading .. in LEAN_PATH"
else
  bad "lock --check refuses a symlinked package root reached via leading .. in LEAN_PATH"
fi

mkdir -p "$symws/.lake/packages/inpkg/.lake/build/lib/lean"
lock_ec=0
(cd "$symws" && LEAN_PATH="core/.lake/build/lib/lean:.lake/packages/inpkg/.lake/build/lib/lean:$base_lean_path" \
  "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 0 ] && grep -q 'statements.lock up to date' "$out"; then
  ok "lock --check accepts ordinary core and in-package LEAN_PATH entries"
else
  bad "lock --check accepts ordinary core and in-package LEAN_PATH entries"
fi

lock_ec=0
(cd "$symws" && LEAN_PATH="$symws/.lake/packages/../outside:$base_lean_path" \
  "$bin" lock --check >"$out" 2>&1) || lock_ec=$?
if [ "$lock_ec" = 1 ] && grep -q 'escapes' "$out" \
    && ! grep -q 'uncaught exception' "$out"; then
  ok "lock --check refuses a LEAN_PATH entry escaping packagesDir via .."
else
  bad "lock --check refuses a LEAN_PATH entry escaping packagesDir via .."
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
