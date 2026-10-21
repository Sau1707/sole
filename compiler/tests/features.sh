#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-features-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cp "$root/compiler/tests/source-cases/features/main.sole" "$temporary/main.sole"

"$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole"
"$compiler" check "$temporary/main.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    timeout 10 "$temporary/program"
done

for name in integer real; do
    for declaration in struct; do
        printf '%s %s:\n    pass\n\n\ndef main() -> int32:\n    return 0\n' "$declaration" "$name" > "$temporary/reserved.sole"
        for command in check build; do
            status=0
            "$compiler" "$command" "$temporary/reserved.sole" > "$temporary/error" 2>&1 || status=$?
            test "$status" -eq 1
            grep -Fq 'duplicate or reserved type' "$temporary/error"
        done
    done
done

echo 'Passed combined struct, shared array, range, and += checks.'
