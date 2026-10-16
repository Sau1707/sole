#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-atomic-write-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

${CC:-cc} -std=gnu11 -Wall -Wextra -Werror \
    "$root/compiler/tests/atomic-write.c" "$root/lib/runtime/system.c" \
    -Wl,--wrap=write -Wl,--wrap=close -Wl,--wrap=rename -Wl,--wrap=fchmod -Wl,--wrap=fsync \
    -o "$temporary/atomic-write"
mkdir "$temporary/runtime"
"$temporary/atomic-write" "$temporary/runtime" 2> "$temporary/runtime.log"
grep -q 'dangling output symlink' "$temporary/runtime.log"

compiler=$(command -v "${SOLE_COMPILER:-sole}")
printf 'import core\ndef main() -> void:\n    pass\n' > "$temporary/target"
printf 'import core\n\n\ndef main() -> void:\n    pass\n' > "$temporary/expected"
chmod 640 "$temporary/target"
ln -s target "$temporary/input.sole"
"$compiler" format "$temporary/input.sole"
test -L "$temporary/input.sole"
cmp "$temporary/target" "$temporary/expected"
test "$(stat -c %a "$temporary/target")" = 640
"$compiler" format --check "$temporary/input.sole"

printf 'import core\ndef main() -> void:\n    pass\n' > "$temporary/hard.sole"
cp "$temporary/hard.sole" "$temporary/original"
ln "$temporary/hard.sole" "$temporary/alias.sole"
status=0
"$compiler" format "$temporary/hard.sole" > "$temporary/log" 2>&1 || status=$?
test "$status" -eq 1
grep -Fq "$temporary/hard.sole: error:" "$temporary/log"
grep -q 'multiple hard links' "$temporary/log"
cmp "$temporary/hard.sole" "$temporary/original"
cmp "$temporary/alias.sole" "$temporary/original"
test -z "$(find "$temporary" -name '.sole-format-*' -print)"
echo 'Passed atomic formatter integration checks.'
