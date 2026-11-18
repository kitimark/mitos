#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

git -C "$root" ls-files '*lean-toolchain' '*lake-manifest.json' >"$work/expected"
[ -s "$work/expected" ] || fail "git ls-files listed no lean-toolchain or lake-manifest.json"

(
  cd "$root"
  find . -name lean-toolchain \
    -not -path '*/.lake/*' \
    -print | sed 's|^\./||' | sort >"$work/found-toolchains"
)
grep -E '(^|/)lean-toolchain$' "$work/expected" | sort >"$work/listed-toolchains"
if ! cmp -s "$work/found-toolchains" "$work/listed-toolchains"; then
  diff -u "$work/found-toolchains" "$work/listed-toolchains" >&2 || true
  fail "toolchain list differs from toolchain_files_to_install"
fi

cat >"$work/expected-paths" <<'EOF'
~/.elan
.lake
core/.lake
examples/acme/.lake
eval/score/.lake
eval/mutants/.lake
EOF

: >"$work/blocks"
read_blocks() {
  awk -v file="$2" '
    function strip(s,    q) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      q = "\047"
      if (substr(s, 1, 1) == q) s = substr(s, 2)
      if (substr(s, length(s), 1) == q) s = substr(s, 1, length(s) - 1)
      return s
    }
    function hash_of(line,    s, n, i, part, out) {
      sub(/[[:space:]]#.*$/, "", line)
      if (!match(line, /hashFiles\([^)]*\)/)) return ""
      s = substr(line, RSTART + 10, RLENGTH - 11)
      out = ""
      n = split(s, part, /,/)
      for (i = 1; i <= n; i++) out = out strip(part[i]) "\n"
      return out
    }
    function emit(    kind, label) {
      if (!lean) return
      kind = (uses ~ /cache\/restore/) ? "restore" : "save"
      if (job == "") job = "setup"
      label = file " " job " " kind
      printf "BLOCK\t%s\n", label
      printf "PATHS\n%s", paths
      printf "KEY\n%s", key_files
      printf "RESTORE\n%s", restore_files
      printf "END\n"
    }
    function reset() {
      in_step = 1
      uses = ""
      paths = ""
      key_files = ""
      restore_files = ""
      lean = 0
      in_paths = 0
      path_indent = 0
    }
    /^jobs:[[:space:]]*$/ { in_jobs = 1 }
    in_jobs && /^  [A-Za-z0-9-]+:[[:space:]]*$/ {
      if (in_step) emit()
      in_step = 0
      job = $1
      sub(/:$/, "", job)
    }
    /^[[:space:]]*-[[:space:]]/ {
      if (in_step) emit()
      reset()
    }
    in_step && /uses:[[:space:]]*actions\/cache/ { uses = $0 }
    in_step && /^[[:space:]]*path:[[:space:]]*\|[[:space:]]*$/ {
      in_paths = 1
      match($0, /[^[:space:]]/)
      path_indent = RSTART
      next
    }
    in_step && in_paths {
      match($0, /[^[:space:]]/)
      if (RSTART <= path_indent) {
        in_paths = 0
      } else {
        paths = paths strip($0) "\n"
        next
      }
    }
    in_step && /key:[[:space:]]*lean-/ {
      lean = 1
      key_files = hash_of($0)
    }
    in_step && /restore-keys:[[:space:]]*lean-/ {
      restore_files = hash_of($0)
    }
    END { if (in_step) emit() }
  ' "$1"
}

while IFS= read -r workflow; do
  rel=${workflow#"$root"/}
  read_blocks "$workflow" "$rel" >>"$work/blocks"
done < <(find "$root/.github" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

block_n=0
label=""
section=""
: >"$work/names"
while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    BLOCK$'\t'*)
      label=${line#BLOCK$'\t'}
      printf '%s\n' "$label" >>"$work/names"
      block_n=$((block_n + 1))
      section=""
      : >"$work/paths"
      : >"$work/key"
      : >"$work/restore"
      ;;
    PATHS|KEY|RESTORE)
      section=$line
      ;;
    END)
      [ -n "$label" ] || fail "cache block ended before it started"
      if ! cmp -s "$work/expected" "$work/key"; then
        diff -u "$work/expected" "$work/key" >&2 || true
        fail "$label key: hash list differs from git ls-files"
      fi
      if ! cmp -s "$work/expected" "$work/restore"; then
        diff -u "$work/expected" "$work/restore" >&2 || true
        fail "$label restore-keys: hash list differs from git ls-files"
      fi
      if ! cmp -s "$work/expected-paths" "$work/paths"; then
        diff -u "$work/expected-paths" "$work/paths" >&2 || true
        fail "$label path list differs"
      fi
      label=""
      section=""
      ;;
    *)
      case $section in
        PATHS) printf '%s\n' "$line" >>"$work/paths" ;;
        KEY) printf '%s\n' "$line" >>"$work/key" ;;
        RESTORE) printf '%s\n' "$line" >>"$work/restore" ;;
        *) fail "unexpected cache-block line: $line" ;;
      esac
      ;;
  esac
done <"$work/blocks"

[ "$block_n" -eq 6 ] || fail "found $block_n lean cache blocks, want 6: $(paste -sd ' ' "$work/names")"

cat >"$work/comment-only.yml" <<'EOF'
    - uses: actions/cache@v4
      with:
        key: lean-fixed # ${{ hashFiles('lean-toolchain') }}
        restore-keys: lean-fixed # ${{ hashFiles('lean-toolchain') }}
EOF
read_blocks "$work/comment-only.yml" "comment-only.yml" >"$work/comment-blocks"
grep -q $'BLOCK\tcomment-only.yml setup save' "$work/comment-blocks" \
  || fail "comment-only.yml setup save was not read"
if grep -q lean-toolchain "$work/comment-blocks"; then
  fail "comment-only.yml setup save: hashFiles in a trailing comment was accepted"
fi

file_n=$(wc -l <"$work/expected" | tr -d ' ')
path_n=$(wc -l <"$work/expected-paths" | tr -d ' ')
printf 'ok   cache key: %s blocks hash the same %s files\n' "$block_n" "$file_n"
printf 'ok   cache paths: %s blocks list the same %s paths\n' "$block_n" "$path_n"
