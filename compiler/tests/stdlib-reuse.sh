#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-stdlib-reuse-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cp "$root/compiler/tests/stdlib-reuse.sole" "$temporary/main.sole"
for module in syntax semantic codegen modules diagnostics primitives raw; do
    ln -s "$root/compiler/$module" "$temporary/$module"
done
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/helpers"
    env -u SOLE_CC "$temporary/helpers" cc
    SOLE_CC='' "$temporary/helpers" ''
    SOLE_CC="linker's tool" "$temporary/helpers" "linker's tool"
done

mkdir "$temporary/source"
for name in .sole 猫.sole; do
    printf 'import core\n\n\ndef main() -> void:\n    """Example."""\n    pass\n' > "$temporary/source/$name"
    "$compiler" check "$temporary/source/$name"
done
echo 'Passed standard-library reuse boundary checks.'
