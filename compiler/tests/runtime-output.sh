#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-runtime-output-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

compiler=$(command -v "${SOLE_COMPILER:-sole}")
export SOLE_HOME="$root" SOLE_LIB="$root/lib"
for optimize in -O0 -O2; do
    "$compiler" build "$root/compiler/tests/runtime-bridge.sole" "$optimize" --emit object -o "$temporary/runtime.o"
    ${CC:-cc} -std=gnu11 -Wall -Wextra -Werror \
        "$root/compiler/tests/runtime-output.c" "$temporary/runtime.o" -lm -ldl \
        -o "$temporary/runtime-output"
    mkdir "$temporary/runtime$optimize"
    "$temporary/runtime-output" "$temporary/runtime$optimize" 2> "$temporary/runtime.log"
    grep -q 'dangling output symlink' "$temporary/runtime.log"
done
