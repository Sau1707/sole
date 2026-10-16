#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-types-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

cp "$root/compiler/tests/types.sole" "$temporary/main.sole"
ln -s "$root/compiler/codegen" "$temporary/codegen"
SOLE_HOME="$root" SOLE_LIB="$root/lib" "$compiler" build "$temporary/main.sole" -o "$temporary/types-test"
"$temporary/types-test"
