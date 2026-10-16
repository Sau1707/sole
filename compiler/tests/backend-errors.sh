#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-backend-errors-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

cp "$root/compiler/tests/backend-errors.sole" "$temporary/main.sole"
ln -s "$root/compiler/codegen" "$temporary/codegen"
SOLE_HOME="$root" SOLE_LIB="$root/lib" "$compiler" build "$temporary/main.sole" --link LLVM-21 -o "$temporary/backend-errors"
for optimize in 0 2; do
    "$temporary/backend-errors" "$temporary/output-$optimize.o" "$temporary/missing/output.o" "$optimize"
    test -s "$temporary/output-$optimize.o"
done
test ! -e "$temporary/missing"
echo 'Passed backend error returns and successful object/check calls.'
