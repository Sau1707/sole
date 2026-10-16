#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-files-helpers-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

for optimize in -O0 -O2; do
    "$compiler" build "$root/compiler/tests/files-helpers.sole" "$optimize" -o "$temporary/program"
    mkdir "$temporary/data"
    printf 'original\n' > "$temporary/data/target"
    printf 'original\n' > "$temporary/data/hard"
    chmod 640 "$temporary/data/target"
    ln -s target "$temporary/data/link"
    ln -s missing "$temporary/data/dangling"
    ln "$temporary/data/hard" "$temporary/data/alias"
    timeout 10 "$temporary/program" "$temporary/data" > "$temporary/log"
    grep -q 'multiple hard links' "$temporary/log"
    test -L "$temporary/data/link"
    test -L "$temporary/data/dangling"
    test ! -e "$temporary/data/missing"
    test ! -s "$temporary/data/target"
    test "$(stat -c %a "$temporary/data/target")" = 640
    printf 'original\n' > "$temporary/expected"
    cmp "$temporary/data/hard" "$temporary/expected"
    cmp "$temporary/data/alias" "$temporary/expected"
    test -z "$(find "$temporary/data" -name '.sole-format-*' -print)"
    rm "$temporary/data/link" "$temporary/data/dangling" "$temporary/data/target" \
        "$temporary/data/hard" "$temporary/data/alias"
    rmdir "$temporary/data"
done
echo 'Passed filesystem helper checks.'
